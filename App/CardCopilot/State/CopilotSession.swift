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

    init(_ fix: CheckoutLocationFix) {
        latitude = fix.latitude
        longitude = fix.longitude
        capturedAt = fix.capturedAt
    }
}

enum NearbyPreparationState: Equatable {
    case idle
    case permissionRequired
    case preparing
    case ready(merchantCount: Int)
    case unavailable
}

private enum NearbyLookupFailure: LocalizedError {
    case nearbyTimedOut
    case searchTimedOut

    var errorDescription: String? {
        switch self {
        case .nearbyTimedOut: return "Nearby merchants took too long to respond."
        case .searchTimedOut: return "Merchant search took too long to respond."
        }
    }
}

/// A MapKit result and the exact fix it was queried around. Time alone cannot validate this
/// cache: every foreground preflight compares a new fix with this origin before reusing it.
private struct NearbySnapshot {
    let outcome: FlowOutcome
    let location: CheckoutLocationFix
    let fetchedAt: Date

    var isRecent: Bool {
        Date().timeIntervalSince(fetchedAt) < 60
    }

    func canReuse(at fix: CheckoutLocationFix) -> Bool {
        guard isRecent,
              location.horizontalAccuracyMeters <= 100,
              fix.horizontalAccuracyMeters <= 100 else { return false }
        let accuracyAllowance = min(100, max(50,
            (location.horizontalAccuracyMeters + fix.horizontalAccuracyMeters) / 2))
        return fix.distance(from: location) <= accuracyAllowance
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
    private(set) var nearbyPreparationState: NearbyPreparationState = .idle
    private(set) var nearbyMetrics: NearbyLookupMetrics

    private let locationProvider: any CheckoutLocationProviding
    private let nearbyMetricsStore: NearbyLookupMetricsStore
    private var nearbySnapshot: NearbySnapshot?
    private var preparedNearbyOutcome: FlowOutcome?
    private var preparedLocationFix: CheckoutLocationFix?
    private var nearbyPreparationTask: Task<FlowOutcome?, Never>?
    private var nearbyExpiryTask: Task<Void, Never>?
    private var nearbyPreparationGeneration = 0

    var lastError: FlowError?

    init() {
        let metricsStore = NearbyLookupMetricsStore()
        locationProvider = LocationProvider()
        nearbyMetricsStore = metricsStore
        nearbyMetrics = metricsStore.snapshot
    }

    init(locationProvider: any CheckoutLocationProviding,
         nearbyMetricsStore: NearbyLookupMetricsStore) {
        self.locationProvider = locationProvider
        self.nearbyMetricsStore = nearbyMetricsStore
        nearbyMetrics = nearbyMetricsStore.snapshot
    }

    /// Every real purchase, regardless of whether PickMe was asked before payment. Kept as a UI
    /// read model rather than changing `PredictionLog.recentPurchases`, whose prediction-only
    /// population is still the correct denominator for experiment metrics.
    var recentPurchaseItems: [StoredPurchase] { purchaseHistory }

    func report(_ error: FlowError) { lastError = error }
    func clearError() { lastError = nil }

    func forgetNearbyHistory() {
        nearbyPreparationGeneration &+= 1
        nearbyPreparationTask?.cancel()
        nearbyPreparationTask = nil
        nearbyExpiryTask?.cancel()
        nearbyExpiryTask = nil
        nearbySnapshot = nil
        preparedNearbyOutcome = nil
        preparedLocationFix = nil
        cachedLocation = nil
        nearbyPreparationState = .idle
        nearbyMetricsStore.forgetAll()
        nearbyMetrics = NearbyLookupMetrics()
    }

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

    var preparedNearestMerchant: NearbyMerchant? {
        guard nearbySnapshot?.isRecent == true,
              case .ready = nearbyPreparationState,
              case .found(let merchants) = preparedNearbyOutcome else { return nil }
        return merchants.first
    }

    /// A direct shortcut is offered only when the fix itself is reasonably accurate, the first
    /// result is close, and the runner-up is far enough away not to describe a crowded plaza.
    var confidentPreparedMerchant: NearbyMerchant? {
        guard let fix = preparedLocationFix,
              fix.horizontalAccuracyMeters <= 100,
              case .found(let merchants) = preparedNearbyOutcome,
              let first = merchants.first,
              let firstDistance = first.distanceMeters,
              firstDistance <= 100 else { return nil }
        guard merchants.count > 1 else { return first }
        guard let secondDistance = merchants[1].distanceMeters,
              secondDistance - firstDistance >= 60 else { return nil }
        return first
    }

    /// Returns the already prepared result synchronously and records a zero-wait Radar tap. The
    /// view uses this before entering a loading state, eliminating the cache-hit spinner flash.
    func preparedOutcomeForTap() -> FlowOutcome? {
        guard nearbySnapshot?.isRecent == true,
              case .ready = nearbyPreparationState,
              let preparedNearbyOutcome else { return nil }
        recordNearbyMetric(.tap(prepared: true, durationMilliseconds: 0))
        return preparedNearbyOutcome
    }

    /// Warms both the one-shot fix and MapKit results as soon as the app becomes active. This
    /// never asks for new permission: first-time owners still make that choice by tapping Radar.
    /// A shared task lets a tap join an in-flight launch lookup instead of starting a duplicate.
    func prefetchNearby(using graph: DependencyGraph) async {
        if let existing = nearbyPreparationTask {
            _ = await existing.value
            return
        }

        nearbyPreparationState = .preparing
        recordNearbyMetric(.prefetchAttempt)
        let generation = nearbyPreparationGeneration
        let task: Task<FlowOutcome?, Never> = Task { @MainActor [weak self] in
            guard let self else { return nil }
            return await self.loadNearby(promptForAuthorization: false, using: graph,
                                         generation: generation)
        }
        nearbyPreparationTask = task
        _ = await task.value
        if nearbyPreparationGeneration == generation {
            nearbyPreparationTask = nil
        }
    }

    /// Finds shops near the owner. A fresh launch prefetch returns immediately; an in-flight one
    /// is awaited. Only a first-use miss takes the permission-and-fetch path.
    func findNearby(using graph: DependencyGraph) async -> FlowOutcome {
        let started = ContinuousClock.now
        if let outcome = preparedOutcomeForTap() { return outcome }
        if let preparation = nearbyPreparationTask {
            let preparationGeneration = nearbyPreparationGeneration
            if let outcome = await preparation.value {
                if nearbyPreparationGeneration == preparationGeneration {
                    recordTapLatency(since: started, prepared: true)
                }
                return outcome
            }
            guard nearbyPreparationGeneration == preparationGeneration else {
                return await findNearby(using: graph)
            }
            // A best-effort launch prefetch can finish without a result (for example, before
            // permission has been granted). Clear that completed miss before starting the
            // owner-requested permission path below.
            nearbyPreparationTask = nil
        }
        nearbyPreparationState = .preparing
        let generation = nearbyPreparationGeneration
        let task: Task<FlowOutcome?, Never> = Task { @MainActor [weak self] in
            guard let self else { return nil }
            return await self.loadNearby(promptForAuthorization: true, using: graph,
                                         generation: generation)
        }
        nearbyPreparationTask = task
        let outcome = await task.value ?? .failed("Location is temporarily unavailable.")
        if nearbyPreparationGeneration == generation {
            nearbyPreparationTask = nil
            recordTapLatency(since: started, prepared: false)
        }
        return outcome
    }

    private func loadNearby(promptForAuthorization: Bool,
                            using graph: DependencyGraph,
                            generation: Int) async -> FlowOutcome? {
        do {
            let fix: CheckoutLocationFix
            if promptForAuthorization {
                fix = try await locationProvider.requestLocation()
            } else {
                guard let authorizedFix = try await locationProvider.requestLocationIfAuthorized()
                else {
                    guard generation == nearbyPreparationGeneration else { return nil }
                    preparedNearbyOutcome = nil
                    preparedLocationFix = nil
                    nearbyPreparationState = .permissionRequired
                    return nil
                }
                fix = authorizedFix
            }

            guard generation == nearbyPreparationGeneration else { return nil }
            locationDenied = false
            cachedLocation = CachedLocation(fix)
            refresh(using: graph)

            if let snapshot = nearbySnapshot, snapshot.canReuse(at: fix) {
                let outcome = rebase(snapshot.outcome, around: fix)
                publishPrepared(outcome, fix: fix)
                recordNearbyMetric(.movementCacheHit)
                return outcome
            }

            let merchants = rankNearbyMerchants(try await nearbyMerchants(
                latitude: fix.latitude, longitude: fix.longitude, using: graph.provider))
            guard generation == nearbyPreparationGeneration else { return nil }
            let outcome: FlowOutcome = merchants.isEmpty
                ? .nothingFound(query: nil)
                : .found(merchants)
            if merchants.isEmpty { recordNearbyMetric(.emptyResult) }
            nearbySnapshot = NearbySnapshot(outcome: outcome, location: fix, fetchedAt: Date())
            publishPrepared(outcome, fix: fix)
            return outcome
        } catch let unavailable as LocationUnavailable {
            guard generation == nearbyPreparationGeneration else { return nil }
            switch unavailable {
            case .permissionDenied, .permissionRestricted:
                locationDenied = true
                nearbyPreparationState = .permissionRequired
                return .locationDenied
            case .timedOut:
                recordNearbyMetric(.locationTimeout)
                nearbyPreparationState = .unavailable
                return promptForAuthorization ? .failed(unavailable.localizedDescription) : nil
            case .fixFailed:
                recordNearbyMetric(.failure)
                nearbyPreparationState = .unavailable
                return promptForAuthorization ? .failed(unavailable.localizedDescription) : nil
            }
        } catch is NearbyLookupFailure {
            guard generation == nearbyPreparationGeneration else { return nil }
            recordNearbyMetric(.merchantTimeout)
            nearbyPreparationState = .unavailable
            return promptForAuthorization
                ? .failed(NearbyLookupFailure.nearbyTimedOut.localizedDescription) : nil
        } catch {
            guard generation == nearbyPreparationGeneration else { return nil }
            // Background prefetch is best effort. A tap retries instead of surfacing an error
            // caused before the owner asked for nearby results.
            recordNearbyMetric(.failure)
            nearbyPreparationState = .unavailable
            return promptForAuthorization ? .failed(error.localizedDescription) : nil
        }
    }

    private func nearbyMerchants(latitude: Double, longitude: Double,
                                 using provider: any MerchantProviding) async throws -> [NearbyMerchant] {
        try await withThrowingTaskGroup(of: [NearbyMerchant].self) { group in
            group.addTask {
                try await provider.nearby(latitude: latitude, longitude: longitude)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(4))
                throw NearbyLookupFailure.nearbyTimedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw NearbyLookupFailure.nearbyTimedOut
            }
            return result
        }
    }

    private func publishPrepared(_ outcome: FlowOutcome, fix: CheckoutLocationFix) {
        preparedNearbyOutcome = outcome
        preparedLocationFix = fix
        let count = if case .found(let merchants) = outcome { merchants.count } else { 0 }
        nearbyPreparationState = .ready(merchantCount: count)
        schedulePreparedExpiry()
    }

    private func schedulePreparedExpiry() {
        nearbyExpiryTask?.cancel()
        guard let fetchedAt = nearbySnapshot?.fetchedAt else { return }
        let remaining = max(0, 60 - Date().timeIntervalSince(fetchedAt))
        nearbyExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled,
                  self?.nearbySnapshot?.fetchedAt == fetchedAt else { return }
            self?.preparedNearbyOutcome = nil
            self?.preparedLocationFix = nil
            self?.nearbyPreparationState = .idle
        }
    }

    private func rebase(_ outcome: FlowOutcome, around fix: CheckoutLocationFix) -> FlowOutcome {
        guard case .found(let merchants) = outcome else { return outcome }
        let origin = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
        let rebased = merchants.map { merchant in
            NearbyMerchant(
                id: merchant.id, name: merchant.name, poiCategoryRaw: merchant.poiCategoryRaw,
                latitude: merchant.latitude, longitude: merchant.longitude,
                distanceMeters: origin.distance(from: CLLocation(latitude: merchant.latitude,
                                                                  longitude: merchant.longitude)))
        }
        return .found(rankNearbyMerchants(rebased))
    }

    private func recordTapLatency(since start: ContinuousClock.Instant, prepared: Bool) {
        let duration = start.duration(to: .now)
        let milliseconds = Int(duration.components.seconds * 1_000)
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
        recordNearbyMetric(.tap(prepared: prepared, durationMilliseconds: milliseconds))
    }

    private func recordNearbyMetric(_ event: NearbyLookupMetricsStore.Event) {
        nearbyMetricsStore.record(event)
        nearbyMetrics = nearbyMetricsStore.snapshot
    }

    private func searchMerchants(_ text: String,
                                 using provider: any MerchantProviding) async throws -> [NearbyMerchant] {
        try await withThrowingTaskGroup(of: [NearbyMerchant].self) { group in
            group.addTask { try await provider.search(text: text) }
            group.addTask {
                try await Task.sleep(for: .seconds(4))
                throw NearbyLookupFailure.searchTimedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw NearbyLookupFailure.searchTimedOut
            }
            return result
        }
    }

    /// The Apple guideline 5.1.1 fallback: carries no location bias and must work with zero
    /// location access.
    func search(_ text: String, using graph: DependencyGraph) async -> FlowOutcome {
        guard !text.isEmpty else { return .nothingFound(query: text) }
        do {
            let merchants = try await searchMerchants(text, using: graph.provider)
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

    /// Refines an already-shown answer at a new amount — `AmountRefineRow` on the recommendation
    /// screen, still before the owner has tapped Pay. Deliberately does not call `recommend`
    /// again: that persists a fresh `StoredPrediction` and opens a second purchase, so this
    /// re-scores in memory via `rescoreCheckout` and only ever updates the ORIGINAL prediction's
    /// `scoredAmountCad`. Returns nil (leaving the prior result on screen) if the engine cannot
    /// advise at the new amount, or if refining fails outright.
    func refine(_ result: CheckoutResult, amountCad: Double, using graph: DependencyGraph) -> CheckoutResult? {
        let today = Date().formatted(.iso8601.year().month().day())
        guard let refined = rescoreCheckout(result, amountCad: amountCad, engine: graph.engine, asOf: today)
        else { return nil }
        do {
            try graph.service.log.recordScoredAmount(amountCad, forPredictionId: result.storedPredictionId)
        } catch {
            report(FlowError(error))
        }
        return refined
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

    /// Records the amount charged for a purchase and re-evaluates card assessment.
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

    /// Records the card used for a purchase and re-evaluates card assessment.
    func recordCard(_ cardUsedId: String?, for purchase: StoredPurchase,
                    using graph: DependencyGraph) {
        do {
            try graph.service.log.recordCard(cardUsedId, source: .recalledLater, on: purchase)
            try graph.service.assessPurchase(purchase)
            refresh(using: graph)
        } catch {
            report(FlowError(error))
        }
    }

    /// Deletes a purchase record from history.
    func deletePurchase(_ purchase: StoredPurchase, using graph: DependencyGraph) {
        do {
            try graph.service.log.deletePurchase(purchase)
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
