import XCTest
@testable import CardCopilot

/// Chip is the only surface that volunteers app-health problems unasked, so what he pins to the
/// front of his queue is a product claim about what blocks what — worth pinning down in tests
/// rather than leaving to the order someone happened to write the `if`s in.
final class ChipAdvisorTests: XCTestCase {

    private var healthyAmbient: AmbientRuntimeStatus {
        var status = AmbientRuntimeStatus()
        status.locationAlways = true
        status.notificationAuthorization = .allowed
        status.backgroundRefresh = .available
        status.monitoredRegionCount = 4
        return status
    }

    private var blockedAmbient: AmbientRuntimeStatus {
        var status = healthyAmbient
        status.notificationAuthorization = .denied
        return status
    }

    private func evaluate(
        walletIsEmpty: Bool = false,
        hasSyncIssue: Bool = false,
        ambientIsEnabled: Bool = true,
        ambientStatus: AmbientRuntimeStatus? = nil
    ) -> [ChipAdvisory] {
        ChipAdvisor.evaluate(
            walletIsEmpty: walletIsEmpty,
            hasSyncIssue: hasSyncIssue,
            ambientIsEnabled: ambientIsEnabled,
            ambientStatus: ambientStatus ?? healthyAmbient)
    }

    // MARK: - Silence

    func testAHealthyAppGivesChipNothingToReport() {
        XCTAssertTrue(evaluate().isEmpty)
    }

    // MARK: - Priority

    /// An empty wallet stops checkout advice outright. Nothing else matters until there is a card
    /// to recommend, so it leads even when other things are also broken.
    func testEmptyWalletLeadsEvenWhenEverythingElseIsBrokenToo() {
        let advisories = evaluate(
            walletIsEmpty: true,
            hasSyncIssue: true,
            ambientStatus: blockedAmbient)

        XCTAssertEqual(advisories.first?.kind, .emptyWallet)
        XCTAssertEqual(advisories.count, 3)
    }

    func testUrgentAdvisoriesAllSortAheadOfTheRest() {
        let advisories = evaluate(
            walletIsEmpty: true,
            hasSyncIssue: true,
            ambientStatus: blockedAmbient)

        let firstUnpinned = advisories.firstIndex { !$0.isUrgent } ?? advisories.count
        XCTAssertTrue(advisories.prefix(firstUnpinned).allSatisfy(\.isUrgent))
        XCTAssertTrue(advisories.dropFirst(firstUnpinned).allSatisfy { !$0.isUrgent })
    }

    func testBrokenArrivalAlertsArePinned() {
        let advisories = evaluate(ambientStatus: blockedAmbient)
        XCTAssertEqual(advisories.map(\.kind), [.ambient(.notificationsBlocked)])
        XCTAssertEqual(advisories.first?.isUrgent, true)
    }

    /// Picks still work offline, so a stalled sync is worth mentioning but not worth interrupting
    /// for. Pinning it would spend Chip's one attention-grabbing move on something that is fine.
    func testAStalledSyncIsMentionedButNotPinned() {
        let advisories = evaluate(hasSyncIssue: true)
        XCTAssertEqual(advisories.map(\.kind), [.syncStalled])
        XCTAssertEqual(advisories.first?.isUrgent, false)
    }

    func testNeverConfiguredArrivalAlertsAreNotPinned() {
        let advisories = evaluate(ambientIsEnabled: false)
        XCTAssertEqual(advisories.map(\.kind), [.ambient(.notSetUp)])
        XCTAssertEqual(advisories.first?.isUrgent, false)
    }

    // MARK: - Every advisory leads somewhere

    func testEveryAdvisoryCarriesCopyAndARoute() {
        let advisories = evaluate(
            walletIsEmpty: true,
            hasSyncIssue: true,
            ambientStatus: blockedAmbient)

        XCTAssertFalse(advisories.isEmpty)
        for advisory in advisories {
            XCTAssertFalse(advisory.text.isEmpty, "\(advisory.kind) needs something to say")
            XCTAssertFalse(advisory.tag.isEmpty, "\(advisory.kind) needs a tag")
            XCTAssertFalse(advisory.actionLabel.isEmpty, "\(advisory.kind) needs an action label")
        }
    }

    func testAdvisoriesRouteToThePlaceThatFixesThem() {
        XCTAssertEqual(evaluate(walletIsEmpty: true).first?.destination, .walletSetup)
        XCTAssertEqual(evaluate(ambientStatus: blockedAmbient).first?.destination, .ambientSetup)
        XCTAssertEqual(evaluate(hasSyncIssue: true).first?.destination, .sync)
    }
}
