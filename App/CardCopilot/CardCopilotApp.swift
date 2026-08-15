import SwiftUI
import CardCopilotEngine

@main
struct CardCopilotApp: App {
    var body: some Scene {
        WindowGroup {
            EngineSmokeTestView()
        }
    }
}

/// Task 1 placeholder: proves the engine package links and its seed resources load
/// inside an iOS app bundle. Replaced by HomeView in Task 6.
struct EngineSmokeTestView: View {
    @State private var status: String = "loading…"
    @State private var headline: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Card Copilot").font(.largeTitle.bold())
            Text(status).font(.headline).foregroundStyle(.secondary)
            if !headline.isEmpty {
                Text(headline).font(.body).padding(.top, 8)
            }
            Spacer()
        }
        .padding()
        .task {
            do {
                let catalogue = try SeedLoader.loadCatalogue()
                let owner = try SeedLoader.loadOwnerState()
                let engine = RecommendationEngine(catalogue: catalogue, ownerState: owner)
                let explainer = RecommendationExplainer(catalogue: catalogue)
                let purchase = PurchaseContext(amountCad: 140, category: "grocery", mcc: 5411,
                                               merchantBrand: "loblaws")
                let recommendation = engine.recommend(purchase, asOf: "2026-08-20")
                status = "Engine linked — \(catalogue.cards.count) cards loaded"
                headline = explainer.explain(recommendation, purchase: purchase).headline
            } catch {
                status = "Engine failed to load: \(error)"
            }
        }
    }
}
