import XCTest
import SwiftData
@testable import CardCopilotStore

/// The till moment (design §3). A purchase sits between the immutable advice and the immutable
/// statement, and holds the two facts neither of the others can honestly carry: which card was
/// actually tapped, and what the charge actually came to.
final class PurchaseRecordTests: XCTestCase {
    var container: ModelContainer!
    var log: PredictionLog!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
            StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        log = PredictionLog(context: ModelContext(container))
    }

    /// Winner earns $7.00 on a scored $140; the default card would have earned $2.80. The
    /// advantage is $4.20, i.e. 3 cents per dollar.
    private func samplePrediction(scoredAmountCad: Double? = 140) -> StoredPrediction {
        StoredPrediction(
            merchantName: "Loblaws", merchantIdentifier: "poi-123",
            predictedCategory: "grocery", confidenceSource: .brandPrior,
            winnerCardId: "amex-cobalt", winnerValueCad: 7.00,
            defaultCardValueCad: 2.80, winnerRuleId: "cobalt-eats-5x",
            runnerUpCardId: "mbna-rewards-we", runnerUpValueCad: 7.00,
            scoredAmountCad: scoredAmountCad, valuationCentsPerPoint: 1.0,
            headline: "Use American Express Cobalt Card.",
            recordedAt: Date(timeIntervalSince1970: 1_786_000_000))
    }

    // MARK: - The record itself

    func testAPurchaseStartsIncompleteWhenNeitherFactIsKnown() throws {
        let prediction = try log.record(samplePrediction())
        let purchase = try log.recordPurchase(for: prediction)
        XCTAssertNil(purchase.cardUsedId)
        XCTAssertNil(purchase.amountCad)
        XCTAssertNil(purchase.completedAt)
    }

    func testAPurchaseCompletesOnlyOnceBothFactsAreKnown() throws {
        let prediction = try log.record(samplePrediction())
        let purchase = try log.recordPurchase(for: prediction, cardUsedId: "amex-cobalt",
                                              cardSource: .atTill)
        XCTAssertNil(purchase.completedAt, "a card without an amount is not a complete purchase")

        try log.recordAmount(47.83, source: .atTill, on: purchase)
        XCTAssertNotNil(purchase.completedAt)
        XCTAssertEqual(purchase.amountCad, 47.83)
    }

    /// Provenance is per-field because the two facts arrive by different routes at different
    /// times — a card tapped from the lock screen, an amount typed a week later at reconcile.
    func testCardAndAmountCarryTheirOwnProvenance() throws {
        let prediction = try log.record(samplePrediction())
        let purchase = try log.recordPurchase(for: prediction, cardUsedId: "amex-cobalt",
                                              cardSource: .atTill)
        try log.recordAmount(47.83, source: .recalledLater, on: purchase)
        XCTAssertEqual(purchase.cardSource, .atTill)
        XCTAssertEqual(purchase.amountSource, .recalledLater)
    }

    func testAPredictionHasAtMostOnePurchase() throws {
        let prediction = try log.record(samplePrediction())
        let first = try log.recordPurchase(for: prediction, cardUsedId: "amex-cobalt",
                                           cardSource: .atTill)
        let second = try log.recordPurchase(for: prediction)
        XCTAssertEqual(first.id, second.id, "a second call must return the existing record")
        XCTAssertEqual(second.cardUsedId, "amex-cobalt", "and must not erase what it already held")
    }

    // MARK: - Value recovered

    /// THE BUG THIS MODEL EXISTS TO FIX. Value recovered means "I earned more *because* I took
    /// the advice." Today's implementation never checks which card was tapped, so ignoring the
    /// recommendation and paying with the default card still credits the full advantage.
    func testIgnoringTheAdviceRecoversNothing() throws {
        let prediction = try log.record(samplePrediction())
        let purchase = try log.recordPurchase(for: prediction, cardUsedId: "wealthsimple-vip",
                                              cardSource: .atTill)
        try log.recordAmount(140, source: .atTill, on: purchase)
        try log.confirm(purchase, observedCategory: "grocery", missClass: nil, note: nil)

        XCTAssertEqual(try log.valueRecovered().confirmedCad, 0, accuracy: 0.001)
    }

    func testFollowingTheAdviceRecoversTheAdvantage() throws {
        let prediction = try log.record(samplePrediction())
        let purchase = try log.recordPurchase(for: prediction, cardUsedId: "amex-cobalt",
                                              cardSource: .atTill)
        try log.recordAmount(140, source: .atTill, on: purchase)
        try log.confirm(purchase, observedCategory: "grocery", missClass: nil, note: nil)

        XCTAssertEqual(try log.valueRecovered().confirmedCad, 4.20, accuracy: 0.001)
    }

    /// The scoreboard must be built on what was charged, not on the preset the owner tapped
    /// before paying. Half the scored amount recovers half the advantage.
    func testTheActualChargeScalesTheAdvantageRatherThanTheEstimate() throws {
        let prediction = try log.record(samplePrediction(scoredAmountCad: 140))
        let purchase = try log.recordPurchase(for: prediction, cardUsedId: "amex-cobalt",
                                              cardSource: .atTill)
        try log.recordAmount(70, source: .atTill, on: purchase)
        try log.confirm(purchase, observedCategory: "grocery", missClass: nil, note: nil)

        XCTAssertEqual(try log.valueRecovered().confirmedCad, 2.10, accuracy: 0.001)
    }

    /// An advice-time figure anchored to a category estimate cannot be rescaled to a real
    /// charge — there is no per-dollar advantage to scale. Excluded rather than guessed at.
    func testAPredictionScoredAgainstAnEstimateIsExcluded() throws {
        let prediction = try log.record(samplePrediction(scoredAmountCad: nil))
        let purchase = try log.recordPurchase(for: prediction, cardUsedId: "amex-cobalt",
                                              cardSource: .atTill)
        try log.recordAmount(140, source: .atTill, on: purchase)
        try log.confirm(purchase, observedCategory: "grocery", missClass: nil, note: nil)

        XCTAssertEqual(try log.valueRecovered().confirmedCad, 0, accuracy: 0.001)
    }

    /// Reconciled and unreconciled value are reported separately. Requiring a statement for the
    /// headline figure is the honest reading; holding the scoreboard at $0 for weeks would be a
    /// bad incentive on a feature whose whole job is getting purchases logged.
    func testUnreconciledPurchasesCountAsPendingRatherThanConfirmed() throws {
        let prediction = try log.record(samplePrediction())
        let purchase = try log.recordPurchase(for: prediction, cardUsedId: "amex-cobalt",
                                              cardSource: .atTill)
        try log.recordAmount(140, source: .atTill, on: purchase)

        let recovered = try log.valueRecovered()
        XCTAssertEqual(recovered.confirmedCad, 0, accuracy: 0.001)
        XCTAssertEqual(recovered.pendingCad, 4.20, accuracy: 0.001)
    }

    // MARK: - Queues

    func testAPurchaseMissingAFactAwaitsCompletionRatherThanReconciliation() throws {
        let prediction = try log.record(samplePrediction())
        _ = try log.recordPurchase(for: prediction, cardUsedId: "amex-cobalt", cardSource: .atTill)

        XCTAssertEqual(try log.awaitingCompletion().count, 1)
        XCTAssertEqual(try log.awaitingConfirmation().count, 0,
                       "an incomplete purchase cannot be checked against a statement yet")
    }

    func testACompletePurchaseAwaitsReconciliationRatherThanCompletion() throws {
        let prediction = try log.record(samplePrediction())
        let purchase = try log.recordPurchase(for: prediction, cardUsedId: "amex-cobalt",
                                              cardSource: .atTill)
        try log.recordAmount(140, source: .atTill, on: purchase)

        XCTAssertEqual(try log.awaitingCompletion().count, 0)
        XCTAssertEqual(try log.awaitingConfirmation().count, 1)
    }
}
