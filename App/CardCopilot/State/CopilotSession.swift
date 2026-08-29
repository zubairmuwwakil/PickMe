import Foundation
import Observation
import CoreLocation
import CardCopilotEngine
import CardCopilotStore
import CardCopilotCapture

/// An operational failure the owner should be told about without losing their place.
///
/// Distinct from `CheckoutStep.failed`, which is a checkout dead end. This is presented as an
/// alert over whatever screen the owner is on. The old code had only the first kind, so a
/// SwiftData write failure during reconcile tore down the checkout flow.
struct FlowError: Identifiable, Equatable {
    let id = UUID()
    let message: String

    init(message: String) { self.message = message }
    init(_ error: Error) { self.message = error.localizedDescription }

    /// Compared by message, not by `id`. The synthesised `==` would include the fresh UUID, so
    /// two reports of the same failure were never equal and any test asserting on a whole
    /// FlowError would fail for a reason nothing on screen could explain. `id` still exists and
    /// still varies per report — that is what makes `.alert(item:)` re-present a repeat failure.
    static func == (lhs: FlowError, rhs: FlowError) -> Bool { lhs.message == rhs.message }
}

/// The last known device location, and whether it is fresh enough to sort by.
struct CachedLocation: Equatable {
    let latitude: Double
    let longitude: Double
    let capturedAt: Date

    var isRecent: Bool {
        Date().timeIntervalSince(capturedAt) < 15 * 60
    }
}

/// Whether the card used was PickMe's best material choice for this purchase.
enum PurchaseCardAssessment: Equatable {
    case best
    case better(cardId: String, advantageCad: Double?)
    case unavailable(reason: String)
}

/// Pure, read-only interpretation for Activity rows. Checkout rows use the recommendation frozen
/// when advice was given. Automatic captures are scored only when merchant category, amount, and
/// tapped card are all known; an unknown merchant stays unknown instead of being guessed as
/// general merchandise.
enum PurchaseActivityEvaluator {
    static func category(for purchase: StoredPurchase,
                         knownMerchants: [StoredMerchant] = []) -> String? {
        if let category = purchase.displayCategory, category != "other" { return category }
        let name = purchase.displayMerchant
        if let known = knownMerchants.first(where: {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            let prediction = predictionForKnownMerchant(known)
            if prediction.confidenceSource != .fallback, prediction.candidates.count == 1 {
                return prediction.category
            }
        }
        if let indexed = MerchantRecognizer.recognise(name), indexed.category != "other" {
            return indexed.category
        }
        let prediction = CardCopilotStore.predict(poiCategoryRaw: nil, merchantName: name)
        guard prediction.confidenceSource == .brandPrior,
              prediction.candidates.count == 1 else { return nil }
        return prediction.category
    }

    static func cardAssessment(for purchase: StoredPurchase,
                               graph: DependencyGraph,
                               knownMerchants: [StoredMerchant] = [],
                               walletFeedback: WalletFeedback? = nil) -> PurchaseCardAssessment {
        guard let usedCardId = purchase.cardUsedId else {
            return .unavailable(reason: purchase.prediction == nil ? "Card not captured"
                                                                  : "Add the card used to compare")
        }
        if let bestCardId = purchase.bestCardId {
            guard usedCardId != bestCardId else { return .best }
            return .better(cardId: bestCardId, advantageCad: purchase.advantageCad)
        }

        if let prediction = purchase.prediction {
            guard usedCardId != prediction.winnerCardId else { return .best }
            let advantage = scoreDifference(
                betterCardId: prediction.winnerCardId,
                usedCardId: usedCardId,
                merchantName: purchase.displayMerchant,
                amountCad: purchase.amountCad ?? prediction.scoredAmountCad,
                category: category(for: purchase, knownMerchants: knownMerchants),
                at: purchase.createdAt,
                graph: graph)
            return .better(cardId: prediction.winnerCardId, advantageCad: advantage)
        }
        guard let amountCad = purchase.amountCad else {
            return .unavailable(reason: "Add the amount to compare cards")
        }
        if let walletFeedback,
           ["best", "optimal"].contains(walletFeedback.verdict.lowercased()) { return .best }
        guard let category = category(for: purchase, knownMerchants: knownMerchants) else {
            return .unavailable(reason: "Category needed to compare cards")
        }
        guard let recommendation = recommendation(merchantName: purchase.displayMerchant,
                                                  amountCad: amountCad, category: category,
                                                  at: purchase.createdAt, graph: graph) else {
            return .unavailable(reason: "Card comparison unavailable")
        }
        guard recommendation.winner.cardId != usedCardId else { return .best }
        guard let used = recommendation.allCandidates.first(where: { $0.cardId == usedCardId }) else {
            return .better(cardId: recommendation.winner.cardId, advantageCad: nil)
        }
        let advantage = recommendation.winner.netValueCad - used.netValueCad
        return advantage > 0.0001
            ? .better(cardId: recommendation.winner.cardId, advantageCad: advantage) : .best
    }

    private static func scoreDifference(betterCardId: String, usedCardId: String,
                                        merchantName: String, amountCad: Double?, category: String?,
                                        at date: Date, graph: DependencyGraph) -> Double? {
        guard let amountCad, let category,
              let recommendation = recommendation(merchantName: merchantName,
                                                  amountCad: amountCad,
                                                  category: category,
                                                  at: date,
                                                  graph: graph),
              let better = recommendation.allCandidates.first(where: { $0.cardId == betterCardId }),
              let used = recommendation.allCandidates.first(where: { $0.cardId == usedCardId })
        else { return nil }
        let difference = better.netValueCad - used.netValueCad
        return difference > 0.0001 ? difference : nil
    }

    private static func recommendation(merchantName: String, amountCad: Double, category: String,
                                       at date: Date, graph: DependencyGraph) -> Recommendation? {
        let indexed = MerchantRecognizer.recognise(merchantName)
        let brand = indexed?.merchantBrand ?? canonicalEngineBrand(merchantName)
        let networks = indexed?.acceptedNetworks
            ?? knownAcceptedNetworks(for: brand, merchantName: merchantName)
        let purchase = PurchaseContext(amountCad: amountCad,
                                       category: category,
                                       mcc: indexed?.mcc,
                                       merchantBrand: brand,
                                       acceptedNetworks: networks)
        guard case .advised(let recommendation) = graph.engine.recommend(
            purchase, asOf: date.formatted(.iso8601.year().month().day())) else { return nil }
        return recommendation
    }
}

/// Everything that changes while the owner is using the app, and the operations that change it.
///
/// Owns no navigation. Operations that affect where the owner goes return a `FlowOutcome` and
/// let `CheckoutFlowRouting` decide, so this object never imports the router and the router
/// never imports MapKit.
@Observable
@MainActor
final class CopilotSession {
    private(set) var valueRecoveredCad: Double = 0
    /// Complete purchases not yet checked against a statement. Shown beside the confirmed
    /// figure rather than added to it — see PredictionLog.ValueRecovered.
    private(set) var pendingValueCad: Double = 0
    /// Purchases missing a card or a charge: one field each, no statement needed.
    private(set) var completionQueue: [StoredPrediction] = []
    private(set) var reconcileQueue: [StoredPrediction] = []
    private(set) var recentPurchases: [StoredPrediction] = []
    /// One direct fetch over StoredPurchase, regardless of origin.
    private(set) var purchaseHistory: [StoredPurchase] = []
    private(set) var metrics: ExperimentMetrics?
    private(set) var homeMerchants: [StoredMerchant] = []
    private(set) var cachedLocation: CachedLocation?
    private(set) var locationDenied = false

    var lastError: FlowError?

    /// Every real purchase, regardless of whether PickMe was asked before payment. Kept as a UI
    /// read model rather than changing `PredictionLog.recentPurchases`, whose prediction-only
    /// population is still the correct denominator for experiment metrics.
    var recentPurchaseItems: [StoredPurchase] { purchaseHistory }

    func report(_ error: FlowError) { lastError = error }
    func clearError() { lastError = nil }

    /// One fetch, four answers. Calling the individual accessors here ran three unfiltered
    /// fetches per screen refresh, each walking the same rows again.
    func refresh(using graph: DependencyGraph) {
        do {
            let snapshot = try graph.service.log.snapshot()
            valueRecoveredCad = snapshot.valueRecovered.confirmedCad
            pendingValueCad = snapshot.valueRecovered.pendingCad
            completionQueue = snapshot.awaitingCompletion
            reconcileQueue = snapshot.awaitingConfirmation
            recentPurchases = snapshot.recentPurchases
            purchaseHistory = snapshot.purchaseHistory
            metrics = snapshot.metrics
            homeMerchants = sortedHomeMerchants(try graph.service.knownMerchants())
        } catch {
            report(FlowError(error))
        }
    }

    /// Supplying the till facts, without touching anything already recorded.
    func finish(_ prediction: StoredPrediction, entry: FinishEntry, using graph: DependencyGraph) {
        do {
            let purchase = try graph.service.log.recordPurchase(for: prediction,
                                                                cardUsedId: entry.cardUsedId,
                                                                cardSource: entry.cardSource,
                                                                walletEventId: entry.walletEventId)
            if let amount = entry.actualAmountCad {
                try graph.service.log.recordAmount(amount,
                                                   source: entry.amountSource ?? .recalledLater,
                                                   on: purchase)
            }
            try graph.service.assessPurchase(purchase)
            recordPatronage(purchase)
            refresh(using: graph)
        } catch {
            report(FlowError(error))
        }
    }

    /// Recording what happened. The prediction is never touched — the store offers no way to
    /// touch it — so this reads as "record what happened", not "fix the guess".
    func confirm(_ prediction: StoredPrediction, entry: ReconcileEntry, using graph: DependencyGraph) {
        do {
            let purchase = try graph.service.log.recordPurchase(for: prediction,
                                                                cardUsedId: entry.cardUsed,
                                                                cardSource: .recalledLater)
            if let amount = entry.actualAmountCad {
                try graph.service.log.recordAmount(amount, source: .recalledLater, on: purchase)
            }
            try graph.service.log.confirm(purchase,
                                          observedCategory: entry.observedCategory,
                                          observedRewardUnits: entry.observedRewardUnits,
                                          missClass: entry.missClass,
                                          note: entry.note)
            try graph.service.assessPurchase(purchase)
            recordPatronage(purchase)
            refresh(using: graph)
        } catch {
            report(FlowError(error))
        }
    }

    /// Finds shops near the owner. Returns an outcome rather than setting navigation, so the
    /// mapping to a step stays a pure function that tests can exercise.
    func findNearby(using graph: DependencyGraph) async -> FlowOutcome {
        do {
            let location = try await LocationProvider().requestLocation()
            cachedLocation = CachedLocation(latitude: location.latitude,
                                            longitude: location.longitude,
                                            capturedAt: Date())
            refresh(using: graph)
            let merchants = try await graph.provider.nearby(latitude: location.latitude,
                                                            longitude: location.longitude)
            return merchants.isEmpty ? .nothingFound(query: nil) : .found(merchants)
        } catch is LocationUnavailable {
            // Permission declined: Apple requires the manual path to stand on its own.
            locationDenied = true
            return .locationDenied
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The Apple guideline 5.1.1 fallback: carries no location bias and must work with zero
    /// location access.
    func search(_ text: String, using graph: DependencyGraph) async -> FlowOutcome {
        guard !text.isEmpty else { return .nothingFound(query: text) }
        do {
            let merchants = try await graph.provider.search(text: text)
            return merchants.isEmpty ? .nothingFound(query: text) : .found(merchants)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Scores a purchase. Returns a step directly rather than an outcome: a recommendation
    /// carries a `CheckoutResult`, which no other outcome case can hold.
    ///
    /// Ported verbatim from `CheckoutFlowView.recommend` (846-line predecessor): the Live
    /// Activity start is not incidental UI, it is the reason the owner opens the app mid-checkout
    /// at all, so the fork/single branch, headline, and advantage text must survive the move.
    ///
    /// Deliberately does not `refresh`, matching the original. The rows this writes — a
    /// prediction, an open purchase, a merchant — are all behind the recommendation screen the
    /// owner is about to see, and `RecommendationView`'s Done already refreshes on the way out.
    /// A snapshot fetch here would only add store reads to the one path where the owner is
    /// standing at a till waiting for an answer.
    func recommend(merchant: NearbyMerchant, amount: Double?,
                   using graph: DependencyGraph) -> CheckoutStep {
        do {
            let today = Date().formatted(.iso8601.year().month().day())
            let result = try graph.service.recommend(merchant: merchant,
                                                     amountCad: amount,
                                                     asOf: today)
            let (winnerCardId, headline, advantageCad, isFork): (String, String, Double?, Bool) = {
                switch result.outcome {
                case .single(let rec):
                    let returnText = String(format: "$%.2f back", rec.winner.netValueCad)
                    return (rec.winner.cardId, returnText, rec.advantageOverDefaultCad, false)
                case .fork(let branches):
                    if let first = branches.first {
                        let returnText = String(format: "$%.2f back", first.recommendation.winner.netValueCad)
                        return (first.recommendation.winner.cardId, returnText,
                                first.recommendation.advantageOverDefaultCad, true)
                    }
                    return ("", "", nil, true)
                }
            }()
            let cardName = graph.catalogue.cards.first { $0.cardId == winnerCardId }?.officialName ?? winnerCardId
            let meta = CategoryVisuals.meta(for: result.prediction.category)
            let advantageText = advantageCad.map { String(format: "+$%.2f", $0) } ?? ""
            LiveActivityManager.shared.startRecommendationActivity(
                merchantName: merchant.name,
                cardName: cardName,
                cardId: winnerCardId,
                multiplierHeadline: headline,
                advantageDescription: advantageText,
                categoryDisplayName: meta.displayName,
                categoryIcon: meta.icon,
                isFork: isFork
            )
            return .recommendation(result)
        } catch {
            report(FlowError(error))
            return .idle
        }
    }

    /// What the Apple Wallet Shortcut already answered for the checkouts still in the finish
    /// queue. Recomputed from the two published facts rather than stored, so it can never
    /// disagree with the queue it annotates — a stale proposal would offer to fill a field that
    /// was filled a moment ago.
    func captureProposals(sync: SyncCoordinator) -> [UUID: CaptureProposal] {
        Dictionary(CaptureMatcher.proposals(for: completionQueue, from: sync.walletFeedback)
                    .map { ($0.predictionId, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// This is the point of instant repeats: local row -> amount capture, with no location
    /// request and no MapKit lookup.
    func startInstantRepeat(_ merchant: StoredMerchant) -> CheckoutStep {
        .amount(NearbyMerchant(id: merchant.identifier ?? merchant.id.uuidString,
                               name: merchant.name,
                               poiCategoryRaw: merchant.poiCategoryRaw,
                               latitude: merchant.latitude,
                               longitude: merchant.longitude,
                               distanceMeters: nil))
    }

    func startInstantRepeatWithAmount(_ merchant: StoredMerchant, amount: Double,
                                      using graph: DependencyGraph) -> CheckoutStep {
        let nearby = NearbyMerchant(id: merchant.identifier ?? merchant.id.uuidString,
                                    name: merchant.name,
                                    poiCategoryRaw: merchant.poiCategoryRaw,
                                    latitude: merchant.latitude,
                                    longitude: merchant.longitude,
                                    distanceMeters: nil)
        return recommend(merchant: nearby, amount: amount, using: graph)
    }

    /// The 1-tap path: score and record in the same call, with no intermediate recommendation
    /// screen. A write failure here is an alert, not a full-screen error (Design Decision 3) —
    /// the owner is mid-checkout, not on a dedicated reconcile screen, but losing their place to
    /// report a write failure is still the wrong trade.
    func logInstantPurchase(_ merchant: StoredMerchant, amount: Double, using graph: DependencyGraph) {
        let nearby = NearbyMerchant(id: merchant.identifier ?? merchant.id.uuidString,
                                    name: merchant.name,
                                    poiCategoryRaw: merchant.poiCategoryRaw,
                                    latitude: merchant.latitude,
                                    longitude: merchant.longitude,
                                    distanceMeters: nil)
        do {
            let today = Date().formatted(.iso8601.year().month().day())
            let result = try graph.service.recommend(merchant: nearby, amountCad: amount, asOf: today)
            let winnerCardId: String = {
                switch result.outcome {
                case .single(let rec): return rec.winner.cardId
                case .fork(let branches): return branches.first?.recommendation.winner.cardId ?? ""
                }
            }()
            let allPredictions = try graph.service.log.allPredictions()
            if let stored = allPredictions.first(where: { $0.id == result.storedPredictionId }) {
                let purchase = try graph.service.log.recordPurchase(for: stored, cardUsedId: winnerCardId,
                                                                    cardSource: .atTill)
                try graph.service.log.recordAmount(amount, source: .atTill, on: purchase)
                try graph.service.assessPurchase(purchase)
                recordPatronage(purchase)
            }
            refresh(using: graph)

            let cardName = graph.catalogue.cards.first { $0.cardId == winnerCardId }?.officialName ?? winnerCardId
            let meta = CategoryVisuals.meta(for: result.prediction.category)
            LiveActivityManager.shared.startRecommendationActivity(
                merchantName: merchant.name,
                cardName: cardName,
                cardId: winnerCardId,
                multiplierHeadline: String(format: "$%.2f logged", amount),
                advantageDescription: "1-Tap Checkout",
                categoryDisplayName: meta.displayName,
                categoryIcon: meta.icon,
                isFork: false
            )
        } catch {
            report(FlowError(error))
        }
    }

    /// The prediction is never touched — the store offers no way to touch it — this corrects the
    /// statement-derived category on the purchase's observation. Silent on failure, matching the
    /// original `try?`: a mis-tapped category correction is low-stakes and the owner has no
    /// screen dedicated to it to keep them on.
    func updateCategory(for prediction: StoredPrediction, to newCategory: String, using graph: DependencyGraph) {
        try? graph.service.log.updateCategory(for: prediction, to: newCategory)
        refresh(using: graph)
    }

    /// Corrects either kind of purchase. Automatic captures keep their original machine snapshot
    /// and receive a separate owner observation; prediction-backed rows retain their existing
    /// correction stamp and experiment safeguards.
    func updateCategory(for purchase: StoredPurchase, to newCategory: String,
                        using graph: DependencyGraph) {
        do {
            try graph.service.log.updateCategory(for: purchase, to: newCategory)
            try graph.service.assessPurchase(purchase)
            refresh(using: graph)
        } catch {
            report(FlowError(error))
        }
    }

    /// Fills a missing receipt total from purchase history. Because this happens after capture,
    /// the amount is explicitly marked as recalled rather than machine-captured.
    func recordAmount(_ amount: Double, for purchase: StoredPurchase,
                      using graph: DependencyGraph) {
        do {
            try graph.service.log.recordAmount(amount, source: .recalledLater, on: purchase)
            try graph.service.assessPurchase(purchase)
            refresh(using: graph)
        } catch {
            report(FlowError(error))
        }
    }

    private func sortedHomeMerchants(_ merchants: [StoredMerchant]) -> [StoredMerchant] {
        guard let cachedLocation, cachedLocation.isRecent else {
            return merchants.sorted { $0.lastSeenAt > $1.lastSeenAt }
        }
        let origin = CLLocation(latitude: cachedLocation.latitude, longitude: cachedLocation.longitude)
        return merchants.sorted { lhs, rhs in
            let lhsDistance = origin.distance(from: CLLocation(latitude: lhs.latitude,
                                                               longitude: lhs.longitude))
            let rhsDistance = origin.distance(from: CLLocation(latitude: rhs.latitude,
                                                               longitude: rhs.longitude))
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return lhs.lastSeenAt > rhs.lastSeenAt
        }
    }

    private func recordPatronage(_ purchase: StoredPurchase) {
        guard let key = purchase.merchantKey
                ?? merchantActivityKey(name: purchase.displayMerchant,
                                       locationIdentifier: purchase.merchantIdentifier) else { return }
        MerchantPatronageStore().recordVisit(merchantKey: key,
                                             displayName: purchase.displayMerchant,
                                             at: purchase.createdAt)
    }
}
