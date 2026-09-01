import XCTest
@testable import CardCopilot

/// Arrival alerts fail silently by construction — the symptom of a revoked permission is that
/// nothing happens, which looks exactly like not having been near a store. These pin down when
/// Chip speaks up about it, and just as importantly when he stays quiet.
final class ChipAmbientHealthTests: XCTestCase {

    private func status(
        locationAlways: Bool = true,
        notifications: AmbientNotificationAuthorization = .allowed,
        backgroundRefresh: AmbientBackgroundRefreshState = .available,
        regions: Int = 4
    ) -> AmbientRuntimeStatus {
        var status = AmbientRuntimeStatus()
        status.locationAlways = locationAlways
        status.notificationAuthorization = notifications
        status.backgroundRefresh = backgroundRefresh
        status.monitoredRegionCount = regions
        return status
    }

    // MARK: - Silence

    func testHealthyAlertsSayNothing() {
        XCTAssertNil(ChipAmbientAdvisory.evaluate(isEnabled: true, status: status()))
    }

    /// Region monitoring populates a moment after setup. That resolves itself, so nagging about
    /// it would train the owner to ignore Chip on the one occasion it matters.
    func testStillPreparingRegionsSaysNothing() {
        XCTAssertNil(ChipAmbientAdvisory.evaluate(isEnabled: true, status: status(regions: 0)))
    }

    // MARK: - Degraded

    func testRevokedNotificationsAreReported() {
        XCTAssertEqual(
            ChipAmbientAdvisory.evaluate(isEnabled: true, status: status(notifications: .denied)),
            .notificationsBlocked)
    }

    func testDisabledBackgroundRefreshIsReported() {
        XCTAssertEqual(
            ChipAmbientAdvisory.evaluate(isEnabled: true, status: status(backgroundRefresh: .denied)),
            .backgroundRefreshBlocked)
    }

    func testDowngradedLocationIsReported() {
        XCTAssertEqual(
            ChipAmbientAdvisory.evaluate(isEnabled: true, status: status(locationAlways: false)),
            .locationBlocked)
    }

    /// Always-location is the root dependency: without it the other two cannot matter, so
    /// reporting them first would send the owner to fix the wrong switch.
    func testLocationOutranksTheOtherBlockers() {
        let everythingBroken = status(
            locationAlways: false,
            notifications: .denied,
            backgroundRefresh: .denied)
        XCTAssertEqual(
            ChipAmbientAdvisory.evaluate(isEnabled: true, status: everythingBroken),
            .locationBlocked)
    }

    // MARK: - Discovery

    func testNeverConfiguredIsOfferedButNotUrgent() {
        let advisory = ChipAmbientAdvisory.evaluate(isEnabled: false, status: status())
        XCTAssertEqual(advisory, .notSetUp)
        XCTAssertEqual(advisory?.isUrgent, false, "an unconfigured optional feature is a choice, not a fault")
    }

    func testEveryDegradedStateIsUrgent() {
        for advisory in ChipAmbientAdvisory.allCases where advisory != .notSetUp {
            XCTAssertTrue(advisory.isUrgent, "\(advisory) should jump the queue")
        }
    }

    func testEveryAdvisoryCarriesCopyAndAWayOut() {
        for advisory in ChipAmbientAdvisory.allCases {
            XCTAssertFalse(advisory.text.isEmpty, "\(advisory) needs something to say")
            XCTAssertFalse(advisory.tag.isEmpty, "\(advisory) needs a tag")
            XCTAssertFalse(advisory.actionLabel.isEmpty, "\(advisory) needs an action label")
        }
    }
}
