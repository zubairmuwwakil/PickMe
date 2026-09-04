import XCTest
@testable import CardCopilotStore

final class MerchantMCCGraphTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSeedIsUsefulButNeverObservedTruth() {
        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "No Frills"),
            seedMCC: 5411,
            evidence: [],
            now: now)

        XCTAssertEqual(prediction.bestMCC, 5411)
        XCTAssertFalse(prediction.isObserved)
        XCTAssertFalse(prediction.isTrusted)
        XCTAssertLessThan(prediction.confidence, 0.8)
    }

    func testDirectLocationEvidenceOverridesConflictingSeed() {
        let evidence = MerchantMCCEvidence(
            id: "owner-1", merchantKey: "Walmart", placeID: "apple-place-1",
            channel: .inStore, mcc: 5311, kind: .directOwnerMcc,
            observedAt: now)

        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Walmart", placeID: "apple-place-1",
                                  channel: .inStore),
            seedMCC: 5411,
            evidence: [evidence],
            now: now)

        XCTAssertEqual(prediction.bestMCC, 5311)
        XCTAssertTrue(prediction.isObserved)
        XCTAssertEqual(prediction.directObservationCount, 1)
    }

    func testRepeatedDirectEvidenceCanPromoteExactLocationToTrusted() {
        let evidence = [
            MerchantMCCEvidence(id: "owner-1", merchantKey: "Walmart",
                                placeID: "apple-place-1", channel: .inStore,
                                mcc: 5411, kind: .directOwnerMcc, observedAt: now),
            MerchantMCCEvidence(id: "owner-2", merchantKey: "Walmart",
                                placeID: "apple-place-1", channel: .inStore,
                                mcc: 5411, kind: .directOwnerMcc, observedAt: now)
        ]

        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Walmart", placeID: "apple-place-1",
                                  channel: .inStore),
            seedMCC: 5311,
            evidence: evidence,
            now: now)

        XCTAssertEqual(prediction.bestMCC, 5411)
        XCTAssertGreaterThanOrEqual(prediction.confidence, 0.80)
        XCTAssertTrue(prediction.isTrusted)
    }

    func testDirectEvidenceFromAnotherBranchCannotMakeThisLocationObserved() {
        let evidence = [
            MerchantMCCEvidence(id: "other-1", merchantKey: "Walmart",
                                latitude: 43.90, longitude: -79.90,
                                channel: .inStore, mcc: 5411,
                                kind: .directOwnerMcc, observedAt: now),
            MerchantMCCEvidence(id: "other-2", merchantKey: "Walmart",
                                latitude: 43.90, longitude: -79.90,
                                channel: .inStore, mcc: 5411,
                                kind: .directOwnerMcc, observedAt: now)
        ]

        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Walmart",
                                  latitude: 43.65, longitude: -79.38,
                                  channel: .inStore),
            evidence: evidence,
            now: now)

        XCTAssertEqual(prediction.bestMCC, 5411,
                       "another branch may remain weak brand evidence")
        XCTAssertEqual(prediction.directObservationCount, 0,
                       "another branch must not count toward terminal trust")
        XCTAssertFalse(prediction.isObserved)
        XCTAssertFalse(prediction.isTrusted)
    }

    func testDirectCoordinateEvidenceWithin75MetresCountsAsObserved() {
        let evidence = MerchantMCCEvidence(
            id: "nearby", merchantKey: "Metro",
            latitude: 43.6500, longitude: -79.3800,
            channel: .inStore, mcc: 5411,
            kind: .directOwnerMcc, observedAt: now)

        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Metro",
                                  latitude: 43.6503, longitude: -79.3802,
                                  channel: .inStore),
            evidence: [evidence], now: now)

        XCTAssertEqual(prediction.directObservationCount, 1)
        XCTAssertTrue(prediction.isObserved)
    }

    func testConflictingLocationReportsRemainAProbabilityDistribution() {
        let evidence = [
            MerchantMCCEvidence(id: "langley", merchantKey: "McDonald's",
                                latitude: 49.10, longitude: -122.65,
                                channel: .inStore, mcc: 5814,
                                kind: .externalLocationReport, observedAt: now),
            MerchantMCCEvidence(id: "winnipeg", merchantKey: "McDonald's",
                                latitude: 49.90, longitude: -97.15,
                                channel: .inStore, mcc: 5812,
                                kind: .externalLocationReport, observedAt: now)
        ]

        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "McDonald's", channel: .inStore),
            evidence: evidence,
            now: now)

        XCTAssertEqual(Set(prediction.candidates.map(\.mcc)), Set([5812, 5814]))
        XCTAssertFalse(prediction.isObserved)
        XCTAssertFalse(prediction.isTrusted)
    }

    func testCategoryOutcomeNeverFabricatesExactMCC() {
        let evidence = MerchantMCCEvidence(
            id: "category-only", merchantKey: "Shoppers Drug Mart",
            category: "drugStore", kind: .categoryOutcome, observedAt: now)

        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Shoppers Drug Mart"),
            evidence: [evidence],
            now: now)

        XCTAssertNil(prediction.bestMCC)
        XCTAssertEqual(prediction.categoryEvidenceCount, 1)
    }

    func testChannelSpecificEvidenceDoesNotLeakAcrossOnlineAndStorefront() {
        let evidence = MerchantMCCEvidence(
            id: "online", merchantKey: "Example Merchant", channel: .online,
            mcc: 5969, kind: .directOwnerMcc, observedAt: now)

        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Example Merchant", channel: .inStore),
            evidence: [evidence],
            now: now)

        XCTAssertNil(prediction.bestMCC)
    }

    func testDuplicateLocationEvidenceIdCountsOnce() {
        let item = MerchantMCCEvidence(
            id: "same", merchantKey: "Metro", latitude: 43.65, longitude: -79.38,
            channel: .inStore, mcc: 5411,
            kind: .directOwnerMcc, observedAt: now)

        let prediction = MerchantMCCGraph.predict(
            for: MerchantMCCQuery(merchantKey: "Metro", latitude: 43.65,
                                  longitude: -79.38, channel: .inStore),
            evidence: [item, item],
            now: now)

        XCTAssertEqual(prediction.directObservationCount, 1)
    }
}
