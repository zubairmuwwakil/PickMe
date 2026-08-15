import XCTest
@testable import CardCopilotEngine

/// Not a gate — a readable walkthrough. Run with:
///   swift test --filter DemoWalkthroughTests
/// to see what the recommendation screen would say for a day of real checkouts.
final class DemoWalkthroughTests: XCTestCase {
    func testPrintWalkthrough() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        var state = try SeedLoader.loadOwnerState()
        let explainer = RecommendationExplainer(catalogue: catalogue)

        let day: [(String, PurchaseContext)] = [
            ("Coffee shop, $6",
             PurchaseContext(amountCad: 6, category: "dining", mcc: 5814)),
            ("Loblaws groceries, $140",
             PurchaseContext(amountCad: 140, category: "grocery", mcc: 5411, merchantBrand: "loblaws")),
            ("Costco run, $220 (Mastercard only)",
             PurchaseContext(amountCad: 220, category: "wholesaleClub", mcc: 5300,
                             merchantBrand: "costco", acceptedNetworks: [.mastercard])),
            ("Canadian Tire, $150",
             PurchaseContext(amountCad: 150, category: "ctFamily", mcc: 5200,
                             merchantBrand: "canadian-tire")),
            ("US online order, ~C$165",
             PurchaseContext(amountCad: 165, currency: "USD", category: "other", channel: "online")),
        ]

        print("\n════════ A day of checkouts ════════")
        for (label, purchase) in day {
            let e = explainer.explain(
                RecommendationEngine(catalogue: catalogue, ownerState: state)
                    .recommend(purchase, asOf: "2026-08-20"),
                purchase: purchase)
            print("\n▸ \(label)\n  \(e.headline)\n  \(e.why)")
            if let runnerUp = e.runnerUpLine { print("  \(runnerUp)") }
            if let valuation = e.valuationLine { print("  ⓘ \(valuation)") }
            for warning in e.warningLines { print("  ⚠ \(warning)") }
        }

        print("\n════════ Same grocery run, but Cobalt's monthly cap is spent ════════")
        state.cardStates["amex-cobalt"]?.capProgress?["cobalt-eats-monthly"] = 2500
        let capped = PurchaseContext(amountCad: 140, category: "grocery", mcc: 5411,
                                     merchantBrand: "loblaws")
        let e = explainer.explain(
            RecommendationEngine(catalogue: catalogue, ownerState: state)
                .recommend(capped, asOf: "2026-08-20"),
            purchase: capped)
        print("\n▸ Loblaws groceries, $140\n  \(e.headline)\n  \(e.why)")
        if let runnerUp = e.runnerUpLine { print("  \(runnerUp)") }
        if let valuation = e.valuationLine { print("  ⓘ \(valuation)") }
        print("")
    }
}
