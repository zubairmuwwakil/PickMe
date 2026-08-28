import SwiftUI
import CardCopilotEngine
import CardCopilotStore

struct WalletChecklistItem: Identifiable, Equatable {
    enum Kind: Equatable { case addCards, chooseDefault, answerCondition }

    let id: String
    let kind: Kind
    let title: String
    /// What answering it buys. An item that cannot say why it matters does not belong here.
    let payoff: String?
    let cardId: String?
}

/// Derives what is still outstanding, from catalogue + setup. Not persisted and not dismissible:
/// it is a live view of state, so it disappears by being resolved rather than by being ignored.
enum WalletChecklist {

    static func items(setup: WalletSetup, catalogue: Catalogue) -> [WalletChecklistItem] {
        var items: [WalletChecklistItem] = []

        if setup.ownedCardIds.isEmpty {
            items.append(WalletChecklistItem(
                id: "addCards", kind: .addCards,
                title: String(localized: "Add your cards"),
                payoff: String(localized: "PickMe only recommends cards you add."),
                cardId: nil))
            return items   // nothing else is answerable yet
        }

        if setup.defaultCardId.isEmpty || !setup.ownedCardIds.contains(setup.defaultCardId) {
            items.append(WalletChecklistItem(
                id: "chooseDefault", kind: .chooseDefault,
                title: String(localized: "Choose a default card"),
                payoff: String(localized: "Used when no card is clearly better."),
                cardId: nil))
        }

        for gap in WalletConditions.unanswered(ownedCardIds: setup.ownedCardIds,
                                               catalogue: catalogue,
                                               answers: setup.conditionAnswers) {
            let name = catalogue.cards.first { $0.cardId == gap.cardId }?.officialName ?? gap.cardId
            items.append(WalletChecklistItem(
                id: "\(gap.cardId).\(gap.conditionId)",
                kind: .answerCondition,
                title: String(localized: "Answer 1 question about \(name)"),
                payoff: WalletConditions.detail(for: gap.conditionId),
                cardId: gap.cardId))
        }

        return items
    }
}

struct WalletChecklistBanner: View {
    let items: [WalletChecklistItem]
    let totalSteps: Int
    let onSelect: (WalletChecklistItem) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Finish setting up · \(totalSteps - items.count) of \(totalSteps)")
                    .font(.subheadline.weight(.semibold))

                ForEach(items) { item in
                    Button { onSelect(item) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.footnote.weight(.medium))
                                if let payoff = item.payoff {
                                    Text(payoff).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens the item that needs an answer"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.accentColor.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.35)))
        }
    }
}
