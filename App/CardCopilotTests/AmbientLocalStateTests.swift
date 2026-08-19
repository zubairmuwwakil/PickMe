import XCTest
import CardCopilotEngine
@testable import CardCopilot

/// The two UserDefaults-backed stores behind ambient arrival alerts. They were the only
/// app-target state with no coverage at all, and they are exactly what the "erase this iPhone's
/// history" choice has to clear: the mute list is keyed to merchant place identities, and the
/// counters are a per-day record of when the app decided to speak up.
@MainActor
final class AmbientLocalStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

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

    private func suppressed(_ reason: AmbientSuppressionReason) -> AmbientGateDecision {
        AmbientGateDecision(suppressionReasons: [reason])
    }

    private var fired: AmbientGateDecision { AmbientGateDecision(suppressionReasons: []) }

    // MARK: - Mute list

    // Mute identity is `NearbyMerchant.id`: the Apple Maps place identifier the POI carries, not
    // `StoredMerchant.id`. Discovery reaches merchants that have never been stored locally and so
    // have no local UUID, and the place id is the only identity the stored and discovered rungs
    // share. These stand in for what MapKit hands back.
    private let placeIdentifier = "I2A0F1C6D4B89E37"
    private let otherPlaceIdentifier = "I7E3B95AC28D064F"

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

    // MARK: - Explainer View

    func testExplainerViewInitializesInEnabledAndUnenabledStates() {
        let unenabledView = AmbientLocationExplainerView(
            isEnabled: false,
            diagnostics: nil,
            onEnable: {},
            onDone: {}
        )
        XCTAssertFalse(unenabledView.isEnabled)
        XCTAssertNil(unenabledView.diagnostics)

        let diagnostics = SuppressionLog(fired: 3, suppressed: 1)
        let enabledView = AmbientLocationExplainerView(
            isEnabled: true,
            diagnostics: diagnostics,
            onEnable: {},
            onDone: {}
        )
        XCTAssertTrue(enabledView.isEnabled)
        XCTAssertEqual(enabledView.diagnostics?.fired, 3)
        XCTAssertEqual(enabledView.diagnostics?.suppressed, 1)
    }
}
