import XCTest
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

/// The second delivery sample: what Notification Center is holding next time the app is opened.
///
/// One sample is not enough. Taken alone, "not in Notification Center" seconds after scheduling
/// cannot tell a notification iOS dropped from one that simply had not landed yet, and taken alone
/// on next foreground it cannot tell one that was dropped from one the owner saw and cleared.
@MainActor
final class ArrivalDeliveryLogTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> ArrivalFieldLogStore {
        ArrivalFieldLogStore(
            defaults: UserDefaults(suiteName: "ArrivalDelivery.\(UUID().uuidString)")!)
    }

    private func arrival(requestIdentifier: String?,
                         atSchedule: ArrivalNotificationDelivery) -> ArrivalFieldRecord {
        var record = ArrivalFieldRecord(
            recordedAt: epoch, regionId: "ambient.region.area:1", source: .regionEntry,
            rung: .areaMember, resolvedMerchantName: "Shoppers Drug Mart",
            resolvedCategory: "drugStore", estimatedAmountCad: 25,
            gateInput: AmbientGateInput(
                merchantConfidence: .brandMatched, recommendedCardId: "amex-cobalt",
                defaultCardId: "wealthsimple-vip",
                advantage: AmbientAdvantage(percentagePoints: 2, cad: 0.5),
                switchThreshold: SwitchThreshold(minAdvantagePercentagePoints: 0.5,
                                                 minAdvantageCad: 0.25, semantics: "both"),
                isMuted: false),
            deliveryTier: .interrupt, suppressionReasons: [], policy: .shipped)
        record.notificationRequestIdentifier = requestIdentifier
        record.notificationDeliveryAtSchedule = atSchedule
        return record
    }

    /// The alert was there when it was scheduled and is gone now. Either the owner saw it, or iOS
    /// cleared it — and either way it reached Notification Center, which is what separates this
    /// from a drop.
    func testAnAlertPresentAtScheduleAndGoneLaterIsRecordedAsAbsentOnForeground() throws {
        let store = makeStore()
        store.record(arrival(requestIdentifier: "ambient.arrival.a.1",
                             atSchedule: .acceptedAndPresent))

        store.recordForegroundDelivery(deliveredIdentifiers: [])

        XCTAssertEqual(store.all()[0].notificationDeliveryOnForeground, .acceptedThenAbsent)
        // The first sample is not rewritten: the two together are the finding.
        XCTAssertEqual(store.all()[0].notificationDeliveryAtSchedule, .acceptedAndPresent)
    }

    /// A notification that had not landed when it was sampled and is there now. Without the second
    /// sample this would have been filed as a drop.
    func testAnAlertAbsentAtScheduleAndPresentLaterIsRecordedAsPresentOnForeground() {
        let store = makeStore()
        store.record(arrival(requestIdentifier: "ambient.arrival.a.1",
                             atSchedule: .acceptedThenAbsent))

        store.recordForegroundDelivery(deliveredIdentifiers: ["ambient.arrival.a.1"])

        XCTAssertEqual(store.all()[0].notificationDeliveryOnForeground, .acceptedAndPresent)
    }

    /// An arrival that never asked for a notification has nothing to resample. Writing a second
    /// sample for it would turn a policy decision into a delivery statistic.
    func testAnArrivalThatNeverRequestedIsLeftAlone() {
        let store = makeStore()
        store.record(arrival(requestIdentifier: nil, atSchedule: .neverRequested))

        store.recordForegroundDelivery(deliveredIdentifiers: [])

        XCTAssertNil(store.all()[0].notificationDeliveryOnForeground)
    }

    /// "Next foreground" is once. A second opening of the app hours later says nothing about
    /// delivery and would overwrite the answer with the owner's tidying habits.
    func testTheForegroundSampleIsTakenOnlyOnce() {
        let store = makeStore()
        store.record(arrival(requestIdentifier: "ambient.arrival.a.1",
                             atSchedule: .acceptedAndPresent))

        store.recordForegroundDelivery(deliveredIdentifiers: ["ambient.arrival.a.1"])
        store.recordForegroundDelivery(deliveredIdentifiers: [])

        XCTAssertEqual(store.all()[0].notificationDeliveryOnForeground, .acceptedAndPresent)
    }

    /// A Radar scan asks for no notification at all, so it must not acquire a delivery outcome.
    func testARadarScanIsNotGivenADeliveryOutcome() {
        let store = makeStore()
        store.record(radarFieldRecord(recordedAt: epoch, fix: nil, rawResultCount: 0,
                                      merchants: []))

        store.recordForegroundDelivery(deliveredIdentifiers: [])

        XCTAssertNil(store.all()[0].notificationDeliveryOnForeground)
    }
}
