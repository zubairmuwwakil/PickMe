import XCTest
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

final class InstantRepeatAdvisorTests: XCTestCase {

    func testNoFrillsEnforcesNetworkConstraintExcludingAmex() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let programs = try SeedLoader.loadPrograms()
        // Wallet with Amex Cobalt (5x grocery), PC Financial World Elite, and Rogers Red World Elite
        let setup = WalletSetup(
            ownedCardIds: ["amex-cobalt", "pc-financial-world-elite", "rogers-red-we"],
            defaultCardId: "rogers-red-we",
            switchThreshold: SwitchThreshold(minAdvantagePercentagePoints: 0.5, minAdvantageCad: 0.50, semantics: "either"),
            valuationsCad: Valuations(programs: programs.defaults)
        )
        let ownerState = OwnerStateBuilder.make(setup: setup, catalogue: catalogue)
        let engine = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)

        let noFrills = StoredMerchant(name: "No Frills", identifier: "preindex:no frills", poiCategoryRaw: "FoodMarket", latitude: 0, longitude: 0)

        let eval = InstantRepeatAdvisor.evaluate(
            merchant: noFrills,
            amountCad: 50,
            catalogue: catalogue,
            ownerState: ownerState,
            engine: engine
        )

        XCTAssertNotNil(eval)
        guard let eval else { return }

        // Amex Cobalt must NOT win because No Frills accepts Mastercard and Visa only.
        XCTAssertNotEqual(eval.winnerCardId, "amex-cobalt", "Amex Cobalt must be excluded at No Frills due to network acceptance")
        XCTAssertEqual(eval.networkBadge, "MC / Visa Only")
        XCTAssertTrue(eval.winnerCardId == "pc-financial-world-elite" || eval.winnerCardId == "rogers-red-we")
    }

    func testMetroAllowsAmexCobaltForGrocery() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let programs = try SeedLoader.loadPrograms()
        let setup = WalletSetup(
            ownedCardIds: ["amex-cobalt", "rogers-red-we"],
            defaultCardId: "rogers-red-we",
            switchThreshold: SwitchThreshold(minAdvantagePercentagePoints: 0.5, minAdvantageCad: 0.50, semantics: "either"),
            valuationsCad: Valuations(programs: programs.defaults)
        )
        let ownerState = OwnerStateBuilder.make(setup: setup, catalogue: catalogue)
        let engine = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)

        let metro = StoredMerchant(name: "Metro", identifier: "preindex:metro", poiCategoryRaw: "FoodMarket", latitude: 0, longitude: 0)

        let eval = InstantRepeatAdvisor.evaluate(
            merchant: metro,
            amountCad: 50,
            catalogue: catalogue,
            ownerState: ownerState,
            engine: engine
        )

        XCTAssertNotNil(eval)
        guard let eval else { return }

        XCTAssertEqual(eval.winnerCardId, "amex-cobalt")
        XCTAssertNil(eval.networkBadge, "Metro accepts all networks, so no network restriction badge")
        XCTAssertEqual(eval.multiplierText, "5x Points")
        XCTAssertGreaterThan(eval.returnCad, 0)
    }

    func testCostcoEnforcesMastercardOnly() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let programs = try SeedLoader.loadPrograms()
        let setup = WalletSetup(
            ownedCardIds: ["amex-cobalt", "cibc-dividend-visa-infinite", "rogers-red-we"],
            defaultCardId: "cibc-dividend-visa-infinite",
            switchThreshold: SwitchThreshold(minAdvantagePercentagePoints: 0.5, minAdvantageCad: 0.50, semantics: "either"),
            valuationsCad: Valuations(programs: programs.defaults)
        )
        let ownerState = OwnerStateBuilder.make(setup: setup, catalogue: catalogue)
        let engine = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)

        let costco = StoredMerchant(name: "Costco Wholesale", identifier: "preindex:costco wholesale", poiCategoryRaw: "Store", latitude: 0, longitude: 0)

        let eval = InstantRepeatAdvisor.evaluate(
            merchant: costco,
            amountCad: 100,
            catalogue: catalogue,
            ownerState: ownerState,
            engine: engine
        )

        XCTAssertNotNil(eval)
        guard let eval else { return }

        XCTAssertEqual(eval.winnerCardId, "rogers-red-we", "Costco must exclude Visa and Amex, picking Mastercard")
        XCTAssertEqual(eval.networkBadge, "Mastercard Only")
    }

    func testAmountSensitivityAndCalculation() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let programs = try SeedLoader.loadPrograms()
        let setup = WalletSetup(
            ownedCardIds: ["amex-cobalt", "rogers-red-we"],
            defaultCardId: "rogers-red-we",
            switchThreshold: SwitchThreshold(minAdvantagePercentagePoints: 0.5, minAdvantageCad: 0.50, semantics: "either"),
            valuationsCad: Valuations(programs: programs.defaults)
        )
        let ownerState = OwnerStateBuilder.make(setup: setup, catalogue: catalogue)
        let engine = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)

        let metro = StoredMerchant(name: "Metro", identifier: "preindex:metro", poiCategoryRaw: "FoodMarket", latitude: 0, longitude: 0)

        let eval10 = InstantRepeatAdvisor.evaluate(merchant: metro, amountCad: 10, catalogue: catalogue, ownerState: ownerState, engine: engine)
        let eval50 = InstantRepeatAdvisor.evaluate(merchant: metro, amountCad: 50, catalogue: catalogue, ownerState: ownerState, engine: engine)
        let eval100 = InstantRepeatAdvisor.evaluate(merchant: metro, amountCad: 100, catalogue: catalogue, ownerState: ownerState, engine: engine)

        XCTAssertNotNil(eval10)
        XCTAssertNotNil(eval50)
        XCTAssertNotNil(eval100)

        guard let r10 = eval10?.returnCad, let r50 = eval50?.returnCad, let r100 = eval100?.returnCad else {
            XCTFail("Missing returnCad")
            return
        }

        // Scaling checks
        XCTAssertEqual(r50, r10 * 5, accuracy: 0.01)
        XCTAssertEqual(r100, r50 * 2, accuracy: 0.01)
        XCTAssertTrue(eval50?.calculationText.contains("$50") == true)
    }
}
