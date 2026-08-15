import XCTest
@testable import CardCopilotEngine

/// Behaviour tests pin the Membership Rewards value rather than inheriting owner-state.json,
/// which now ranks at the 1.0¢ cash floor. Pinning above the floor keeps these cases exercising
/// points-vs-cash ranking, and stops a personal preference change from re-baselining the suite.
extension SeedLoader {
    static func loadPinnedOwnerState(mrCentsPerPoint: Double = 1.8) throws -> OwnerState {
        var state = try loadOwnerState()
        state.valuationsCad.amexMembershipRewards.centsPerPoint = mrCentsPerPoint
        return state
    }
}
