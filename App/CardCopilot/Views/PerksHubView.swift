import SwiftUI
import CardCopilotEngine

/// The Perks & Insurance hub: Big Purchase & Trip Protection Lens and Card Benefits Library.
struct PerksHubView: View {
    let deps: DependencyGraph?
    let onProtectionLens: (BenefitContextKind) -> Void
    let onBenefitsReference: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                // Hero Banner
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.headline)
                            .foregroundStyle(.indigo)
                        Text("PROTECTION & PERKS")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    }

                    Text("Insurance & Verified Benefits")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Compare certificate-backed coverage before booking flights, renting cars, or buying expensive electronics.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                )

                // Section: Protection Lens (Category Quick Launch)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trip & Purchase Lens")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    VStack(spacing: 10) {
                        protectionLensCard(
                            kind: .flight,
                            icon: "airplane",
                            iconColor: .indigo,
                            title: "Flight & Travel Delay",
                            subtitle: "Emergency medical, trip cancellation, delay & baggage protection"
                        )

                        protectionLensCard(
                            kind: .carRental,
                            icon: "car.fill",
                            iconColor: .blue,
                            title: "Rental Car CDW",
                            subtitle: "Collision damage waiver coverage terms and deductible rules"
                        )

                        protectionLensCard(
                            kind: .electronics,
                            icon: "laptopcomputer",
                            iconColor: .purple,
                            title: "Purchase Protection & Warranty",
                            subtitle: "90-day purchase security & extended manufacturer warranty"
                        )
                    }
                }

                // Section: Benefits Reference Library
                VStack(alignment: .leading, spacing: 12) {
                    Text("Full Benefits Library")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Button(action: onBenefitsReference) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.teal.opacity(0.14))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "books.vertical.fill")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(.teal)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Card Benefits Reference")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Text("Search all verified card certificates, lounge passes, and perks")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

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
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 90) // Inset for floating glass nav
        }
        .background(Color(.systemGroupedBackground))
    }

    private func protectionLensCard(
        kind: BenefitContextKind,
        icon: String,
        iconColor: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey
    ) -> some View {
        Button {
            onProtectionLens(kind)
        } label: {
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
        .buttonStyle(.plain)
    }
}
