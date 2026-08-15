import SwiftUI
import CardCopilotStore

/// The experiment scoreboard: the two metrics that decide whether this MVP passes, what the
/// misses were, and how far the 30 checkouts have got. Every number here refuses to exist
/// before the evidence does — an unmeasured experiment is not a failing one.
struct DashboardView: View {
    let metrics: ExperimentMetrics
    let valueRecoveredCad: Double
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                progress
                MetricCard(title: "Category accuracy",
                           caption: "Predicted category confirmed against the statement.",
                           rate: metrics.categoryAccuracy,
                           barText: "Bar: 85%",
                           meetsBar: metrics.meetsCategoryBar,
                           denominator: metrics.confirmedCount == 0 ? nil
                               : "\(metrics.categoryCorrectCount) of \(metrics.confirmedCount) confirmed",
                           emptyLine: "No confirmations yet — reconcile a checkout to start measuring.")
                MetricCard(title: "Arithmetic correctness",
                           caption: "Posted rewards match the catalogue math the app used at the time.",
                           rate: metrics.arithmeticCorrectRate,
                           barText: "Bar: 100%",
                           meetsBar: metrics.meetsArithmeticBar,
                           denominator: metrics.arithmeticEligibleCount == 0 ? nil
                               : "\(metrics.arithmeticCorrectCount) of \(metrics.arithmeticEligibleCount) checkable",
                           emptyLine: eligibilityEmptyLine)
                missBreakdown
                valueRecovered
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Experiment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progress")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(metrics.progressToTarget) of \(metrics.targetCheckouts)")
                .font(.largeTitle.bold())
            ProgressView(value: Double(min(metrics.progressToTarget, metrics.targetCheckouts)),
                         total: Double(metrics.targetCheckouts))
            Text("confirmed checkouts")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    /// Why an arithmetic figure can be missing even with confirmations on the board — the
    /// eligibility rule drops rows it cannot honestly judge, and hiding that would make the
    /// dashboard look broken.
    private var eligibilityEmptyLine: String {
        metrics.confirmedCount == 0
            ? "No confirmations yet — reconcile a checkout to start measuring."
            : "Nothing checkable yet. A row counts only when the category was right, the amount was real, you tapped the card the app named, and the statement showed the rewards."
    }

    private var missBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Misses")
                .font(.title3.weight(.semibold))
            if metrics.missBreakdown.isEmpty {
                Text(metrics.confirmedCount == 0
                     ? "Nothing reconciled yet."
                     : "No misses recorded so far.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(MissClass.allCases, id: \.self) { miss in
                    if let count = metrics.missBreakdown[miss] {
                        HStack {
                            Text(missLabel(miss)).font(.subheadline)
                            Spacer()
                            Text("\(count)").font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private var valueRecovered: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Value recovered")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(String(format: "$%.2f", valueRecoveredCad))
                .font(.title2.bold())
            Text("Winner minus your default card, counted only on confirmed checkouts with a real amount.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func missLabel(_ miss: MissClass) -> String {
        switch miss {
        case .wrongCategory: return "Wrong category"
        case .capExceeded: return "Cap exceeded"
        case .staleRule: return "Catalogue rule wrong or stale"
        case .processorWeirdness: return "Processor weirdness"
        case .networkNotAccepted: return "Network not accepted"
        }
    }
}

/// One metric with its bar. A nil rate renders as an honest sentence, never as 0%.
private struct MetricCard: View {
    let title: String
    let caption: String
    let rate: Double?
    let barText: String
    let meetsBar: Bool?
    let denominator: String?
    let emptyLine: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                Text(barText).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(caption).font(.footnote).foregroundStyle(.secondary)

            if let rate {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.0f%%", rate * 100))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(meetsBar == true ? Color.green : Color.orange)
                    if let meetsBar {
                        Label(meetsBar ? "meets the bar" : "below the bar",
                              systemImage: meetsBar ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(meetsBar ? Color.green : Color.orange)
                    }
                }
                if let denominator {
                    Text(denominator).font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Text("Not enough evidence yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(emptyLine)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12))
    }
}
