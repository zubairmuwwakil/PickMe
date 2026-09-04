import XCTest
import CardCopilotStore
@testable import CardCopilot

/// The outcome→step mapping is the only part of the checkout flow that was previously
/// untestable at any price: it lived inline in a 846-line SwiftUI view, tangled with MapKit
/// calls and @State mutation. Pulling it out as a pure function is the point of the split.
final class CheckoutFlowRoutingTests: XCTestCase {

    private func merchant(_ name: String) -> NearbyPlace {
        NearbyPlace(id: "test:\(name)", name: name, poiCategoryRaw: nil,
                       latitude: 0, longitude: 0, distanceMeters: nil)
    }

    func testFoundMerchantsGoesToConfirming() {
        let found = [merchant("Loblaws"), merchant("Metro")]
        guard case .confirming(let merchants) = CheckoutFlowRouting.step(for: .found(found)) else {
            return XCTFail("expected .confirming")
        }
        XCTAssertEqual(merchants, found)
    }

    /// An empty result is a dead end in the checkout flow, so it stays a full-screen step
    /// rather than an alert — the owner has nothing to act on and must start over.
    func testNothingFoundNearbyReportsTheNearbyCase() {
        guard case .failed(let message) = CheckoutFlowRouting.step(for: .nothingFound(query: nil)) else {
            return XCTFail("expected .failed")
        }
        XCTAssertTrue(message.contains("nearby"), "got: \(message)")
    }

    /// A failed text search must name what was searched for. Losing the query was a real
    /// wording regression risk when this logic moved out of the view.
    func testNothingFoundBySearchQuotesTheQuery() {
        guard case .failed(let message) = CheckoutFlowRouting.step(for: .nothingFound(query: "Loblws")) else {
            return XCTFail("expected .failed")
        }
        XCTAssertTrue(message.contains("Loblws"), "got: \(message)")
    }

    /// Apple guideline 5.1.1: declining location must leave the manual path usable, so this
    /// returns to idle rather than to an error the owner cannot clear.
    func testLocationDeniedReturnsToIdleNotAnError() {
        guard case .idle = CheckoutFlowRouting.step(for: .locationDenied) else {
            return XCTFail("expected .idle")
        }
    }

    func testFailurePropagatesItsMessage() {
        guard case .failed(let message) = CheckoutFlowRouting.step(for: .failed("network down")) else {
            return XCTFail("expected .failed")
        }
        XCTAssertEqual(message, "network down")
    }
}
