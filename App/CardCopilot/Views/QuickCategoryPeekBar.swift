import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// A fast, horizontal category peek strip allowing owners to glance at their best card
/// for everyday categories in 1 tap without searching or typing an amount.
struct QuickCategoryPeekBar: View {
    let deps: DependencyGraph
    var onSelectCategory: ((String) -> Void)? = nil

    @State private var peekedCategory: String? = nil
    private let topCategories: [(id: String, name: String, icon: String, color: Color)] = [
        ("dining", "Dining", "fork.knife", Color.orange),
        ("grocery", "Groceries", "cart.fill", Color.green),
        ("travel", "Travel", "airplane", Color.blue),
        ("gasStation", "Gas", "fuelpump.fill", Color.red),
        ("drugStore", "Drugstore", "pills.fill", Color.teal),
        ("transit", "Transit", "tram.fill", Color.indigo),
        ("recurring", "Bills", "repeat", Color.purple)
    ]

    /// The same amount used by the quick recommendation entry points elsewhere in the app.
    /// The label below makes this assumption visible instead of presenting a banded answer as
    /// though it were amount-independent.
    private let peekAmountCad = 50.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Category Peek")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Spacer()

                Text("1-Tap Check")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(topCategories, id: \.id) { cat in
                        categorySquircleItem(cat)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }

            // Quick Inline Glance Card when tapped
            if let activeId = peekedCategory,
               let peekSummary = categoryWinnerSummary(for: activeId) {
                quickGlanceCard(summary: peekSummary)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: peekedCategory)
    }

    private func categorySquircleItem(_ cat: (id: String, name: String, icon: String, color: Color)) -> some View {
        let isSelected = peekedCategory == cat.id

        return Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                if peekedCategory == cat.id {
                    peekedCategory = nil
                } else {
                    peekedCategory = cat.id
                    onSelectCategory?(cat.id)
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            isSelected
                                ? cat.color
                                : cat.color.opacity(0.16)
                        )
                        .frame(width: 58, height: 58)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.white.opacity(0.4) : cat.color.opacity(0.12),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: isSelected ? cat.color.opacity(0.35) : Color.clear,
                            radius: 6,
                            x: 0,
                            y: 3
                        )

                    Image(systemName: cat.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : cat.color)
                }

                Text(cat.name)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(width: 62)
        }
        .buttonStyle(.plain)
    }

    private func quickGlanceCard(summary: CategoryWinnerSummary) -> some View {
        HStack(spacing: 12) {
            CardMiniBadge(cardId: summary.cardId, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(summary.cardName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(summary.earnRateText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }

                Text(summary.reasonText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                withAnimation { peekedCategory = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Quick Evaluation Helper

    private struct CategoryWinnerSummary {
        let cardId: String
        let cardName: String
        let earnRateText: String
        let reasonText: String
    }

    private func categoryWinnerSummary(for category: String) -> CategoryWinnerSummary? {
        let distribution = SpendDistribution.placeholderCanadianHousehold
        let asOf = Date().formatted(.iso8601.year().month().day())
        let bands = CategoryPickerAdvisor.bands(
            for: category,
            catalogue: deps.catalogue,
            ownerState: deps.ownerState,
            distribution: distribution,
            asOf: asOf
        )

        guard let selectedBand = CategoryPickerAdvisor.band(containing: peekAmountCad,
                                                            in: bands) else { return nil }
        let winnerCardId = selectedBand.cardId
        let winnerCardName = deps.catalogue.cards.first { $0.cardId == winnerCardId }?.officialName ?? winnerCardId

        let earnText: String = {
            if let ruleId = selectedBand.recommendation.winner.appliedRuleId,
               let card = deps.catalogue.cards.first(where: { $0.cardId == winnerCardId }),
               let rule = card.earnRules.first(where: { $0.ruleId == ruleId }) {
                switch rule.earn {
                case .points(let perCad):
                    return "\(CategoryPickerFormatting.multiplier(perCad))x pts"
                case .cashback(let rate, _):
                    return "\(CategoryPickerFormatting.percent(rate)) cash"
                case .centsPerLitre:
                    return "Gas savings"
                }
            }
            return "Top Card"
        }()

        let categoryLabel = CategoryPickerAdvisor.label(for: category, distribution: distribution)
        let amountText = WalletHealthFormatting.cad(peekAmountCad)
        let reasonText = selectedBand.recommendation.switchedFromDefault
            ? "Best at \(amountText) for \(categoryLabel)"
            : "Default is optimal at \(amountText)"

        return CategoryWinnerSummary(
            cardId: winnerCardId,
            cardName: winnerCardName,
            earnRateText: earnText,
            reasonText: reasonText
        )
    }
}
