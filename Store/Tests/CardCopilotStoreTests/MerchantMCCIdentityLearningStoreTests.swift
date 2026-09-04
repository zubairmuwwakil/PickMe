import XCTest
@testable import CardCopilotStore

final class MerchantMCCIdentityLearningStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "MerchantMCCIdentityLearningStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        suite = nil
        super.tearDown()
    }

    func testAliasNeedsTwoIndependentObservationsBeforeItResolves() throws {
        let store = MerchantMCCIdentityLearningStore(defaults: defaults, storageKey: "identity")
        let alias = "WMTX 9087"

        XCTAssertTrue(store.record(alias: alias, merchantID: "walmart",
                                   sourceFingerprint: "wallet:event-1"))
        XCTAssertNil(store.match(merchantName: alias))

        XCTAssertTrue(store.record(alias: alias, merchantID: "walmart",
                                   sourceFingerprint: "wallet:event-2"))
        let match = try XCTUnwrap(store.match(merchantName: alias))
        XCTAssertEqual(match.merchant.id, "walmart")
        XCTAssertEqual(store.evidenceCount(for: alias), 2)
    }

    func testReplayDoesNotInflateAliasConfidence() {
        let store = MerchantMCCIdentityLearningStore(defaults: defaults, storageKey: "identity")
        let alias = "WMTX 9087"

        XCTAssertTrue(store.record(alias: alias, merchantID: "walmart",
                                   sourceFingerprint: "wallet:event-1"))
        XCTAssertFalse(store.record(alias: alias, merchantID: "walmart",
                                    sourceFingerprint: "wallet:event-1"))
        XCTAssertEqual(store.evidenceCount(for: alias), 1)
        XCTAssertNil(store.match(merchantName: alias))
    }

    func testConflictingMerchantAnchorsFailClosed() {
        let store = MerchantMCCIdentityLearningStore(defaults: defaults, storageKey: "identity")
        let alias = "PROCESSOR MERCHANT 4432"

        XCTAssertTrue(store.record(alias: alias, merchantID: "walmart",
                                   sourceFingerprint: "wallet:event-1"))
        XCTAssertTrue(store.record(alias: alias, merchantID: "walmart",
                                   sourceFingerprint: "wallet:event-2"))
        XCTAssertNotNil(store.match(merchantName: alias))

        XCTAssertTrue(store.record(alias: alias, merchantID: "best-buy",
                                   sourceFingerprint: "wallet:event-3"))
        XCTAssertNil(store.match(merchantName: alias),
                     "one conflicting canonical identity must disable the learned alias")
    }

    func testCuratedCanonicalMatchCannotBeShadowed() throws {
        let store = MerchantMCCIdentityLearningStore(defaults: defaults, storageKey: "identity")

        XCTAssertFalse(store.record(alias: "Best Buy", merchantID: "walmart",
                                    sourceFingerprint: "wallet:event-1"))
        let canonical = try XCTUnwrap(MerchantMCCSeedCatalogue.canonicalMatch(merchantName: "Best Buy"))
        XCTAssertEqual(canonical.merchant.id, "best-buy")
    }

    func testObservationsPersistAcrossStoreInstances() throws {
        let alias = "WMTX 9087"
        var store = MerchantMCCIdentityLearningStore(defaults: defaults, storageKey: "identity")
        XCTAssertTrue(store.record(alias: alias, merchantID: "walmart",
                                   sourceFingerprint: "wallet:event-1"))
        XCTAssertTrue(store.record(alias: alias, merchantID: "walmart",
                                   sourceFingerprint: "wallet:event-2"))

        store = MerchantMCCIdentityLearningStore(defaults: defaults, storageKey: "identity")
        XCTAssertEqual(try XCTUnwrap(store.match(merchantName: alias)).merchant.id, "walmart")
    }
}
