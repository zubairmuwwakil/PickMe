import SwiftUI

/// Emotional & operational states for Chip the EMV Micro-Bot.
enum ChipMood: Equatable {
    case idle
    case wink
    case calculating
    case celebrating
    case alert
}

/// A pure SwiftUI vector-rendered and animated mascot companion for PickMe.
/// Chip is a friendly micro-robot inspired by the golden EMV smart chip on credit cards,
/// featuring an expressive OLED matrix face, metallic brushed chassis, golden PCB circuit traces,
/// articulated robot limbs, and laser-engraved details.
struct ChipMascotView: View {
    var mood: ChipMood = .idle
    var size: CGFloat = 56
    var isWaving: Bool = true
    var onTap: (() -> Void)? = nil

    init(
        mood: ChipMood = .idle,
        size: CGFloat = 56,
        isWaving: Bool = true,
        onTap: (() -> Void)? = nil
    ) {
        self.mood = mood
        self.size = size
        self.isWaving = isWaving
        self.onTap = onTap
    }

    @State private var isBlinking = false
    @State private var isWinking = false
    @State private var isHovering = false
    @State private var isPressed = false
    @State private var waveAngle: Double = 0
    @State private var bodyTilt: Double = 0
    @State private var scanOffset: CGFloat = -1

    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
                isPressed = true
                bodyTilt = -5
                isWinking = true
                waveAngle = -22
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    isPressed = false
                    bodyTilt = 0
                    waveAngle = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                withAnimation { isWinking = false }
            }
            onTap?()
        } label: {
            ZStack(alignment: .bottom) {
                // Ground Ambient Shadow
                Ellipse()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: size * 0.95, height: size * 0.12)
                    .blur(radius: max(1.5, size * 0.04))
                    .offset(y: size * 0.06)

                // Whole Robot Assembly
                VStack(spacing: 0) {
                    ZStack {
                        // Left & Right Articulated Limbs
                        HStack(spacing: 0) {
                            // Left Arm (Thumbs up / friendly hand)
                            leftArm
                                .offset(x: -size * 0.04, y: size * 0.04)

                            Spacer()

                            // Right Arm (Waving hand)
                            rightArm
                                .offset(x: size * 0.04, y: -size * 0.02)
                        }
                        .frame(width: size * 1.52)

                        // Main Robot Torso / Chassis
                        chassisBody
                            .frame(width: size, height: size * 1.34)
                    }

                    // Legs & Shoes
                    legsAndShoes
                        .frame(width: size * 0.62, height: size * 0.24)
                        .offset(y: -size * 0.02)
                }
                .scaleEffect(isPressed ? 0.92 : (isHovering ? 1.02 : 1.0))
                .rotationEffect(.degrees(bodyTilt))
                .animation(
                    .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                    value: isHovering
                )

                if mood == .celebrating {
                    sparkleBadge
                        .offset(x: size * 0.42, y: -size * 1.30)
                }
            }
            .frame(width: size * 1.55, height: size * 1.62)
        }
        .buttonStyle(.plain)
        .onAppear {
            isHovering = true
            scheduleBlinking()
            if isWaving {
                startWaving()
            }
        }
    }

    // MARK: - 1. Robot Chassis & Triple-Deck Housing

    private var chassisBody: some View {
        ZStack {
            // Subtle ambient warm glow behind chassis
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.98, green: 0.82, blue: 0.40).opacity(0.35),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size * 0.15,
                        endRadius: size * 0.85
                    )
                )
                .frame(width: size * 1.18, height: size * 1.50)

            // Outer 3D Beveled Golden Rim
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.86, blue: 0.52),
                            Color(red: 0.82, green: 0.66, blue: 0.32),
                            Color(red: 0.64, green: 0.48, blue: 0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    Color(red: 1.0, green: 0.90, blue: 0.55),
                                    Color(red: 0.45, green: 0.32, blue: 0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1.6, size * 0.045)
                        )
                )
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)

            // Inner Platinum Bevel Plate
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.94, green: 0.93, blue: 0.91),
                            Color(red: 0.82, green: 0.81, blue: 0.79),
                            Color(red: 0.72, green: 0.71, blue: 0.69)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(size * 0.04)

            // Main Face Stacking (Screen + Circuit Belly + Engraved Chin)
            VStack(spacing: size * 0.035) {
                // Top: OLED Glass Screen
                oledScreenFace
                    .frame(width: size * 0.82, height: size * 0.46)

                // Middle: Golden PCB Circuit Inlay with EMV Contacts
                goldenCircuitBoardInlay
                    .frame(width: size * 0.82, height: size * 0.52)

                // Bottom: Brushed Platinum Chin with "CHIP" & Power LED
                engravedChin
                    .frame(width: size * 0.82, height: size * 0.16)
            }
            .padding(.vertical, size * 0.06)
        }
    }

    // MARK: - 2. OLED Matrix Screen

    private var oledScreenFace: some View {
        ZStack {
            // Glass screen background with deep OLED black
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.09, green: 0.10, blue: 0.13),
                            Color(red: 0.01, green: 0.01, blue: 0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.05),
                                    Color.black.opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

            // Subtle Glass Glint & Horizon Curvature
            LinearGradient(
                colors: [Color.white.opacity(0.18), Color.white.opacity(0.02), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))

            // LED Matrix Expression (Eyes + Smile)
            VStack(spacing: size * 0.025) {
                HStack(spacing: size * 0.18) {
                    eye(isLeft: true)
                    eye(isLeft: false)
                }

                if !isBlinking && (mood == .idle || mood == .celebrating) {
                    digitalSmile
                }
            }
        }
    }

    @ViewBuilder
    private func eye(isLeft: Bool) -> some View {
        let isWinkingEye = isLeft && isWinking

        if isBlinking || isWinkingEye {
            // Blink / wink slit
            Capsule()
                .fill(ledColor)
                .frame(width: size * 0.14, height: size * 0.038)
                .shadow(color: ledColor.opacity(0.9), radius: 3)
        } else if mood == .celebrating {
            // Star eyes
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.15, weight: .bold))
                .foregroundStyle(ledColor)
                .shadow(color: ledColor.opacity(0.9), radius: 3)
        } else if mood == .alert {
            // Alert mark
            Text("!")
                .font(.system(size: size * 0.17, weight: .black, design: .monospaced))
                .foregroundStyle(Color.orange)
                .shadow(color: Color.orange.opacity(0.9), radius: 3)
        } else {
            // Standard warm glowing dot-matrix eye (vertical capsule)
            Capsule()
                .fill(ledColor)
                .frame(width: size * 0.10, height: size * 0.16)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.4), lineWidth: 0.6)
                )
                .shadow(color: ledColor.opacity(0.95), radius: 4)
        }
    }

    private var digitalSmile: some View {
        Circle()
            .trim(from: 0.18, to: 0.82)
            .stroke(
                ledColor,
                style: StrokeStyle(lineWidth: max(1.4, size * 0.038), lineCap: .round)
            )
            .frame(width: size * 0.17, height: size * 0.11)
            .rotationEffect(.degrees(180))
            .shadow(color: ledColor.opacity(0.85), radius: 3)
    }

    private var ledColor: Color {
        switch mood {
        case .alert:
            return Color(red: 1.0, green: 0.62, blue: 0.15)
        case .celebrating:
            return Color(red: 1.0, green: 0.88, blue: 0.28)
        default:
            // Warm Champagne Amber LED (exact match to 3D mascot render)
            return Color(red: 1.0, green: 0.90, blue: 0.52)
        }
    }

    // MARK: - 3. Golden PCB Circuit Board Inlay & EMV Smart Pad

    private var goldenCircuitBoardInlay: some View {
        ZStack {
            // Brushed Satin Gold Base Plate
            RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.85, blue: 0.44),
                            Color(red: 0.88, green: 0.72, blue: 0.32),
                            Color(red: 0.78, green: 0.60, blue: 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                        .strokeBorder(Color(red: 0.65, green: 0.48, blue: 0.16), lineWidth: 0.8)
                )

            // Intricate PCB Trace Lines Flowing Outwards
            pcbTracesPath
                .stroke(Color(red: 0.58, green: 0.42, blue: 0.14), lineWidth: max(0.8, size * 0.016))

            // Solder Vias / Test Points
            pcbViaDots

            // Central EMV Smart Chip Contact Pad
            emvContactPad
                .frame(width: size * 0.44, height: size * 0.40)
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
    }

    private var pcbTracesPath: Path {
        Path { path in
            let w = size * 0.82
            let h = size * 0.52

            // Left Side Traces
            // Trace 1
            path.move(to: CGPoint(x: w * 0.26, y: h * 0.20))
            path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.20))
            path.addLine(to: CGPoint(x: w * 0.05, y: h * 0.28))
            path.addLine(to: CGPoint(x: w * 0.05, y: h * 0.75))

            // Trace 2
            path.move(to: CGPoint(x: w * 0.26, y: h * 0.38))
            path.addLine(to: CGPoint(x: w * 0.16, y: h * 0.38))
            path.addLine(to: CGPoint(x: w * 0.10, y: h * 0.45))
            path.addLine(to: CGPoint(x: w * 0.10, y: h * 0.82))

            // Trace 3
            path.move(to: CGPoint(x: w * 0.26, y: h * 0.58))
            path.addLine(to: CGPoint(x: w * 0.18, y: h * 0.58))
            path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.63))
            path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.88))

            // Trace 4
            path.move(to: CGPoint(x: w * 0.26, y: h * 0.78))
            path.addLine(to: CGPoint(x: w * 0.20, y: h * 0.78))
            path.addLine(to: CGPoint(x: w * 0.18, y: h * 0.84))
            path.addLine(to: CGPoint(x: w * 0.18, y: h * 0.94))

            // Right Side Traces
            // Trace 1
            path.move(to: CGPoint(x: w * 0.74, y: h * 0.20))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.20))
            path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.28))
            path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.75))

            // Trace 2
            path.move(to: CGPoint(x: w * 0.74, y: h * 0.38))
            path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.38))
            path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.45))
            path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.82))

            // Trace 3
            path.move(to: CGPoint(x: w * 0.74, y: h * 0.58))
            path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.58))
            path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.63))
            path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.88))

            // Trace 4
            path.move(to: CGPoint(x: w * 0.74, y: h * 0.78))
            path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.78))
            path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.84))
            path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.94))
        }
    }

    private var pcbViaDots: some View {
        ZStack {
            // 3 small left square test pads (as in reference image)
            VStack(spacing: size * 0.02) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color(red: 0.58, green: 0.42, blue: 0.14))
                    .frame(width: size * 0.025, height: size * 0.025)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color(red: 0.58, green: 0.42, blue: 0.14))
                    .frame(width: size * 0.025, height: size * 0.025)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color(red: 0.58, green: 0.42, blue: 0.14))
                    .frame(width: size * 0.025, height: size * 0.025)
            }
            .offset(x: -size * 0.35, y: -size * 0.02)

            // Small circular via points
            Circle()
                .strokeBorder(Color(red: 0.58, green: 0.42, blue: 0.14), lineWidth: 0.7)
                .frame(width: size * 0.035, height: size * 0.035)
                .offset(x: size * 0.32, y: -size * 0.18)

            Circle()
                .strokeBorder(Color(red: 0.58, green: 0.42, blue: 0.14), lineWidth: 0.7)
                .frame(width: size * 0.035, height: size * 0.035)
                .offset(x: -size * 0.28, y: size * 0.18)
        }
    }

    private var emvContactPad: some View {
        ZStack {
            // Gold Chip Plate
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.88, blue: 0.48),
                            Color(red: 0.90, green: 0.74, blue: 0.32)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                        .strokeBorder(Color(red: 0.55, green: 0.38, blue: 0.12), lineWidth: 0.9)
                )

            // EMV 8-Contact Grooved Grid
            VStack(spacing: size * 0.04) {
                // Horizontal divider top
                Rectangle()
                    .fill(Color(red: 0.52, green: 0.35, blue: 0.10))
                    .frame(height: 0.8)

                // Middle segment with loops
                HStack(spacing: size * 0.08) {
                    Rectangle()
                        .fill(Color(red: 0.52, green: 0.35, blue: 0.10))
                        .frame(width: 0.8, height: size * 0.16)

                    // Center keyhole loops
                    RoundedRectangle(cornerRadius: 1.5)
                        .strokeBorder(Color(red: 0.52, green: 0.35, blue: 0.10), lineWidth: 0.8)
                        .frame(width: size * 0.13, height: size * 0.16)

                    Rectangle()
                        .fill(Color(red: 0.52, green: 0.35, blue: 0.10))
                        .frame(width: 0.8, height: size * 0.16)
                }

                // Horizontal divider bottom
                Rectangle()
                    .fill(Color(red: 0.52, green: 0.35, blue: 0.10))
                    .frame(height: 0.8)
            }
            .frame(width: size * 0.36, height: size * 0.30)
        }
    }

    // MARK: - 4. Laser-Engraved Platinum Chin & Power LED

    private var engravedChin: some View {
        VStack(spacing: size * 0.015) {
            // "CHIP" Laser Engraved Typography
            Text("CHIP")
                .font(.system(size: max(8, size * 0.11), weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.46, green: 0.44, blue: 0.42),
                            Color(red: 0.30, green: 0.28, blue: 0.26)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.white.opacity(0.8), radius: 0, x: 0, y: 0.8)

            // Micro Power Indicator Slit
            Capsule()
                .fill(
                    mood == .alert
                        ? Color.orange
                        : Color(red: 0.98, green: 0.84, blue: 0.42)
                )
                .frame(width: size * 0.15, height: size * 0.024)
                .shadow(
                    color: (mood == .alert ? Color.orange : Color(red: 1.0, green: 0.85, blue: 0.45)).opacity(0.95),
                    radius: 2.5
                )
        }
    }

    // MARK: - 5. Articulated Robot Limbs (Arms & Hands)

    private var leftArm: some View {
        // Left Arm (Viewer's Left): Lowered thumbs up
        HStack(spacing: 0) {
            // Hand (Thumbs up fist)
            ZStack {
                // Main fist sphere
                Circle()
                    .fill(metallicGradient)
                    .frame(width: size * 0.14, height: size * 0.14)

                // Thumb pointing up
                Capsule()
                    .fill(metallicGradient)
                    .frame(width: size * 0.05, height: size * 0.10)
                    .offset(x: -size * 0.035, y: -size * 0.05)
                    .rotationEffect(.degrees(-15))
            }
            .shadow(color: Color.black.opacity(0.14), radius: 2, x: -1, y: 1)

            // Forearm cylinder
            Capsule()
                .fill(metallicGradient)
                .frame(width: size * 0.16, height: size * 0.07)
                .rotationEffect(.degrees(18))

            // Elbow hinge ball
            Circle()
                .fill(metallicJointGradient)
                .frame(width: size * 0.10, height: size * 0.10)

            // Upper arm cylinder
            Capsule()
                .fill(metallicGradient)
                .frame(width: size * 0.14, height: size * 0.075)
                .rotationEffect(.degrees(-25))

            // Shoulder ball socket
            Circle()
                .fill(metallicJointGradient)
                .frame(width: size * 0.12, height: size * 0.12)
        }
    }

    private var rightArm: some View {
        // Right Arm (Viewer's Right): Raised waving hand with 3 digits
        HStack(spacing: 0) {
            // Shoulder ball socket
            Circle()
                .fill(metallicJointGradient)
                .frame(width: size * 0.12, height: size * 0.12)

            // Upper arm cylinder
            Capsule()
                .fill(metallicGradient)
                .frame(width: size * 0.15, height: size * 0.075)
                .rotationEffect(.degrees(32))

            // Elbow hinge ball
            Circle()
                .fill(metallicJointGradient)
                .frame(width: size * 0.10, height: size * 0.10)

            // Forearm cylinder
            Capsule()
                .fill(metallicGradient)
                .frame(width: size * 0.16, height: size * 0.07)
                .rotationEffect(.degrees(-38))

            // Waving Hand (Open palm with 3 cute rounded robot fingers)
            ZStack {
                // Palm base sphere
                Circle()
                    .fill(metallicGradient)
                    .frame(width: size * 0.13, height: size * 0.13)

                // 3 Fingers
                HStack(spacing: size * 0.015) {
                    Capsule()
                        .fill(metallicGradient)
                        .frame(width: size * 0.038, height: size * 0.09)
                        .rotationEffect(.degrees(-20))

                    Capsule()
                        .fill(metallicGradient)
                        .frame(width: size * 0.040, height: size * 0.11)

                    Capsule()
                        .fill(metallicGradient)
                        .frame(width: size * 0.038, height: size * 0.09)
                        .rotationEffect(.degrees(20))
                }
                .offset(y: -size * 0.065)
            }
            .rotationEffect(.degrees(waveAngle))
            .shadow(color: Color.black.opacity(0.14), radius: 2, x: 1, y: 1)
        }
    }

    // MARK: - 6. Robot Legs & Brushed Pewter Shoes

    private var legsAndShoes: some View {
        HStack(spacing: size * 0.18) {
            singleLegAndShoe
            singleLegAndShoe
        }
    }

    private var singleLegAndShoe: some View {
        VStack(spacing: -size * 0.02) {
            // Thigh cylinder
            Capsule()
                .fill(metallicJointGradient)
                .frame(width: size * 0.14, height: size * 0.13)

            // Curved 3D Robot Shoe / Foot
            ZStack(alignment: .top) {
                // Main rounded foot
                RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.90, green: 0.86, blue: 0.80),
                                Color(red: 0.72, green: 0.68, blue: 0.62),
                                Color(red: 0.52, green: 0.48, blue: 0.42)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.22, height: size * 0.13)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.6)
                    )

                // Specular toe shine
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: size * 0.12, height: size * 0.03)
                    .offset(y: size * 0.015)
            }
            .shadow(color: Color.black.opacity(0.20), radius: 2.5, x: 0, y: 1.5)
        }
    }

    // MARK: - Gradients & Shading Helpers

    private var metallicGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.94, green: 0.92, blue: 0.88),
                Color(red: 0.76, green: 0.74, blue: 0.70),
                Color(red: 0.58, green: 0.56, blue: 0.52)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var metallicJointGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.82, green: 0.80, blue: 0.76),
                Color(red: 0.60, green: 0.58, blue: 0.54),
                Color(red: 0.42, green: 0.40, blue: 0.38)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var sparkleBadge: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.35, weight: .bold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.yellow, Color.orange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: Color.yellow.opacity(0.8), radius: 4)
    }

    // MARK: - Animation Loops

    private func startWaving() {
        withAnimation(
            .easeInOut(duration: 0.9)
            .repeatForever(autoreverses: true)
        ) {
            waveAngle = 14
        }
    }

    private func scheduleBlinking() {
        let delay = Double.random(in: 2.8...4.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeInOut(duration: 0.10)) {
                isBlinking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeInOut(duration: 0.10)) {
                    isBlinking = false
                }
                scheduleBlinking()
            }
        }
    }
}

// MARK: - Interactive Chip Companion Header Card

/// An Apple Intelligence-inspired interactive card pairing Chip with rotating smart tips and insights.
struct ChipCompanionHeaderCard: View {
    let statusText: String
    let subtitle: String
    var onSearchTap: (() -> Void)? = nil

    @State private var tipIndex: Int = 0
    @State private var isBubblePresented: Bool = false

    private let chipWisdom: [String] = [
        "Chip's Rule: Amex Cobalt earns 5x points on dining & groceries up to $2,500/month!",
        "Chip's Alert: Costco Canada only accepts Mastercard at the warehouse register!",
        "Chip's Tip: Loblaws & No Frills don't take Amex—tap your PC Financial or Visa.",
        "Chip's Security: Flights and electronics come with built-in warranty on select premium cards.",
        "Chip's Math: Log your exact spend to calibrate your machine-learning accuracy model."
    ]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ChipMascotView(mood: isBubblePresented ? .wink : .idle, size: 44) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isBubblePresented.toggle()
                        if isBubblePresented {
                            tipIndex = (tipIndex + 1) % chipWisdom.count
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(statusText)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                    }

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isBubblePresented.toggle()
                        if isBubblePresented {
                            tipIndex = (tipIndex + 1) % chipWisdom.count
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isBubblePresented ? "xmark.circle.fill" : "lightbulb.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isBubblePresented ? Color.secondary : Color.orange)
                        Text(isBubblePresented ? "Hide" : "Chip's Tip")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(isBubblePresented ? Color.secondary : Color.orange)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        isBubblePresented
                            ? Color(.tertiarySystemFill)
                            : Color.orange.opacity(0.12),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            // Interactive Speech Bubble
            if isBubblePresented {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.orange.opacity(0.8))

                    Text(chipWisdom[tipIndex])
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineSpacing(2)

                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                        )
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95, anchor: .topLeading).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }
}
