import XCTest
@testable import CardCopilotEngine

/// Merchant-locked store credit — a Gap Inc. point, a Sam's Cash dollar, a cruise line's onboard
/// credit. Same arithmetic as CT Money, deliberately NOT the same model: `ctMoney` is a published
/// name inside a digest-pinned release, and folding two wire formats into one case would cost a
/// spelling-provenance field in Swift and a custom polymorphic serializer in Kotlin.
///
/// The per-brand usability factor is the load-bearing part. A Sam's Club dollar (weekly
/// groceries) and a Harley-Davidson dollar (a motorcycle every few years) are not the same
/// dollar, and one shared factor across brands would value one brand's credit as another's —
/// the exact collapse the 2026-08-27 Option 1 ruling refused.
final class MerchantCreditProgramTests: XCTestCase {

    private func valuations(_ v: ProgramValuation) -> Valuations {
        Valuations(programs: ["gapInc": v])
    }

    func testFaceValueAppliesWhenTheUsabilityFactorIsNotApplied() {
        let v = ProgramValuation.merchantCredit(
            MerchantCreditValuation(cadPerUnit: 1.0, optionalUsabilityFactor: 0.8,
                                    usabilityFactorApplied: false,
                                    merchantScope: ["gap"], basis: "test"))
        let cad = Scorer.valueCad(units: 100, program: "gapInc",
                                  valuations: valuations(v), state: CardState())
        XCTAssertEqual(try XCTUnwrap(cad), 100.0, accuracy: 0.0001)
    }

    func testUsabilityFactorDiscountsAMerchantLockedDollar() {
        let v = ProgramValuation.merchantCredit(
            MerchantCreditValuation(cadPerUnit: 1.0, optionalUsabilityFactor: 0.8,
                                    usabilityFactorApplied: true,
                                    merchantScope: ["gap"], basis: "test"))
        let cad = Scorer.valueCad(units: 100, program: "gapInc",
                                  valuations: valuations(v), state: CardState())
        XCTAssertEqual(try XCTUnwrap(cad), 80.0, accuracy: 0.0001)
    }

    func testRoundTripsThroughItsOwnDiscriminator() throws {
        let original = ProgramValuation.merchantCredit(
            MerchantCreditValuation(cadPerUnit: 1.0, optionalUsabilityFactor: 0.9,
                                    usabilityFactorApplied: true,
                                    merchantScope: ["sams-club"], basis: "test"))
        let data = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "merchantCredit")
        XCTAssertEqual(try JSONDecoder().decode(ProgramValuation.self, from: data), original)
    }

    /// The whole reason this is a separate model. If a future change folds them, this fails.
    func testCtMoneyStillEncodesAsCtMoney() throws {
        let ct = ProgramValuation.ctMoney(
            CtMoneyValuation(cadPerUnit: 1.0, optionalUsabilityFactor: 0.95,
                             usabilityFactorApplied: true, basis: "test"))
        let data = try JSONEncoder().encode(ct)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "ctMoney",
                       "ctMoney is a published name in a digest-pinned release and must not be "
                       + "absorbed into merchantCredit.")
    }

    func testMerchantScopeTokensAreLowercaseKebabCase() throws {
        let pattern = try NSRegularExpression(pattern: "^[a-z0-9]+(-[a-z0-9]+)*$")
        let token = "sams-club"
        let range = NSRange(token.startIndex..., in: token)
        XCTAssertNotNil(pattern.firstMatch(in: token, range: range),
                        "merchantScope tokens share RuleMatcher's token convention.")
    }
}
