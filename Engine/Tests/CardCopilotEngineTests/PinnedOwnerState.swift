import XCTest
@testable import CardCopilotEngine

/// The catalogue's programId for Amex Membership Rewards — the currency almost every behaviour
/// test pins, because it is the one whose valuation actually flips recommendations.
let mrProgramId = "amexMembershipRewards"

/// Reading and pinning a points valuation now goes through a dictionary lookup that can return
/// nil. These helpers make that nil a loud test failure instead of a silent no-op.
///
/// This matters more than it looks. Before the dictionary, `state.valuationsCad
/// .amexMembershipRewards.centsPerPoint = 1.8` could not fail to take effect. Written naively
/// against the dictionary — `valuationsCad[points: mrProgramId]?.centsPerPoint = 1.8` — it
/// silently does nothing when the key is missing, the suite re-baselines against
/// owner-state.json's 1.0¢, and the golden fixtures move for a reason no diff explains.
extension OwnerState {

    /// The points valuation for `programId`. Fails the test and returns NaN when absent, so a
    /// missing valuation propagates into every downstream assertion rather than passing quietly.
    func pointsValuation(_ programId: String = mrProgramId,
                         file: StaticString = #filePath, line: UInt = #line) -> PointValuation {
        guard let valuation = valuationsCad[points: programId] else {
            XCTFail("owner state has no points valuation for '\(programId)'", file: file, line: line)
            return PointValuation(centsPerPoint: .nan)
        }
        return valuation
    }

    /// Mutate `programId`'s points valuation in place, failing the test when there is none.
    mutating func withPointsValuation(_ programId: String = mrProgramId,
                                      file: StaticString = #filePath, line: UInt = #line,
                                      _ mutate: (inout PointValuation) -> Void) {
        guard var valuation = valuationsCad[points: programId] else {
            return XCTFail("owner state has no points valuation for '\(programId)' to mutate",
                           file: file, line: line)
        }
        mutate(&valuation)
        valuationsCad[points: programId] = valuation
    }
}

/// Behaviour tests pin the Membership Rewards value rather than inheriting owner-state.json,
/// which now ranks at the 1.0¢ cash floor. Pinning above the floor keeps these cases exercising
/// points-vs-cash ranking, and stops a personal preference change from re-baselining the suite.
extension SeedLoader {
    static func loadPinnedOwnerState(mrCentsPerPoint: Double = 1.8) throws -> OwnerState {
        var state = try loadOwnerState()
        state.withPointsValuation { $0.centsPerPoint = mrCentsPerPoint }
        return state
    }
}

/// Every card in the catalogue, owned, with the owner's own valuations left exactly as shipped.
///
/// Deliberately does NOT hand-assemble `Valuations(programs: SeedLoader.loadPrograms().defaults)`.
/// Doing that would make the catalogue defaults present by construction, and a test built on it
/// would keep passing with the merge in `RecommendationEngine.init` deleted — testing the data
/// file rather than the path that reads it. Pass this to a `RecommendationEngine` and let the
/// engine supply the defaults, the way every real caller does.
extension OwnerState {
    static func seedWithAllCardsOwned(catalogue: Catalogue) throws -> OwnerState {
        var state = try SeedLoader.loadPinnedOwnerState()
        state.ownedCardIds = catalogue.cards.map(\.cardId)
        return state
    }
}
