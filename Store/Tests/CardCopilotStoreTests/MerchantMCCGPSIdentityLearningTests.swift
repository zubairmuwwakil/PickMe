import XCTest
@testable import CardCopilotStore

final class MerchantMCCGPSIdentityLearningTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var identityStore: MerchantMCCIdentityLearningStore!

    override func setUp() {
        super.setUp()
        suite = "MerchantMCCGPSIdentityLearningTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        identityStore = MerchantMCCIdentityLearningStore(defaults: defaults,
                                                         storageKey: "gps-identity")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        identityStore = nil
        defaults = nil
        suite = nil
        super.tearDown()
    }

    private func purchase(eventID: String, alias: String = "PIZZAPIZZAONLINE") -> StoredPurchase {
        StoredPurchase(createdAt: Date(timeIntervalSince1970: 1_788_528_000),
                       merchantLabel: alias,
                       walletEventId: eventID,
                       activitySource: .walletCapture)
    }

    private func resolution(name: String = "Pizza Pizza") -> WalletMerchantResolution {
        WalletMerchantResolution(
            merchant: NearbyPlace(id: "mapkit-pizza-pizza", placeID: "apple-pizza-pizza",
                                  name: name, poiCategoryRaw: "MKPOICategoryRestaurant",
                                  latitude: 43.65, longitude: -79.38, distanceMeters: 24),
            prediction: CategoryPrediction(category: "dining",
                                           confidenceSource: .mapKitCategory,
                                           candidates: ["dining"]))
    }

    func testTwoResolvedWalletPurchasesActivateAnAlias() throws {
        XCTAssertNil(MerchantMCCSeedCatalogue.canonicalMatch(
            merchantName: "PIZZAPIZZAONLINE"),
            "fixture must prove GPS learning adds coverage beyond the static matcher")

        XCTAssertTrue(learnMerchantAliasFromGPSResolution(
            purchase: purchase(eventID: "gps-evt-1"),
            resolution: resolution(),
            identityStore: identityStore))
        XCTAssertEqual(identityStore.evidenceCount(for: "PIZZAPIZZAONLINE"), 1)
        XCTAssertNil(identityStore.match(merchantName: "PIZZAPIZZAONLINE"))

        XCTAssertTrue(learnMerchantAliasFromGPSResolution(
            purchase: purchase(eventID: "gps-evt-2"),
            resolution: resolution(),
            identityStore: identityStore))

        XCTAssertEqual(identityStore.evidenceCount(for: "PIZZAPIZZAONLINE"), 2)
        XCTAssertEqual(identityStore.match(merchantName: "PIZZAPIZZAONLINE")?.merchant.id,
                       "pizza-pizza")
    }

    func testReplayingTheSameWalletEventCannotInflateConfidence() {
        let purchase = purchase(eventID: "gps-evt-1")
        XCTAssertTrue(learnMerchantAliasFromGPSResolution(
            purchase: purchase, resolution: resolution(), identityStore: identityStore))
        XCTAssertFalse(learnMerchantAliasFromGPSResolution(
            purchase: purchase, resolution: resolution(), identityStore: identityStore))
        XCTAssertEqual(identityStore.evidenceCount(for: "PIZZAPIZZAONLINE"), 1)
    }

    func testResolvedIndependentMerchantCannotBecomeASeedAlias() {
        XCTAssertFalse(learnMerchantAliasFromGPSResolution(
            purchase: purchase(eventID: "gps-local"),
            resolution: resolution(name: "Mom's Kitchen"),
            identityStore: identityStore))
        XCTAssertEqual(identityStore.evidenceCount(for: "PIZZAPIZZAONLINE"), 0)
    }
}
