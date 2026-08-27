import XCTest
@testable import CardCopilotEngine

/// `noRewards` — the valuation model for a card that earns nothing.
///
/// The distinction under test is the one `Scorer.valueCad` has always drawn and could not
/// previously express: a MISSING valuation answers nil, and `Scorer.score` excludes the card with
/// `.unsupportedProgram`, because "we do not know what this is worth" must never rank as "worth
/// nothing". A card with no rewards programme is the other case — it IS valued, at zero — and
/// before this it had no way to say so, because `program` is a required field with a closed
/// `programId` enum. MBNA True Line and Capital One Guaranteed Secured are the real products
/// that forced it.
final class NoRewardsProgramTests: XCTestCase {

    func testNoRewardsValuesToZeroRatherThanNil() throws {
        let valuations = try Valuations(programs: SeedLoader.loadPrograms().defaults)
        let value = Scorer.valueCad(units: 100, program: "noRewards",
                                    valuations: valuations, state: CardState())
        XCTAssertEqual(value, 0.0, "noRewards must value to zero, not nil — nil excludes the card")
    }

    func testAnUnknownProgramStillAnswersNil() throws {
        let valuations = try Valuations(programs: SeedLoader.loadPrograms().defaults)
        XCTAssertNil(Scorer.valueCad(units: 100, program: "notARealProgramme",
                                     valuations: valuations, state: CardState()),
                     "the unvalued case must stay distinct from the valued-at-zero case")
    }

    func testTheCatalogueShipsTheDefaultSoNoOwnerHasToDeclareIt() throws {
        let defaults = try SeedLoader.loadPrograms().defaults
        guard case .noRewards(let v) = try XCTUnwrap(defaults["noRewards"]) else {
            return XCTFail("programs.json must ship a noRewards default, or every card on it is excluded")
        }
        XCTAssertFalse((v.basis ?? "").isEmpty, "a shipped default must disclose its basis")
    }

    func testRoundTripsThroughCodable() throws {
        let encoded = try JSONEncoder().encode(ProgramValuation.noRewards(NoRewardsValuation(basis: "b")))
        XCTAssertTrue(String(data: encoded, encoding: .utf8)!.contains("\"model\":\"noRewards\""))
        XCTAssertEqual(try JSONDecoder().decode(ProgramValuation.self, from: encoded),
                       .noRewards(NoRewardsValuation(basis: "b")))
    }
}
