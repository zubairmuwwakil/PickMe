import SwiftUI
import CardCopilotEngine

/// Which conditions a card raises, and how to word them. Derived entirely from the catalogue and
/// the registry — no card id appears in this file. Adding a conditional card to the catalogue
/// makes its question appear with no App change, which is the whole point of the registry.
enum WalletConditions {

    static func ids(for cardId: String, catalogue: Catalogue) -> [String] {
        guard let card = catalogue.cards.first(where: { $0.cardId == cardId }) else { return [] }
        var seen: Set<String> = []
        return card.earnRules
            .compactMap(\.ownerConditions)
            .flatMap { $0 }
            .filter { seen.insert($0).inserted }
    }

    static func condition(_ id: String) -> OwnerCondition? { SeedLoader.ownerConditions[id] }

    /// Localized question, falling back to the registry's English source string. A condition
    /// added to the contract is askable the day it lands and picks up fr-CA on the next
    /// translation pass, with no contract release in between.
    static func prompt(for id: String) -> String {
        let fallback = condition(id)?.prompt ?? id
        return Bundle.main.localizedString(forKey: "ownerCondition.\(id).prompt",
                                           value: fallback, table: nil)
    }

    static func detail(for id: String) -> String? {
        guard let fallback = condition(id)?.detail else { return nil }
        return Bundle.main.localizedString(forKey: "ownerCondition.\(id).detail",
                                           value: fallback, table: nil)
    }

    /// Conditions on owned cards with no answer recorded. Drives the checklist banner and the
    /// per-card badge. Only `boolean` conditions count — a category selection legitimately has
    /// no answer when the owner has selected nothing.
    static func unanswered(ownedCardIds: [String], catalogue: Catalogue,
                           answers: [String: [String: Bool]]) -> [(cardId: String, conditionId: String)] {
        ownedCardIds.flatMap { cardId in
            ids(for: cardId, catalogue: catalogue)
                .filter { condition($0)?.answerKind == .boolean }
                .filter { answers[cardId]?[$0] == nil }
                .map { (cardId: cardId, conditionId: $0) }
        }
    }
}

/// One card's conditions, rendered inline beneath it in the wallet editor.
struct OwnerConditionEditor: View {
    let cardId: String
    let conditionIds: [String]
    @Binding var answers: [String: Bool]
    @Binding var tangerineCategories: [String]?

    var body: some View {
        ForEach(conditionIds, id: \.self) { id in
            if let condition = WalletConditions.condition(id) {
                switch condition.answerKind {
                case .boolean: booleanRow(id, condition)
                case .categorySelection: categoryRows(id, condition)
                }
            }
        }
    }

    private func booleanRow(_ id: String, _ condition: OwnerCondition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(WalletConditions.prompt(for: id))
                .font(.subheadline)
            if let detail = WalletConditions.detail(for: id) {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            // Tri-state, never two. "I'm not sure" is a real answer that keeps the rule skipped;
            // collapsing it into "No" would tell the engine something the owner never said.
            Picker(WalletConditions.prompt(for: id), selection: triState(id)) {
                Text("Yes").tag("yes")
                Text("No").tag("no")
                Text("I'm not sure").tag("unknown")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private func triState(_ id: String) -> Binding<String> {
        Binding(
            get: { answers[id].map { $0 ? "yes" : "no" } ?? "unknown" },
            set: { answers[id] = $0 == "unknown" ? nil : ($0 == "yes") })
    }

    @ViewBuilder
    private func categoryRows(_ id: String, _ condition: OwnerCondition) -> some View {
        let limit = condition.maxSelections ?? 3
        if let detail = WalletConditions.detail(for: id) {
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        ForEach(TangerineMoneyBackCategory.allCases, id: \.rawValue) { category in
            Toggle(category.setupLabel, isOn: categoryBinding(category, limit: limit))
                .disabled(!isSelected(category) && (tangerineCategories?.count ?? 0) >= limit)
        }
    }

    private func isSelected(_ category: TangerineMoneyBackCategory) -> Bool {
        tangerineCategories?.contains(category.rawValue) == true
    }

    private func categoryBinding(_ category: TangerineMoneyBackCategory,
                                 limit: Int) -> Binding<Bool> {
        Binding(
            get: { isSelected(category) },
            set: { selected in
                var categories = tangerineCategories ?? []
                if selected, !categories.contains(category.rawValue), categories.count < limit {
                    categories.append(category.rawValue)
                } else {
                    categories.removeAll { $0 == category.rawValue }
                }
                tangerineCategories = categories.isEmpty ? nil : categories
            })
    }
}

extension TangerineMoneyBackCategory {
    var setupLabel: LocalizedStringKey {
        switch self {
        case .grocery: "Grocery"
        case .dining: "Restaurants"
        case .gasStation: "Gas"
        case .entertainment: "Entertainment"
        case .furniture: "Furniture"
        case .lodging: "Hotel-Motel"
        case .drugStore: "Drug Store"
        case .recurring: "Recurring Bill Payments"
        case .homeImprovement: "Home Improvement"
        case .transit: "Public Transportation and Parking"
        case .eGames: "E-Games"
        case .fitness: "Fitness and Sports Clubs"
        case .foreignCurrency: "Foreign Currency Spend"
        }
    }
}
