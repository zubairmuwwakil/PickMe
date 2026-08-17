import SwiftUI
import CardCopilotStore

/// The experiment scoreboard: the two metrics that decide whether this MVP passes, what the
/// misses were, and how far the 30 checkouts have got.
struct DashboardView: View {
    let metrics: ExperimentMetrics
    let valueRecoveredCad: Double
    let pendingValueCad: Double
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                progressCard

                MetricCard(
                    title: "Category Accuracy",
                    caption: "Predicted category confirmed against the posted statement.",
                    rate: metrics.categoryAccuracy,
                    barText: "Target: 85%",
                    meetsBar: metrics.meetsCategoryBar,
                    denominator: metrics.confirmedCount == 0 ? nil : "\(metrics.categoryCorrectCount) of \(metrics.confirmedCount) confirmed",
                    emptyLine: "No confirmations yet — reconcile a checkout to start measuring."
                )

                MetricCard(
                    title: "Arithmetic Correctness",
                    caption: "Posted rewards match the catalogue math used at checkout.",
                    rate: metrics.arithmeticCorrectRate,
                    barText: "Target: 100%",
                    meetsBar: metrics.meetsArithmeticBar,
                    denominator: metrics.arithmeticEligibleCount == 0 ? nil : "\(metrics.arithmeticCorrectCount) of \(metrics.arithmeticEligibleCount) checkable",
                    emptyLine: eligibilityEmptyLine
                )

                missBreakdownCard
                valueRecoveredCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Experiment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .font(.headline)
            }
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXPERIMENT PROGRESS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(metrics.progressToTarget)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("/ \(metrics.targetCheckouts) checkouts")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.15), lineWidth: 6)
                        .frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(Double(metrics.progressToTarget) / Double(metrics.targetCheckouts), 1.0)))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((Double(min(metrics.progressToTarget, metrics.targetCheckouts)) / Double(metrics.targetCheckouts)) * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }

            ProgressView(
                value: Double(min(metrics.progressToTarget, metrics.targetCheckouts)),
                total: Double(metrics.targetCheckouts)
            )
            .tint(.blue)

            HStack {
                Text("Validation target: 30 physical Canadian checkouts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if metrics.progressToTarget >= metrics.targetCheckouts {
                    Label("Target Reached", systemImage: "flag.checkered")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }

    private var eligibilityEmptyLine: String {
        metrics.confirmedCount == 0
            ? "No confirmations yet — reconcile a checkout to start measuring."
            : "Nothing checkable yet. A row counts only when the category was right, the amount was real, you tapped the card the app named, and the statement showed the rewards."
    }

    private var missBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Taxonomy Breakdown")
                .font(.system(size: 17, weight: .bold, design: .rounded))

            if metrics.missBreakdown.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    Text(metrics.confirmedCount == 0 ? "Nothing reconciled yet." : "No misses recorded so far across all confirmed checkouts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(MissClass.allCases, id: \.self) { miss in
                        if let count = metrics.missBreakdown[miss] {
                            HStack {
                                Text(missLabel(miss))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(count)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var valueRecoveredCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NET VALUE RECOVERED")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.secondary)

            Text(String(format: "$%.2f", valueRecoveredCad))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            if pendingValueCad > 0 {
                Text(String(format: "+$%.2f recorded but not yet reconciled", pendingValueCad))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
            }

            Text("Counted only where you used the recommended card and recorded what it actually cost, scaled from the amount the engine scored. Reconciled purchases only — the pending figure is not included, because until a statement confirms how a charge coded, the return is an assumption.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func missLabel(_ miss: MissClass) -> String {
        switch miss {
        case .wrongCategory: return "Wrong Category"
        case .capExceeded: return "Cap Exceeded"
        case .staleRule: return "Catalogue Rule Outdated"
        case .processorWeirdness: return "Processor / Gateway Coding"
        case .networkNotAccepted: return "Network Not Accepted"
        }
    }
}

/// One metric card with its threshold bar and color status.
private struct MetricCard: View {
    let title: String
    let caption: String
    let rate: Double?
    let barText: String
    let meetsBar: Bool?
    let denominator: String?
    let emptyLine: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text(barText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let rate {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%.0f%%", rate * 100))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(meetsBar == true ? Color.green : Color.orange)

                    if let meetsBar {
                        Label(
                            meetsBar ? "Meets Target" : "Below Target",
                            systemImage: meetsBar ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                        )
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(meetsBar ? Color.green : Color.orange)
                    }
                }

                if let denominator {
                    Text(denominator)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Awaiting Evidence")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(emptyLine)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}
