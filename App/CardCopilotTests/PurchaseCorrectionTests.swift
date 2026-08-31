import XCTest
import SwiftData
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

@MainActor
final class PurchaseCorrectionTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CardCopilotSchema.current)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func makeGraph(context: ModelContext) throws -> DependencyGraph {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        return DependencyGraph(
            catalogue: catalogue,
            candidateCardIds: [],
            ownerState: owner,
            benefits: try SeedLoader.loadBenefitsCatalogue(),
            service: CheckoutService(catalogue: catalogue, ownerState: owner, context: context),
            explainer: RecommendationExplainer(catalogue: catalogue),
            engine: RecommendationEngine(catalogue: catalogue, ownerState: owner),
            provider: LiveMerchantProvider())
    }

    // MARK: - Attention Status & Evaluator Tests

    func testAttentionEvaluatorDetectsMissingAmountAndCard() throws {
        let purchase = StoredPurchase(
            createdAt: Date(),
            merchantLabel: "Coffee Shop",
            activitySource: .walletCapture,
            merchantKey: "coffee-shop",
            categoryAtPurchase: "dining",
            categoryConfidence: .brandPrior
        )

        let issues = PurchaseAttentionEvaluator.issues(for: purchase)
        XCTAssertTrue(issues.contains(.missingAmount))
        XCTAssertTrue(issues.contains(.missingCard))
        XCTAssertTrue(PurchaseAttentionEvaluator.needsAttention(purchase))
        XCTAssertEqual(PurchaseAttentionEvaluator.primaryIssue(for: purchase), .missingAmount)
    }

    func testAttentionEvaluatorDetectsUncertainCategoryWhenFallback() throws {
        let purchase = StoredPurchase(
            createdAt: Date(),
            merchantLabel: "Unknown Corner Shop",
            activitySource: .walletCapture,
            merchantKey: "unknown-shop",
            categoryAtPurchase: "other",
            categoryConfidence: .fallback
        )
        purchase.amountCad = 15.50
        purchase.cardUsedId = "amex-cobalt"

        let issues = PurchaseAttentionEvaluator.issues(for: purchase)
        XCTAssertFalse(issues.contains(.missingAmount))
        XCTAssertFalse(issues.contains(.missingCard))
        XCTAssertTrue(issues.contains(.uncertainCategory(category: "other")))
        XCTAssertTrue(PurchaseAttentionEvaluator.needsAttention(purchase))
    }

    func testAttentionEvaluatorClearedWhenFullyResolved() throws {
        let prediction = StoredPrediction(
            merchantName: "Metro Grocery",
            predictedCategory: "grocery",
            confidenceSource: .brandPrior,
            winnerCardId: "amex-cobalt",
            winnerValueCad: 2.50,
            headline: "Use Cobalt for 5x"
        )
        let purchase = StoredPurchase(
            createdAt: Date(),
            merchantLabel: "Metro Grocery",
            activitySource: .pickMeCheckout,
            merchantKey: "metro",
            categoryAtPurchase: "grocery",
            categoryConfidence: .brandPrior
        )
        purchase.prediction = prediction
        purchase.amountCad = 82.40
        purchase.cardUsedId = "amex-cobalt"
        purchase.completedAt = Date()

        let issues = PurchaseAttentionEvaluator.issues(for: purchase)
        XCTAssertFalse(PurchaseAttentionEvaluator.needsAttention(purchase))
        XCTAssertTrue(issues.contains(.unreconciled))
    }

    // MARK: - Transaction Currency Tests

    func testTransactionCurrenciesContainAllMajorCurrencies() {
        let currencies = TransactionCurrency.all
        let codes = Set(currencies.map(\.code))

        XCTAssertTrue(codes.contains("CAD"))
        XCTAssertTrue(codes.contains("USD"))
        XCTAssertTrue(codes.contains("EUR"))
        XCTAssertTrue(codes.contains("GBP"))
        XCTAssertTrue(codes.contains("JPY"))
        XCTAssertTrue(codes.contains("MXN"))
        XCTAssertTrue(codes.contains("AUD"))

        let usd = currencies.first(where: { $0.code == "USD" })!
        XCTAssertEqual(usd.symbol, "$")
        XCTAssertEqual(usd.flag, "🇺🇸")
        XCTAssertGreaterThan(usd.defaultCadRate, 1.0)
    }

    // MARK: - Card Switching and Session State Tests

    func testUpdatingCardReevaluatesAssessmentAndPersists() throws {
        let context = try makeContext()
        let graph = try makeGraph(context: context)
        let session = CopilotSession()

        let prediction = StoredPrediction(
            merchantName: "Whole Foods",
            predictedCategory: "grocery",
            confidenceSource: .brandPrior,
            winnerCardId: "amex-cobalt",
            winnerValueCad: 5.0,
            headline: "Use Cobalt for 5x"
        )
        context.insert(prediction)
        try context.save()

        let purchase = try graph.service.log.recordPurchase(for: prediction)
        try graph.service.log.recordAmount(50.0, source: .recalledLater, on: purchase)

        // Record initial card
        session.recordCard("tangerine-world", for: purchase, using: graph)
        XCTAssertEqual(purchase.cardUsedId, "tangerine-world")

        // Switch to Cobalt
        session.recordCard("amex-cobalt", for: purchase, using: graph)
        XCTAssertEqual(purchase.cardUsedId, "amex-cobalt")

        // Clear recorded card
        session.recordCard(nil, for: purchase, using: graph)
        XCTAssertNil(purchase.cardUsedId)
    }

    func testUpdatingAmountAndCategoryUpdatesPurchaseState() throws {
        let context = try makeContext()
        let graph = try makeGraph(context: context)
        let session = CopilotSession()

        let purchase = StoredPurchase(
            createdAt: Date(),
            merchantLabel: "Cafe Nero",
            activitySource: .pickMeCheckout,
            merchantKey: "cafe-nero"
        )
        context.insert(purchase)
        try context.save()

        session.recordAmount(12.75, for: purchase, using: graph)
        XCTAssertEqual(purchase.amountCad, 12.75)

        session.updateCategory(for: purchase, to: "dining", using: graph)
        XCTAssertEqual(purchase.displayCategory, "dining")
    }
}
