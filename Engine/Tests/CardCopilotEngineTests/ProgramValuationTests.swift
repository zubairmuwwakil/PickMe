import XCTest
@testable import CardCopilotEngine

final class ProgramValuationTests: XCTestCase {

    private func roundTrip(_ value: ProgramValuation) throws -> ProgramValuation {
        try JSONDecoder().decode(ProgramValuation.self, from: JSONEncoder().encode(value))
    }

    func testPointsRoundTrips() throws {
        var p = PointValuation(centsPerPoint: 1.0)
        p.floorCentsPerPoint = 0.9
        p.aspirationalCentsPerPoint = 2.2
        p.basis = "cash floor"
        XCTAssertEqual(try roundTrip(.points(p)), .points(p))
    }

    func testCashbackRoundTrips() throws {
        XCTAssertEqual(try roundTrip(.cashback(CashBackValuation(cadPerDollar: 1.0))),
                       .cashback(CashBackValuation(cadPerDollar: 1.0)))
    }

    func testCtMoneyRoundTrips() throws {
        let v = CtMoneyValuation(cadPerUnit: 1.0, optionalUsabilityFactor: 0.95,
                                 usabilityFactorApplied: true)
        XCTAssertEqual(try roundTrip(.ctMoney(v)), .ctMoney(v))
    }

    func testCroRoundTrips() throws {
        let v = CroValuation(redemptionModel: "reward-currency", faceValueFactorIfAutoSold: 1.0,
                             defaultHeldRiskFactor: 0.8)
        XCTAssertEqual(try roundTrip(.cro(v)), .cro(v))
    }

    func testDecodesFromModelDiscriminator() throws {
        let json = Data(#"{"model":"points","centsPerPoint":1.5}"#.utf8)
        guard case .points(let p) = try JSONDecoder().decode(ProgramValuation.self, from: json)
        else { return XCTFail("expected .points") }
        XCTAssertEqual(p.centsPerPoint, 1.5)
    }

    /// An unknown model is a hard decode failure, not a silent default. A valuation the engine
    /// cannot interpret must never be mistaken for one it can.
    func testUnknownModelIsADecodeError() {
        let json = Data(#"{"model":"cryptoKittyPoints","centsPerPoint":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ProgramValuation.self, from: json))
    }

    /// The discriminator sits at the same JSON level as the payload, so `cro`'s own model field
    /// had to be renamed out of the way. Encoding must emit both, distinctly.
    func testCroEncodesBothTheDiscriminatorAndItsRedemptionModel() throws {
        let v = CroValuation(redemptionModel: "reward-currency", faceValueFactorIfAutoSold: 1.0,
                             defaultHeldRiskFactor: 0.8)
        let object = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(ProgramValuation.cro(v))) as? [String: Any]
        XCTAssertEqual(object?["model"] as? String, "cro")
        XCTAssertEqual(object?["redemptionModel"] as? String, "reward-currency")
    }
}

extension ProgramValuationTests {

    /// Every wallet already on a device is written in the legacy shape. Failing to read it would
    /// evict the owner's declared valuations on upgrade.
    func testLegacyNamedFieldShapeStillDecodes() throws {
        let legacy = Data("""
        {
          "amexMembershipRewards": {"centsPerPoint": 1.0, "floorCentsPerPoint": 1.0},
          "marriottBonvoy": {"centsPerPoint": 0.8},
          "mbnaRewards": {"centsPerPoint": 1.0},
          "ctMoney": {"cadPerUnit": 1.0, "optionalUsabilityFactor": 0.95,
                      "usabilityFactorApplied": true},
          "cro": {"redemptionModel": "reward-currency", "faceValueFactorIfAutoSold": 1.0,
                  "defaultHeldRiskFactor": 0.8},
          "cashBack": {"cadPerDollar": 1.0}
        }
        """.utf8)
        let v = try JSONDecoder().decode(Valuations.self, from: legacy)

        guard case .points(let amex) = try XCTUnwrap(v["amexMembershipRewards"])
        else { return XCTFail("expected .points") }
        XCTAssertEqual(amex.centsPerPoint, 1.0)

        guard case .cashback(let cash) = try XCTUnwrap(v["cashback"])
        else { return XCTFail("expected .cashback") }
        XCTAssertEqual(cash.cadPerDollar, 1.0)

        guard case .cro(let cro) = try XCTUnwrap(v["cro"]) else { return XCTFail("expected .cro") }
        XCTAssertEqual(cro.defaultHeldRiskFactor, 0.8)
    }

    func testNewProgramsShapeDecodes() throws {
        let modern = Data("""
        {"programs": {"aeroplan": {"model": "points", "centsPerPoint": 1.9}}}
        """.utf8)
        let v = try JSONDecoder().decode(Valuations.self, from: modern)
        guard case .points(let p) = try XCTUnwrap(v["aeroplan"])
        else { return XCTFail("expected .points") }
        XCTAssertEqual(p.centsPerPoint, 1.9)
    }

    /// Legacy in, modern out — so a wallet upgrades itself the first time it is written back.
    func testLegacyShapeReEncodesAsProgramsDictionary() throws {
        let legacy = Data("""
        {"cashBack": {"cadPerDollar": 1.0}}
        """.utf8)
        let decoded = try JSONDecoder().decode(Valuations.self, from: legacy)
        let reencoded = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(decoded)) as? [String: Any]
        XCTAssertNotNil(reencoded?["programs"])
        XCTAssertNil(reencoded?["cashBack"])
    }

    /// The legacy file's `cashBack` key is `cashback` as a programId — the catalogue spells it
    /// lowercase. A mismatch here would silently unvalue every cash-back card.
    func testLegacyCashBackKeyMapsToCatalogueProgramId() throws {
        let legacy = Data(#"{"cashBack": {"cadPerDollar": 1.0}}"#.utf8)
        let v = try JSONDecoder().decode(Valuations.self, from: legacy)
        XCTAssertNotNil(v["cashback"], "catalogue programId is 'cashback', not 'cashBack'")
    }

    /// owner-state.json carries a `rogersEligibleServiceRedemption` block that is not a catalogue
    /// programId and has no ProgramValuation model. It must be ignored, not a decode failure.
    func testUnknownLegacyKeyIsIgnoredNotFatal() throws {
        let legacy = Data("""
        {"cashBack": {"cadPerDollar": 1.0},
         "rogersEligibleServiceRedemption": {"redemptionFactor": 1.5, "appliedAtCheckout": false}}
        """.utf8)
        let v = try JSONDecoder().decode(Valuations.self, from: legacy)
        XCTAssertNotNil(v["cashback"])
        XCTAssertNil(v["rogersEligibleServiceRedemption"])
    }

    /// A full round trip through the modern shape must be lossless, or a wallet degrades a
    /// little on every save.
    func testModernShapeRoundTripsLosslessly() throws {
        let original = Valuations(programs: [
            "amexMembershipRewards": .points(PointValuation(centsPerPoint: 1.0,
                                                            floorCentsPerPoint: 1.0,
                                                            aspirationalCentsPerPoint: 2.2,
                                                            basis: "cash floor")),
            "ctMoney": .ctMoney(CtMoneyValuation(cadPerUnit: 1.0, optionalUsabilityFactor: 0.95,
                                                 usabilityFactorApplied: true)),
            "cashback": .cashback(CashBackValuation(cadPerDollar: 1.0)),
        ])
        let decoded = try JSONDecoder().decode(
            Valuations.self, from: try JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    /// The shipped owner state is still written in the legacy shape, so this is the live proof
    /// that the compatibility branch reads a real file and loses nothing. If this drops to five
    /// entries, some behaviour test somewhere is silently scoring a program at $0.00.
    func testShippedOwnerStateDecodesAllSixLegacyPrograms() throws {
        let v = try SeedLoader.loadOwnerState().valuationsCad
        XCTAssertEqual(Set(v.programs.keys),
                       ["amexMembershipRewards", "marriottBonvoy", "mbnaRewards",
                        "ctMoney", "cro", "cashback"])
        XCTAssertNotNil(v[points: "amexMembershipRewards"],
                        "the fixture pin writes through this accessor; a nil here is a silent no-op")
    }
}
