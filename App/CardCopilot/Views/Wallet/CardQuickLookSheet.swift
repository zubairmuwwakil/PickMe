import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// An Apple Pay-style modal inspection sheet giving users a comprehensive,
/// high-fidelity preview of a card's earn rates, annual fee, foreign transaction fee,
/// and perks before adding it to their wallet.
struct CardQuickLookSheet: View {
    let card: CardProduct
    let isOwned: Bool
    let onAdd: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasAdded = false

    private var style: CardVisualTheme.CardStyle {
        CardVisualTheme.style(for: card.cardId)
    }

    private var feeDisplay: String {
        let amount = card.fee.annual?.amount ?? 0
        let currency = card.billingCurrency.rawValue
        if amount == 0 {
            return String(localized: "No Annual Fee")
        }
        return "\(currency) \(Int(amount)) / year"
    }

    private var fxFeeDisplay: String {
        if let fxRule = card.fxRules.first {
            if fxRule.rate == 0 {
                return String(localized: "0% (No FX Fee)")
            } else {
                let pct = Int(fxRule.rate * 100)
                return "\(pct)% Foreign Exchange"
            }
        }
        return String(localized: "Standard (2.5%)")
    }

    private struct ParsedEarnTier: Identifiable {
        let id: String
        let icon: String
        let category: String
        let multiplier: String
        let isTopRate: Bool
        let capDescription: String?
    }

    private var earnTiers: [ParsedEarnTier] {
        var tiers: [ParsedEarnTier] = []
        var seenCategories = Set<String>()

        for rule in card.earnRules {
            let mult: String
            switch rule.earn {
            case .points(let pts):
                mult = pts == floor(pts) ? "\(Int(pts))x" : String(format: "%.1fx", pts)
            case .cashback(let rate, _):
                let pct = rate * 100
                mult = pct == floor(pct) ? "\(Int(pct))%" : String(format: "%.1f%%", pct)
            case .centsPerLitre:
                mult = "¢/L"
            }

            let categories = rule.predicate.categories ?? []
            let catName: String
            let icon: String

            if categories.isEmpty {
                if seenCategories.contains("Base") { continue }
                catName = String(localized: "All other purchases")
                icon = "bag.fill"
                seenCategories.insert("Base")
            } else {
                let raw = categories.joined(separator: ", ")
                if seenCategories.contains(raw) { continue }
                seenCategories.insert(raw)
                catName = raw.capitalized
                icon = categoryIcon(for: raw)
            }

            var capDesc: String? = nil
            if let capIds = rule.capIds, !capIds.isEmpty {
                if let cap = card.caps.first(where: { capIds.contains($0.capId) }) {
                    let limit = Int(cap.limit)
                    capDesc = "Up to \(card.billingCurrency.rawValue) \(limit)"
                }
            }

            tiers.append(ParsedEarnTier(
                id: rule.ruleId,
                icon: icon,
                category: catName,
                multiplier: mult,
                isTopRate: tiers.isEmpty,
                capDescription: capDesc
            ))
        }

        if tiers.isEmpty {
            tiers.append(ParsedEarnTier(
                id: "default-base",
                icon: "bag.fill",
                category: String(localized: "Base Purchases"),
                multiplier: "1x",
                isTopRate: true,
                capDescription: nil
            ))
        }

        return tiers
    }

    private func categoryIcon(for category: String) -> String {
        let lower = category.lowercased()
        if lower.contains("dining") || lower.contains("restaurant") || lower.contains("food") {
            return "fork.knife"
        } else if lower.contains("grocer") || lower.contains("supermarket") {
            return "cart.fill"
        } else if lower.contains("travel") || lower.contains("flight") || lower.contains("airline") {
            return "airplane"
        } else if lower.contains("gas") || lower.contains("fuel") || lower.contains("transit") {
            return "fuelpump.fill"
        } else if lower.contains("stream") || lower.contains("subscription") {
            return "play.tv.fill"
        } else if lower.contains("drug") || lower.contains("pharmacy") {
            return "cross.case.fill"
        } else if lower.contains("bill") || lower.contains("recurring") {
            return "arrow.triangle.2.circlepath"
        }
        return "star.fill"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: Hero Card Artwork
                    VStack(spacing: 14) {
                        CardArtView(cardId: card.cardId, officialName: card.officialName, isHero: true, cleanArtwork: true)
                            .frame(maxWidth: 320)
                            .shadow(color: style.gradientColors.first?.opacity(0.3) ?? Color.black.opacity(0.2), radius: 18, x: 0, y: 10)
                            .padding(.top, 8)

                        VStack(spacing: 4) {
                            Text(style.shortName)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)

                            Text("\(style.issuer) · \(style.network.rawValue)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)

                    // MARK: Key Stats Grid
                    HStack(spacing: 12) {
                        statPill(title: String(localized: "Annual Fee"), value: feeDisplay, icon: "tag.fill")
                        statPill(title: String(localized: "FX Fee"), value: fxFeeDisplay, icon: "globe")
                    }
                    .padding(.horizontal, 20)

                    // MARK: Reward Multipliers Breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Earn Rates & Multipliers")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 20)

                        VStack(spacing: 1) {
                            ForEach(earnTiers) { tier in
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(tier.isTopRate ? Color.blue.opacity(0.15) : Color(.tertiarySystemFill))
                                            .frame(width: 36, height: 36)

                                        Image(systemName: tier.icon)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(tier.isTopRate ? Color.blue : Color.secondary)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tier.category)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.primary)

                                        if let cap = tier.capDescription {
                                            Text(cap)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Text(tier.multiplier)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(tier.isTopRate ? Color.blue : Color.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(tier.isTopRate ? Color.blue.opacity(0.12) : Color(.tertiarySystemFill))
                                        )
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemGroupedBackground))

                                if tier.id != earnTiers.last?.id {
                                    Divider()
                                        .padding(.leading, 64)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 20)
                    }

                    // MARK: Card Program & Highlights
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Card Details")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 20)

                        VStack(spacing: 12) {
                            detailRow(label: String(localized: "Rewards Program"), value: card.program.programId.uppercased())
                            Divider()
                            detailRow(label: String(localized: "Billing Currency"), value: card.billingCurrency.rawValue)
                            Divider()
                            detailRow(label: String(localized: "Payment Network"), value: card.network.rawValue.uppercased())
                            Divider()
                            detailRow(label: String(localized: "Card Type"), value: card.kind.rawValue.capitalized)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDismiss()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // MARK: Bottom CTA Button
                VStack(spacing: 8) {
                    Divider()

                    if isOwned || hasAdded {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.green)
                            Text("In Your Wallet")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    } else {
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            hasAdded = true
                            onAdd()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                onDismiss()
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Add to Wallet")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }
                }
                .background(.ultraThinMaterial)
            }
        }
    }

    private func statPill(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}
