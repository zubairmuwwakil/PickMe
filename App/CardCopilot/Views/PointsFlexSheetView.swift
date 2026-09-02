import SwiftUI

/// A sleek, shareable luxury Apple Wallet-style proof card showing total points value rescued by PickMe.
struct PointsFlexSheetView: View {
    let valueRecoveredCad: Double
    let onOpenDashboard: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var shareText: String {
        "I've saved $\(String(format: "%.2f", valueRecoveredCad)) CAD at Canadian checkouts using PickMe to automate 5x card multipliers! 💳🇨🇦 Never swipe 1x."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 22) {
                    Spacer(minLength: 8)

                    // The Premium Flex Card
                    VStack(spacing: 18) {
                        // Card Header
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.yellow)
                                Text("PICKME REWARDS PROOF")
                                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .tracking(1.2)
                            }

                            Spacer()

                            Text("🇨🇦 CANADA")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        // Big Value Hero
                        VStack(spacing: 6) {
                            Text("Total Value Rescued")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text(String(format: "+$%.2f", valueRecoveredCad))
                                .font(.system(size: 44, weight: .black, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.88, blue: 0.45),
                                            Color(red: 0.95, green: 0.65, blue: 0.20)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.orange.opacity(0.35), radius: 8, y: 3)

                            Text("above standard 1x base earn")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.green)
                        }
                        .padding(.vertical, 6)

                        Divider()
                            .overlay(Color.white.opacity(0.12))

                        // Mascot & Endorsement
                        HStack(spacing: 12) {
                            ChipMascotView(mood: .celebrating, size: 40, isWaving: true)
                                .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Co-Piloted by Chip")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text("Zero 1x multiplier traps. Maximum effort.")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .padding(22)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))

                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.orange.opacity(0.40),
                                            Color.yellow.opacity(0.20),
                                            Color.cyan.opacity(0.25)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        }
                        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
                    )
                    .padding(.horizontal, 20)

                    // Action Buttons
                    VStack(spacing: 12) {
                        ShareLink(
                            item: shareText,
                            subject: Text("My PickMe Rewards Savings"),
                            message: Text("Check out how much I've saved with PickMe:")
                        ) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Share Rewards Proof")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        Button {
                            dismiss()
                            onOpenDashboard()
                        } label: {
                            HStack(spacing: 6) {
                                Text("View Detailed Dashboard")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 12)
                }
            }
            .navigationTitle("Rewards Proof")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
