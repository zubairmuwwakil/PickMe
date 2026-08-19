import SwiftUI
import CardCopilotEngine
import CardCopilotStore

public struct WatchCapView: View {
    public init() {}

    private var activeCaps: [(card: String, name: String, spent: Double, limit: Double, remaining: Double)] {
        let catalogue = (try? SeedLoader.loadCatalogue()) ?? Catalogue.empty
        let ownerState = OwnerStateLocalStore().load()
        guard let ownerState else { return [] }

        var list: [(card: String, name: String, spent: Double, limit: Double, remaining: Double)] = []
        for cardId in ownerState.ownedCardIds {
            guard let card = catalogue.cards.first(where: { $0.cardId == cardId }) else { continue }
            let state = ownerState.cardStates[cardId]
            for cap in card.caps {
                let spent = state?.capProgress?[cap.capId] ?? 0
                let limit = cap.limit
                let remaining = max(0, limit - spent)
                let capName = cap.capId.replacingOccurrences(of: "-", with: " ").capitalized
                list.append((card: card.officialName, name: capName, spent: spent, limit: limit, remaining: remaining))
            }
        }
        return list
    }

    public var body: some View {
        List {
            if activeCaps.isEmpty {
                Text("No monthly caps on active cards.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeCaps, id: \.name) { cap in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cap.card)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(cap.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        HStack {
                            ProgressView(value: cap.limit > 0 ? (cap.spent / cap.limit) : 0)
                                .tint(.blue)
                            Text(String(format: "$%.0f left", cap.remaining))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Spending Caps")
    }
}
