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
    private func loggedEventIds() throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<StoredPurchase>()).compactMap(\.walletEventId))
    }

    /// Logs every capture from `feedback` that matches no open prediction and has not already been
    /// logged, and returns the rows written. Safe to call on every sync: idempotent by
    /// `walletEventId`, and a no-op when there is nothing new to log.
    @discardableResult
    public func ingest(feedback: [WalletFeedback], openPredictions: [StoredPrediction]) throws -> [StoredPurchase] {
        let alreadyLogged = try loggedEventIds()
        let candidates = CaptureMatcher.unclaimedCaptures(from: feedback, openPredictions: openPredictions)
            .filter { !alreadyLogged.contains($0.eventId) }
        return try candidates.map(record)
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
        let purchase = StoredPurchase(createdAt: capture.capturedAt,
                                      merchantLabel: capture.merchant,
                                      walletEventId: capture.eventId)
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
        try context.save()
        return purchase
    }
}
