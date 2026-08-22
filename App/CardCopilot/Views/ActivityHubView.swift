import SwiftUI
import CardCopilotStore

/// The Activity hub: Pending queues (Finish Purchases, Reconcile Statements) & Experiment Scoreboard.
struct ActivityHubView: View {
    let finishCount: Int
    let reconcileCount: Int
    let metrics: ExperimentMetrics?
    let valueRecoveredCad: Double
    let pendingValueCad: Double
    let onFinish: () -> Void
    let onReconcile: () -> Void
    let onOpenDashboard: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section: Action Queues
                VStack(alignment: .leading, spacing: 12) {
                    Text("Action Queues")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    VStack(spacing: 10) {
                        // Finish Purchases
                        Button(action: onFinish) {
                            queueActionRow(
                                icon: "square.and.pencil",
                                iconColor: finishCount > 0 ? .blue : .green,
                                title: finishCount == 0 ? "Finish Purchases" : "\(finishCount) to Finish",
                                subtitle: finishCount == 0 ? "All purchases have card & cost recorded" : "Add the card tapped and charge amount",
                                count: finishCount,
                                badgeColor: Color.blue
                            )
                        }
                        .buttonStyle(.plain)

                        // Reconcile Statements
                        Button(action: onReconcile) {
                            queueActionRow(
                                icon: "tray.full.fill",
                                iconColor: reconcileCount > 0 ? .orange : .green,
                                title: reconcileCount == 0 ? "Reconcile Queue" : "\(reconcileCount) Waiting to Reconcile",
                                subtitle: reconcileCount == 0 ? "All predictions confirmed against statements" : "Match posted issuer rewards to predictions",
                                count: reconcileCount,
                                badgeColor: Color(red: 0.13, green: 0.77, blue: 0.37)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Section: Experiment Validation & Scoreboard
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Experiment Scoreboard")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button(action: onOpenDashboard) {
                            Text("Full Breakdown")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.blue)
                        }
                    }

                    if let metrics {
                        experimentOverviewCard(metrics: metrics)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 90) // Inset for floating glass nav
        }
        .background(Color(.systemGroupedBackground))
    }

    private func queueActionRow(
        icon: String,
        iconColor: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        count: Int,
        badgeColor: Color
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(badgeColor, in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
    }

    private func experimentOverviewCard(metrics: ExperimentMetrics) -> some View {
        VStack(spacing: 16) {
            progressHeader(metrics: metrics)
            ProgressView(value: Double(min(metrics.progressToTarget, metrics.targetCheckouts)), total: Double(metrics.targetCheckouts))
                .tint(.blue)
            Divider()
            metricsGrid(metrics: metrics)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
    }

    private func progressHeader(metrics: ExperimentMetrics) -> some View {
        let progress = Double(min(metrics.progressToTarget, metrics.targetCheckouts))
        let target = Double(metrics.targetCheckouts)
        let percent = Int((progress / target) * 100)

        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("VALIDATION PROGRESS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(metrics.progressToTarget)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("/ \(metrics.targetCheckouts) checkouts")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 5)
                    .frame(width: 48, height: 48)
                Circle()
                    .trim(from: 0, to: CGFloat(min(progress / target, 1.0)))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))
                Text("\(percent)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
    }

    private func metricsGrid(metrics: ExperimentMetrics) -> some View {
        HStack(spacing: 12) {
            metricMiniTile(
                title: "Category Accuracy",
                rate: metrics.categoryAccuracy,
                target: "85%",
                isMet: metrics.meetsCategoryBar == true
            )
            metricMiniTile(
                title: "Math Correctness",
                rate: metrics.arithmeticCorrectRate,
                target: "100%",
                isMet: metrics.meetsArithmeticBar == true
            )
        }
    }

    private func metricMiniTile(
        title: LocalizedStringKey,
        rate: Double?,
        target: String,
        isMet: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if isMet {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if let rate {
                Text("\(Int(round(rate * 100)))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(isMet ? .green : .primary)
            } else {
                Text("—")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text("Target: \(target)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
