import Foundation
import Observation
import CoreLocation
import CardCopilotStore

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
    private(set) var metrics: ExperimentMetrics?
    private(set) var homeMerchants: [StoredMerchant] = []
    private(set) var cachedLocation: CachedLocation?
    private(set) var locationDenied = false

    var lastError: FlowError?

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
                                                                cardSource: entry.cardSource)
            if let amount = entry.actualAmountCad {
                try graph.service.log.recordAmount(amount,
                                                   source: entry.amountSource ?? .recalledLater,
                                                   on: purchase)
            }
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
            refresh(using: graph)
        } catch {
            report(FlowError(error))
        }
    }

    func noteLocationDenied() { locationDenied = true }

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

    // Set by the flow operations in Task 6.
    fileprivate func setCachedLocation(_ location: CachedLocation?) { cachedLocation = location }
}
