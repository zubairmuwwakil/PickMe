import XCTest
import CardCopilotEngine
@testable import CardCopilotStore

/// Delivery truth: what actually became of an arrival notification.
///
/// Today the app records only "iOS accepted the request", which cannot separate "we never asked",
/// "iOS dropped it" and "it appeared and was missed" — the exact ambiguity that opened this
/// investigation.
final class ArrivalDeliveryTests: XCTestCase {

    /// The gate never reached `.interrupt`. Nothing was asked of iOS, and reporting that as a
    /// delivery failure would blame the plumbing for a policy decision.
    func testAnArrivalThatNeverAskedIsNeverRequested() {
        XCTAssertEqual(
            arrivalNotificationDelivery(requestIdentifier: nil, requestFailed: false,
                                        deliveredIdentifiers: []),
            .neverRequested)
    }

    /// `UNUserNotificationCenter.add` threw. The app asked and was refused, which is a different
    /// fault from the app never asking.
    func testARequestThatThrewIsRequestFailed() {
        XCTAssertEqual(
            arrivalNotificationDelivery(requestIdentifier: nil, requestFailed: true,
                                        deliveredIdentifiers: []),
            .requestFailed)
    }

    func testAnAcceptedRequestPresentInNotificationCentreIsAcceptedAndPresent() {
        XCTAssertEqual(
            arrivalNotificationDelivery(requestIdentifier: "ambient.arrival.a.1",
                                        requestFailed: false,
                                        deliveredIdentifiers: ["ambient.arrival.a.1"]),
            .acceptedAndPresent)
    }

    /// **The outcome nothing could previously see.** iOS took the request and the notification is
    /// not in Notification Center — the alert the owner never got despite a "fired" count.
    func testAnAcceptedRequestMissingFromNotificationCentreIsAcceptedThenAbsent() {
        XCTAssertEqual(
            arrivalNotificationDelivery(requestIdentifier: "ambient.arrival.a.1",
                                        requestFailed: false,
                                        deliveredIdentifiers: ["ambient.arrival.b.2"]),
            .acceptedThenAbsent)
    }

    /// A throw beats an identifier. If both are somehow present the request did not succeed, and
    /// reading the identifier first would report a delivery that never happened.
    func testAFailedRequestIsReportedAsFailedEvenWithAnIdentifier() {
        XCTAssertEqual(
            arrivalNotificationDelivery(requestIdentifier: "ambient.arrival.a.1",
                                        requestFailed: true, deliveredIdentifiers: []),
            .requestFailed)
    }
}
