import WidgetKit
import SwiftUI
import CardCopilotEngine
import CardCopilotStore

public struct QuickRecommendEntry: TimelineEntry {
    public let date: Date
    public let categories: [(name: String, icon: String, card: String, multiplier: String)]

    public static var placeholder: QuickRecommendEntry {
        QuickRecommendEntry(
            date: Date(),
            categories: [
                (name: "Groceries", icon: "cart.fill", card: "Cobalt", multiplier: "5×"),
                (name: "Dining", icon: "fork.knife", card: "Cobalt", multiplier: "5×"),
                (name: "Gas", icon: "fuelpump.fill", card: "Costco MC", multiplier: "3%"),
                (name: "Transit", icon: "tram.fill", card: "Cobalt", multiplier: "2×")
            ]
        )
    }
}

public struct QuickRecommendProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> QuickRecommendEntry {
        .placeholder
    }

    public func getSnapshot(in context: Context, completion: @escaping (QuickRecommendEntry) -> Void) {
        completion(loadEntry())
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<QuickRecommendEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadEntry() -> QuickRecommendEntry {
        let ownerState = OwnerStateLocalStore().loadForRecommendation()
        let catalogue = (try? SeedLoader.loadCatalogue()) ?? Catalogue.empty

        guard let ownerState else { return .placeholder }

        let testCategories = [
            (id: "grocery", name: "Groceries", icon: "cart.fill", amount: 100.0),
            (id: "dining", name: "Dining", icon: "fork.knife", amount: 40.0),
            (id: "gasStation", name: "Gas", icon: "fuelpump.fill", amount: 60.0),
            (id: "transit", name: "Transit", icon: "tram.fill", amount: 20.0)
        ]

        var results: [(name: String, icon: String, card: String, multiplier: String)] = []

        let today = Date().formatted(.iso8601.year().month().day())
        for item in testCategories {
            let context = PurchaseContext(amountCad: item.amount, category: item.id)
            guard case .advised(let rec) = RecommendationEngine(catalogue: catalogue, ownerState: ownerState).recommend(context, asOf: today) else { continue }
            let cardName = catalogue.cards.first(where: { $0.cardId == rec.winner.cardId })?.officialName ?? rec.winner.cardId
            // Shorten card name for widget
            let shortCardName = cardName.replacingOccurrences(of: "American Express", with: "Amex")
                .replacingOccurrences(of: "World Elite Mastercard", with: "WE MC")
                .replacingOccurrences(of: "Mastercard", with: "MC")
                .replacingOccurrences(of: "Visa Infinite", with: "VI")

            results.append((name: item.name, icon: item.icon, card: shortCardName, multiplier: String(format: "$%.2f back", rec.winner.netValueCad)))
        }

        return QuickRecommendEntry(date: Date(), categories: results)
    }
}

public struct QuickRecommendWidgetView: View {
    let entry: QuickRecommendEntry

    public init(entry: QuickRecommendEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("PickMe: Best Card Quick Sheet", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(entry.categories, id: \.name) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.blue)
                            .frame(width: 28, height: 28)
                            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(item.card)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
    }
}

public struct QuickRecommendWidget: Widget {
    public let kind: String = "QuickRecommendWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRecommendProvider()) { entry in
            QuickRecommendWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.secondarySystemBackground) }
        }
        .configurationDisplayName("Quick Card Advisor")
        .description("Glance at the top cards for Groceries, Dining, Gas, and Transit.")
        .supportedFamilies([.systemMedium])
    }
}
