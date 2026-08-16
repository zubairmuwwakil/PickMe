import SwiftUI
import CardCopilotEngine

/// Surfaces `PortfolioAnalyzer` — the keep/cancel question — for the first time anywhere in the
/// app. Two facts stay visible everywhere on this screen, never buried behind a tap:
/// the spend profile is a placeholder (decision #19), and every dollar figure that drives a
/// verdict is marginal, never gross (decision #17).
struct WalletHealthView: View {
    let deps: CheckoutFlowView.Dependencies
    let onDone: () -> Void

    @State private var analysis: PortfolioAnalysis?

    private let distribution = SpendDistribution.placeholderCanadianHousehold

    private var cardNames: [String: String] {
        Dictionary(uniqueKeysWithValues: deps.catalogue.cards.map { ($0.cardId, $0.officialName) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let analysis {
                    assumptionBanner
                    summaryCard(analysis)
                    cardsSection(analysis)
                    if !analysis.redundantPairs.isEmpty {
                        redundantPairsSection(analysis)
                    }
                    footer
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Wallet Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .font(.headline)
            }
        }
        .task {
            guard analysis == nil else { return }
            let today = Date().formatted(.iso8601.year().month().day())
            analysis = PortfolioAnalyzer(catalogue: deps.catalogue, ownerState: deps.ownerState)
                .analyze(distribution, asOf: today)
        }
    }

    // MARK: - Assumption banner (decision #19: viewable, never editable)

    private var assumptionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                Text("SPEND PROFILE: PLACEHOLDER")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
            }

            Text("Every verdict below runs against a documented guess at a \(WalletHealthFormatting.cad(distribution.totalAnnualCad))/yr Canadian household — not your real spending. No statement history exists yet to replace it.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            DisclosureGroup("View the \(distribution.buckets.count) assumed categories") {
                VStack(spacing: 6) {
                    ForEach(distribution.buckets, id: \.label) { bucket in
                        HStack {
                            Text(bucket.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(WalletHealthFormatting.cad(bucket.annualCad))
                                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .tint(.orange)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Portfolio summary

    private func summaryCard(_ analysis: PortfolioAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WALLET, OPTIMALLY USED")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WalletHealthFormatting.cad(analysis.portfolioValueCad))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("earned/yr, every purchase on its best card")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(WalletHealthFormatting.cad(analysis.totalAnnualFeesCad))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("in fees across \(analysis.contributions.count) cards")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("A ceiling, not a forecast — it assumes every purchase always lands on its best card. The per-card verdicts below are what each card actually contributes toward it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - Per-card verdicts

    private func cardsSection(_ analysis: PortfolioAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per Card")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(spacing: 10) {
                ForEach(analysis.contributions, id: \.cardId) { contribution in
                    CardContributionRow(contribution: contribution,
                                        cardName: cardNames[contribution.cardId] ?? contribution.cardId,
                                        cardNames: cardNames)
                }
            }
        }
    }

    // MARK: - Redundant pairs (decision #17: a pair observation, never two cancel verdicts)

    private func redundantPairsSection(_ analysis: PortfolioAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.purple)
                Text("Cards Covering For Each Other")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Text("Each card below measures near-$0 alone only because the other already earns the same spend. That is a pair fact, not two individual cancel verdicts — cancelling both loses real value.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(analysis.redundantPairs, id: \.cardIds) { pair in
                    redundantPairRow(pair)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.purple.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func redundantPairRow(_ pair: RedundantPair) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pair.cardIds.map { cardNames[$0] ?? $0 }.joined(separator: " + "))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Jointly worth \(WalletHealthFormatting.cad(pair.jointMarginalCad))/yr, versus \(WalletHealthFormatting.cad(pair.sumOfIndividualMarginalsCad)) summing their individual marginals — against \(WalletHealthFormatting.cad(pair.combinedAnnualFeeCad)) combined fees.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var footer: some View {
        Text("Estimates only, from a placeholder spend profile — not a recommendation to cancel any card. Verdicts are re-derived from the same rules the checkout engine uses, never guessed.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}

/// One card's marginal-value row: verdict, the marginal-vs-fee headline, and every state the
/// analyzer can report (`requiredBenefitValueCad`, `feeWaiverUnresolved`, `neverScorable`,
/// `backfilledBy`) rendered explicitly rather than folded into the verdict pill.
private struct CardContributionRow: View {
    let contribution: CardContribution
    let cardName: String
    let cardNames: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CardMiniBadge(cardId: contribution.cardId, size: 22)
                Text(cardName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                verdictPill
            }

            if contribution.neverScorable {
                stateLine(icon: "xmark.octagon.fill", color: .gray,
                          text: "Never scores on this spend profile — owner state or network acceptance gates it out of every purchase.")
            } else {
                headline
                if contribution.feeWaiverUnresolved {
                    stateLine(icon: "questionmark.circle.fill", color: .orange,
                              text: "Fee waiver status unknown — this verdict assumes the stated fee applies.")
                }
                if contribution.requiredBenefitValueCad > 0 {
                    Text("Keep only if its benefits are worth ≥ \(WalletHealthFormatting.cad(contribution.requiredBenefitValueCad))/yr to you.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                }
                ForEach(contribution.backfilledBy, id: \.cardId) { share in
                    Text("If cancelled, \(cardNames[share.cardId] ?? share.cardId) absorbs \(WalletHealthFormatting.cad(share.valueRetainedCad))/yr of this spend (\(share.bucketLabels.joined(separator: ", "))).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(WalletHealthFormatting.cad(contribution.marginalValueCad))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("marginal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("vs")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(WalletHealthFormatting.cad(contribution.annualFeeCad))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("fee")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            // Gross is shown for contrast only — decision #17 exists because subtracting the fee
            // from this number, not the marginal figure above, is the classic wrong answer.
            if abs(contribution.grossRewardValueCad - contribution.marginalValueCad) > 0.01 {
                Text("Gross \(WalletHealthFormatting.cad(contribution.grossRewardValueCad))/yr before removing duplicate coverage — not what this card is actually worth to the wallet.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var verdictPill: some View {
        Text(WalletHealthFormatting.verdictLabel(contribution.verdict))
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(WalletHealthFormatting.verdictColor(contribution.verdict), in: Capsule())
    }

    private func stateLine(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

enum WalletHealthFormatting {
    static func cad(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CAD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return formatter.string(from: value as NSNumber) ?? "$\(Int(value))"
    }

    static func verdictLabel(_ verdict: PortfolioVerdict) -> String {
        switch verdict {
        case .freeToKeep: return "Free to keep"
        case .keep: return "Keep"
        case .downgrade: return "Downgrade"
        case .cancel: return "Cancel"
        }
    }

    static func verdictColor(_ verdict: PortfolioVerdict) -> Color {
        switch verdict {
        case .freeToKeep: return .gray
        case .keep: return .green
        case .downgrade: return .orange
        case .cancel: return .red
        }
    }
}
