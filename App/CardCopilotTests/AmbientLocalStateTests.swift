import XCTest
import CardCopilotEngine
@testable import CardCopilot

/// The two UserDefaults-backed stores behind ambient arrival alerts. They were the only
/// app-target state with no coverage at all, and they are exactly what the "erase this iPhone's
/// history" choice has to clear: the mute list is keyed to merchant rows, and the counters are a
/// per-day record of when the app decided to speak up.
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

    func testAMutedMerchantStaysMutedForALaterReader() {
        let merchant = UUID()
        AmbientMerchantMuteStore(defaults: defaults).mute(merchant)

        // A fresh instance, as the notification handler creates: muting has to survive the store.
        XCTAssertTrue(AmbientMerchantMuteStore(defaults: defaults).isMuted(merchant))
    }

    func testMutingOneMerchantDoesNotMuteAnother() {
        let store = AmbientMerchantMuteStore(defaults: defaults)
        store.mute(UUID())

        XCTAssertFalse(store.isMuted(UUID()))
    }

    func testForgettingEverythingClearsTheMuteList() {
        let store = AmbientMerchantMuteStore(defaults: defaults)
        let merchant = UUID()
        store.mute(merchant)

        store.forgetAll()

        XCTAssertFalse(store.isMuted(merchant))
        XCTAssertFalse(AmbientMerchantMuteStore(defaults: defaults).isMuted(merchant))
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
}
