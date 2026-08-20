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
