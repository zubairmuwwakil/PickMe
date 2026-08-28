import XCTest
@testable import CardCopilotEngine

final class BillRouteScorerTests: XCTestCase {

    func testDurhamWaterCategoryAutoDetection() {
        let category = BillCategory.detect(from: "DURHAM WATER, REG MUN OF")
        XCTAssertEqual(category, .utilitiesWater)
        XCTAssertEqual(category.iconSymbol, "drop.fill")
    }

    func testHydroCategoryAutoDetection() {
        let category = BillCategory.detect(from: "TORONTO HYDRO-ELECTRIC SYSTEM")
        XCTAssertEqual(category, .utilitiesHydro)
        XCTAssertEqual(category.iconSymbol, "bolt.fill")
    }

    func testScorerWithScotiaMomentumChoosesChexyAsOptimal() {
        let payee = BillPayee(
            payeeName: "DURHAM WATER, REG MUN OF",
            accountNumber: "1643208999",
            nickname: "Durham Water",
            estimatedMonthlyCad: 150.0
        )

        let scorer = BillRouteScorer.loadDefault()
        let routes = scorer.scoreRoutes(for: payee, ownedCardIds: ["scotiabank-momentum-vi", "triangle-we"])

        XCTAssertFalse(routes.isEmpty)
        let topRoute = routes[0]
        
        // Chexy should win with 4.0% - 1.75% = 2.25% net spread ($40.50/yr on $1800 spend)
        XCTAssertEqual(topRoute.intermediary.id, "chexy")
        XCTAssertTrue(topRoute.isOptimal)
        XCTAssertEqual(topRoute.netSpreadRate, 0.0225, accuracy: 0.0001)
        XCTAssertEqual(topRoute.estimatedAnnualNetCad, 40.50, accuracy: 0.01)
    }

    func testScorerWithTriangleOnlyPicksTriangleAsOptimal() {
        let payee = BillPayee(
            payeeName: "DURHAM WATER, REG MUN OF",
            accountNumber: "1643208999",
            nickname: "Durham Water",
            estimatedMonthlyCad: 200.0
        )

        let scorer = BillRouteScorer.loadDefault()
        let routes = scorer.scoreRoutes(for: payee, ownedCardIds: ["triangle-we"])

        XCTAssertFalse(routes.isEmpty)
        let topRoute = routes[0]

        // Triangle should win over baseline and Chexy (which would have standard rate - 1.75% < 1.0%)
        XCTAssertEqual(topRoute.intermediary.id, "triangle-bill-pay")
        XCTAssertTrue(topRoute.isOptimal)
        XCTAssertEqual(topRoute.netSpreadRate, 0.01, accuracy: 0.0001)
        XCTAssertEqual(topRoute.estimatedAnnualNetCad, 24.00, accuracy: 0.01)
    }

    func testScorerIncludesNeoFinancialFloatOption() {
        let payee = BillPayee(
            payeeName: "DURHAM WATER, REG MUN OF",
            accountNumber: "1643208999",
            estimatedMonthlyCad: 100.0
        )

        let scorer = BillRouteScorer.loadDefault()
        let routes = scorer.scoreRoutes(for: payee, ownedCardIds: [])

        let neoRoute = routes.first { $0.intermediary.id == "neobanc" }
        XCTAssertNotNil(neoRoute)
        XCTAssertEqual(neoRoute?.intermediary.type, .fintechAccountRouting)
        XCTAssertGreaterThan(neoRoute?.estimatedAnnualNetCad ?? 0, 0.0)
    }
}
