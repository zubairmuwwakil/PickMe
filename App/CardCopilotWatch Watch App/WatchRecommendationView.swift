import SwiftUI
import CardCopilotEngine
import CardCopilotStore

public struct WatchRecommendationView: View {
    let categoryName: String
    let categoryId: String
    let icon: String
    let amountCad: Double

    public init(categoryName: String, categoryId: String, icon: String, amountCad: Double = 50.0) {
        self.categoryName = categoryName
        self.categoryId = categoryId
        self.icon = icon
        self.amountCad = amountCad
    }

    private var recommendation: (cardName: String, multiplier: String, advantage: String) {
        let catalogue = (try? SeedLoader.loadCatalogue()) ?? Catalogue.empty
        let ownerState = OwnerStateLocalStore().loadForRecommendation()

        guard let ownerState else {
            return ("Open iPhone App", "Set up cards", "")
        }

        let today = Date().formatted(.iso8601.year().month().day())
        let context = PurchaseContext(amountCad: amountCad, category: categoryId)
        guard case .advised(let rec) = RecommendationEngine(catalogue: catalogue, ownerState: ownerState).recommend(context, asOf: today) else {
            return ("Open iPhone App", "Cannot advise", "")
        }
        let card = catalogue.cards.first(where: { $0.cardId == rec.winner.cardId })
        let name = card?.officialName.replacingOccurrences(of: "American Express", with: "Amex")
            .replacingOccurrences(of: "World Elite Mastercard", with: "WE MC")
            .replacingOccurrences(of: "Mastercard", with: "MC") ?? rec.winner.cardId

        let adv = (rec.advantageOverDefaultCad ?? 0) > 0 ? String(format: "+$%.2f", rec.advantageOverDefaultCad!) : ""
        let returnLabel = String(format: "$%.2f return", rec.winner.netValueCad)
        return (name, returnLabel, adv)
    }

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)

            Text(categoryName)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(recommendation.cardName)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if !recommendation.multiplier.isEmpty {
                Text(recommendation.multiplier)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.teal)
            }

            if !recommendation.advantage.isEmpty {
                Text(recommendation.advantage)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.green)
            }
        }
        .padding(8)
        .navigationTitle(categoryName)
    }
}
