import XCTest
import SwiftData
import CardCopilotEngine
@testable import CardCopilotStore

final class ObservedSpendProfileBuilderTests: XCTestCase {
    func testEmptyPredictionsFallBackToBaseline() {
        let builder = ObservedSpendProfileBuilder()
        let result = builder.build(from: [], baseline: .placeholderCanadianHousehold)
        XCTAssertEqual(result.profileId, SpendDistribution.placeholderCanadianHousehold.profileId)
        XCTAssertEqual(result.totalAnnualCad, SpendDistribution.placeholderCanadianHousehold.totalAnnualCad)
    }

    func testObservedPurchasesAreAnnualizedAndBlended() {
        let builder = ObservedSpendProfileBuilder(minimumObservationDays: 30)
        let now = Date()

        let pred1 = StoredPrediction(
            merchantName: "Metro",
            predictedCategory: "grocery",
            confidenceSource: .brandPrior,
            winnerCardId: "amex-cobalt",
            winnerValueCad: 10.0,
            scoredAmountCad: 200.0,
            headline: "Use Cobalt",
            recordedAt: now.addingTimeInterval(-15 * 86400)
        )
        let purchase1 = StoredPurchase(createdAt: now.addingTimeInterval(-15 * 86400))
        purchase1.cardUsedId = "amex-cobalt"
        purchase1.amountCad = 200.0
        purchase1.completedAt = now.addingTimeInterval(-15 * 86400)
        pred1.purchase = purchase1

        let pred2 = StoredPrediction(
            merchantName: "Starbucks",
            predictedCategory: "dining",
            confidenceSource: .brandPrior,
            winnerCardId: "amex-cobalt",
            winnerValueCad: 1.0,
            scoredAmountCad: 10.0,
            headline: "Use Cobalt",
            recordedAt: now.addingTimeInterval(-5 * 86400)
        )
        let purchase2 = StoredPurchase(createdAt: now.addingTimeInterval(-5 * 86400))
        purchase2.cardUsedId = "amex-cobalt"
        purchase2.amountCad = 10.0
        purchase2.completedAt = now.addingTimeInterval(-5 * 86400)
        pred2.purchase = purchase2

        let result = builder.build(from: [pred1, pred2], baseline: .placeholderCanadianHousehold, asOf: now)

        XCTAssertEqual(result.profileId, "observed-spend-profile")
        XCTAssertTrue(result.basis.contains("OBSERVED SPEND"))

        // Grocery was $200 over 30 min days -> 200 * (365 / 30) = ~2433.33
        let groceryBucket = result.buckets.first { $0.context.category == "grocery" }
        XCTAssertNotNil(groceryBucket)
        XCTAssertEqual(groceryBucket!.annualCad, 200.0 * (365.0 / 30.0), accuracy: 1.0)
    }
}
