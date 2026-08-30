import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// Branded circular logo / avatar for merchants.
public struct MerchantBrandIconView: View {
    let merchantName: String
    let category: String
    var size: CGFloat = 24

    private var brandConfig: (color: Color, icon: String, letter: String?) {
        let lower = merchantName.lowercased()
        if lower.contains("shoppers") {
            return (Color(red: 0.85, green: 0.15, blue: 0.18), "cross.fill", "S")
        } else if lower.contains("loblaw") || lower.contains("no frills") || lower.contains("superstore") || lower.contains("fortinos") {
            return (Color(red: 0.95, green: 0.42, blue: 0.08), "cart.fill", "L")
        } else if lower.contains("cineplex") {
            return (Color(red: 0.08, green: 0.32, blue: 0.72), "film.fill", "C")
        } else if lower.contains("starbucks") {
            return (Color(red: 0.00, green: 0.40, blue: 0.24), "cup.and.saucer.fill", nil)
        } else if lower.contains("costco") {
            return (Color(red: 0.88, green: 0.12, blue: 0.15), "bag.fill", "C")
        } else if lower.contains("tim hortons") || lower.contains("tims") {
            return (Color(red: 0.78, green: 0.12, blue: 0.16), "cup.and.saucer.fill", nil)
        } else if lower.contains("walmart") {
            return (Color(red: 0.00, green: 0.44, blue: 0.86), "sparkle", nil)
        } else if lower.contains("shell") {
            return (Color(red: 0.95, green: 0.75, blue: 0.08), "fuelpump.fill", nil)
        } else if lower.contains("esso") || lower.contains("mobil") {
            return (Color(red: 0.86, green: 0.14, blue: 0.14), "fuelpump.fill", nil)
        } else if lower.contains("amazon") {
            return (Color(red: 0.95, green: 0.60, blue: 0.05), "shippingbox.fill", nil)
        } else if lower.contains("apple") {
            return (Color.black, "apple.logo", nil)
        } else if lower.contains("lcbo") {
            return (Color(red: 0.45, green: 0.10, blue: 0.20), "wineglass.fill", nil)
        } else if lower.contains("canadian tire") {
            return (Color(red: 0.85, green: 0.15, blue: 0.15), "triangle.fill", nil)
        } else if lower.contains("metro") {
            return (Color(red: 0.88, green: 0.12, blue: 0.15), "cart.fill", "M")
        } else {
            let meta = CategoryVisuals.meta(for: category)
            return (meta.color, meta.icon, nil)
        }
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(brandConfig.color)
                .frame(width: size, height: size)

            if let letter = brandConfig.letter {
                Text(letter)
                    .font(.system(size: size * 0.52, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: brandConfig.icon)
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
        )
        .shadow(color: brandConfig.color.opacity(0.25), radius: 2, x: 0, y: 1)
    }
}

/// A Concept A Apple-grade Instant Repeat card featuring full physical card art,
/// merchant logo, live spend statistics, and dynamic return badges.
struct InstantRepeatCardView: View {
    @Environment(CopilotSession.self) private var session
    let merchant: StoredMerchant
    let deps: DependencyGraph
    let onSelect: (StoredMerchant) -> Void

    private var evaluation: InstantRepeatEvaluation? {
        InstantRepeatAdvisor.evaluate(
            merchant: merchant,
            amountCad: 50,
            catalogue: deps.catalogue,
            ownerState: deps.ownerState,
            engine: deps.engine
        )
    }

    private var meta: CategoryVisuals.Meta {
        if let eval = evaluation {
            return CategoryVisuals.meta(for: eval.category)
        }
        let prediction = predictionForKnownMerchant(merchant)
        return CategoryVisuals.meta(for: prediction.category)
    }

    private var cardDisplayName: String {
        guard let eval = evaluation else { return "Card" }
        let short = CardVisualTheme.style(for: eval.winnerCardId).shortName
        return short.isEmpty ? eval.winnerCardName : short
    }

    private var activityStats: (headline: String, caption: String) {
        if let recent = session.recentPurchases.first(where: { prediction in
            prediction.merchantName.localizedCaseInsensitiveContains(merchant.name) ||
            merchant.name.localizedCaseInsensitiveContains(prediction.merchantName)
        }), let amount = recent.purchase?.amountCad ?? recent.scoredAmountCad, amount > 0 {
            return (WalletHealthFormatting.cad(amount), "Last Spend")
        } else if merchant.confirmationCount > 0 {
            return ("\(merchant.confirmationCount)x", "Confirmed")
        } else {
            let relative = CategoryVisuals.relativeTime(from: merchant.lastSeenAt)
            return (relative, "Last Seen")
        }
    }

    private var returnBadgeInfo: (text: String, subtext: String, isCash: Bool) {
        guard let eval = evaluation else {
            return ("Top", "Card", true)
        }
        let mult = eval.multiplierText
        let isCash = mult.localizedCaseInsensitiveContains("cash")
        let isPoints = mult.localizedCaseInsensitiveContains("point") || mult.localizedCaseInsensitiveContains("pts")

        if isCash {
            let num = mult
                .replacingOccurrences(of: " Cash Back", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: " Cash", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            let formatted = num.hasPrefix("+") ? num : "+\(num)"
            return (formatted, "Cash Back", true)
        } else if isPoints {
            let num = mult
                .replacingOccurrences(of: " points", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: " pts", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            let formatted = num.hasPrefix("+") ? num : "+\(num)"
            return (formatted, "Points", false)
        } else {
            return (mult, "Reward", false)
        }
    }

    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onSelect(merchant)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // 1. Full Physical Credit Card Art (Aspect Ratio 85.60 / 53.98)
                if let eval = evaluation {
                    CardArtView(
                        cardId: eval.winnerCardId,
                        officialName: eval.winnerCardName,
                        isHero: true,
                        cleanArtwork: true
                    )
                    .frame(maxWidth: .infinity)
                    .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .aspectRatio(85.60 / 53.98, contentMode: .fit)
                }

                // 2. Merchant Brand Icon & Name
                HStack(spacing: 7) {
                    MerchantBrandIconView(
                        merchantName: merchant.name,
                        category: meta.displayName,
                        size: 22
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(merchant.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(meta.displayName)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                // 3. Bottom Row: Real Live Activity Stats & Dynamic Return Badge
                HStack(alignment: .bottom, spacing: 4) {
                    let stats = activityStats
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stats.headline)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(stats.caption)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 2)

                    // Dynamic Return Badge from Catalogue Rules
                    let badge = returnBadgeInfo
                    VStack(spacing: 0) {
                        Text(badge.text)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(badge.subtext)
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        badge.isCash
                            ? Color(red: 0.08, green: 0.48, blue: 0.98) // Apple Blue
                            : Color(red: 0.14, green: 0.72, blue: 0.38), // Apple Green
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .shadow(
                        color: (badge.isCash ? Color.blue : Color.green).opacity(0.25),
                        radius: 4,
                        x: 0,
                        y: 1.5
                    )
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainPressableGridButtonStyle())
    }
}

private struct PlainPressableGridButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}
