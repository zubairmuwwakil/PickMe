import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The Wallet hub: Visual cards in wallet, Wallet Health, Which Card matrix, and Valuation Sandbox.
struct WalletHubView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(CheckoutRouter.self) private var router

    @State private var selectedCardIndex: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Section: Visual Wallet Cards
                if let cards = environment.graph?.walletCards, !cards.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Your Cards")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("\(cards.count) active")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(.tertiarySystemFill), in: Capsule())

                            Button { router.push(.walletSetup) } label: {
                                Text("Edit")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.blue)
                            }
                        }

                        // Horizontal Cards Carousel
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(cards, id: \.cardId) { card in
                                    VStack(alignment: .leading, spacing: 8) {
                                        CardArtView(cardId: card.cardId, officialName: card.officialName, isHero: true)
                                            .frame(width: 240)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(card.officialName)
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)

                                            HStack(spacing: 4) {
                                                Text(card.network.rawValue.capitalized)
                                                Text("•")
                                                // A single card's own fee, shown in its own billing
                                                // currency — not a cross-card sum, so this is never
                                                // converted to the CAD reporting currency (see
                                                // ReportingCurrency.swift).
                                                let fee = card.fee.annual?.amount ?? 0
                                                Text(fee == 0 ? "No Fee" : String(format: "$%.0f/yr", fee))
                                            }
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 240, alignment: .leading)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Section: Card Copilot Tools
                VStack(alignment: .leading, spacing: 10) {
                    Text("Decision Tools")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    VStack(spacing: 8) {
                        // Which Card?
                        Button { router.push(.categoryPicker) } label: {
                            toolCard(
                                icon: "square.grid.2x2.fill",
                                iconColor: .teal,
                                title: "Which Card?",
                                subtitle: "Select any category to see which card in your wallet earns highest",
                                badge: "Lookup",
                                badgeColor: .teal
                            )
                        }
                        .buttonStyle(.plain)

                        // Wallet Health
                        Button { router.push(.walletHealth) } label: {
                            toolCard(
                                icon: "heart.text.square.fill",
                                iconColor: .mint,
                                title: "Wallet Health",
                                subtitle: "Marginal value audit: what to keep, cancel, or optimize",
                                badge: "Estimate",
                                badgeColor: .mint
                            )
                        }
                        .buttonStyle(.plain)

                        // Valuation Sandbox
                        Button { router.push(.valuationSandbox) } label: {
                            toolCard(
                                icon: "slider.horizontal.3",
                                iconColor: .purple,
                                title: "Valuation Sandbox",
                                subtitle: "Adjust redemption value per point for MR, Aeroplan, Scene+ & Avion",
                                badge: "Live",
                                badgeColor: .purple
                            )
                        }
                        .buttonStyle(.plain)

                        // Edit Wallet Setup
                        Button { router.push(.walletSetup) } label: {
                            toolCard(
                                icon: "creditcard.and.123",
                                iconColor: .blue,
                                title: "Manage Wallet Cards",
                                subtitle: "Add new cards, change default checkout card, or configure spend caps",
                                badge: nil,
                                badgeColor: .blue
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 90) // Inset for floating glass nav
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    private func toolCard(
        icon: String,
        iconColor: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        badge: String?,
        badgeColor: Color
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor, in: Capsule())
                    }
                }

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
        )
    }
}
