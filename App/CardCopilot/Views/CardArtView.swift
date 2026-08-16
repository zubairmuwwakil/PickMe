import SwiftUI

/// A sleek, physical credit card representation for visual recognition at checkout.
struct CardArtView: View {
    let cardId: String
    let officialName: String
    var rewardHeadline: String? = nil
    var effectiveReturnText: String? = nil
    var isHero: Bool = true

    private var style: CardVisualTheme.CardStyle {
        CardVisualTheme.style(for: cardId)
    }

    var body: some View {
        if isHero {
            heroCard
        } else {
            compactCard
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Bar: Issuer & Contactless Wave
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.issuer.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(style.textColor.opacity(0.8))
                    Text(officialName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(style.textColor)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "wave.3.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(style.textColor.opacity(0.7))
            }

            Spacer(minLength: 16)

            // Center: EMV Chip Graphic
            HStack(spacing: 8) {
                emvChipView
                Spacer()
                if let returnText = effectiveReturnText {
                    Text(returnText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(style.isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.12))
                        )
                        .foregroundStyle(style.textColor)
                }
            }

            Spacer(minLength: 16)

            // Bottom Bar: Reward Headline & Network
            HStack(alignment: .bottom) {
                if let headline = rewardHeadline {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TOP REWARD")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(style.accentColor)
                        Text(headline)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(style.textColor)
                            .lineLimit(1)
                    }
                } else {
                    Text("••••  ••••  ••••  ••••")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(style.textColor.opacity(0.5))
                }

                Spacer()

                Text(style.network.rawValue)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(style.textColor.opacity(0.15))
                    )
                    .foregroundStyle(style.textColor.opacity(0.9))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(
            ZStack {
                LinearGradient(
                    colors: style.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Subtle card lighting overlay
                LinearGradient(
                    colors: [Color.white.opacity(0.15), Color.clear, Color.black.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(style.isDark ? 0.22 : 0.4), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: style.gradientColors.first?.opacity(0.35) ?? Color.black.opacity(0.2), radius: 16, x: 0, y: 8)
    }

    private var compactCard: some View {
        HStack(spacing: 12) {
            ZStack {
                LinearGradient(
                    colors: style.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(style.textColor.opacity(0.9))
            }
            .frame(width: 38, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(officialName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(style.issuer) · \(style.network.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let returnText = effectiveReturnText {
                Text(returnText)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.secondarySystemFill), in: Capsule())
                    .foregroundStyle(.primary)
            }
        }
    }

    private var emvChipView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.9, green: 0.78, blue: 0.45), Color(red: 0.75, green: 0.62, blue: 0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 24)

            // Chip contact lines
            VStack(spacing: 3) {
                Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1)
                HStack(spacing: 6) {
                    Rectangle().fill(Color.black.opacity(0.25)).frame(width: 1)
                    Rectangle().fill(Color.black.opacity(0.25)).frame(width: 1)
                }
                Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1)
            }
            .frame(width: 28, height: 18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
        )
    }
}

/// Miniature card pill / icon used in lists and comparison rows.
struct CardMiniBadge: View {
    let cardId: String
    var size: CGFloat = 24

    private var style: CardVisualTheme.CardStyle {
        CardVisualTheme.style(for: cardId)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: style.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "creditcard.fill")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(style.textColor.opacity(0.9))
        }
        .frame(width: size * 1.5, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
    }
}
