import XCTest
import SwiftData
import CardCopilotEngine
@testable import CardCopilotStore

/// The loop that makes the app learn: a reconciled outcome promotes THAT terminal, and the next
/// checkout there skips the guess. Terminal-level only — the dossier (§6) is explicit that a
/// confirmation at one Walmart says nothing about another, and that owner-reconciled outcomes
/// are the only source allowed to promote a merchant at all.
final class TruthGraphTests: XCTestCase {
    var container: ModelContainer!
    var service: CheckoutService!
    let asOf = "2026-08-20"

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self, StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        service = CheckoutService(catalogue: try SeedLoader.loadCatalogue(),
                                  ownerState: try SeedLoader.loadOwnerState(),
                                  context: ModelContext(container))
    }

    /// Two real Toronto branches, at roughly their real coordinates and about four kilometres
    /// apart.
    ///
    /// They used to share one coordinate and differ only by id. That was invisible while merchant
    /// identity was pure string equality, and stopped being invisible once `MerchantIdentity`
    /// gained a proximity rung: two Walmart Supercentres zero metres apart are one storefront by
    /// any honest reading, so the fixture was asserting the terminal-level promotion rule with a
    /// geometry that cannot express it. Separating them does not weaken these tests — it is what
    /// makes them test the rule for the reason the rule is true.
    private static let branches = [
        "poi-walmart-dufferin": (latitude: 43.6549, longitude: -79.4358),
        "poi-walmart-stockyards": (latitude: 43.6707, longitude: -79.4718),
    ]

    private func walmart(id: String) -> NearbyPlace {
        let branch = Self.branches[id] ?? (latitude: 43.65, longitude: -79.38)
        return NearbyPlace(id: id, name: "Walmart Supercentre",
                           poiCategoryRaw: "MKPOICategoryFoodMarket",
                           latitude: branch.latitude, longitude: branch.longitude,
                           distanceMeters: 40)
    }

    @discardableResult
    private func checkout(_ merchant: NearbyPlace, amount: Double = 100) throws -> CheckoutResult {
        try service.recommend(merchant: merchant, amountCad: amount, asOf: asOf)
    }

    private func reconcileLatest(as category: String, units: Double? = 500) throws {
        // A fresh checkout leaves an INCOMPLETE purchase — the card and the real charge are both
        // still unknown at that point — so it waits in the completion queue, not the reconcile one.
        let latest = try XCTUnwrap(try service.log.awaitingCompletion().first)
        try service.log.settle(latest, cardUsed: latest.winnerCardId, observedCategory: category,
                                observedRewardUnits: units, missClass: nil, note: nil)
    }

    private func merchant(id: String) throws -> StoredMerchant {
        try XCTUnwrap(try service.knownMerchants().first { $0.identifier == id })
    }

    // MARK: promotion

    func testConfirmingPromotesTheExactTerminal() throws {
        try checkout(walmart(id: "poi-walmart-dufferin"))
        try reconcileLatest(as: "grocery")

        let promoted = try merchant(id: "poi-walmart-dufferin")
        XCTAssertEqual(promoted.confirmedCategory, "grocery")
        XCTAssertEqual(promoted.confirmationCount, 1)
    }

    func testConfirmingOneStoreLeavesAnotherOfTheSameBrandUnknown() throws {
        try checkout(walmart(id: "poi-walmart-dufferin"))
        try checkout(walmart(id: "poi-walmart-stockyards"))
        // Reconcile only the Dufferin visit (the older of the two unconfirmed rows).
        let dufferin = try XCTUnwrap(try service.log.awaitingCompletion().last)
        try service.log.settle(dufferin, cardUsed: dufferin.winnerCardId,
                                observedCategory: "grocery", observedRewardUnits: 500,
                                missClass: nil, note: nil)

        XCTAssertEqual(try merchant(id: "poi-walmart-dufferin").confirmedCategory, "grocery")
        XCTAssertNil(try merchant(id: "poi-walmart-stockyards").confirmedCategory,
                     "promotion is terminal-level: one Walmart says nothing about another")
    }

    func testRepeatedMatchingConfirmationsRaiseTheTerminalToRepeated() throws {
        try checkout(walmart(id: "poi-walmart-dufferin"))
        try reconcileLatest(as: "grocery")
        try checkout(walmart(id: "poi-walmart-dufferin"))
        try reconcileLatest(as: "grocery")

        XCTAssertEqual(try merchant(id: "poi-walmart-dufferin").confirmationCount, 2)
        let third = try checkout(walmart(id: "poi-walmart-dufferin"))
        XCTAssertEqual(third.prediction.confidenceSource, .repeatedTerminal)
    }

    func testATerminalThatRecodesRestartsItsRepeatCount() throws {
        try checkout(walmart(id: "poi-walmart-dufferin"))
        try reconcileLatest(as: "grocery")
        try checkout(walmart(id: "poi-walmart-dufferin"))
        try reconcileLatest(as: "grocery")
        try checkout(walmart(id: "poi-walmart-dufferin"))
        try reconcileLatest(as: "other")

        let recoded = try merchant(id: "poi-walmart-dufferin")
        XCTAssertEqual(recoded.confirmedCategory, "other")
        XCTAssertEqual(recoded.confirmationCount, 1,
                       "the count is a streak of the same result — a processor that re-codes starts over")
        XCTAssertEqual(try checkout(walmart(id: "poi-walmart-dufferin")).prediction.confidenceSource,
                       .ownerConfirmedTerminal,
                       "one contradicted observation is not a repeated result")
    }

    // MARK: the ladder in the checkout path

    func testWalmartForksBeforeAnyConfirmation() throws {
        guard case .fork = try checkout(walmart(id: "poi-walmart-dufferin")).outcome else {
            return XCTFail("an unconfirmed Walmart is genuinely ambiguous")
        }
    }

    func testAConfirmedTerminalAnswersInstantlyWithNoFork() throws {
        // The literal promise the fork view makes: "next time the answer is instant."
        try checkout(walmart(id: "poi-walmart-dufferin"))
        try reconcileLatest(as: "grocery")

        let repeatVisit = try checkout(walmart(id: "poi-walmart-dufferin"))
        guard case .single(let recommendation) = repeatVisit.outcome else {
            return XCTFail("a confirmed terminal must not fork")
        }
        XCTAssertEqual(repeatVisit.prediction.category, "grocery")
        XCTAssertEqual(repeatVisit.prediction.confidenceSource, .ownerConfirmedTerminal)
        XCTAssertEqual(repeatVisit.prediction.candidates, ["grocery"])
        XCTAssertFalse(repeatVisit.categoryWasAmbiguous)
        XCTAssertEqual(recommendation.winner.cardId, "amex-cobalt")
        XCTAssertEqual(try service.log.allPredictions().first?.confidenceSource,
                       .ownerConfirmedTerminal,
                       "the stored prediction must record which rung of the ladder answered")
    }

    func testADifferentWalmartStillForksAfterOneIsConfirmed() throws {
        try checkout(walmart(id: "poi-walmart-dufferin"))
        try reconcileLatest(as: "grocery")

        guard case .fork = try checkout(walmart(id: "poi-walmart-stockyards")).outcome else {
            return XCTFail("a different terminal has no evidence — it must still fork")
        }
    }

    func testAConfirmedTerminalOutranksItsBrandPrior() throws {
        // Costco codes as wholesaleClub by brand prior (rung 5). An owner-reconciled result for
        // this exact warehouse is rung 1 and must win.
        let costco = NearbyPlace(id: "poi-costco-etobicoke", name: "Costco Wholesale",
                                    poiCategoryRaw: nil, latitude: 43.65, longitude: -79.38,
                                    distanceMeters: 40)
        try checkout(costco, amount: 220)
        try reconcileLatest(as: "grocery", units: 3.30)

        let repeatVisit = try checkout(costco, amount: 220)
        XCTAssertEqual(repeatVisit.prediction.category, "grocery")
        XCTAssertEqual(repeatVisit.prediction.confidenceSource, .ownerConfirmedTerminal)
    }
}
