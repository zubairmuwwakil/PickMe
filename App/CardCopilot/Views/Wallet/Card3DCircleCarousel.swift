import SwiftUI
import CardCopilotEngine

/// 3D Radial Spoke Carousel matching the exact visual mockup.
///
/// Features:
/// - Overhead 3D perspective pitch looking onto a floating glowing circular ring arena
/// - Concentric glowing neon rings on the floor with central ambient glow
/// - Vertical portrait cards standing on edge along the circular orbit
/// - Front-most card stands flat facing forward with crisp gold/metallic rim and elevated scale
/// - High-fidelity authentic card art (Amex Gold with Greek key border and embossed numbers,
///   Visa Infinite, World Mastercard, Cyan Visa, Silver Mastercard)
/// - Smooth drag rotation with momentum and auto-snap physics
/// - Tap to select any card in the background
struct Card3DCircleCarousel: View {
    let cards: [CardProduct]
    @Binding var selectedCardId: String
    var onAddCard: (() -> Void)? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @State private var isDragging: Bool = false

    private let cardWidth: CGFloat = 138
    private let cardHeight: CGFloat = 218

    var body: some View {
        VStack(spacing: 8) {
            if cards.isEmpty {
                emptyCarouselView
            } else if cards.count == 1, let card = cards.first {
                singleCardView(card)
            } else {
                radialSpoke3DCircleView
            }

            // Indicator Dots
            if !cards.isEmpty && cards.count > 1 {
                indicatorBar
            }
        }
        .onAppear {
            syncSelectedCardRotation()
        }
        .onChange(of: selectedCardId) { _, newId in
            if !isDragging {
                animateToCard(id: newId)
            }
        }
        .onChange(of: cards.count) { _, _ in
            syncSelectedCardRotation()
        }
    }

    // MARK: - Radial Spoke 3D Carousel
    private var radialSpoke3DCircleView: some View {
        let count = cards.count
        let angleStep = 360.0 / Double(count)
        let radiusX: Double = 132.0
        let radiusY: Double = 60.0

        return ZStack {
            // Layer 1: Glowing Circular Floor Base & Concentric Light Rings
            floorGlowRings

            // Layer 2: 3D Radial Spoke Cards
            ForEach(Array(cards.enumerated()), id: \.element.cardId) { index, card in
                let baseAngle = Double(index) * angleStep
                let totalAngle = baseAngle + rotationAngle + Double(dragOffset * 0.45)
                let normalizedAngle = normalizeAngle(totalAngle)
                let radians = normalizedAngle * .pi / 180.0
                let isFrontCard = abs(normalizedAngle) < (angleStep / 2.0)

                // Position on 3D elliptical circle
                let xOffset = sin(radians) * radiusX
                let zDepthOffset = cos(radians) * radiusY - radiusY
                let yElevation = -cos(radians) * 14.0 + (zDepthOffset * 0.18)

                // Radial fin rotation: 0° at front (flat), turning into edge profile on sides (±75°)
                let rotY = normalizedAngle * 0.82

                // Perspective depth factors
                let depthFactor = (cos(radians) + 1.0) / 2.0 // 1.0 at front, 0.0 at back
                let scale = 0.75 + (0.28 * depthFactor)
                let opacity = 0.45 + (0.55 * depthFactor)

                portraitCardView(card: card, isFront: isFrontCard)
                    .frame(width: cardWidth, height: cardHeight)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .rotation3DEffect(
                        .degrees(rotY),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.45
                    )
                    .offset(x: CGFloat(xOffset), y: CGFloat(yElevation))
                    .zIndex(cos(radians) * 100)
                    .onTapGesture {
                        if !isFrontCard {
                            playHaptic()
                            animateToCard(id: card.cardId)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(card.officialName))
                    .accessibilityAddTraits(isFrontCard ? .isSelected : [])
            }
        }
        .frame(height: cardHeight + 48)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    isDragging = false
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    let totalDrag = value.translation.width + (velocity * 0.35)
                    let angleDelta = Double(totalDrag * 0.45)
                    let finalAngle = rotationAngle + angleDelta

                    // Snap to closest card
                    let nearestIndex = Int(round(-finalAngle / angleStep))
                    let normalizedIndex = ((nearestIndex % count) + count) % count
                    let targetRotation = -Double(nearestIndex) * angleStep

                    dragOffset = 0
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        rotationAngle = targetRotation
                    }

                    if normalizedIndex < cards.count {
                        let newSelectedId = cards[normalizedIndex].cardId
                        if selectedCardId != newSelectedId {
                            selectedCardId = newSelectedId
                            playHaptic()
                        }
                    }
                }
        )
    }

    // MARK: - Concentric Glowing Floor Rings Base (from Mockup)
    private var floorGlowRings: some View {
        ZStack {
            // Central floor spotlight bloom
            RadialGradient(
                colors: [
                    Color.white.opacity(0.85),
                    Color(red: 0.88, green: 0.94, blue: 1.0).opacity(0.45),
                    Color.cyan.opacity(0.12),
                    Color.clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 150
            )
            .frame(width: 320, height: 140)
            .offset(y: cardHeight * 0.38)
            .blur(radius: 12)

            // Outer subtle glowing ellipse track
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.7),
                            Color(red: 0.7, green: 0.85, blue: 1.0).opacity(0.4),
                            Color.white.opacity(0.15)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 295, height: 125)
                .offset(y: cardHeight * 0.38)
                .shadow(color: Color.cyan.opacity(0.35), radius: 8, x: 0, y: 0)

            // Inner bright neon glowing light ring
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 0.8, green: 0.95, blue: 1.0),
                            Color.cyan.opacity(0.6),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 2.2
                )
                .frame(width: 255, height: 105)
                .offset(y: cardHeight * 0.38)
                .shadow(color: Color.white.opacity(0.9), radius: 6, x: 0, y: 0)
                .shadow(color: Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.6), radius: 14, x: 0, y: 0)

            // Innermost subtle reflection track
            Ellipse()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .frame(width: 215, height: 85)
                .offset(y: cardHeight * 0.38)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Portrait Card View with Authentic Artwork
    private func portraitCardView(card: CardProduct, isFront: Bool) -> some View {
        let style = CardVisualTheme.style(for: card.cardId)
        let isAmexGold = card.cardId.contains("gold") || card.officialName.localizedCaseInsensitiveContains("gold")

        return ZStack {
            if isAmexGold {
                amexGoldCardContent
            } else if let uiImage = UIImage(named: card.cardId) {
                // Real Image Asset
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                // Procedural Luxury Card Layout
                proceduralCardContent(card: card, style: style)
            }

            // Glossy Glass Highlight Overlay
            LinearGradient(
                colors: [
                    Color.white.opacity(isFront ? 0.22 : 0.12),
                    Color.clear,
                    Color.black.opacity(isFront ? 0.25 : 0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isFront
                        ? LinearGradient(
                            colors: [Color(red: 1.0, green: 0.92, blue: 0.65), Color.white, Color.white.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                    lineWidth: isFront ? 1.5 : 0.6
                )
        )
        .shadow(
            color: isFront ? Color.black.opacity(0.30) : Color.black.opacity(0.16),
            radius: isFront ? 16 : 8,
            x: 0,
            y: isFront ? 10 : 4
        )
    }

    // MARK: - Authentic Amex Gold Card Content (Exact Match to Mockup)
    private var amexGoldCardContent: some View {
        ZStack {
            // Gold metallic brushed gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.91, green: 0.81, blue: 0.52),
                    Color(red: 0.83, green: 0.71, blue: 0.40),
                    Color(red: 0.92, green: 0.83, blue: 0.56),
                    Color(red: 0.76, green: 0.63, blue: 0.33)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Ornate Greek key border frame
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Color(red: 0.22, green: 0.18, blue: 0.08).opacity(0.75),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 2])
                )
                .padding(6)

            VStack(alignment: .leading, spacing: 0) {
                // Header: AMERICAN EXPRESS GOLD
                VStack(alignment: .leading, spacing: 1) {
                    Text("AMERICAN EXPRESS")
                        .font(.system(size: 8.5, weight: .heavy, design: .serif))
                        .tracking(0.6)
                        .foregroundStyle(Color(red: 0.18, green: 0.14, blue: 0.06))

                    Text("GOLD")
                        .font(.system(size: 6.5, weight: .bold, design: .serif))
                        .tracking(1.0)
                        .foregroundStyle(Color(red: 0.28, green: 0.22, blue: 0.08))
                }
                .padding(.top, 10)
                .padding(.horizontal, 12)

                HStack {
                    Spacer()
                    // Contactless icon + 7907
                    VStack(alignment: .trailing, spacing: 1) {
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.08))
                        Text("7907")
                            .font(.system(size: 6.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.08))
                    }
                    .padding(.trailing, 14)
                }

                // Center Centurion Medallion & EMV Chip
                HStack(spacing: 8) {
                    // Mini Gold Chip
                    ZStack {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.95, green: 0.88, blue: 0.65), Color(red: 0.78, green: 0.68, blue: 0.42)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 22, height: 17)

                        VStack(spacing: 2) {
                            Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.5)
                            Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.5)
                        }
                        .frame(width: 18)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                    )

                    Spacer()

                    // Centurion Head Graphic Badge
                    ZStack {
                        Circle()
                            .strokeBorder(Color(red: 0.25, green: 0.20, blue: 0.08).opacity(0.6), lineWidth: 1)
                            .frame(width: 44, height: 44)

                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.08).opacity(0.35))
                    }
                    .padding(.trailing, 8)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                Spacer()

                // Embossed Numbers: 3739 876543 31001
                VStack(alignment: .leading, spacing: 3) {
                    Text("3739  876543  31001")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.15, green: 0.12, blue: 0.05))
                        .shadow(color: Color.white.opacity(0.6), radius: 0.5, x: 0.5, y: 0.5)

                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("GOOD THRU")
                                .font(.system(size: 4.5, weight: .medium))
                                .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.08))
                            Text("10/26")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.15, green: 0.12, blue: 0.05))
                        }
                        .padding(.trailing, 14)
                    }

                    Text("CARDHOLDER NAME")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color(red: 0.15, green: 0.12, blue: 0.05))
                        .shadow(color: Color.white.opacity(0.6), radius: 0.5, x: 0.5, y: 0.5)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Procedural Card Layout
    private func proceduralCardContent(card: CardProduct, style: CardVisualTheme.CardStyle) -> some View {
        ZStack {
            LinearGradient(
                colors: style.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                // Top row: Issuer and Contactless / Chip
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.issuer.uppercased())
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(style.textColor.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(style.textColor.opacity(0.8))
                }

                // Mini Chip
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.9, green: 0.78, blue: 0.45), Color(red: 0.75, green: 0.62, blue: 0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 16)
                    .padding(.top, 8)

                Spacer()

                // Card Name
                Text(card.officialName)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(style.textColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Bottom: Network and Last 4
                HStack(alignment: .bottom) {
                    Text(style.network.rawValue)
                        .font(.system(size: 7.5, weight: .black, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(style.textColor.opacity(0.85))
                    Spacer()
                    Text("•••• \(lastFourDigits(for: card.cardId))")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(style.textColor.opacity(0.85))
                }
            }
            .padding(12)
        }
    }

    private func lastFourDigits(for cardId: String) -> String {
        if cardId.contains("amex") { return "31001" }
        if cardId.contains("momentum") || cardId.contains("red") { return "4004" }
        if cardId.contains("infinite") || cardId.contains("vip") { return "3003" }
        if cardId.contains("pc") || cardId.contains("tangerine") { return "2002" }
        return "1001"
    }

    // MARK: - Single Card View
    private func singleCardView(_ card: CardProduct) -> some View {
        ZStack {
            floorGlowRings

            portraitCardView(card: card, isFront: true)
                .frame(width: cardWidth, height: cardHeight)
                .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 10)
        }
        .frame(height: cardHeight + 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty Carousel View
    private var emptyCarouselView: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .frame(width: cardWidth, height: cardHeight)
                    .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 8) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No cards in wallet")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if let onAddCard {
                Button(action: onAddCard) {
                    Label("Add your first card", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .frame(height: cardHeight + 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Indicator Dots Bar
    private var indicatorBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(cards.enumerated()), id: \.element.cardId) { index, card in
                let isSelected = card.cardId == selectedCardId
                Circle()
                    .fill(isSelected ? Color.blue : Color.secondary.opacity(0.3))
                    .frame(width: isSelected ? 6 : 4.5, height: isSelected ? 6 : 4.5)
                    .animation(.spring(response: 0.3), value: isSelected)
                    .onTapGesture {
                        playHaptic()
                        animateToCard(id: card.cardId)
                    }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Helper Methods
    private func normalizeAngle(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 360.0)
        if a > 180.0 { a -= 360.0 }
        if a < -180.0 { a += 360.0 }
        return a
    }

    private func animateToCard(id: String) {
        guard let index = cards.firstIndex(where: { $0.cardId == id }) else { return }
        let count = cards.count
        guard count > 0 else { return }
        let angleStep = 360.0 / Double(count)

        let currentTargetIndex = Int(round(-rotationAngle / angleStep))
        var diff = (index - (currentTargetIndex % count + count) % count)
        if diff > count / 2 { diff -= count }
        if diff < -count / 2 { diff += count }

        let targetRotation = rotationAngle - Double(diff) * angleStep
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            rotationAngle = targetRotation
            selectedCardId = id
        }
    }

    private func syncSelectedCardRotation() {
        guard !cards.isEmpty else { return }
        if selectedCardId.isEmpty || !cards.contains(where: { $0.cardId == selectedCardId }) {
            selectedCardId = cards[0].cardId
        }
        guard let index = cards.firstIndex(where: { $0.cardId == selectedCardId }) else { return }
        let angleStep = 360.0 / Double(cards.count)
        rotationAngle = -Double(index) * angleStep
    }

    private func playHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
