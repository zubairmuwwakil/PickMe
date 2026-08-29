import XCTest
@testable import CardCopilotEngine

final class CategoryTaxonomyTests: XCTestCase {

    func testKnownDisplayAliasesResolveToCatalogueIds() {
        let aliases = [
            "Groceries": "grocery",
            "gas": "gasStation",
            "Gas Station": "gasStation",
            "drugstore": "drugStore",
            "Pharmacy": "drugStore",
            "Food Delivery": "foodDelivery",
            "Hotels": "lodging",
            "Recurring Bills": "recurring",
            "General Merchandise": "other",
        ]

        for (raw, expected) in aliases {
            XCTAssertEqual(CategoryTaxonomy.canonicalID(raw), expected, "Alias: \(raw)")
        }
    }

    func testUnknownCategoryIsPreservedForCatalogueGrowth() {
        XCTAssertEqual(CategoryTaxonomy.canonicalID("someBrandNewSpendCategory"),
                       "someBrandNewSpendCategory")
        XCTAssertEqual(CategoryTaxonomy.canonicalID(""), "")
    }

    func testPurchaseContextNormalizesAtTheEngineBoundary() {
        let context = PurchaseContext(amountCad: 50, category: " groceries ")
        XCTAssertEqual(context.category, "grocery")
    }

    func testCategoryAdvisorTreatsAliasesAndCanonicalIdsIdentically() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        let distribution = SpendDistribution.placeholderCanadianHousehold

        for (alias, canonical) in [("groceries", "grocery"),
                                    ("gas", "gasStation"),
                                    ("drugstore", "drugStore")] {
            let aliasBands = CategoryPickerAdvisor.bands(
                for: alias, catalogue: catalogue, ownerState: owner,
                distribution: distribution, asOf: "2026-08-20")
            let canonicalBands = CategoryPickerAdvisor.bands(
                for: canonical, catalogue: catalogue, ownerState: owner,
                distribution: distribution, asOf: "2026-08-20")

            XCTAssertEqual(aliasBands, canonicalBands, "Alias: \(alias)")
        }
    }

    func testBandSelectionUsesTheFollowingBandAtAnExactBoundary() {
        let firstScore = score(cardId: "first")
        let secondScore = score(cardId: "second")
        let bands = [
            CategoryPickerAdvisor.AmountBand(lowerBoundCad: 0, upperBoundCad: 10,
                                              cardId: "first", recommendation: firstScore),
            CategoryPickerAdvisor.AmountBand(lowerBoundCad: 10, upperBoundCad: nil,
                                              cardId: "second", recommendation: secondScore),
        ]

        XCTAssertEqual(CategoryPickerAdvisor.band(containing: 9.99, in: bands)?.cardId, "first")
        XCTAssertEqual(CategoryPickerAdvisor.band(containing: 10, in: bands)?.cardId, "second")
        XCTAssertEqual(CategoryPickerAdvisor.band(containing: 100, in: bands)?.cardId, "second")
    }

    private func score(cardId: String) -> Recommendation {
        let candidate = CandidateScore(cardId: cardId, appliedRuleId: nil, rewardUnits: 0,
                                       grossRewardCad: 0, fxCostCad: 0, netValueCad: 0,
                                       floorNetValueCad: 0, aspirationalNetValueCad: 0,
                                       warnings: [], excluded: false, exclusionReason: nil)
        return Recommendation(winner: candidate, runnerUp: nil, switchedFromDefault: false,
                              advantageOverDefaultCad: nil, defaultNotAccepted: false,
                              suppressedBetterCard: nil, valuationSensitive: false,
                              valuationDirection: nil, alternateWinnerCardId: nil,
                              breakevenCentsPerPoint: nil, declaredCentsPerPoint: nil,
                              allCandidates: [candidate])
    }
}
