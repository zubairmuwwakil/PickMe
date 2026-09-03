import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

/// The metrics an export exists to produce, against fixtures. No real coordinates and no device
/// data: every arrival below is a synthetic plaza on a meridian.
final class ArrivalFieldMetricsTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let threshold = SwitchThreshold(minAdvantagePercentagePoints: 0.5,
                                            minAdvantageCad: 0.25, semantics: "both")

    private func candidate(_ name: String, metresNorth: Double, category: String = "drugStore",
                           card: String?) -> ArrivalCandidateRecord {
        ArrivalCandidateRecord(name: name, poiCategoryRaw: nil,
                               latitude: 45 + metresNorth / 111_000, longitude: -75,
                               distanceFromFixMeters: metresNorth, recognisedByPack: true,
                               resolvedCategory: category, confidence: .brandMatched,
                               recommendedCardId: card, advantageOverDefaultCad: 0.5)
    }

    private func record(at offset: TimeInterval = 0,
                        candidates: [ArrivalCandidateRecord],
                        chosen: Int?,
                        advantage: AmbientAdvantage = AmbientAdvantage(percentagePoints: 1.5,
                                                                       cad: 0.375),
                        estimate: Double = 25,
                        reasons: [AmbientSuppressionReason] = [.advantageBelowUnverifiedThreshold])
    -> ArrivalFieldRecord {
        let input = AmbientGateInput(merchantConfidence: .brandMatched,
                                     recommendedCardId: "amex-cobalt",
                                     defaultCardId: "wealthsimple-vip",
                                     advantage: advantage, switchThreshold: threshold,
                                     isMuted: false)
        return ArrivalFieldRecord(
            recordedAt: epoch.addingTimeInterval(offset), regionId: "ambient.region.area:1",
            source: .regionEntry, candidates: candidates, chosenCandidateIndex: chosen,
            rung: .areaMember,
            resolvedMerchantName: chosen.map { candidates[$0].name } ?? "",
            resolvedCategory: "drugStore", estimatedAmountCad: estimate,
            gateInput: input,
            deliveryTier: AmbientGateDecision(suppressionReasons: Set(reasons)).tier,
            suppressionReasons: reasons, policy: .shipped)
    }

    private func receipt(_ descriptor: String, amount: Double = 33.90,
                         offset: TimeInterval = 600) -> ArrivalReceipt {
        ArrivalReceipt(merchantDescriptor: descriptor, amountCad: amount,
                       capturedAt: epoch.addingTimeInterval(offset))
    }

    // MARK: - The join

    func testAReceiptInsideTheWindowJoinsTheArrivalAndNamesTheTrueStore() throws {
        let candidates = [candidate("Dollarama", metresNorth: 20, card: "amex-cobalt"),
                          candidate("Shoppers Drug Mart", metresNorth: 90, card: "amex-cobalt")]
        let joined = joinReceipts([record(candidates: candidates, chosen: 0)],
                                  receipts: [receipt("SHOPPERS DRUG MART #1234")])
        XCTAssertEqual(joined[0].receipt?.amountCad, 33.90)
        XCTAssertEqual(joined[0].receiptCandidateIndex, 1)
    }

    /// Ninety minutes is the window. A charge that lands the next morning is a different trip,
    /// and joining it would invent an accuracy figure out of a coincidence.
    func testAReceiptOutsideTheWindowDoesNotJoin() {
        let candidates = [candidate("Shoppers Drug Mart", metresNorth: 20, card: "amex-cobalt")]
        let joined = joinReceipts([record(candidates: candidates, chosen: 0)],
                                  receipts: [receipt("SHOPPERS DRUG MART", offset: 91 * 60)])
        XCTAssertNil(joined[0].receipt)
    }

    /// A charge cannot precede the arrival that produced it.
    func testAReceiptBeforeTheArrivalDoesNotJoin() {
        let candidates = [candidate("Shoppers Drug Mart", metresNorth: 20, card: "amex-cobalt")]
        let joined = joinReceipts([record(candidates: candidates, chosen: 0)],
                                  receipts: [receipt("SHOPPERS DRUG MART", offset: -60)])
        XCTAssertNil(joined[0].receipt)
    }

    /// One purchase, one arrival. Two arrivals inside one window must not both claim it, or a
    /// single Tim Hortons coffee inflates every accuracy figure twice.
    func testOneReceiptJoinsOnlyTheNearestArrival() {
        let candidates = [candidate("Shoppers Drug Mart", metresNorth: 20, card: "amex-cobalt")]
        let joined = joinReceipts([record(at: 0, candidates: candidates, chosen: 0),
                                   record(at: 300, candidates: candidates, chosen: 0)],
                                  receipts: [receipt("SHOPPERS DRUG MART", offset: 420)])
        XCTAssertNil(joined[0].receipt)
        XCTAssertNotNil(joined[1].receipt)
    }

    /// The containment ceiling. A receipt naming a store that was never a candidate joins — the
    /// purchase happened — but names no candidate, and that distinction is the difference between
    /// "we ranked wrong" and "it was never on the list".
    func testAReceiptForAStoreOutsideTheCandidateSetJoinsWithNoIndex() {
        let candidates = [candidate("Dollarama", metresNorth: 20, card: "amex-cobalt")]
        let joined = joinReceipts([record(candidates: candidates, chosen: 0)],
                                  receipts: [receipt("SHOPPERS DRUG MART")])
        XCTAssertNotNil(joined[0].receipt)
        XCTAssertNil(joined[0].receiptCandidateIndex)
    }

    // MARK: - Metrics

    func testTopOneAccuracyAndContainmentAreCountedOverArrivalsWithReceipts() {
        let plaza = [candidate("Dollarama", metresNorth: 20, card: "amex-cobalt"),
                     candidate("Shoppers Drug Mart", metresNorth: 90, card: "amex-cobalt")]
        let joined = joinReceipts([
            record(at: 0, candidates: plaza, chosen: 0),        // guessed Dollarama, was Shoppers
            record(at: 7200, candidates: plaza, chosen: 1),     // guessed Shoppers, was Shoppers
            record(at: 14400, candidates: [plaza[0]], chosen: 0), // Shoppers was not a candidate
        ], receipts: [receipt("SHOPPERS DRUG MART", offset: 600),
                      receipt("SHOPPERS DRUG MART", offset: 7800),
                      receipt("SHOPPERS DRUG MART", offset: 15000)])

        let metrics = arrivalFieldMetrics(joined)
        XCTAssertEqual(metrics.arrivalsWithAReceipt, 3)
        XCTAssertEqual(try XCTUnwrap(metrics.topOneStoreAccuracy), 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(metrics.candidateContainment), 2.0 / 3, accuracy: 1e-9)
    }

    /// **The number that decides the rework.** Of the arrivals where the store was guessed wrong,
    /// how often was the card still right. High means "answer when it doesn't matter" is a viable
    /// design and per-store resolution never has to be solved.
    func testCardEquivalenceCountsOnlyArrivalsWhereTheStoreWasWrong() throws {
        let sameCard = [candidate("Dollarama", metresNorth: 20, card: "amex-cobalt"),
                        candidate("Shoppers Drug Mart", metresNorth: 90, card: "amex-cobalt")]
        let differentCard = [candidate("Petro-Canada", metresNorth: 20, category: "gasStation",
                                       card: "scotia-momentum-vi-plus"),
                             candidate("Shoppers Drug Mart", metresNorth: 90, card: "amex-cobalt")]
        let joined = joinReceipts([
            record(at: 0, candidates: sameCard, chosen: 0),
            record(at: 7200, candidates: differentCard, chosen: 0),
            // Guessed right: excluded from the denominator entirely, not counted as a success.
            record(at: 14400, candidates: sameCard, chosen: 1),
        ], receipts: [receipt("SHOPPERS DRUG MART", offset: 600),
                      receipt("SHOPPERS DRUG MART", offset: 7800),
                      receipt("SHOPPERS DRUG MART", offset: 15000)])

        let metrics = arrivalFieldMetrics(joined)
        XCTAssertEqual(metrics.storeWrongArrivals, 2)
        XCTAssertEqual(try XCTUnwrap(metrics.cardEquivalenceAccuracy), 0.5, accuracy: 1e-9)
    }

    func testMetricsOverAnEmptyLogReportNoRatios() {
        let metrics = arrivalFieldMetrics([])
        XCTAssertEqual(metrics.arrivals, 0)
        XCTAssertNil(metrics.topOneStoreAccuracy)
        XCTAssertNil(metrics.candidateContainment)
        XCTAssertNil(metrics.cardEquivalenceAccuracy)
    }

    // MARK: - What the estimate ate

    /// The reported incident. $0.51 on a real $33.90 basket is 1.50pp; the arrival was scored
    /// against a guessed $25, where the doubled $0.25 floor costs 2.0pp. Replayed at the real
    /// amount with the CAD floor unscaled, it clears — so the estimate, not the policy, is what
    /// kept the app quiet.
    func testAnAlertTheEstimateAteIsCountedOnReplay() throws {
        let candidates = [candidate("Shoppers Drug Mart", metresNorth: 20, card: "amex-cobalt")]
        let arrival = record(candidates: candidates, chosen: 0,
                             advantage: AmbientAdvantage(percentagePoints: 1.5, cad: 0.375))
        let joined = joinReceipts([arrival], receipts: [receipt("SHOPPERS DRUG MART")])

        XCTAssertFalse(AmbientGate.evaluate(try XCTUnwrap(joined[0].gateInput)).fires)
        XCTAssertEqual(try? XCTUnwrap(replayAtRealAmount(joined[0])).fires, true)
        XCTAssertEqual(arrivalFieldMetrics(joined).alertsEatenByTheEstimate, 1)
    }

    /// An alert that already fired was not eaten by anything, however the replay comes out.
    func testAnAlertThatFiredIsNotCountedAsEaten() {
        let candidates = [candidate("Shoppers Drug Mart", metresNorth: 20, card: "amex-cobalt")]
        let arrival = record(candidates: candidates, chosen: 0,
                             advantage: AmbientAdvantage(percentagePoints: 4, cad: 1),
                             reasons: [])
        let joined = joinReceipts([arrival], receipts: [receipt("SHOPPERS DRUG MART")])
        XCTAssertEqual(arrivalFieldMetrics(joined).alertsEatenByTheEstimate, 0)
    }

    func testAnArrivalWithNoReceiptCannotBeReplayed() {
        let candidates = [candidate("Shoppers Drug Mart", metresNorth: 20, card: "amex-cobalt")]
        XCTAssertNil(replayAtRealAmount(record(candidates: candidates, chosen: 0)))
    }
}
