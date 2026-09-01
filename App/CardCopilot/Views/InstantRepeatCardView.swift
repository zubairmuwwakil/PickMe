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

enum InstantRepeatContext: Equatable {
    case nearby
    case recent

    var eyebrow: String {
        switch self {
        case .nearby: return "NEAR YOU"
        case .recent: return "RECENT PLACE"
        }
    }
}

/// A read-only recommendation for a remembered merchant.
///
/// This view deliberately exposes no checkout action. Looking at advice is not evidence that a
/// purchase happened; the Wallet tap remains the only event that belongs in Activity.
struct InstantRepeatCardView: View {
    let merchant: StoredMerchant
    let deps: DependencyGraph
    let context: InstantRepeatContext

    @State private var selectedAmount: Double = InstantRepeatAdvisor.comparisonAmountCad

    private var evaluation: InstantRepeatEvaluation? {
        InstantRepeatAdvisor.evaluate(
            merchant: merchant,
            amountCad: selectedAmount,
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

    private var cardDisplayName: String? {
        guard let eval = evaluation else { return nil }
        let short = CardVisualTheme.style(for: eval.winnerCardId).shortName
        return short.isEmpty ? eval.winnerCardName : short
    }

    private var confidenceLabel: String {
        merchant.confirmedCategory == nil ? "Best available pick" : "Confirmed here"
    }

    private var confidenceIcon: String {
        merchant.confirmedCategory == nil ? "sparkles" : "checkmark.seal.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                MerchantBrandIconView(
                    merchantName: merchant.name,
                    category: meta.displayName,
                    size: 38
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.eyebrow)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(context == .nearby ? Color.green : Color.secondary)

                    Text(merchant.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Label(confidenceLabel, systemImage: confidenceIcon)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(merchant.confirmedCategory == nil ? Color.secondary : Color.green)
                    .lineLimit(1)
            }

            Divider()

            if let eval = evaluation,
               let cardDisplayName {
                HStack(spacing: 14) {
                    CardArtView(
                        cardId: eval.winnerCardId,
                        officialName: eval.winnerCardName,
                        isHero: true,
                        cleanArtwork: true
                    )
                    .frame(width: 112)
                    .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("USE THIS CARD")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(cardDisplayName)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(eval.multiplierText)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.green)

                        if let networkBadge = eval.networkBadge {
                            Label(networkBadge, systemImage: "creditcard.trianglebadge.exclamationmark")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                // Amount What-If Preset Selector
                HStack(spacing: 6) {
                    Text("Amount:")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    ForEach([25.0, 50.0, 100.0, 250.0], id: \.self) { amt in
                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selectedAmount = amt
                            }
                        } label: {
                            Text("$\(Int(amt))")
                                .font(.system(size: 11, weight: selectedAmount == amt ? .bold : .medium, design: .rounded))
                                .foregroundStyle(selectedAmount == amt ? Color.blue : Color.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    selectedAmount == amt ? Color.blue.opacity(0.12) : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if let adv = eval.advantageText, eval.switchedFromDefault {
                        Text(adv)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.top, 2)
            } else {
                Label("Recommendation unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let evaluation,
              let cardDisplayName else {
            return "No recommendation available for \(merchant.name)"
        }
        return "At \(merchant.name), use \(cardDisplayName). \(evaluation.multiplierText). \(confidenceLabel)."
    }
}
