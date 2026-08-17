import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The answer screen. Displays the winning card with a physical card visual,
/// structured reward breakdown, and honest split-branch scenarios for ambiguous merchants.
struct RecommendationView: View {
    let result: CheckoutResult
    let deps: CheckoutFlowView.Dependencies?
    let onCompare: ((BenefitContextKind) -> Void)?
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch result.outcome {
                case .single(let recommendation):
                    singleOutcomeView(recommendation)
                case .fork(let branches):
                    forkOutcomeView(branches)
                }

                if result.amountWasEstimated {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                        Text("Based on a typical ~$\(Int(result.effectiveAmountCad)) purchase. Exact amounts you enter feed your value-recovered scoreboard.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(0.08))
                    )
                }

                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden()
    }

    // MARK: - Single Outcome View

    @ViewBuilder
    private func singleOutcomeView(_ recommendation: Recommendation) -> some View {
        let explanation = explanation(for: recommendation, category: result.prediction.category)
        let winnerCard = recommendation.winner
        let officialName = cardName(winnerCard.cardId)
        let returnText = String(format: "$%.2f back", winnerCard.netValueCad)

        VStack(alignment: .leading, spacing: 16) {
            // Hero Card Visual
            CardArtView(
                cardId: winnerCard.cardId,
                officialName: officialName,
                rewardHeadline: explanation?.headline,
                effectiveReturnText: returnText,
                isHero: true
            )

            // Value summary banner
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ESTIMATED RETURN")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", winnerCard.netValueCad))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                if winnerCard.rewardUnits > 0 {
                    let unitKind = deps?.catalogue.cards.first { $0.cardId == winnerCard.cardId }?.program.unit
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("REWARDS EARNED")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                        Text(formatRewardUnits(units: winnerCard.rewardUnits, kind: unitKind))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            // Explanations & Insights
            VStack(spacing: 10) {
                if let why = explanation?.why {
                    insightRow(
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        title: "Why this card won",
                        detail: why
                    )
                }

                if let runnerUp = explanation?.runnerUpLine {
                    insightRow(
                        icon: "arrow.up.arrow.down",
                        iconColor: .blue,
                        title: "Runner-up Comparison",
                        detail: runnerUp
                    )
                }

                if let valuation = explanation?.valuationLine {
                    insightRow(
                        icon: "slider.horizontal.3",
                        iconColor: .purple,
                        title: "Point Valuation",
                        detail: valuation
                    )
                }

                ForEach(explanation?.warningLines ?? [], id: \.self) { warning in
                    insightRow(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: .orange,
                        title: "Important Note",
                        detail: warning
                    )
                }
            }

            // Benefits and protections section
            if let deps {
                BenefitsDisclosureSection(
                    result: result,
                    deps: deps,
                    winnerCardId: winnerCard.cardId,
                    onCompare: { onCompare?($0) }
                )
            }
        }
    }

    // MARK: - Fork Outcome View (Ambiguous Merchant)

    @ViewBuilder
    private func forkOutcomeView(_ branches: [CheckoutBranch]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("Ambiguous Merchant Coding")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Text("This merchant location may code differently depending on the register terminal. Reconcile this purchase once posted to lock in the exact terminal rule.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            ForEach(branches, id: \.category) { branch in
                let cardId = branch.recommendation.winner.cardId
                let cardOfficialName = cardName(cardId)
                let netValue = branch.recommendation.winner.netValueCad

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(
                            "If Coded as \(categoryLabel(branch.category).uppercased())",
                            systemImage: CategoryVisuals.meta(for: branch.category).icon
                        )
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(CategoryVisuals.meta(for: branch.category).color)

                        Spacer()

                        Text(String(format: "≈ $%.2f back", netValue))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    CardArtView(
                        cardId: cardId,
                        officialName: cardOfficialName,
                        rewardHeadline: "Best if coded as \(categoryLabel(branch.category))",
                        effectiveReturnText: String(format: "$%.2f", netValue),
                        isHero: false
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                )
            }
        }
    }

    private func insightRow(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func formatRewardUnits(units: Double, kind: String?) -> String {
        switch kind {
        case "point":
            return "\(Int(units)) pts"
        case "cad":
            return String(format: "$%.2f cash", units)
        case "ctDollar":
            return String(format: "$%.2f CT Money", units)
        case "cro":
            return String(format: "%.2f CRO", units)
        default:
            return String(format: "%.1f units", units)
        }
    }

    private func explanation(for recommendation: Recommendation, category: String) -> Explanation? {
        deps?.explainer.explain(
            recommendation,
            purchase: PurchaseContext(amountCad: result.effectiveAmountCad, category: category)
        )
    }

    private func cardName(_ cardId: String) -> String {
        deps?.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }

    /// Routes through the same shared, catalogue-derived label source the category picker uses
    /// (`CategoryPickerAdvisor.label`), so a fork branch and a category pill never disagree on
    /// what to call the same category — and so a category the catalogue grows into never falls
    /// through to a raw identifier here either.
    private func categoryLabel(_ category: String) -> String {
        CategoryPickerAdvisor.label(for: category)
    }
}
