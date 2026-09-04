import Foundation
import SwiftData

/// Writes wallet taps the owner never asked the app about directly into the purchase log.
///
/// `PredictionLog` is the append-only log of ADVICE — every accessor on it walks the graph
/// starting from `StoredPrediction`, because its whole charter is measuring whether that advice
/// held up. A card tap with no live "which card here?" behind it is a different kind of fact: a
/// purchase happened, evidenced by the Wallet capture Inunity already accepted, and grading the
/// app's own recommendation quality never entered into it. This type exists to log exactly that
/// fact, as a `StoredPurchase` with no `StoredPrediction` attached, so it shows up in Recent
/// Purchases without becoming a second, fabricated data point in the Experiment Scoreboard.
///
/// Complete, unique checkout matches are applied by `CheckoutService` before this type runs.
/// Partial or ambiguous matches wait in Finish Purchases. `CaptureMatcher.unclaimedCaptures` only
/// hands this type events that match no open checkout, plausibly or otherwise.
public struct AutoCaptureLog {
    private let context: ModelContext

    /// Counts which rung of the resolution ladder answered a Wallet capture. This is the path
    /// where "my Apple Pay purchase has no category" actually happens, so it is the counter worth
    /// reading before deciding the pack needs more rows.
    private let metrics: CategoryResolutionMetricsStore

    /// Learns exact Wallet/processor descriptors from strict one-to-one checkout joins. Separate
    /// from category learning: this answers only which canonical merchant a descriptor names.
    private let identityStore: MerchantMCCIdentityLearningStore

    public init(context: ModelContext,
                metrics: CategoryResolutionMetricsStore = CategoryResolutionMetricsStore(),
                identityStore: MerchantMCCIdentityLearningStore = .shared) {
        self.metrics = metrics
        self.identityStore = identityStore
        self.context = context
    }

    /// Every wallet-tap already represented by some purchase, whether logged automatically by this
    /// type or filled in by hand through `CaptureProposal`/`FinishPurchaseView`. The union matters:
    /// a tap accepted into an existing checkout must never ALSO be auto-logged as a second,
    /// standalone purchase on some later sync where it no longer matches an open prediction (the
    /// checkout it was accepted into is complete by then, so `unclaimedCaptures` would otherwise
    /// see it as orphaned).
    private func purchasesByWalletEventId() throws -> [String: StoredPurchase] {
        try context.fetch(FetchDescriptor<StoredPurchase>()).reduce(into: [:]) { result, purchase in
            guard let eventId = purchase.walletEventId else { return }
            // A wallet event is intended to identify exactly one purchase. If an older store ever
            // contains a duplicate, hydrate one deterministically rather than crashing sync.
            if result[eventId] == nil {
                result[eventId] = purchase
            }
        }
    }

    /// Logs every capture from `feedback` that matches no open prediction and has not already been
    /// logged, and returns the rows written. Safe to call on every sync: idempotent by
    /// `walletEventId`, and a no-op when there is nothing new to log.
    @discardableResult
    public func ingest(feedback: [WalletFeedback], openPredictions: [StoredPrediction]) throws -> [StoredPurchase] {
        // `CheckoutService` calls this with the ORIGINAL open-prediction population after applying
        // automatic matches. That is exactly the training set we want: `automaticProposals` repeats
        // the same strict one-to-one/CAD/resolved-card gate that was just trusted to mutate a
        // purchase. The event id is the independent fingerprint, so replaying sync cannot inflate
        // alias confidence.
        learnMerchantAliases(from: feedback, openPredictions: openPredictions)

        let loggedPurchases = try purchasesByWalletEventId()
        var didHydrate = false
        for event in feedback {
            guard let purchase = loggedPurchases[event.eventId] else { continue }
            didHydrate = hydrateMissingLocation(on: purchase, from: event) || didHydrate
        }
        if didHydrate {
            try context.save()
        }

        let alreadyLogged = Set(loggedPurchases.keys)
        let candidates = CaptureMatcher.unclaimedCaptures(from: feedback, openPredictions: openPredictions)
            .filter { !alreadyLogged.contains($0.eventId) }
        return try candidates.map(record)
    }

    /// Teaches descriptor identity only when the existing fail-closed capture matcher already says
    /// one Wallet event belongs to one live checkout and the checkout merchant itself resolves to a
    /// canonical seed row. Raw and server-normalized descriptors are both useful aliases; they use
    /// the same event fingerprint and therefore still count as one observation each per alias.
    private func learnMerchantAliases(from feedback: [WalletFeedback],
                                      openPredictions: [StoredPrediction]) {
        let predictionsByID = Dictionary(uniqueKeysWithValues: openPredictions.map { ($0.id, $0) })
        let eventsByID = Dictionary(grouping: feedback, by: \.eventId)

        for proposal in CaptureMatcher.automaticProposals(for: openPredictions, from: feedback) {
            guard let prediction = predictionsByID[proposal.predictionId],
                  let canonical = MerchantMCCSeedCatalogue.canonicalMatch(
                    merchantName: prediction.merchantName),
                  let events = eventsByID[proposal.eventId], events.count == 1,
                  let event = events.first else { continue }

            let aliases = [event.merchantRaw, event.merchantNormalized]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for alias in Set(aliases) {
                identityStore.record(alias: alias,
                                     merchantID: canonical.merchant.id,
                                     sourceFingerprint: "wallet:\(event.eventId)",
                                     observedAt: event.capturedAt)
            }
        }
    }

    /// Event-id deduplication prevents duplicate purchases, but it must not also freeze an older
    /// partial local copy forever. V3 purchases predate the local coordinate columns, so their
    /// event can carry a valid server-side location while the migrated V4 row remains nil. Fill
    /// only that missing pair; a location already attached to the historical purchase wins.
    private func hydrateMissingLocation(on purchase: StoredPurchase,
                                        from event: WalletFeedback) -> Bool {
        guard !purchase.hasPreciseLocation,
              let latitude = event.latitude,
              let longitude = event.longitude,
              latitude.isFinite,
              longitude.isFinite,
              (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude),
              latitude != 0 || longitude != 0 else { return false }
        purchase.merchantLatitude = latitude
        purchase.merchantLongitude = longitude
        return true
    }

    /// Purchases logged this way, newest first — the "Logged Automatically" section of Activity.
    ///
    /// Filtered on `prediction == nil`, NOT `walletEventId != nil`: the latter would also match a
    /// checkout-originated purchase once its owner accepts a `CaptureProposal` (see
    /// `StoredPurchase.walletEventId`'s doc comment for why that purchase carries one too), and
    /// that purchase belongs in Recent Purchases, not this section — it has a real prediction
    /// behind it. `isAutoLogged` names the same test; inlined here because `#Predicate` cannot
    /// call a computed property.
    public func recent(limit: Int = 20) throws -> [StoredPurchase] {
        var descriptor = FetchDescriptor<StoredPurchase>(
            predicate: #Predicate { $0.prediction == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    @discardableResult
    private func record(_ capture: CaptureMatcher.UnclaimedCapture) throws -> StoredPurchase {
        let learned = try learnedPrediction(for: capture.merchant)

        // Use the same graph-aware resolver as live checkout. A descriptor that has accumulated two
        // independent identity observations can therefore reach the 500-merchant MCC graph even
        // with no MapKit lookup, while a one-off descriptor remains a fallback exactly as before.
        let syntheticMerchant = NearbyPlace(
            id: merchantActivityKey(name: capture.merchant, locationIdentifier: nil,
                                    latitude: capture.latitude, longitude: capture.longitude)
                ?? capture.merchant,
            name: capture.merchant,
            poiCategoryRaw: nil,
            latitude: capture.latitude ?? 0,
            longitude: capture.longitude ?? 0,
            distanceMeters: nil)
        let categoryPrediction = learned ?? resolveCategory(for: syntheticMerchant)
        let category = categoryPrediction.confidenceSource == .fallback
            ? nil : categoryPrediction.category
        metrics.record(.resolved(rung: categoryPrediction.confidenceSource,
                                 forked: categoryPrediction.candidates.count > 1))
        if category == nil && !purchaseHasUsableLocation(capture) {
            // Distinguishes "we looked and found nothing" from "we were never able to look".
            // WalletFeedback.latitude/longitude are optional and older servers omit them, so a
            // capture with no fix can never reach location enrichment at all.
            metrics.record(.walletEnrichmentSkippedWithoutLocation)
        }
        let purchase = StoredPurchase(createdAt: capture.capturedAt,
                                      merchantLabel: capture.merchant,
                                      walletEventId: capture.eventId,
                                      activitySource: .walletCapture,
                                      // Pinned to the capture's own fix when it has one. A
                                      // descriptor alone cannot tell two same-named independents
                                      // apart, and the key it produces is the one every namesake
                                      // in the country shares; the coordinates Wallet sometimes
                                      // sends are the only thing that can. When they are absent
                                      // this yields exactly the key it always did, and location
                                      // enrichment re-keys it later if a POI is ever matched.
                                      merchantKey: merchantActivityKey(name: capture.merchant,
                                                                       locationIdentifier: nil,
                                                                       latitude: capture.latitude,
                                                                       longitude: capture.longitude),
                                      merchantLatitude: capture.latitude,
                                      merchantLongitude: capture.longitude,
                                      categoryAtPurchase: category,
                                      categoryConfidence: category == nil
                                        ? nil : categoryPrediction.confidenceSource,
                                      rawCategoryAtPurchase: categoryPrediction.rawCategory,
                                      categoryTaxonomyVersion: category == nil
                                        ? nil : categoryPrediction.taxonomyVersion,
                                      categoryConfidenceScore: category == nil
                                        ? nil : categoryPrediction.confidenceScore,
                                      merchantCategoryCode: categoryPrediction.merchantCategoryCode,
                                      merchantGroupID: categoryPrediction.merchantGroupID)
        context.insert(purchase)
        if let cardUsedId = capture.cardUsedId {
            purchase.cardUsedId = cardUsedId
            purchase.cardSourceRaw = CaptureSource.walletCapture.rawValue
        }
        if let amountCad = capture.amountCad {
            purchase.amountCad = amountCad
            purchase.amountSourceRaw = CaptureSource.walletCapture.rawValue
        }
        // Mirrors `PredictionLog`'s own completion rule (both facts known) rather than asserting
        // completion unconditionally — a foreign-currency tap or an unresolved card alias can still
        // leave one fact missing, and this purchase should say so honestly rather than claim done.
        if purchase.cardUsedId != nil, purchase.amountCad != nil {
            purchase.completedAt = capture.capturedAt
        }
        if let used = purchase.cardUsedId,
           ["best", "optimal"].contains(capture.verdict.lowercased()) {
            purchase.bestCardId = used
            purchase.advantageCad = 0
            purchase.evaluatedAt = capture.capturedAt
        }
        try context.save()
        return purchase
    }

    /// Owner corrections and previously resolved MapKit POIs outrank a fresh name guess. The
    /// fallback identity for local merchants is the same normalized-name key used by purchase
    /// history, so a corrected or location-resolved "Mom's Kitchen" capture teaches the next
    /// capture even when Wallet supplies no MapKit identifier.
    ///
    /// Deliberately keyed on the name alone, without coordinates, even though `merchantActivityKey`
    /// can now pin a key to a place. What is being looked up here is a *category*, and a category
    /// is a property of the business rather than of the branch — a descriptor with no fix at all
    /// should still inherit what the owner taught at the branch they were standing in. Identity is
    /// what needs splitting by location; classification is not.
    private func learnedPrediction(for merchantName: String) throws -> CategoryPrediction? {
        guard let key = merchantActivityKey(name: merchantName, locationIdentifier: nil) else {
            return nil
        }
        let merchants = try context.fetch(FetchDescriptor<StoredMerchant>())
        guard let learned = merchants.first(where: {
            merchantActivityKey(name: $0.name, locationIdentifier: nil) == key
        }) else { return nil }
        let prediction = predictionForKnownMerchant(learned)
        guard prediction.confidenceSource != .fallback,
              prediction.category != "other",
              prediction.candidates.count == 1 else { return nil }
        return prediction
    }
}

/// Whether a capture carries a fix precise enough for location enrichment to be attempted later.
/// Mirrors `StoredPurchase.hasPreciseLocation`, which cannot be asked before the row exists.
private func purchaseHasUsableLocation(_ capture: CaptureMatcher.UnclaimedCapture) -> Bool {
    guard let latitude = capture.latitude, let longitude = capture.longitude else { return false }
    return latitude != 0 || longitude != 0
}
