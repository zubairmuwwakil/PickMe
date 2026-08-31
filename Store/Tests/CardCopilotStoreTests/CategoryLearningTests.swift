import XCTest
import SwiftData
import CardCopilotEngine
@testable import CardCopilotStore

final class CategoryLearningTests: XCTestCase {
    func testObservedMCCOutranksAWeakerPOIGuess() {
        let prediction = predict(poiCategoryRaw: "store", merchantName: "Local Market",
                                 merchantCategoryCode: 5411)
        XCTAssertEqual(prediction.category, "grocery")
        XCTAssertEqual(prediction.confidenceSource, .observedMcc)
        XCTAssertEqual(prediction.confidenceScore, 0.85)
        XCTAssertEqual(prediction.rawCategory, "store")
        XCTAssertEqual(prediction.taxonomyVersion, CategoryTaxonomy.taxonomyVersion)
    }

    func testOtherAuditRecoversOnlyFromPreservedEvidence() {
        let recoverable = StoredPurchase(merchantLabel: "Old shop", categoryAtPurchase: "other",
                                         rawCategoryAtPurchase: "home_improvement")
        let ambiguous = StoredPurchase(merchantLabel: "Mystery shop", categoryAtPurchase: "other")

        let report = OtherCategoryAuditor.audit(purchases: [recoverable, ambiguous], merchants: [])
        XCTAssertEqual(report.safelyRecoverable.count, 1)
        XCTAssertEqual(report.safelyRecoverable.first?.suggestedCategory, "homeImprovement")
        XCTAssertEqual(report.safelyRecoverable.first?.basis, .preservedRawCategory)
        XCTAssertEqual(report.ambiguous.count, 1)
        XCTAssertEqual(report.ambiguous.first?.basis, .insufficientEvidence)
    }

    func testOtherAuditUsesRepeatedTerminalAndDecisiveMCC() {
        let terminalPurchase = StoredPurchase(merchantLabel: "Local shop",
                                              merchantIdentifier: "poi-1",
                                              categoryAtPurchase: "other")
        let mccPurchase = StoredPurchase(merchantLabel: "Fuel stop",
                                         categoryAtPurchase: "other",
                                         merchantCategoryCode: 5541)
        let merchant = StoredMerchant(name: "Local shop", identifier: "poi-1",
                                      latitude: 0, longitude: 0,
                                      confirmedCategory: "furniture", confirmationCount: 2)

        let report = OtherCategoryAuditor.audit(
            purchases: [terminalPurchase, mccPurchase], merchants: [merchant])
        XCTAssertEqual(report.safelyRecoverable.map(\.suggestedCategory),
                       ["furniture", "gasStation"])
    }

    func testAggregateSignalRequiresExplicitConsentAndRepeatedEvidence() throws {
        let suite = "CategoryLearningTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = CategoryLearningConsentStore(defaults: defaults)
        let merchant = StoredMerchant(name: "Private merchant", identifier: "poi-private",
                                      latitude: 43.6, longitude: -79.4,
                                      confirmedCategory: "grocery", confirmationCount: 2,
                                      merchantCategoryCode: 5411)

        XCTAssertThrowsError(try AggregateCategorySignalBuilder.build(from: merchant,
                                                                       consent: consent)) {
            XCTAssertEqual($0 as? AggregateCategorySignalError, .consentRequired)
        }
        consent.aggregateContributionEnabled = true
        let signal = try AggregateCategorySignalBuilder.build(from: merchant, consent: consent)
        XCTAssertEqual(signal.category, "grocery")
        XCTAssertEqual(signal.merchantCategoryCode, 5411)
        XCTAssertEqual(signal.confirmationCount, 2)
        // The signal type intentionally has no merchant name, identifier, coordinates, amount,
        // or timestamp fields.
    }

    func testTransactionToCategoryToCardRuleEndToEnd() throws {
        let container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
            StoredMerchant.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let service = CheckoutService(catalogue: try SeedLoader.loadCatalogue(),
                                      ownerState: try SeedLoader.loadOwnerState(),
                                      context: ModelContext(container))
        let merchant = NearbyMerchant(id: "poi-grocery", name: "Neighbourhood Market",
                                      poiCategoryRaw: "store", merchantCategoryCode: 5411,
                                      latitude: 43.6, longitude: -79.4, distanceMeters: 10)

        let result = try service.recommend(merchant: merchant, amountCad: 100,
                                           asOf: "2026-08-20")
        XCTAssertEqual(result.prediction.category, "grocery")
        guard case .single(let recommendation) = result.outcome else {
            return XCTFail("decisive MCC should not fork")
        }
        XCTAssertEqual(recommendation.winner.cardId, "amex-cobalt")
        XCTAssertEqual(recommendation.winner.appliedRuleId, "cobalt-eats-5x")

        let stored = try XCTUnwrap(try service.log.allPredictions().first)
        XCTAssertEqual(stored.rawCategory, "store")
        XCTAssertEqual(stored.merchantCategoryCode, 5411)
        XCTAssertEqual(stored.categoryTaxonomyVersion, CategoryTaxonomy.taxonomyVersion)
        XCTAssertEqual(stored.categoryConfidenceScore, 0.85)
    }
}
