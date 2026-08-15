import XCTest
@testable import CardCopilotEngine

final class CapMathTests: XCTestCase {
    func testFullyUnderCap() {
        let s = CapMath.split(amount: 100, capLimit: 2500, usage: 0)
        XCTAssertEqual(s.inCap, 100, accuracy: 0.005)
        XCTAssertEqual(s.overCap, 0, accuracy: 0.005)
    }

    func testStraddlesCap() {
        let s = CapMath.split(amount: 100, capLimit: 2500, usage: 2450)
        XCTAssertEqual(s.inCap, 50, accuracy: 0.005)
        XCTAssertEqual(s.overCap, 50, accuracy: 0.005)
    }

    func testCapExhausted() {
        let s = CapMath.split(amount: 100, capLimit: 2500, usage: 2500)
        XCTAssertEqual(s.inCap, 0, accuracy: 0.005)
        XCTAssertEqual(s.overCap, 100, accuracy: 0.005)
    }

    func testUsageBeyondLimitClampsToZeroRoom() {
        let s = CapMath.split(amount: 100, capLimit: 2500, usage: 2600)
        XCTAssertEqual(s.inCap, 0, accuracy: 0.005)
        XCTAssertEqual(s.overCap, 100, accuracy: 0.005)
    }
}
