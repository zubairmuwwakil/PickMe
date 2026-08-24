import SwiftUI

private let physicalCardAspectRatio: CGFloat = 85.60 / 53.98

// MARK: - Card photo loader
// Checks local bundled image in Assets.xcassets first,
// then falls back to https://inunity.ca/cards/{cardId}.png,
// and finally to the gradient design.

private struct CardPhotoView: View {
    let cardId: String
    let cornerRadius: CGFloat
    let fallback: AnyView

    private var remoteURL: URL? {
        URL(string: "https://inunity.ca/cards/\(cardId).png")
    }

    var body: some View {
        if let uiImage = UIImage(named: cardId) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else if let url = remoteURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                case .failure, .empty:
                    fallback
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }
}

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

    // MARK: Hero card — real photo overlaid on gradient, text floats above
    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            // Layer 1: gradient background (always present)
            gradientBackground

            // Layer 2: real card photo from Cloudflare R2 (fills the card)
            CardPhotoView(
                cardId: cardId,
                cornerRadius: 18,
                fallback: AnyView(Color.clear)   // transparent — gradient already showing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Layer 3: subtle bottom gradient scrim so text stays legible
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.clear],
                startPoint: .bottom,
                endPoint: .center
            )

            // Layer 4: card text overlay
            heroTextOverlay
                .padding(18)
        }
        .aspectRatio(physicalCardAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: style.gradientColors.first?.opacity(0.35) ?? Color.black.opacity(0.2), radius: 16, x: 0, y: 8)
    }

    private var heroTextOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let headline = rewardHeadline {
                        Text("TOP REWARD")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(style.accentColor)
                        Text(headline)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    } else {
                        Text(officialName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(style.issuer)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                }

                Spacer()

                if let returnText = effectiveReturnText {
                    Text(returnText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.22))
                        )
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var gradientBackground: some View {
        ZStack {
            LinearGradient(
                colors: style.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [Color.white.opacity(0.15), Color.clear, Color.black.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(style.isDark ? 0.22 : 0.4), lineWidth: 1)
        }
    }

    // MARK: Compact row card — real photo thumbnail, fallback to gradient pill
    private var compactCard: some View {
        HStack(spacing: 12) {
            CardPhotoView(
                cardId: cardId,
                cornerRadius: 6,
                fallback: AnyView(
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
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                )
            )
            .frame(width: 57, height: 38)
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
        CardPhotoView(
            cardId: cardId,
            cornerRadius: size * 0.22,
            fallback: AnyView(
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
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            )
        )
        .frame(width: size * 1.5, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
    }
}
