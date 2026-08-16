import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The answer screen. Two shapes: a single verdict with the full explanation, or — when the
/// category is genuinely ambiguous AND the branches disagree — the fork, shown as honest
/// uncertainty rather than fake confidence.
struct RecommendationView: View {
    let result: CheckoutResult
    let deps: CheckoutFlowView.Dependencies?
    let onCompare: ((BenefitContextKind) -> Void)?
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch result.outcome {
                case .single(let recommendation):
                    singleView(recommendation)
                case .fork(let branches):
                    forkView(branches)
                }

                if result.amountWasEstimated {
                    Label("Based on a typical ~$\(Int(result.effectiveAmountCad)) purchase — amounts you enter feed your value-recovered total.",
                          systemImage: "questionmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Done") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding()
        }
        .navigationBarBackButtonHidden()
    }

    @ViewBuilder
    private func singleView(_ recommendation: Recommendation) -> some View {
        let explanation = explanation(for: recommendation, category: result.prediction.category)
        VStack(alignment: .leading, spacing: 12) {
            Text(cardName(recommendation.winner.cardId))
                .font(.largeTitle.bold())
            Text(explanation?.headline ?? "")
                .font(.title3)

            if let why = explanation?.why {
                Text(why).font(.subheadline).foregroundStyle(.secondary)
            }
            if let runnerUp = explanation?.runnerUpLine {
                Text(runnerUp).font(.subheadline).foregroundStyle(.secondary)
            }
            if let valuation = explanation?.valuationLine {
                Label(valuation, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.blue)
            }
            ForEach(explanation?.warningLines ?? [], id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if let deps {
                BenefitsDisclosureSection(result: result,
                                          deps: deps,
                                          winnerCardId: recommendation.winner.cardId,
                                          onCompare: { onCompare?($0) })
            }
        }
    }

    @ViewBuilder
    private func forkView(_ branches: [CheckoutBranch]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("This one could code either way", systemImage: "arrow.triangle.branch")
                .font(.title3.weight(.semibold))
            Text("After it posts, tell the app which it was — next time the answer is instant.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(branches, id: \.category) { branch in
                VStack(alignment: .leading, spacing: 4) {
                    Text("If it codes as \(readableCategory(branch.category))")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(cardName(branch.recommendation.winner.cardId))
                        .font(.headline)
                    Text(String(format: "≈ $%.2f back", branch.recommendation.winner.netValueCad))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func explanation(for recommendation: Recommendation, category: String) -> Explanation? {
        deps?.explainer.explain(recommendation,
                                purchase: PurchaseContext(amountCad: result.effectiveAmountCad,
                                                          category: category))
    }

    private func cardName(_ cardId: String) -> String {
        deps?.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }

    private func readableCategory(_ category: String) -> String {
        switch category {
        case "grocery": return "grocery"
        case "gasStation": return "a gas station"
        case "dining": return "dining"
        case "other": return "general merchandise"
        default: return category
        }
    }
}
