import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// Surfaces `PortfolioAnalyzer` — the keep/cancel question — for the first time anywhere in the
/// app. Two facts stay visible everywhere on this screen, never buried behind a tap:
/// the spend profile is a placeholder (decision #19), and every dollar figure that drives a
/// verdict is marginal, never gross (decision #17).
struct WalletHealthView: View {
    let deps: DependencyGraph
    var recentPurchases: [StoredPrediction] = []
    let onDone: () -> Void

    @State private var analysis: PortfolioAnalysis?
    @State private var acquisitionAnalysis: AcquisitionAnalysis?
    @State private var mode: Mode = .wallet

    private enum Mode: String, CaseIterable, Identifiable {
        case wallet = "Keep or cancel"
        case acquisition = "Cards to add"
        var id: String { rawValue }
    }

    private enum SpendProfileChoice: String, CaseIterable, Identifiable {
        case personalized = "Your Real Spend"
        case standard = "Standard ($40k)"
        case student = "Student ($18k)"
        case traveler = "Traveler ($84k)"
        var id: String { rawValue }
    }

    @State private var selectedProfile: SpendProfileChoice

    init(deps: DependencyGraph, recentPurchases: [StoredPrediction] = [], onDone: @escaping () -> Void) {
        self.deps = deps
        self.recentPurchases = recentPurchases
        self.onDone = onDone
        _selectedProfile = State(initialValue: recentPurchases.isEmpty ? .standard : .personalized)
    }

    private var activeDistribution: SpendDistribution {
        switch selectedProfile {
        case .personalized:
            if !recentPurchases.isEmpty {
                return ObservedSpendProfileBuilder().build(from: recentPurchases, baseline: .placeholderCanadianHousehold)
            } else {
                return .placeholderCanadianHousehold
            }
        case .standard:
            return .placeholderCanadianHousehold
        case .student:
            return .frugalStudent
        case .traveler:
            return .frequentTraveler
        }
    }

    private var cardNames: [String: String] {
        Dictionary(uniqueKeysWithValues: deps.catalogue.cards.map { ($0.cardId, $0.officialName) })
    }

    /// Names come from the one corpus now; the candidate list only says WHICH products are
    /// candidates, so there is no second place for a card's name to disagree with itself.
    private var candidateNames: [String: String] {
        let byId = Dictionary(deps.catalogue.cards.map { ($0.cardId, $0.officialName) },
                              uniquingKeysWith: { first, _ in first })
        return Dictionary(uniqueKeysWithValues:
            deps.candidateCardIds.compactMap { id in byId[id].map { (id, $0) } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let analysis, let acquisitionAnalysis {
                    assumptionBanner
                    profileSwitcher
                    modePicker
                    if mode == .wallet {
                        summaryCard(analysis)
                        cardsSection(analysis)
                        if !analysis.redundantPairs.isEmpty {
                            redundantPairsSection(analysis)
                        }
                    } else {
                        acquisitionSection(acquisitionAnalysis)
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
            recalculateAnalysis()
        }
    }

    private func recalculateAnalysis() {
        let today = Date().formatted(.iso8601.year().month().day())
        analysis = PortfolioAnalyzer(catalogue: deps.catalogue, ownerState: deps.ownerState)
            .analyze(activeDistribution, asOf: today)
        acquisitionAnalysis = AcquisitionAnalyzer(
            catalogue: deps.catalogue,
            candidateCardIds: deps.candidateCardIds,
            ownerState: deps.ownerState)
            .analyze(activeDistribution, asOf: today)
    }

    private var profileSwitcher: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spend Profile").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("Spend Profile", selection: $selectedProfile) {
                ForEach(SpendProfileChoice.allCases) { profile in
                    Text(profile.rawValue).tag(profile)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedProfile) { _, _ in
                recalculateAnalysis()
            }
        }
    }

    private var modePicker: some View {
        Picker("Analysis", selection: $mode) {
            ForEach(Mode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Assumption banner (decision #19: viewable, never editable)

    private var isPersonalized: Bool {
        selectedProfile == .personalized && !recentPurchases.isEmpty
    }

    private var themeColor: Color {
        isPersonalized ? .teal : .orange
    }

    private var assumptionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: isPersonalized ? "person.crop.circle.badge.checkmark" : "slider.horizontal.2.square")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(themeColor)
                Text(isPersonalized ? "SPEND PROFILE: YOUR REAL SPEND (PERSONALIZED)" : "SPEND PROFILE: \(selectedProfile.rawValue.uppercased())")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
            }

            Text(isPersonalized
                 ? "Verdicts personalized to \(recentPurchases.count) recorded checkouts on this device, annualized to \(WalletHealthFormatting.cad(activeDistribution.totalAnnualCad))/yr. Unobserved categories blended from Canadian baseline."
                 : "Verdicts run against \(WalletHealthFormatting.cad(activeDistribution.totalAnnualCad))/yr Canadian spend profile. Switch profiles to test if verdicts hold under your spending style.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            DisclosureGroup("View the \(activeDistribution.buckets.count) \(isPersonalized ? "annualized" : "assumed") categories") {
                VStack(spacing: 6) {
                    ForEach(activeDistribution.buckets, id: \.label) { bucket in
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
            .tint(themeColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(themeColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(themeColor.opacity(0.25), lineWidth: 1)
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

    // MARK: - Acquisition (the reverse portfolio counterfactual)

    private func acquisitionSection(_ acquisition: AcquisitionAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            acquisitionOutcome(acquisition)

            VStack(alignment: .leading, spacing: 4) {
                Text("Ranked by recurring net value")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Each card is added alone, then every purchase is re-optimized across your wallet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(acquisition.candidates.enumerated()), id: \.element.cardId) {
                    index, candidate in
                    AcquisitionCandidateRow(
                        rank: index + 1,
                        candidate: candidate,
                        cardName: candidateNames[candidate.cardId] ?? candidate.cardId,
                        walletNames: cardNames)
                    if index < acquisition.candidates.count - 1 {
                        Divider().padding(.leading, 42)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Label("What is not in the number", systemImage: "equal.circle")
                    .font(.subheadline.weight(.semibold))
                Text("Welcome bonuses, first-year fee rebates, approval odds, credit-score effects, insurance, lounges and statement credits are excluded. Income eligibility is not assessed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
    }

    private func acquisitionOutcome(_ acquisition: AcquisitionAnalysis) -> some View {
        let hasRecommendation = !acquisition.recommended.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: hasRecommendation ? "plus.circle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(hasRecommendation ? Color.teal : Color.green)
                Text(hasRecommendation ? "A card earns its recurring fee" : "No new card earns its fee")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            Text(hasRecommendation
                 ? "The positive results below add more annual reward value than their stated recurring fee."
                 : "Against this wallet and spend profile, keeping the wallet unchanged beats every researched candidate on recurring earn after fees.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(acquisition.candidates.count) issuer-verified candidates · year-two economics")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.teal)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill((hasRecommendation ? Color.teal : Color.green).opacity(0.09))
        )
    }

    private var footer: some View {
        Text("Estimates only, from a placeholder spend profile — not financial advice or an application recommendation. Every result is re-derived from the checkout engine's rules, never an affiliate ranking.")
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

/// A candidate is a comparison, not an offer. The collapsed row answers the decision; expanding
/// it exposes the counterfactual evidence without turning the screen into a comparison-site grid.
private struct AcquisitionCandidateRow: View {
    let rank: Int
    let candidate: AcquisitionCandidate
    let cardName: String
    let walletNames: [String: String]

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            evidence
                .padding(.top, 12)
                .padding(.leading, 42)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(rank)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 24)
                CardMiniBadge(cardId: candidate.cardId, size: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(cardName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(WalletHealthFormatting.acquisitionLabel(candidate.verdict))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WalletHealthFormatting.acquisitionColor(candidate.verdict))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(WalletHealthFormatting.signedCad(candidate.netAnnualValueCad))
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(candidate.netAnnualValueCad > 0.01 ? Color.green : Color.secondary)
                    Text("net / yr")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 14)
        }
        .tint(.secondary)
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                metric("Marginal rewards", candidate.marginalRewardValueCad)
                metric("Recurring fee", candidate.annualFeeCad)
            }

            if candidate.grossRewardValueCad > candidate.marginalRewardValueCad + 0.01 {
                Text("It would earn \(WalletHealthFormatting.cad(candidate.grossRewardValueCad)) gross, but most of that spend is already covered by cards you own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if candidate.bucketGains.isEmpty {
                Label("No spend category improves", systemImage: "minus.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(candidate.bucketGains, id: \.label) { gain in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(gain.label)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(WalletHealthFormatting.signedCad(gain.marginalValueCad))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.teal)
                        }
                        if !gain.displacedCardIds.isEmpty {
                            Text("Replaces \(gain.displacedCardIds.map { walletNames[$0] ?? $0 }.joined(separator: ", ")) on \(WalletHealthFormatting.cad(gain.annualSpendCad)) of annual spend.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if candidate.requiredBenefitValueCad > 0, candidate.marginalRewardValueCad > 0.01 {
                Text("Its unpriced benefits must be worth at least \(WalletHealthFormatting.cad(candidate.requiredBenefitValueCad))/yr to break even.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            if candidate.feeWaiverUnresolved {
                Label("A possible fee waiver is unresolved; ranking uses the stated fee.",
                      systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.bottom, 14)
    }

    private func metric(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WalletHealthFormatting.cad(value))
                .font(.subheadline.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
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

    static func signedCad(_ value: Double) -> String {
        if abs(value) < 0.005 { return "$0" }
        return (value > 0 ? "+" : "−") + cad(abs(value))
    }

    static func acquisitionLabel(_ verdict: AcquisitionVerdict) -> String {
        switch verdict {
        case .worthAdding: return "Earns its fee"
        case .benefitsRequired: return "Benefits must cover the gap"
        case .noEarnAdvantage: return "No recurring earn advantage"
        }
    }

    static func acquisitionColor(_ verdict: AcquisitionVerdict) -> Color {
        switch verdict {
        case .worthAdding: return .green
        case .benefitsRequired: return .orange
        case .noEarnAdvantage: return .secondary
        }
    }
}
