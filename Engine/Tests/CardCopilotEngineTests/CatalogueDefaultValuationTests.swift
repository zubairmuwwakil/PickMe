import XCTest
@testable import CardCopilotEngine

/// contracts/programs.json is only worth shipping if the scoring path actually reads it.
///
/// These tests are deliberately built around a gap, not around the shipped data. Against
/// owner-state.json the merge is a NO-OP — it and programs.json value the same six programs, and
/// the owner wins every key — so a test written against the seed would pass just as happily with
/// the wiring removed. Each case here removes a program from the owner state first, so the only
/// thing that can make it pass is the catalogue default actually being consulted.
final class CatalogueDefaultValuationTests: XCTestCase {

    private let pinnedDefaults: [String: ProgramValuation] = [
        "cashback": .cashback(CashBackValuation(cadPerDollar: 1.0)),
        "aeroplan": .points(PointValuation(centsPerPoint: 1.9)),
    ]

    // MARK: - The merge itself

    func testCatalogueDefaultFillsAProgramTheOwnerDoesNotDeclare() throws {
        var owner = try SeedLoader.loadPinnedOwnerState()
        owner.valuationsCad["cashback"] = nil

        let effective = owner.applyingCatalogueValuationDefaults(pinnedDefaults)

        guard case .cashback(let cash) = try XCTUnwrap(effective.valuationsCad["cashback"])
        else { return XCTFail("expected .cashback") }
        XCTAssertEqual(cash.cadPerDollar, 1.0)
    }

    /// A valuation is a personal forecast. The catalogue may fill a gap; it may never overrule a
    /// number the owner has declared for themselves.
    func testOwnerDeclarationBeatsTheCatalogueDefault() throws {
        var owner = try SeedLoader.loadPinnedOwnerState()
        owner.valuationsCad["cashback"] = .cashback(CashBackValuation(cadPerDollar: 0.5))

        let effective = owner.applyingCatalogueValuationDefaults(pinnedDefaults)

        guard case .cashback(let cash) = try XCTUnwrap(effective.valuationsCad["cashback"])
        else { return XCTFail("expected .cashback") }
        XCTAssertEqual(cash.cadPerDollar, 0.5, accuracy: 0.0005,
                       "the catalogue overrode the owner's own declared valuation")
    }

    func testDefaultsDoNotDisturbProgramsTheOwnerAlreadyDeclares() throws {
        let owner = try SeedLoader.loadPinnedOwnerState()
        XCTAssertEqual(owner.applyingCatalogueValuationDefaults(pinnedDefaults).valuationsCad["cro"],
                       owner.valuationsCad["cro"])
    }

    /// The merge stopped being a no-op on 2026-08-20, which is the point of that day's work.
    /// It replaces `testMergeIsANoOpAgainstTheShippedContractsToday`, which pinned the no-op
    /// while programs.json and owner-state.json valued the same six programs and which its own
    /// comment said to retire here.
    ///
    /// Two halves, and both matter. The merge must ADD the ten programs the owner has never
    /// declared — otherwise every card on them is still excluded — and it must leave the six the
    /// owner HAS declared untouched, byte for byte. A merge that quietly restated the owner's own
    /// Membership Rewards number as the catalogue's would move the 27 golden fixtures, because
    /// they are pinned above the shipped 1.0¢ floor.
    func testMergeAddsTheCatalogueOnlyProgramsAndDisturbsNoneTheOwnerDeclares() throws {
        let owner = try SeedLoader.loadOwnerState()
        let merged = owner.applyingCatalogueValuationDefaults().valuationsCad

        for (programId, declared) in owner.valuationsCad.programs {
            XCTAssertEqual(merged[programId], declared,
                           "the catalogue overwrote the owner's own valuation for '\(programId)'")
        }

        let added = Set(merged.programs.keys).subtracting(owner.valuationsCad.programs.keys)
        XCTAssertEqual(added, ["scenePlus", "aeroplan", "rbcAvion", "tdRewards", "bmoRewards",
                               "aventura", "nbcRewards", "pcOptimum", "westJetPoints",
                               "amazonRewards", "noRewards"],
                       "the catalogue-only programs are what make the other 14 cards scorable")
    }

    // MARK: - The wiring

    /// RecommendationEngine is the single funnel: PortfolioAnalyzer, RecurringAuditor,
    /// CategoryPickerAdvisor and Store's CheckoutService all construct one. Merging here is what
    /// reaches owner states loaded from a device, which never pass through SeedLoader at all.
    func testRecommendationEngineAppliesCatalogueDefaults() throws {
        var owner = try SeedLoader.loadPinnedOwnerState()
        owner.valuationsCad["cashback"] = nil

        let engine = RecommendationEngine(catalogue: try SeedLoader.loadCatalogue(),
                                          ownerState: owner)

        XCTAssertNotNil(engine.ownerState.valuationsCad["cashback"],
                        "the engine scored against an owner state with no cash-back valuation")
    }

    /// The behaviour that motivates all of it: a card whose program the owner has not valued
    /// still earns a real number, because the catalogue supplies one. Without the wiring this
    /// scores exactly $0.00 — which is what 14 of 27 cards did before this work.
    func testCardOnAnUndeclaredProgramStillScores() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        var owner = try SeedLoader.loadPinnedOwnerState()
        owner.valuationsCad["cashback"] = nil

        let purchase = PurchaseContext(amountCad: 100, category: "other")
        guard case .advised(let recommendation) = RecommendationEngine(catalogue: catalogue, ownerState: owner)
            .recommend(purchase, asOf: "2026-08-20") else {
            return XCTFail("expected .advised recommendation")
        }
        let wealthsimple = try XCTUnwrap(
            recommendation.allCandidates.first { $0.cardId == "wealthsimple-vip" },
            "wealthsimple-vip is the seed default card and is on the cashback program")

        XCTAssertGreaterThan(wealthsimple.netValueCad, 0,
            "a cash-back card scored $0.00 because the owner state declared no cashback valuation "
          + "and the catalogue default was never consulted")
    }
}
