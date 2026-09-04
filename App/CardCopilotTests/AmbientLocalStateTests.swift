import XCTest
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

/// The three UserDefaults-backed stores behind ambient arrival alerts, and exactly what the
/// "erase this iPhone's history" choice has to clear: the mute list is keyed to merchant place
/// identities, the suppression counters are a per-day record of when the app decided to speak up,
/// and the coverage counters are a per-day record of what it never got the chance to decide.
final class AmbientLocalStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let placeIdentifier = "I2A0F1C6D4B89E37"
    private let otherPlaceIdentifier = "I7E3B95AC28D064F"

    override func setUpWithError() throws {
        // A private suite, never `.standard`: these tests must not read or write the state of a
        // real install on the same machine.
        suiteName = "AmbientLocalStateTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }
}

@MainActor
extension AmbientLocalStateTests {
    private func suppressed(_ reason: AmbientSuppressionReason) -> AmbientGateDecision {
        AmbientGateDecision(suppressionReasons: [reason])
    }

    private var fired: AmbientGateDecision { AmbientGateDecision(suppressionReasons: []) }

    // MARK: - Mute list

    // Mute identity is `NearbyPlace.id`: the Apple Maps place identifier the POI carries, not
    // `StoredMerchant.id`. Discovery reaches merchants that have never been stored locally and so
    // have no local UUID, and the place id is the only identity the stored and discovered rungs
    // share. These stand in for what MapKit hands back.
    func testAMutedMerchantStaysMutedForALaterReader() {
        AmbientMerchantMuteStore(defaults: defaults).mute(placeIdentifier)

        // A fresh instance, as the notification handler creates: muting has to survive the store.
        XCTAssertTrue(AmbientMerchantMuteStore(defaults: defaults).isMuted(placeIdentifier))
    }

    func testMutingOneMerchantDoesNotMuteAnother() {
        let store = AmbientMerchantMuteStore(defaults: defaults)
        store.mute(placeIdentifier)

        XCTAssertFalse(store.isMuted(otherPlaceIdentifier))
    }

    /// The fallback rung. A POI without a place identifier is keyed by its name, and a stored
    /// merchant without one by its UUID string — the store takes both as opaque keys, so a mute
    /// on the fallback must not leak onto the place-id keyspace or vice versa.
    func testAMerchantWithNoPlaceIdentifierMutesUnderItsFallbackKey() {
        let store = AmbientMerchantMuteStore(defaults: defaults)
        let fallbackKey = UUID().uuidString

        store.mute(fallbackKey)

        XCTAssertTrue(store.isMuted(fallbackKey))
        XCTAssertFalse(store.isMuted(placeIdentifier))
    }

    func testForgettingEverythingClearsTheMuteList() {
        let store = AmbientMerchantMuteStore(defaults: defaults)
        store.mute(placeIdentifier)

        store.forgetAll()

        XCTAssertFalse(store.isMuted(placeIdentifier))
        XCTAssertFalse(AmbientMerchantMuteStore(defaults: defaults).isMuted(placeIdentifier))
    }

    // MARK: - Field-test counters

    func testCountersSeparateFiredDecisionsFromSuppressedOnes() {
        let store = AmbientDiagnosticsStore(defaults: defaults)
        let day = Date(timeIntervalSince1970: 1_786_000_000)
        store.record(fired, at: day)
        store.record(suppressed(.merchantMuted), at: day)
        store.record(suppressed(.merchantMuted), at: day)

        let log = store.lastSevenDays(ending: day)

        XCTAssertEqual(log.fired, 1)
        XCTAssertEqual(log.suppressed, 2)
        XCTAssertEqual(log.suppressedByReason[.merchantMuted], 2)
    }

    func testCountersOlderThanTheWindowAreNotReported() {
        let store = AmbientDiagnosticsStore(defaults: defaults)
        let today = Date(timeIntervalSince1970: 1_786_000_000)
        let eightDaysAgo = today.addingTimeInterval(-8 * 24 * 60 * 60)
        store.record(fired, at: eightDaysAgo)
        store.record(fired, at: today)

        // The dashboard claims "the last seven days"; a stale day leaking in would overstate it.
        XCTAssertEqual(store.lastSevenDays(ending: today).fired, 1)
    }

    func testForgettingEverythingClearsTheCounters() {
        let store = AmbientDiagnosticsStore(defaults: defaults)
        let day = Date(timeIntervalSince1970: 1_786_000_000)
        store.record(fired, at: day)
        store.record(suppressed(.advantageBelowSwitchThreshold), at: day)

        store.forgetAll()

        XCTAssertEqual(store.lastSevenDays(ending: day), SuppressionLog())
    }

    // MARK: - Coverage counters

    private func rotation(granted: Int, evicted: [AmbientRegionTier]) -> RegionAllocation {
        RegionAllocation(
            granted: (0..<granted).map {
                RegionCandidate(id: "granted\($0)", tier: .discoveredArea, distanceMeters: 0)
            },
            evicted: evicted.enumerated().map {
                RegionCandidate(id: "evicted\($0.offset)", tier: $0.element, distanceMeters: 999)
            },
            limit: granted)
    }

    func testCoverageSurvivesTheStore() {
        let day = Date(timeIntervalSince1970: 1_786_000_000)
        AmbientCoverageStore(defaults: defaults)
            .record(rotation(granted: 20, evicted: [.frequentedMerchant, .discoveredArea]), at: day)

        // A fresh instance, as the geofence wake creates.
        let reread = AmbientCoverageStore(defaults: defaults).lastSevenDays(ending: day)
        XCTAssertEqual(reread.rotations, 1)
        XCTAssertEqual(reread.rotationsAtCapacity, 1)
        XCTAssertEqual(reread.evictedWithStanding, 1)
        XCTAssertEqual(reread.evicted, 2)
    }

    func testCoverageOlderThanTheWindowIsNotReported() {
        let store = AmbientCoverageStore(defaults: defaults)
        let today = Date(timeIntervalSince1970: 1_786_000_000)
        store.record(rotation(granted: 20, evicted: [.frequentedMerchant]),
                     at: today.addingTimeInterval(-8 * 24 * 60 * 60))
        store.record(rotation(granted: 20, evicted: []), at: today)

        XCTAssertEqual(store.lastSevenDays(ending: today).rotations, 1)
        XCTAssertEqual(store.lastSevenDays(ending: today).evicted, 0)
    }

    func testTheArrivalFunnelPersistsItsDropouts() {
        let store = AmbientCoverageStore(defaults: defaults)
        let day = Date(timeIntervalSince1970: 1_786_000_000)
        store.recordArrival(.resolved, at: day)
        store.recordArrival(.unresolved, at: day)
        store.recordArrival(.notAdvised, at: day)

        let log = store.lastSevenDays(ending: day)
        XCTAssertEqual(log.arrivals, 3)
        XCTAssertEqual(log.arrivalsReachingTheGate, 1)
        XCTAssertEqual(log.arrivalsUnresolved, 1)
        XCTAssertEqual(log.arrivalsNotAdvised, 1)
    }

    func testForgettingEverythingClearsTheCoverageCounters() {
        let store = AmbientCoverageStore(defaults: defaults)
        let day = Date(timeIntervalSince1970: 1_786_000_000)
        store.record(rotation(granted: 20, evicted: [.confirmedMerchant]), at: day)
        store.recordArrival(.unresolved, at: day)

        store.forgetAll()

        XCTAssertEqual(store.lastSevenDays(ending: day), AmbientCoverageLog())
    }

    /// The hazard introduced by generalising both stores onto one `DailyLogStore`: they now share
    /// a class, a day-key format, and a defaults suite, and only their key string keeps them
    /// apart. A copy-pasted key would silently fold the coverage counters into the suppression
    /// counters — where they would decode as garbage or, worse, as plausible numbers.
    func testTheTwoLogsDoNotShareAKeyspace() {
        let day = Date(timeIntervalSince1970: 1_786_000_000)
        AmbientDiagnosticsStore(defaults: defaults).record(fired, at: day)
        AmbientCoverageStore(defaults: defaults)
            .record(rotation(granted: 20, evicted: [.frequentedMerchant]), at: day)

        XCTAssertEqual(AmbientDiagnosticsStore(defaults: defaults).lastSevenDays(ending: day).fired, 1)
        XCTAssertEqual(AmbientCoverageStore(defaults: defaults).lastSevenDays(ending: day).rotations, 1)
    }

    /// Wiping one log must not wipe the other: "erase local history" clears both, but each store
    /// is also reachable on its own.
    func testForgettingCoverageLeavesTheSuppressionCountersAlone() {
        let day = Date(timeIntervalSince1970: 1_786_000_000)
        AmbientDiagnosticsStore(defaults: defaults).record(fired, at: day)

        AmbientCoverageStore(defaults: defaults).forgetAll()

        XCTAssertEqual(AmbientDiagnosticsStore(defaults: defaults).lastSevenDays(ending: day).fired, 1)
    }

    // MARK: - Delivery health

    func testRuntimeStatusRequiresEveryDeliveryDependencyAndARegion() {
        var status = AmbientRuntimeStatus(locationAlways: true,
                                          notificationAuthorization: .allowed,
                                          backgroundRefresh: .available,
                                          monitoredRegionCount: 0)
        XCTAssertFalse(status.isReady)

        status.monitoredRegionCount = 4
        XCTAssertTrue(status.isReady)

        status.notificationAuthorization = .denied
        XCTAssertFalse(status.isReady)
        XCTAssertTrue(status.hasSystemBlocker)
    }

    func testRuntimeStorePersistsAcceptedNotificationsAndFailures() {
        let scheduledAt = Date(timeIntervalSince1970: 1_786_000_000)
        let failedAt = scheduledAt.addingTimeInterval(60)
        let writer = AmbientRuntimeStore(defaults: defaults)
        writer.recordScheduledNotification(at: scheduledAt)
        writer.recordIssue("region monitoring failed", at: failedAt)

        let reader = AmbientRuntimeStore(defaults: defaults)
        XCTAssertEqual(reader.lastNotificationScheduledAt, scheduledAt)
        XCTAssertEqual(reader.latestIssue,
                       AmbientRuntimeIssue(message: "region monitoring failed", recordedAt: failedAt))

        reader.forgetAll()
        XCTAssertNil(AmbientRuntimeStore(defaults: defaults).lastNotificationScheduledAt)
        XCTAssertNil(AmbientRuntimeStore(defaults: defaults).latestIssue)
    }

    // MARK: - Explainer View

    func testExplainerViewInitializesInEnabledAndUnenabledStates() {
        let unenabledView = AmbientLocationExplainerView(
            isEnabled: false,
            diagnostics: nil,
            coverage: nil,
            onEnable: {},
            onDone: {}
        )
        XCTAssertFalse(unenabledView.isEnabled)
        XCTAssertNil(unenabledView.diagnostics)
        XCTAssertNil(unenabledView.coverage)

        let diagnostics = SuppressionLog(fired: 3, suppressed: 1)
        let enabledView = AmbientLocationExplainerView(
            isEnabled: true,
            diagnostics: diagnostics,
            coverage: AmbientCoverageLog(rotations: 5, rotationsAtCapacity: 4,
                                         evictedByTier: [.frequentedMerchant: 2]),
            runtimeStatus: AmbientRuntimeStatus(locationAlways: true,
                                                notificationAuthorization: .allowed,
                                                monitoredRegionCount: 3),
            onEnable: {},
            onDone: {}
        )
        XCTAssertTrue(enabledView.isEnabled)
        XCTAssertEqual(enabledView.diagnostics?.fired, 3)
        XCTAssertEqual(enabledView.diagnostics?.suppressed, 1)
        XCTAssertEqual(enabledView.coverage?.evictedWithStanding, 2)
        XCTAssertTrue(enabledView.runtimeStatus?.isReady == true)
    }
}
