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
/// Unlike `CaptureProposal` — an offer the owner must accept before anything is written, because
/// what it offers to fill in IS an accuracy-bearing fact (which card the prediction said, versus
/// which card was actually tapped) — nothing here carries that risk, so nothing here waits for a
/// tap to confirm it. `CaptureMatcher.unclaimedCaptures` already only hands this type events that
/// match no open checkout, plausibly or otherwise.
public struct AutoCaptureLog {
    private let context: ModelContext

    public init(context: ModelContext) {
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
        let indexed = MerchantRecognizer.recognise(capture.merchant)
        let categoryPrediction = learned ?? indexed.flatMap { merchant in
                guard merchant.category != "other" else { return nil }
                return CategoryPrediction(category: merchant.category, confidenceSource: .brandPrior,
                                          candidates: [merchant.category],
                                          merchantCategoryCode: merchant.mcc)
            } ?? predict(poiCategoryRaw: nil, merchantName: capture.merchant)
        let category = categoryPrediction.confidenceSource == .fallback
            ? nil : categoryPrediction.category
        let purchase = StoredPurchase(createdAt: capture.capturedAt,
                                      merchantLabel: capture.merchant,
                                      walletEventId: capture.eventId,
                                      activitySource: .walletCapture,
                                      merchantKey: merchantActivityKey(name: capture.merchant,
                                                                       locationIdentifier: nil),
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
