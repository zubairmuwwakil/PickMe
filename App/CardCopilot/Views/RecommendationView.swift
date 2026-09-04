import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The answer screen. Displays the winning card with a physical card visual,
/// structured reward breakdown, and honest split-branch scenarios for ambiguous merchants.
struct RecommendationView: View {
    let onCompare: ((BenefitContextKind) -> Void)?
    /// What's on screen. Seeded from the answer `CheckoutFlowView` handed in, then replaced in
    /// place whenever `AmountRefineRow` re-scores at a different amount — a `CheckoutResult` is
    /// all-`let`, so refining means holding a second one here rather than mutating the first.
    @State private var result: CheckoutResult
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(result: CheckoutResult, onCompare: ((BenefitContextKind) -> Void)?) {
        self._result = State(initialValue: result)
        self.onCompare = onCompare
    }

    var body: some View {
        if let graph = environment.graph {
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch result.outcome {
                case .single(let recommendation):
                    singleOutcomeView(recommendation, graph: graph)
                case .fork(let branches):
                    forkOutcomeView(branches, graph: graph)
                }

                AmountRefineRow(effectiveAmountCad: result.effectiveAmountCad,
                                amountWasEstimated: result.amountWasEstimated) { amountCad in
                    if let refined = session.refine(result, amountCad: amountCad, using: graph) {
                        result = refined
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        LiveActivityManager.shared.endActivity()
                        session.refresh(using: graph)
                        router.resetToIdle()
                        dismiss()
                        if let walletURL = URL(string: "shoebox://") {
                            openURL(walletURL)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "wallet.pass.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Pay with Apple Wallet")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }

                    Button {
                        LiveActivityManager.shared.endActivity()
                        session.refresh(using: graph)
                        router.resetToIdle()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarBackButtonHidden()
        } else {
            EmptyView()
        }
    }

    // MARK: - Single Outcome View

    @ViewBuilder
    private func singleOutcomeView(_ recommendation: Recommendation, graph: DependencyGraph) -> some View {
        let explanation = explanation(for: recommendation, category: result.prediction.category, graph: graph)
        let winnerCard = recommendation.winner
        let officialName = cardName(winnerCard.cardId, graph: graph)
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
                    let unitKind = graph.catalogue.cards.first { $0.cardId == winnerCard.cardId }?.program.unit
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

            if let route = routeEvaluation(for: recommendation, graph: graph) {
                routeOpportunityView(route, graph: graph)
            }

            // Dopamine Callout: Instant micro-gain over default card
            if recommendation.switchedFromDefault,
               let advantage = recommendation.advantageOverDefaultCad,
               advantage > 0.005 {
                let defaultName = graph.catalogue.cards.first { $0.cardId == graph.ownerState.defaultCardId }?.officialName ?? "default card"
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.18))
                            .frame(width: 38, height: 38)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "+$%.2f EARNED OVER DEFAULT", advantage))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                            .tracking(0.6)
                        Text("Extra cash recovered vs tapping \(defaultName)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.green.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.green.opacity(0.35), lineWidth: 1)
                        )
                )
            } else if !recommendation.switchedFromDefault, !graph.ownerState.defaultCardId.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("Your default card is already the optimal pick here.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )
            }

            // Chip Mascot Contextual Voice & Rule Insights
            let purchase = ambientPurchaseContext(merchant: result.merchant, category: result.prediction.category)
            let chipInsights = ChipInsightAdvisor.evaluate(
                recommendation: recommendation,
                purchase: purchase,
                catalogue: graph.catalogue,
                defaultCardId: graph.ownerState.defaultCardId
            )
            if let primaryInsight = chipInsights.first {
                let formatted = ChipInsightFormatter.format(primaryInsight)
                HStack(alignment: .center, spacing: 12) {
                    ChipMascotView(
                        mood: formatted.mood,
                        size: 42,
                        isWaving: true,
                        enable3DTilt: false
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(formatted.tag)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .tracking(0.8)

                        Text(formatted.text)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                        )
                )
            }

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
            BenefitsDisclosureSection(
                result: result,
                deps: graph,
                winnerCardId: winnerCard.cardId,
                onCompare: { onCompare?($0) }
            )
        }
    }

    @ViewBuilder
    private func routeOpportunityView(_ evaluation: PurchaseRouteEvaluation,
                                      graph: DependencyGraph) -> some View {
        let route = evaluation.route
        let acquisitionCard = cardName(evaluation.acquisitionRecommendation.winner.cardId, graph: graph)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("POTENTIALLY BETTER ROUTE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .tracking(0.7)
                    Text("Buy a \(route.instrumentLabel) at \(route.acquisitionMerchantLabel).")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PAY FOR IT WITH")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(acquisitionCard)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("EXTRA VALUE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(String(format: "+$%.2f", evaluation.advantageCad))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Text("\(routeEvidenceLabel(route.evidenceLevel)). \(route.disclosure)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.green.opacity(0.28), lineWidth: 1)
                )
        )
    }

    private func routeEvaluation(for recommendation: Recommendation,
                                 graph: DependencyGraph) -> PurchaseRouteEvaluation? {
        let brand = canonicalEngineBrand(result.merchant.name)
        let destination = PurchaseContext(
            amountCad: result.effectiveAmountCad,
            category: result.prediction.category,
            mcc: result.prediction.merchantCategoryCode,
            merchantBrand: brand,
            acceptedNetworks: knownAcceptedNetworks(for: brand, merchantName: result.merchant.name)
        )
        // Generic acquisition routes must not inherit merchant-specific statement credits. Those
        // are only defensible when the actual acquisition merchant is known.
        let routeEngine = RecommendationEngine(catalogue: graph.catalogue,
                                               ownerState: graph.ownerState,
                                               includeCheckoutCredits: false)
        let today = Date().formatted(.iso8601.year().month().day())
        return PurchaseRouteAdvisor.bestAlternative(
            directRecommendation: recommendation,
            destination: destination,
            destinationMerchantName: result.merchant.name,
            engine: routeEngine,
            asOf: today
        )
    }

    private func routeEvidenceLabel(_ level: PurchaseRouteEvidenceLevel) -> String {
        switch level {
        case .retailerConfirmed:
            return "Retailer-confirmed route"
        case .communityObserved:
            return "Community-observed route; not guaranteed"
        case .experimental:
            return "Experimental route"
        }
    }

    // MARK: - Fork Outcome View (Ambiguous Merchant)

    @ViewBuilder
    private func forkOutcomeView(_ branches: [CheckoutBranch], graph: DependencyGraph) -> some View {
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
                let cardOfficialName = cardName(cardId, graph: graph)
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

    private func explanation(for recommendation: Recommendation, category: String, graph: DependencyGraph) -> Explanation? {
        graph.explainer.explain(
            recommendation,
            purchase: PurchaseContext(amountCad: result.effectiveAmountCad, category: category)
        )
    }

    private func cardName(_ cardId: String, graph: DependencyGraph) -> String {
        graph.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }

    /// Routes through the same shared, catalogue-derived label source the category picker uses
    /// (`CategoryPickerAdvisor.label`), so a fork branch and a category pill never disagree on
    /// what to call the same category — and so a category the catalogue grows into never falls
    /// through to a raw identifier here either.
    private func categoryLabel(_ category: String) -> String {
        CategoryPickerAdvisor.label(for: category)
    }
}
