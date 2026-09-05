import SwiftUI
import CardCopilotStore

/// A compact, on-device diagnostic for the question that justifies MCC learning: whether better
/// evidence changes the card PickMe recommends. This intentionally is not an analytics dashboard.
struct MerchantMCCDecisionQualityView: View {
    let onDone: () -> Void

    @State private var summary = MerchantMCCDecisionQualitySummary(
        graphDecisionCount: 0,
        runtimeEvidenceDecisionCount: 0,
        runtimeEvidenceTopMCCChangeCount: 0,
        scoreableMCCUncertaintyDecisionCount: 0,
        mccUncertaintyWinnerChangeCount: 0,
        unscoreableMCCUncertaintyDecisionCount: 0,
        scoreableRuntimeEvidenceWinnerComparisonCount: 0,
        runtimeEvidenceWinnerChangeCount: 0,
        exactMCCWinnerValidationCount: 0,
        exactMCCValidatedWinnerChangeCount: 0)

    var body: some View {
        List {
            Section {
                headline
            } header: {
                Text("Decision quality")
            } footer: {
                Text("Exact MCCs from reconciliation or a safely joined issuer export validate the classification premise of a changed recommendation. They do not claim to verify every issuer posting or card benefit.")
            }

            Section {
                LabeledContent("Graph-backed checkout decisions",
                               value: "\(summary.graphDecisionCount)")
                LabeledContent("Seed-only decisions", value: "\(summary.seedOnlyDecisionCount)")
                rateRow("Learned evidence available",
                        share: summary.runtimeEvidenceCoverageShare,
                        detail: "\(summary.runtimeEvidenceDecisionCount) decisions")
                rateRow("Learned evidence moved top MCC",
                        share: summary.runtimeEvidenceTopMCCChangeShare,
                        detail: "\(summary.runtimeEvidenceTopMCCChangeCount) of \(summary.runtimeEvidenceDecisionCount)")
                rateRow("MCC uncertainty changed winner",
                        share: summary.mccUncertaintyWinnerChangeShare,
                        detail: "\(summary.mccUncertaintyWinnerChangeCount) of \(summary.scoreableMCCUncertaintyDecisionCount)")
                rateRow("Changed winner (awaiting exact MCC)",
                        share: summary.runtimeEvidenceWinnerChangeShare,
                        detail: "\(summary.runtimeEvidenceWinnerChangeCount) of \(summary.scoreableRuntimeEvidenceWinnerComparisonCount)")

                if summary.unscoreableMCCUncertaintyDecisionCount > 0 {
                    LabeledContent("Unscoreable MCC forks",
                                   value: "\(summary.unscoreableMCCUncertaintyDecisionCount)")
                }
            } header: {
                Text("What PickMe observed")
            } footer: {
                Text("All figures are aggregate-only on this iPhone. No merchant, MCC, category, card, coordinate, or timestamp is kept for this diagnostic. Erasing local history clears it.")
            }
        }
        .navigationTitle("MCC Evidence Quality")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .font(.headline)
            }
        }
        .onAppear(perform: reload)
    }

    @ViewBuilder
    private var headline: some View {
        if let share = summary.exactMCCValidatedWinnerChangeShare {
            VStack(alignment: .leading, spacing: 6) {
                Text(percent(share))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.teal)
                Text("Exact MCC validated a learned card change")
                    .font(.headline)
                Text("\(summary.exactMCCValidatedWinnerChangeCount) of \(summary.exactMCCWinnerValidationCount) changed-winner decisions with an exact MCC")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if summary.exactMCCWinnerValidationCount < 10 {
                    Text("Early signal — more exact-MCC outcomes will make this rate more representative.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        } else {
            ContentUnavailableView(
                "Not enough data yet",
                systemImage: "chart.bar.xaxis",
                description: Text("PickMe needs a changed-winner checkout later matched to an exact MCC. Unavailable is not the same as 0%."))
                .padding(.vertical, 12)
        }
    }

    private func rateRow(_ title: String, share: Double?, detail: String) -> some View {
        LabeledContent(title) {
            if let share {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(percent(share))
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Not scoreable yet")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func reload() {
        summary = CategoryResolutionMetricsStore().snapshot.merchantMCCDecisionQualitySummary
    }
}
