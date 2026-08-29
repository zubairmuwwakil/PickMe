import XCTest
import SwiftData
@testable import CardCopilotStore

/// Logging a Wallet capture with no live checkout behind it (design §8, Path B — the automatic
/// case `CaptureMatcher`'s `CaptureProposal` deliberately leaves for the owner to fill in by hand).
///
/// The property every test here ultimately protects: a purchase this type writes has NO
/// `StoredPrediction`, so it can never become a data point in the Experiment Scoreboard's accuracy
/// figure. That figure is a predicate over graded advice; an auto-logged purchase was never
/// advised on, and must stay invisible to every accessor that measures that.
final class AutoCaptureLogTests: XCTestCase {
    var container: ModelContainer!
    var predictionLog: PredictionLog!
    var autoLog: AutoCaptureLog!

    /// 2026-08-19T12:00:00Z, matching `CaptureMatcherTests`' fixed noon.
    private let noon = Date(timeIntervalSince1970: 1_787_140_800)

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
            StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        predictionLog = PredictionLog(context: context)
        autoLog = AutoCaptureLog(context: context)
    }

    private func openPrediction(merchant: String = "Starbucks", at recordedAt: Date? = nil) throws -> StoredPrediction {
        let stored = try predictionLog.record(StoredPrediction(
            merchantName: merchant, merchantIdentifier: "poi-\(merchant)",
            predictedCategory: "dining", confidenceSource: .brandPrior,
            winnerCardId: "amex-cobalt", winnerValueCad: 0.32,
            scoredAmountCad: 6.00, headline: "Use American Express Cobalt Card.",
            recordedAt: recordedAt ?? noon))
        _ = try predictionLog.recordPurchase(for: stored, at: recordedAt ?? noon)
        return stored
    }

    private func tap(eventId: String = "evt-1", merchant: String = "Tim Hortons",
                     amountMinor: Int? = 419, currency: String? = "CAD",
                     resolvedCardId: String? = "amex-cobalt",
                     latitude: Double? = nil, longitude: Double? = nil,
                     at capturedAt: Date? = nil) -> WalletFeedback {
        WalletFeedback(eventId: eventId, capturedAt: capturedAt ?? noon,
                      merchantRaw: nil, merchantNormalized: merchant,
                      amountMinor: amountMinor, currency: currency,
                      cardRaw: "American Express Cobalt", resolvedCardId: resolvedCardId,
                      verdict: "best", warning: nil,
                      latitude: latitude, longitude: longitude)
    }

    // MARK: - The core behaviour

    func testATapWithNoOpenCheckoutIsLoggedAsAPurchase() throws {
        let written = try autoLog.ingest(feedback: [tap()], openPredictions: [])

        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written[0].displayMerchant, "Tim Hortons")
        XCTAssertEqual(written[0].amountCad, 4.19)
        XCTAssertEqual(written[0].cardUsedId, "amex-cobalt")
        XCTAssertEqual(written[0].cardSource, .walletCapture)
        XCTAssertEqual(written[0].amountSource, .walletCapture)
        XCTAssertTrue(written[0].isComplete)
        XCTAssertTrue(written[0].isAutoLogged)
    }

    func testATapThatMatchesAnOpenCheckoutIsNotLoggedHere() throws {
        let stored = try openPrediction(merchant: "Tim Hortons")

        let written = try autoLog.ingest(feedback: [tap(merchant: "Tim Hortons")], openPredictions: [stored])

        XCTAssertTrue(written.isEmpty, "this belongs to Finish Purchases, not a standalone log entry")
    }

    func testReSyncingTheSameFeedbackNeverDoubleLogs() throws {
        let feedback = [tap()]
        try autoLog.ingest(feedback: feedback, openPredictions: [])
        let second = try autoLog.ingest(feedback: feedback, openPredictions: [])

        XCTAssertTrue(second.isEmpty, "the event was already logged")
        XCTAssertEqual(try autoLog.recent().count, 1)
    }

    func testReSyncBackfillsLocationOnAnOlderPurchaseWithoutLoggingADuplicate() throws {
        let purchase = try XCTUnwrap(autoLog.ingest(
            feedback: [tap(eventId: "evt-old")], openPredictions: []).first)
        XCTAssertNil(purchase.merchantLatitude)
        XCTAssertNil(purchase.merchantLongitude)

        let second = try autoLog.ingest(
            feedback: [tap(eventId: "evt-old", latitude: 43.8501, longitude: -79.0202)],
            openPredictions: [])

        XCTAssertTrue(second.isEmpty, "hydrating an existing event must not create another purchase")
        XCTAssertEqual(purchase.merchantLatitude, 43.8501)
        XCTAssertEqual(purchase.merchantLongitude, -79.0202)
        XCTAssertEqual(try autoLog.recent().count, 1)
    }

    func testReSyncNeverOverwritesALocationAlreadyStoredOnThePurchase() throws {
        let purchase = try XCTUnwrap(autoLog.ingest(
            feedback: [tap(eventId: "evt-1", latitude: 43.85, longitude: -79.02)],
            openPredictions: []).first)

        _ = try autoLog.ingest(
            feedback: [tap(eventId: "evt-1", latitude: 45.42, longitude: -75.69)],
            openPredictions: [])

        XCTAssertEqual(purchase.merchantLatitude, 43.85)
        XCTAssertEqual(purchase.merchantLongitude, -79.02)
    }

    func testOwnerCategoryCorrectionTeachesTheNextCaptureAtTheSameLocalMerchant() throws {
        let first = try XCTUnwrap(autoLog.ingest(
            feedback: [tap(eventId: "evt-1", merchant: "Mom's Kitchen (Ajax)")],
            openPredictions: []).first)
        XCTAssertNil(first.displayCategory)

        try predictionLog.updateCategory(for: first, to: "dining")
        let second = try XCTUnwrap(autoLog.ingest(
            feedback: [tap(eventId: "evt-2", merchant: "Mom's Kitchen (Ajax)")],
            openPredictions: []).first)

        XCTAssertEqual(second.displayCategory, "dining")
        XCTAssertEqual(second.categoryConfidence, .ownerConfirmedTerminal)
    }

    func testATapAcceptedIntoAnExistingCheckoutIsNeverAlsoAutoLoggedLater() throws {
        // Simulates the timeline: first sync sees the tap matching an open checkout, so it is
        // withheld from auto-logging. The owner then accepts it in Finish Purchases — exactly like
        // `FinishPurchaseView.acceptance(of:)`, which is what stamps `walletEventId` here — and the
        // checkout completes. A later sync must not treat the now-complete prediction's tap as
        // orphaned just because it dropped out of the open set.
        let stored = try openPrediction(merchant: "Tim Hortons")
        let event = tap(merchant: "Tim Hortons")
        XCTAssertTrue(try autoLog.ingest(feedback: [event], openPredictions: [stored]).isEmpty)

        _ = try predictionLog.recordPurchase(for: stored, cardUsedId: "amex-cobalt",
                                             cardSource: .walletCapture, walletEventId: event.eventId)
        try predictionLog.recordAmount(4.19, source: .walletCapture, on: stored.purchase!)

        // The prediction is complete now, so it drops out of `openPredictions` on the next sync —
        // exactly the scenario `unclaimedCaptures` would otherwise see as an orphaned tap.
        let secondSync = try autoLog.ingest(feedback: [event], openPredictions: [])
        XCTAssertTrue(secondSync.isEmpty,
                     "a tap already represented by the checkout's own purchase must not be logged again")
    }

    // MARK: - Honest completeness

    func testAForeignCurrencyTapIsLoggedIncompleteRatherThanGuessed() throws {
        let written = try autoLog.ingest(feedback: [tap(currency: "USD")], openPredictions: [])

        XCTAssertEqual(written.first?.cardUsedId, "amex-cobalt")
        XCTAssertNil(written.first?.amountCad, "converting USD here would invent an FX rate")
        XCTAssertFalse(written.first?.isComplete ?? true)
        XCTAssertEqual(written.first?.missingFacts, [.amount])
    }

    func testAnUnresolvedCardIsLoggedIncompleteRatherThanGuessed() throws {
        let written = try autoLog.ingest(feedback: [tap(resolvedCardId: nil)], openPredictions: [])

        XCTAssertEqual(written.first?.amountCad, 4.19)
        XCTAssertNil(written.first?.cardUsedId)
        XCTAssertEqual(written.first?.missingFacts, [.card])
    }

    // MARK: - recent()

    func testRecentOrdersNewestFirst() throws {
        _ = try autoLog.ingest(feedback: [tap(eventId: "evt-1", at: noon)], openPredictions: [])
        _ = try autoLog.ingest(feedback: [tap(eventId: "evt-2", at: noon.addingTimeInterval(3600))],
                               openPredictions: [])

        let recent = try autoLog.recent()
        XCTAssertEqual(recent.map(\.walletEventId), ["evt-2", "evt-1"])
    }

    /// The bug this guards against: `recent()` used to filter on `walletEventId != nil`, which
    /// also matches a checkout-originated purchase once its owner accepts a `CaptureProposal` —
    /// putting a purchase with a REAL graded prediction behind it into the "Logged from Card Taps"
    /// section, where `ActivityHubView` renders it with no category badge and no tap-to-edit.
    func testRecentExcludesACheckoutPurchaseThatMerelyCarriesAWalletEventId() throws {
        let stored = try openPrediction(merchant: "Tim Hortons")
        _ = try predictionLog.recordPurchase(for: stored, cardUsedId: "amex-cobalt",
                                             cardSource: .walletCapture, walletEventId: "evt-1")
        try predictionLog.recordAmount(4.19, source: .walletCapture, on: stored.purchase!)

        _ = try autoLog.ingest(feedback: [tap(eventId: "evt-2", merchant: "Loblaws")],
                               openPredictions: [])

        let recent = try autoLog.recent()
        XCTAssertEqual(recent.map(\.walletEventId), ["evt-2"],
                       "the checkout's own purchase carries a walletEventId too, but has a prediction and does not belong here")
    }

    // MARK: - Isolation from the graded-prediction population

    /// The property this whole type exists to protect: an auto-logged purchase never enters
    /// `PredictionLog`'s own accessors, because every one of them starts from `StoredPrediction`
    /// and this purchase has none. If this test ever fails, `AutoCaptureLog` has started feeding
    /// the Experiment Scoreboard's accuracy figure a data point that was never graded advice.
    func testAnAutoLoggedPurchaseNeverAppearsInAnyPredictionLogAccessor() throws {
        _ = try autoLog.ingest(feedback: [tap()], openPredictions: [])

        let snapshot = try predictionLog.snapshot()
        XCTAssertTrue(snapshot.recentPurchases.isEmpty)
        XCTAssertTrue(snapshot.awaitingCompletion.isEmpty)
        XCTAssertTrue(snapshot.awaitingConfirmation.isEmpty)
        XCTAssertEqual(snapshot.metrics.confirmedCount, 0)
        XCTAssertEqual(snapshot.valueRecovered.confirmedCad, 0)
        XCTAssertEqual(snapshot.valueRecovered.pendingCad, 0)
    }

    /// The other direction: logging a capture must never disturb a checkout-originated purchase
    /// that happens to sit alongside it.
    func testAutoLoggingDoesNotAffectAnUnrelatedOpenCheckout() throws {
        let stored = try openPrediction(merchant: "Loblaws")

        _ = try autoLog.ingest(feedback: [tap(merchant: "Tim Hortons")], openPredictions: [stored])

        let snapshot = try predictionLog.snapshot()
        XCTAssertEqual(snapshot.awaitingCompletion.map(\.id), [stored.id])
    }
}
