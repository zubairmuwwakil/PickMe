import XCTest
@testable import CardCopilotStore

final class ArrivalAlertPreferenceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: ArrivalAlertPreferenceStore!

    override func setUp() {
        super.setUp()
        suiteName = "ArrivalAlertPreferenceStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = ArrivalAlertPreferenceStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testChainPreferencePermitsAnotherBranch() {
        store.save(ArrivalAlertPreference(merchantKey: "walmart", merchantName: "Walmart",
                                          scope: .chain, locationIdentifier: "ajax",
                                          latitude: 43.85, longitude: -79.02))
        XCTAssertEqual(store.permits(merchantKey: "walmart", locationIdentifier: "oshawa",
                                     latitude: 43.90, longitude: -78.86), true)
        XCTAssertEqual(store.chainKeys(), ["walmart"])
    }

    func testExactPreferenceRejectsAnotherBranchAndAcceptsCoordinateFallback() {
        store.save(ArrivalAlertPreference(merchantKey: "walmart", merchantName: "Walmart",
                                          scope: .exactLocation,
                                          locationIdentifier: "ajax-store",
                                          latitude: 43.8500, longitude: -79.0200))
        XCTAssertEqual(store.permits(merchantKey: "walmart", locationIdentifier: "oshawa-store",
                                     latitude: 43.90, longitude: -78.86), false)
        XCTAssertEqual(store.permits(merchantKey: "walmart", locationIdentifier: nil,
                                     latitude: 43.8502, longitude: -79.0202), true)
    }

    func testAutomaticDefersToPatronageAndDisabledRefuses() {
        store.save(ArrivalAlertPreference(merchantKey: "walmart", merchantName: "Walmart",
                                          scope: .automatic))
        XCTAssertNil(store.permits(merchantKey: "walmart", locationIdentifier: "ajax",
                                   latitude: 43.85, longitude: -79.02))

        store.save(ArrivalAlertPreference(merchantKey: "walmart", merchantName: "Walmart",
                                          scope: .disabled))
        XCTAssertEqual(store.permits(merchantKey: "walmart", locationIdentifier: "ajax",
                                     latitude: 43.85, longitude: -79.02), false)
    }
}
