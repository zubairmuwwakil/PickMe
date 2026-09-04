import XCTest
@testable import CardCopilotStore

final class MerchantMCCGraphEvidenceBuilderTests: XCTestCase {
    func testExplicitReconciledMccBecomesDirectGraphEvidence() {
        let purchase = StoredPurchase(
            merchantLabel: "McDonald's #1234",
            merchantLatitude: 43.65,
            merchantLongitude: -79.38)
        let observation = StoredObservation(
            observedCategory: "dining",
            observedMerchantCategoryCode: 5814,
            confirmedAt: Date(timeIntervalSince1970: 1_800_000_000))
        purchase.observation = observation

        let evidence = MerchantMCCGraphEvidenceBuilder.evidence(from: [purchase])

        XCTAssertEqual(evidence.count, 1)
        XCTAssertEqual(evidence[0].mcc, 5814)
        XCTAssertEqual(evidence[0].kind, .directOwnerMcc)
        XCTAssertEqual(evidence[0].latitude, 43.65)
        XCTAssertEqual(evidence[0].longitude, -79.38)
    }

    func testCategoryOnlyReconcileCannotInventAnMcc() {
        let purchase = StoredPurchase(merchantLabel: "Local Pharmacy")
        purchase.observation = StoredObservation(observedCategory: "drugStore")

        let evidence = MerchantMCCGraphEvidenceBuilder.evidence(from: [purchase])
        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Local Pharmacy"),
            evidence: evidence)

        XCTAssertEqual(evidence.first?.kind, .categoryOutcome)
        XCTAssertNil(evidence.first?.mcc)
        XCTAssertNil(prediction.bestMCC)
    }

    func testRepeatedHistoryIsPreservedInsteadOfLastWriteWinning() {
        func purchase(mcc: Int) -> StoredPurchase {
            let purchase = StoredPurchase(merchantLabel: "McDonald's",
                                          merchantLatitude: 49.9,
                                          merchantLongitude: -97.15)
            purchase.observation = StoredObservation(observedCategory: "dining",
                                                     observedMerchantCategoryCode: mcc)
            return purchase
        }

        let evidence = MerchantMCCGraphEvidenceBuilder.evidence(
            from: [purchase(mcc: 5812), purchase(mcc: 5814)])

        XCTAssertEqual(Set(evidence.compactMap(\.mcc)), Set([5812, 5814]))
        XCTAssertEqual(evidence.count, 2)
    }

    func testLearnedAliasJoinsReconciledMccBackToCanonicalMerchant() throws {
        let suite = "MerchantMCCGraphEvidenceBuilderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let identityStore = MerchantMCCIdentityLearningStore(defaults: defaults, storageKey: "identity")
        let alias = "MART #1234"

        XCTAssertTrue(identityStore.record(alias: alias, merchantID: "walmart",
                                           sourceFingerprint: "wallet:event-1"))
        XCTAssertTrue(identityStore.record(alias: alias, merchantID: "walmart",
                                           sourceFingerprint: "wallet:event-2"))

        let purchase = StoredPurchase(merchantLabel: alias,
                                      merchantLatitude: 43.65,
                                      merchantLongitude: -79.38)
        purchase.observation = StoredObservation(observedCategory: "grocery",
                                                 observedMerchantCategoryCode: 5411)

        let evidence = MerchantMCCGraphEvidenceBuilder.evidence(
            from: [purchase], identityStore: identityStore)
        XCTAssertEqual(evidence.first?.merchantKey, "walmart")

        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Walmart"),
            seedMCC: 5311,
            evidence: evidence)
        XCTAssertEqual(prediction.bestMCC, 5411,
                       "direct owner evidence learned under an alias must overpower the seed prior")
    }
}
