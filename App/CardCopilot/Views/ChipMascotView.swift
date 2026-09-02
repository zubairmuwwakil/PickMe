import SwiftUI
import CardCopilotEngine

/// Emotional & operational states for Chip the EMV Micro-Bot.
enum ChipMood: Equatable {
    case idle
    case wink
    case calculating
    case celebrating
    case alert
    case knock      // Reaching right up to the iPhone screen glass & tapping on it
    case cool       // Deadpool sunglasses / smug expression
    case shocked    // Wide OLED eyes & jaw drop
    case sleepy     // Half-shuttered LEDs for the small hours
    case dizzy      // Counter-rotating dual spirals & squiggly mouth after device shake
    case denied     // Crossed 'X' eye, squinting wedge, and robot facepalm arm
    case charging   // Lightning bolt eyes & segmented battery chin bar
}

/// Where Chip is looking when nothing has grabbed him.
///
/// Directed attention is what separates a character from a screensaver: random glancing reads as
/// idle animation, but looking *at the thing the owner is touching* reads as awareness.
enum ChipGaze: Equatable {
    /// Free to glance around on his own schedule.
    case wandering
    /// Something below him has focus — the search field. Chip looks down at it and stops roaming.
    case down
}

/// A pure SwiftUI vector-rendered and animated mascot companion for PickMe.
/// Chip is a friendly, 4th-wall breaking micro-robot inspired by the golden EMV smart chip on credit cards,
/// featuring an expressive OLED matrix face, metallic brushed chassis, golden PCB circuit traces,
/// articulated robot limbs, 3D parallax depth, and glass-knocking screen-breaking physics.
struct ChipMascotView: View {
    var mood: ChipMood = .idle
    var size: CGFloat = 56
    var isWaving: Bool = true
    var enable3DTilt: Bool = true
    var gaze: ChipGaze = .wandering
    var isOverclocked: Bool = false
    var onTap: (() -> Void)? = nil
    var onLongPress: (() -> Void)? = nil

    init(
        mood: ChipMood = .idle,
        size: CGFloat = 56,
        isWaving: Bool = true,
        enable3DTilt: Bool = true,
        gaze: ChipGaze = .wandering,
        isOverclocked: Bool = false,
        onTap: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil
    ) {
        self.mood = mood
        self.size = size
        self.isWaving = isWaving
        self.enable3DTilt = enable3DTilt
        self.gaze = gaze
        self.isOverclocked = isOverclocked
        self.onTap = onTap
        self.onLongPress = onLongPress
    }

    @State private var isBlinking = false
    @State private var isWinking = false
    @State private var isHovering = false
    @State private var isPressed = false
    @State private var waveAngle: Double = 0
    @State private var bodyTilt: Double = 0
    @State private var pitchTilt: Double = 0
    @State private var yawTilt: Double = 0
    @State private var scanOffset: CGFloat = -1
    @State private var isKnockingGlass = false
    @State private var spiralRotationAngle: Double = 0
    @State private var glassRipples: [GlassRipple] = []
    @State private var eyeGlanceOffset: CGFloat = 0
    @State private var idleFloatOffset: CGFloat = 0
    @State private var idleBreathingScale: CGFloat = 1.0
    @State private var idleTiltNudge: Double = 0
    @State private var idleHopOffset: CGFloat = 0
    @State private var lastInteractionAt: Date = .distantPast

    /// Generation counter for the self-rescheduling idle timers (blink, glance, fidget).
    ///
    /// Those timers reschedule themselves through `asyncAfter`, so without a token they outlive
    /// the view and a second `onAppear` starts a *second* chain on top of the first. This is a
    /// plain reference type rather than `@State` of a value so the escaping closures can read
    /// the live generation without touching SwiftUI storage after the view is gone.
    ///
    /// **Note for whoever grows this.** Chip now runs three hand-rolled `asyncAfter` chains per
    /// instance. The token stops them leaking, but it does not make this a scheduler: every
    /// mascot on screen wakes the main thread on its own irregular cadence. That is fine at the
    /// one or two instances this app puts on a screen today. If Chip ever goes into a list — a
    /// mascot per row, recycled on scroll — replace all three with `TimelineView` or
    /// `.phaseAnimator`, which let SwiftUI own the cadence and stop it with the view. Do not
    /// scale this pattern up; it is a small deliberate shortcut, not the design.
    private final class IdleCycleToken {
        var generation = 0
    }
    @State private var idleCycle = IdleCycleToken()
    @State private var didLongPress = false
    @State private var calculatingScanOffset: CGFloat = -1
    @State private var eyeLookDownOffset: CGFloat = 0

    /// Chip's whole body hovers, breathes, tilts in 3D and waves on permanent loops. That is a
    /// lot of unrequested motion for someone who asked the system for less of it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct GlassRipple: Identifiable {
        let id = UUID()
        var scale: CGFloat = 0.2
        var opacity: Double = 0.9
    }

    var body: some View {
        ZStack(alignment: .center) {
            // Glass Shockwave Ripples (appearing right on the "phone screen")
            ForEach(glassRipples) { ripple in
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.cyan.opacity(0.8),
                                Color.white.opacity(0.9),
                                Color.orange.opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(1.5, size * 0.04)
                    )
                    .frame(width: size * 1.6, height: size * 1.6)
                    .scaleEffect(ripple.scale)
                    .opacity(ripple.opacity)
                    .offset(x: size * 0.22, y: -size * 0.15)
            }

            ZStack(alignment: .bottom) {
                // Ground Ambient Depth Shadow (Casts onto card/surface behind)
                Ellipse()
                    .fill(Color.black.opacity(0.22))
                    .frame(width: size * 1.15, height: size * 0.16)
                    .blur(radius: max(2.5, size * 0.06))
                    .offset(y: size * 0.12)

                // Whole Robot Assembly with 3D Pop-Out
                VStack(spacing: 0) {
                    ZStack {
                        // Left & Right Articulated Limbs
                        HStack(spacing: 0) {
                            // Left Arm (Thumbs up / friendly hand)
                            leftArm
                                .offset(x: -size * 0.04, y: size * 0.04)

                            Spacer()

                            // Right Arm (Waving or Screen-Knocking hand)
                            rightArm
                                .offset(x: size * 0.04, y: -size * 0.02)
                        }
                        .frame(width: size * 1.56)

                        // Main Robot Torso / Chassis
                        chassisBody
                            .frame(width: size, height: size * 1.34)
                    }

                    // Legs & Shoes
                    legsAndShoes
                        .frame(width: size * 0.62, height: size * 0.24)
                        .offset(y: -size * 0.02)
                }
                .scaleEffect(isPressed ? 1.18 : (isHovering ? (1.04 * idleBreathingScale) : idleBreathingScale))
                .offset(y: idleFloatOffset + idleHopOffset)
                .rotationEffect(.degrees(bodyTilt + idleTiltNudge))
                .rotation3DEffect(
                    .degrees(pitchTilt),
                    axis: (x: 1.0, y: 0.0, z: 0.0),
                    perspective: 0.4
                )
                .rotation3DEffect(
                    .degrees(yawTilt),
                    axis: (x: 0.0, y: 1.0, z: 0.0),
                    perspective: 0.4
                )
                .shadow(
                    color: Color.black.opacity(isPressed ? 0.35 : 0.18),
                    radius: isPressed ? 14 : 7,
                    x: 0,
                    y: isPressed ? 8 : 4
                )

                if mood == .celebrating {
                    sparkleBadge
                        .offset(x: size * 0.42, y: -size * 1.30)
                }
            }
            .frame(width: size * 1.62, height: size * 1.68)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // A long press fires at its minimumDuration but the tap only lands on release, so
            // without this a founder-protocol hold would also register as a poke and the poke's
            // reaction would overwrite the protocol Chip just unlocked.
            guard !didLongPress else {
                didLongPress = false
                return
            }
            triggerGlassKnockInteraction()
            onTap?()
        }
        .onLongPressGesture(minimumDuration: 2.0) {
            didLongPress = true
            lastInteractionAt = Date()
            onLongPress?()
        }
        .onAppear {
            idleCycle.generation += 1
            let generation = idleCycle.generation

            // Chip's face stays alive either way: blinking and glancing move a few points of
            // LED, not the whole robot, so neither is what Reduce Motion is asking about.
            scheduleBlinking(generation: generation)
            scheduleGlancing(generation: generation)
            if mood == .calculating || isOverclocked { startCalculatingScan() }
            guard !reduceMotion else { return }

            isHovering = true
            scheduleIdleBehaviour(generation: generation)
            startIdleFloatAndBreathe()
            if isWaving {
                startWaving()
            }
            if enable3DTilt {
                startSubtle3DParallax()
            }
        }
        .onDisappear {
            // Retires every in-flight blink/glance chain so they stop waking the main thread.
            idleCycle.generation += 1
        }
        .onChange(of: mood) { _, newMood in
            if newMood == .calculating { startCalculatingScan() }
            if newMood == .dizzy {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    spiralRotationAngle = 360
                }
            } else {
                spiralRotationAngle = 0
            }
        }
        .onChange(of: isOverclocked) { _, overclocked in
            if overclocked { startCalculatingScan() }
        }
        .onChange(of: gaze) { _, newGaze in
            withAnimation(.spring(response: 0.30, dampingFraction: 0.7)) {
                eyeLookDownOffset = newGaze == .down ? size * 0.035 : 0
                if newGaze == .down { eyeGlanceOffset = 0 }
            }
        }
    }

    private func triggerGlassKnockInteraction() {
        lastInteractionAt = Date()
        let impact = UIImpactFeedbackGenerator(style: .rigid)
        impact.impactOccurred(intensity: 1.0)

        // Rapid double knock feel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            impact.impactOccurred(intensity: 0.85)
        }

        withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
            isPressed = true
            isKnockingGlass = true
            bodyTilt = -4
            pitchTilt = -12 // Leans forward toward user
            yawTilt = 6
            waveAngle = -35
        }

        // Spawn glass ripples
        let newRipple = GlassRipple()
        glassRipples.append(newRipple)
        let rippleIndex = glassRipples.count - 1
        withAnimation(.easeOut(duration: 0.55)) {
            if rippleIndex < glassRipples.count {
                glassRipples[rippleIndex].scale = 1.85
                glassRipples[rippleIndex].opacity = 0.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) {
                isPressed = false
                bodyTilt = 0
                pitchTilt = 0
                yawTilt = 0
                waveAngle = 0
                isKnockingGlass = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            glassRipples.removeAll()
        }
    }

    private func startSubtle3DParallax() {
        pitchTilt = 0
        yawTilt = 0
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                pitchTilt = 4.0
                yawTilt = -3.5
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
                            Color(red: 0.98, green: 0.82, blue: 0.40).opacity(0.42),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size * 0.15,
                        endRadius: size * 0.85
                    )
                )
                .frame(width: size * 1.22, height: size * 1.54)

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
                                colors: isOverclocked ? [
                                    Color.cyan,
                                    Color.white,
                                    Color.cyan.opacity(0.8)
                                ] : [
                                    Color.white.opacity(0.98),
                                    Color(red: 1.0, green: 0.90, blue: 0.55),
                                    Color(red: 0.45, green: 0.32, blue: 0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: max(1.8, size * 0.05)
                        )
                )
                .shadow(color: isOverclocked ? Color.cyan.opacity(0.85) : Color.black.opacity(0.24), radius: isOverclocked ? 12 : 8, x: 0, y: 4)

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
                                    Color.white.opacity(0.40),
                                    Color.white.opacity(0.08),
                                    Color.black.opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

            // Glass Glint & 4th-Wall Horizon Curvature
            LinearGradient(
                colors: [Color.white.opacity(0.24), Color.white.opacity(0.04), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))

            // LED Matrix Expression (Eyes + Smile / Deadpool Sunglasses / Shocked Eyes / Dizzy Spirals / Denied Facepalm / Charging Bolts)
            if mood == .cool {
                deadpoolCoolFace
            } else if mood == .shocked {
                shockedFace
            } else if mood == .dizzy {
                dizzyFace
            } else if mood == .denied {
                deniedFace
            } else if mood == .charging {
                chargingFace
            } else {
                standardFace
            }
        }
    }

    private var standardFace: some View {
        VStack(spacing: size * 0.025) {
            HStack(spacing: size * 0.18) {
                eye(isLeft: true)
                eye(isLeft: false)
            }

            if !isBlinking && (mood == .idle || mood == .celebrating || mood == .knock) {
                digitalSmile
            }
        }
    }

    private var deadpoolCoolFace: some View {
        ZStack {
            // Futuristic Gold / Neon Sunglasses
            HStack(spacing: size * 0.04) {
                // Left lens
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.28, height: size * 0.14)
                    .rotationEffect(.degrees(-6))
                    .shadow(color: Color.orange.opacity(0.8), radius: 3)

                // Bridge
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: size * 0.06, height: size * 0.03)

                // Right lens
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.28, height: size * 0.14)
                    .rotationEffect(.degrees(6))
                    .shadow(color: Color.orange.opacity(0.8), radius: 3)
            }
            .offset(y: -size * 0.03)

            // Confident Smirk
            Circle()
                .trim(from: 0.25, to: 0.75)
                .stroke(
                    ledColor,
                    style: StrokeStyle(lineWidth: max(1.4, size * 0.038), lineCap: .round)
                )
                .frame(width: size * 0.16, height: size * 0.10)
                .rotationEffect(.degrees(160))
                .offset(x: size * 0.04, y: size * 0.11)
        }
    }

    private var shockedFace: some View {
        VStack(spacing: size * 0.03) {
            // Wide Round Eyes
            HStack(spacing: size * 0.16) {
                Circle()
                    .strokeBorder(ledColor, lineWidth: max(1.6, size * 0.04))
                    .background(Circle().fill(Color.black))
                    .frame(width: size * 0.16, height: size * 0.16)
                    .shadow(color: ledColor.opacity(0.9), radius: 3)

                Circle()
                    .strokeBorder(ledColor, lineWidth: max(1.6, size * 0.04))
                    .background(Circle().fill(Color.black))
                    .frame(width: size * 0.16, height: size * 0.16)
                    .shadow(color: ledColor.opacity(0.9), radius: 3)
            }

            // O-shaped Jaw Drop Mouth
            Capsule()
                .stroke(ledColor, lineWidth: max(1.4, size * 0.038))
                .frame(width: size * 0.10, height: size * 0.10)
                .shadow(color: ledColor.opacity(0.85), radius: 2)
        }
    }

    private var dizzyFace: some View {
        VStack(spacing: size * 0.02) {
            HStack(spacing: size * 0.16) {
                spiralEye(isClockwise: true)
                spiralEye(isClockwise: false)
            }

            squigglyMouth
        }
    }

    private func spiralEye(isClockwise: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color(red: 0.35, green: 1.0, blue: 0.85).opacity(0.35), lineWidth: 1.0)
                .frame(width: size * 0.18, height: size * 0.18)

            // Outer spiral arc
            Circle()
                .trim(from: 0.1, to: 0.85)
                .stroke(
                    Color(red: 0.35, green: 1.0, blue: 0.85),
                    style: StrokeStyle(lineWidth: max(1.4, size * 0.035), lineCap: .round)
                )
                .frame(width: size * 0.16, height: size * 0.16)

            // Inner spiral arc
            Circle()
                .trim(from: 0.2, to: 0.95)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: max(1.2, size * 0.028), lineCap: .round)
                )
                .frame(width: size * 0.09, height: size * 0.09)
        }
        .rotationEffect(.degrees(isClockwise ? spiralRotationAngle : -spiralRotationAngle))
        .shadow(color: Color(red: 0.35, green: 1.0, blue: 0.85).opacity(0.9), radius: 4)
    }

    private var squigglyMouth: some View {
        Path { path in
            let w = size * 0.18
            let h = size * 0.04
            path.move(to: CGPoint(x: 0, y: h * 0.5))
            path.addCurve(
                to: CGPoint(x: w * 0.5, y: h * 0.5),
                control1: CGPoint(x: w * 0.2, y: 0),
                control2: CGPoint(x: w * 0.35, y: h)
            )
            path.addCurve(
                to: CGPoint(x: w, y: h * 0.5),
                control1: CGPoint(x: w * 0.65, y: 0),
                control2: CGPoint(x: w * 0.8, y: h)
            )
        }
        .stroke(Color(red: 0.35, green: 1.0, blue: 0.85), style: StrokeStyle(lineWidth: max(1.4, size * 0.035), lineCap: .round))
        .frame(width: size * 0.18, height: size * 0.04)
        .shadow(color: Color(red: 0.35, green: 1.0, blue: 0.85).opacity(0.85), radius: 3)
    }

    private var deniedFace: some View {
        VStack(spacing: size * 0.025) {
            HStack(spacing: size * 0.18) {
                // Left Eye: Crossed "X" LED
                ZStack {
                    Capsule()
                        .fill(Color(red: 1.0, green: 0.30, blue: 0.25))
                        .frame(width: size * 0.14, height: size * 0.038)
                        .rotationEffect(.degrees(45))
                    Capsule()
                        .fill(Color(red: 1.0, green: 0.30, blue: 0.25))
                        .frame(width: size * 0.14, height: size * 0.038)
                        .rotationEffect(.degrees(-45))
                }
                .shadow(color: Color.red.opacity(0.9), radius: 3)

                // Right Eye: Strained squinting wedge ">"
                Path { path in
                    let w = size * 0.10
                    let h = size * 0.14
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: w, y: h * 0.5))
                    path.addLine(to: CGPoint(x: 0, y: h))
                }
                .stroke(
                    Color(red: 1.0, green: 0.55, blue: 0.20),
                    style: StrokeStyle(lineWidth: max(1.6, size * 0.04), lineCap: .round, lineJoin: .round)
                )
                .frame(width: size * 0.10, height: size * 0.14)
                .shadow(color: Color.orange.opacity(0.9), radius: 3)
            }

            // Tense horizontal dashed mouth line
            HStack(spacing: size * 0.02) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(Color(red: 1.0, green: 0.40, blue: 0.25))
                        .frame(width: size * 0.035, height: size * 0.025)
                }
            }
            .shadow(color: Color.red.opacity(0.7), radius: 2)
        }
    }

    private var chargingFace: some View {
        VStack(spacing: size * 0.025) {
            HStack(spacing: size * 0.16) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.yellow, Color.white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.yellow.opacity(0.95), radius: 6)

                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.yellow, Color.white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.yellow.opacity(0.95), radius: 6)
            }

            // Energetic charged smirk
            Circle()
                .trim(from: 0.22, to: 0.78)
                .stroke(
                    Color.yellow,
                    style: StrokeStyle(lineWidth: max(1.4, size * 0.038), lineCap: .round)
                )
                .frame(width: size * 0.16, height: size * 0.10)
                .rotationEffect(.degrees(180))
                .shadow(color: Color.yellow.opacity(0.9), radius: 4)
        }
    }

    @ViewBuilder
    private func eye(isLeft: Bool) -> some View {
        let isWinkingEye = isLeft && (isWinking || mood == .wink)

        Group {
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
            } else if mood == .sleepy {
                // Half-shuttered: the lid is a bar across the top of a full-height eye, which
                // reads as drowsy where a simply shorter capsule just reads as a smaller eye.
                Capsule()
                    .fill(ledColor)
                    .frame(width: size * 0.10, height: size * 0.16)
                    .mask(
                        Rectangle()
                            .frame(width: size * 0.14, height: size * 0.07)
                            .offset(y: size * 0.045)
                    )
                    .shadow(color: ledColor.opacity(0.7), radius: 3)
                    .offset(x: gaze == .down ? 0 : eyeGlanceOffset)
            } else if mood == .calculating {
                // Processing: a narrow scanning bar sweeping across the socket, so "thinking"
                // reads as machine work rather than another facial expression.
                ZStack {
                    Capsule()
                        .fill(ledColor.opacity(0.22))
                        .frame(width: size * 0.15, height: size * 0.15)

                    Capsule()
                        .fill(ledColor)
                        .frame(width: size * 0.05, height: size * 0.13)
                        .offset(x: calculatingScanOffset * size * 0.05)
                        .shadow(color: ledColor.opacity(0.95), radius: 3)
                }
            } else if mood == .knock {
                // Focused, direct-eye-contact capsule eyes looking through the screen
                Capsule()
                    .fill(Color.cyan)
                    .frame(width: size * 0.12, height: size * 0.18)
                    .overlay(
                        Capsule()
                            .stroke(Color.white, lineWidth: 0.8)
                    )
                    .shadow(color: Color.cyan.opacity(0.95), radius: 5)
            } else {
                // Standard warm glowing dot-matrix eye (vertical capsule) with dynamic glancing
                Capsule()
                    .fill(ledColor)
                    .frame(width: size * 0.10, height: size * 0.16)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.4), lineWidth: 0.6)
                    )
                    .shadow(color: ledColor.opacity(0.95), radius: 4)
                    .offset(x: gaze == .down ? 0 : eyeGlanceOffset, y: eyeLookDownOffset)
            }
        }
    }

    private var digitalSmile: some View {
        Circle()
            .trim(from: 0.18, to: 0.82)
            .stroke(
                mood == .knock ? Color.cyan : ledColor,
                style: StrokeStyle(lineWidth: max(1.4, size * 0.038), lineCap: .round)
            )
            .frame(width: size * 0.17, height: size * 0.11)
            .rotationEffect(.degrees(180))
            .shadow(color: (mood == .knock ? Color.cyan : ledColor).opacity(0.85), radius: 3)
    }

    private var ledColor: Color {
        switch mood {
        case .alert:
            return Color(red: 1.0, green: 0.62, blue: 0.15)
        case .celebrating:
            return Color(red: 1.0, green: 0.88, blue: 0.28)
        case .knock:
            return Color(red: 0.35, green: 0.85, blue: 1.0)
        case .calculating:
            return Color(red: 0.62, green: 0.88, blue: 1.0)
        case .sleepy:
            return Color(red: 0.86, green: 0.78, blue: 0.58)
        case .dizzy:
            return Color(red: 0.35, green: 1.0, blue: 0.85)
        case .denied:
            return Color(red: 1.0, green: 0.32, blue: 0.28)
        case .charging:
            return Color(red: 1.0, green: 0.92, blue: 0.25)
        default:
            // Warm Champagne Amber LED
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
                        colors: isOverclocked ? [
                            Color(red: 0.92, green: 0.97, blue: 1.0),
                            Color(red: 0.72, green: 0.88, blue: 0.98),
                            Color(red: 0.45, green: 0.78, blue: 0.92)
                        ] : [
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
                        .strokeBorder(
                            isOverclocked
                                ? Color.cyan
                                : Color(red: 0.65, green: 0.48, blue: 0.16),
                            lineWidth: isOverclocked ? 1.2 : 0.8
                        )
                        .shadow(color: isOverclocked ? Color.cyan.opacity(0.85) : .clear, radius: 4)
                )

            // Intricate PCB Trace Lines Flowing Outwards — illuminates with cyan electricity when overclocked
            pcbTracesPath
                .stroke(
                    isOverclocked
                        ? Color.cyan
                        : Color(red: 0.58, green: 0.42, blue: 0.14),
                    lineWidth: max(isOverclocked ? 1.4 : 0.8, size * (isOverclocked ? 0.024 : 0.016))
                )
                .shadow(color: isOverclocked ? Color.cyan.opacity(0.95) : .clear, radius: max(2, size * 0.06))
                .shadow(color: isOverclocked ? Color.cyan : .clear, radius: max(4, size * 0.10))

            // Solder Vias / Test Points
            pcbViaDots
                .overlay(
                    isOverclocked
                        ? pcbViaDots.colorMultiply(Color.cyan).shadow(color: Color.cyan, radius: 2)
                        : nil
                )

            // Central EMV Smart Chip Contact Pad
            emvContactPad
                .frame(width: size * 0.44, height: size * 0.40)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                        .strokeBorder(isOverclocked ? Color.cyan.opacity(0.9) : .clear, lineWidth: 1.2)
                        .shadow(color: isOverclocked ? Color.cyan : .clear, radius: 4)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
    }

    private var pcbTracesPath: Path {
        Path { path in
            let w = size * 0.82
            let h = size * 0.52

            // Left Side Traces
            path.move(to: CGPoint(x: w * 0.26, y: h * 0.20))
            path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.20))
            path.addLine(to: CGPoint(x: w * 0.05, y: h * 0.28))
            path.addLine(to: CGPoint(x: w * 0.05, y: h * 0.75))

            path.move(to: CGPoint(x: w * 0.26, y: h * 0.38))
            path.addLine(to: CGPoint(x: w * 0.16, y: h * 0.38))
            path.addLine(to: CGPoint(x: w * 0.10, y: h * 0.45))
            path.addLine(to: CGPoint(x: w * 0.10, y: h * 0.82))

            path.move(to: CGPoint(x: w * 0.26, y: h * 0.58))
            path.addLine(to: CGPoint(x: w * 0.18, y: h * 0.58))
            path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.63))
            path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.88))

            path.move(to: CGPoint(x: w * 0.26, y: h * 0.78))
            path.addLine(to: CGPoint(x: w * 0.20, y: h * 0.78))
            path.addLine(to: CGPoint(x: w * 0.18, y: h * 0.84))
            path.addLine(to: CGPoint(x: w * 0.18, y: h * 0.94))

            // Right Side Traces
            path.move(to: CGPoint(x: w * 0.74, y: h * 0.20))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.20))
            path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.28))
            path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.75))

            path.move(to: CGPoint(x: w * 0.74, y: h * 0.38))
            path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.38))
            path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.45))
            path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.82))

            path.move(to: CGPoint(x: w * 0.74, y: h * 0.58))
            path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.58))
            path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.63))
            path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.88))

            path.move(to: CGPoint(x: w * 0.74, y: h * 0.78))
            path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.78))
            path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.84))
            path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.94))
        }
    }

    private var pcbViaDots: some View {
        ZStack {
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
                Rectangle()
                    .fill(Color(red: 0.52, green: 0.35, blue: 0.10))
                    .frame(height: 0.8)

                HStack(spacing: size * 0.08) {
                    Rectangle()
                        .fill(Color(red: 0.52, green: 0.35, blue: 0.10))
                        .frame(width: 0.8, height: size * 0.16)

                    RoundedRectangle(cornerRadius: 1.5)
                        .strokeBorder(Color(red: 0.52, green: 0.35, blue: 0.10), lineWidth: 0.8)
                        .frame(width: size * 0.13, height: size * 0.16)

                    Rectangle()
                        .fill(Color(red: 0.52, green: 0.35, blue: 0.10))
                        .frame(width: 0.8, height: size * 0.16)
                }

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

            if mood == .charging {
                HStack(spacing: size * 0.015) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.yellow)
                            .frame(width: size * 0.035, height: size * 0.024)
                            .shadow(color: Color.yellow.opacity(0.95), radius: 2)
                    }
                }
            } else {
                Capsule()
                    .fill(
                        mood == .alert
                            ? Color.orange
                            : (mood == .knock || mood == .dizzy ? Color.cyan : (mood == .denied ? Color.red : Color(red: 0.98, green: 0.84, blue: 0.42)))
                    )
                    .frame(width: size * 0.15, height: size * 0.024)
                    .shadow(
                        color: (mood == .alert ? Color.orange : (mood == .knock || mood == .dizzy ? Color.cyan : (mood == .denied ? Color.red : Color(red: 1.0, green: 0.85, blue: 0.45)))).opacity(0.95),
                        radius: 2.5
                    )
            }
        }
    }

    // MARK: - 5. Articulated Robot Limbs (Arms & Hands)

    private var leftArm: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(metallicGradient)
                    .frame(width: size * 0.14, height: size * 0.14)

                Capsule()
                    .fill(metallicGradient)
                    .frame(width: size * 0.05, height: size * 0.10)
                    .offset(x: -size * 0.035, y: -size * 0.05)
                    .rotationEffect(.degrees(-15))
            }
            .shadow(color: Color.black.opacity(0.14), radius: 2, x: -1, y: 1)

            Capsule()
                .fill(metallicGradient)
                .frame(width: size * 0.16, height: size * 0.07)
                .rotationEffect(.degrees(18))

            Circle()
                .fill(metallicJointGradient)
                .frame(width: size * 0.10, height: size * 0.10)

            Capsule()
                .fill(metallicGradient)
                .frame(width: size * 0.14, height: size * 0.075)
                .rotationEffect(.degrees(-25))

            Circle()
                .fill(metallicJointGradient)
                .frame(width: size * 0.12, height: size * 0.12)
        }
    }

    private var rightArm: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(metallicJointGradient)
                .frame(width: size * 0.12, height: size * 0.12)

            Capsule()
                .fill(metallicGradient)
                .frame(width: size * 0.15, height: size * 0.075)
                .rotationEffect(.degrees(isKnockingGlass ? 15 : 32))

            Circle()
                .fill(metallicJointGradient)
                .frame(width: size * 0.10, height: size * 0.10)

            Capsule()
                .fill(metallicGradient)
                .frame(width: size * 0.16, height: size * 0.07)
                .rotationEffect(.degrees(isKnockingGlass ? -15 : -38))

            // Waving Hand, Screen Knocking Fist, or Facepalm
            if mood == .denied {
                // Facepalm Hand placed over right golden forehead bevel
                ZStack {
                    Circle()
                        .fill(metallicGradient)
                        .frame(width: size * 0.16, height: size * 0.16)
                    Capsule()
                        .fill(metallicGradient)
                        .frame(width: size * 0.05, height: size * 0.12)
                        .rotationEffect(.degrees(-35))
                }
                .offset(x: -size * 0.08, y: -size * 0.22)
            } else if isKnockingGlass || mood == .knock {
                ZStack {
                    // Knocking Fist pressed close to viewer's screen glass
                    Circle()
                        .fill(metallicGradient)
                        .frame(width: size * 0.18, height: size * 0.18)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.8), lineWidth: 1.0)
                        )
                        .shadow(color: Color.cyan.opacity(0.7), radius: 6)

                    // 4 Knuckles
                    HStack(spacing: size * 0.015) {
                        ForEach(0..<4) { _ in
                            Circle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: size * 0.03, height: size * 0.03)
                        }
                    }
                }
                .scaleEffect(1.28)
                .rotationEffect(.degrees(waveAngle))
                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 2, y: 2)
            } else {
                ZStack {
                    Circle()
                        .fill(metallicGradient)
                        .frame(width: size * 0.13, height: size * 0.13)

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
            Capsule()
                .fill(metallicJointGradient)
                .frame(width: size * 0.14, height: size * 0.13)

            ZStack(alignment: .top) {
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

    private func startCalculatingScan() {
        calculatingScanOffset = -1
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                calculatingScanOffset = 1
            }
        }
    }

    private func startWaving() {
        waveAngle = 0
        DispatchQueue.main.async {
            withAnimation(
                .easeInOut(duration: 0.9)
                .repeatForever(autoreverses: true)
            ) {
                waveAngle = 14
            }
        }
    }

    private func scheduleBlinking(generation: Int) {
        let delay = Double.random(in: 2.8...4.8)
        let token = idleCycle
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard token.generation == generation else { return }
            withAnimation(.easeInOut(duration: 0.10)) {
                isBlinking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard token.generation == generation else { return }
                withAnimation(.easeInOut(duration: 0.10)) {
                    isBlinking = false
                }
                scheduleBlinking(generation: generation)
            }
        }
    }

    private func startIdleFloatAndBreathe() {
        // A `repeatForever` animation only attaches to an actual value *change*. On a second
        // onAppear — a NavigationStack pop, say — these already hold their animated values, so
        // withAnimation would find nothing to animate and Chip would hang frozen mid-hover.
        // Snap back to rest first, then start the loop on the next runloop turn.
        idleFloatOffset = 0
        idleBreathingScale = 1.0
        DispatchQueue.main.async {
            withAnimation(
                .easeInOut(duration: 2.4)
                .repeatForever(autoreverses: true)
            ) {
                idleFloatOffset = -2.5
                idleBreathingScale = 1.025
            }
        }
    }

    /// One-off micro-behaviours Chip performs between the permanent idle loops.
    ///
    /// The float, breathe, wave and parallax loops run forever and never vary, which reads as a
    /// screensaver rather than a character. These fire irregularly on top of them — through their
    /// own offsets so they compose with the loops instead of fighting them for the same property.
    private enum IdleBehaviour: CaseIterable {
        case tiltLeft
        case tiltRight
        case hop
        case doubleBlink
        case stretch
    }

    /// How often each behaviour comes up, relative to the others.
    ///
    /// Uniform random over the table reads as twitchy — a hop is a whole-body event and should
    /// not be as likely as a blink. Weighting is the difference between "alive" and "restless".
    private var idleBehaviourWeights: [(IdleBehaviour, Int)] {
        [
            (.doubleBlink, 8),
            (.tiltLeft, 5),
            (.tiltRight, 5),
            (.stretch, isWaving ? 3 : 0),
            (.hop, 2)
        ]
    }

    private func scheduleIdleBehaviour(generation: Int) {
        let delay = Double.random(in: 6.0...11.0)
        let token = idleCycle
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard token.generation == generation else { return }

            // Chip does not fidget over the top of a real interaction: a poke or a knock already
            // gave him something to do, and a stray hop mid-reaction reads as a glitch.
            guard Date().timeIntervalSince(lastInteractionAt) > 3.0 else {
                scheduleIdleBehaviour(generation: generation)
                return
            }

            perform(weightedIdleBehaviour(), generation: generation)
            scheduleIdleBehaviour(generation: generation)
        }
    }

    private func weightedIdleBehaviour() -> IdleBehaviour {
        let table = idleBehaviourWeights.filter { $0.1 > 0 }
        let total = table.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return .doubleBlink }
        var roll = Int.random(in: 0..<total)
        for (behaviour, weight) in table {
            if roll < weight { return behaviour }
            roll -= weight
        }
        return .doubleBlink
    }

    private func perform(_ behaviour: IdleBehaviour, generation: Int) {
        let token = idleCycle
        func settle(after seconds: Double, _ body: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                guard token.generation == generation else { return }
                body()
            }
        }

        switch behaviour {
        case .tiltLeft, .tiltRight:
            let angle: Double = behaviour == .tiltLeft ? -6 : 6
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                idleTiltNudge = angle
            }
            settle(after: 1.1) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                    idleTiltNudge = 0
                }
            }

        case .hop:
            withAnimation(.spring(response: 0.26, dampingFraction: 0.45)) {
                idleHopOffset = -7
            }
            settle(after: 0.28) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.55)) {
                    idleHopOffset = 0
                }
            }

        case .doubleBlink:
            withAnimation(.easeInOut(duration: 0.08)) { isBlinking = true }
            settle(after: 0.10) {
                withAnimation(.easeInOut(duration: 0.08)) { isBlinking = false }
                settle(after: 0.12) {
                    withAnimation(.easeInOut(duration: 0.08)) { isBlinking = true }
                    settle(after: 0.22) {
                        withAnimation(.easeInOut(duration: 0.08)) { isBlinking = false }
                    }
                }
            }

        case .stretch:
            // Reaches the waving arm out further than its loop ever does, then hands the arm
            // back to that loop.
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                waveAngle = 34
            }
            settle(after: 0.85) {
                startWaving()
            }
        }
    }

    private func scheduleGlancing(generation: Int) {
        let delay = Double.random(in: 2.8...5.5)
        let token = idleCycle
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard token.generation == generation else { return }
            // A directed gaze outranks idle roaming: Chip is already looking at something.
            guard gaze == .wandering else {
                scheduleGlancing(generation: generation)
                return
            }
            let options: [CGFloat] = [-1.8, 0.0, 1.8, 0.0]
            let chosen = options.randomElement() ?? 0.0
            withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) {
                eyeGlanceOffset = chosen
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard token.generation == generation else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.70)) {
                    eyeGlanceOffset = 0.0
                }
                scheduleGlancing(generation: generation)
            }
        }
    }
}

// MARK: - Interactive Chip Companion Header Card (4th-Wall Breaking)

/// Something Chip can say, and optionally something the owner can do about it.
struct ChipBanterItem {
    let text: String
    let mood: ChipMood
    let tag: String
    /// Rendered as an extra button in the bubble's action row. Present only on quips that lead
    /// somewhere — an advisory the owner can act on, rather than a joke.
    var action: ChipBanterAction? = nil
}

struct ChipBanterAction {
    let label: String
    let systemImage: String
    let perform: () -> Void
}

/// Formats typed Engine insights into Chip's 4th-wall breaking personality
enum ChipInsightFormatter {
    static func format(_ insight: ChipInsight) -> ChipBanterItem {
        switch insight {
        case .allCardsNegative:
            return ChipBanterItem(
                text: "Whoa, stop! Every single card in your wallet loses money on this after FX fees. Use debit or local cash!",
                mood: .alert,
                tag: "NET NEGATIVE"
            )
        case .networkRestricted(let merchant, let networks, let count):
            let name = merchant ?? "This place"
            let netString = networks.map { $0.rawValue.capitalized }.joined(separator: " or ")
            return ChipBanterItem(
                text: "Hey, put that away! \(name) only takes \(netString). I had to exclude \(count) of your cards from the math.",
                mood: .alert,
                tag: "NETWORK RULE"
            )
        case .declineDcc(let currency):
            return ChipBanterItem(
                text: "We're in \(currency) territory! When the terminal asks if you want to pay in CAD, say NO! Let the card do the math, their rate is a scam.",
                mood: .alert,
                tag: "DCC TRAP"
            )
        case .switchFromDefault(_, let toId, let advantage):
            let visualStyle = CardVisualTheme.style(for: toId)
            let formattedName = visualStyle.shortName.isEmpty
                ? (toId.contains("-") ? toId.split(separator: "-").map(\.capitalized).joined(separator: " ") : toId)
                : visualStyle.shortName
            return ChipBanterItem(
                text: "This is why you hired me! Put your default card away and tap \(formattedName). You're up $\(String(format: "%.2f", advantage)) just for listening to me.",
                mood: .celebrating,
                tag: "SMART SWITCH"
            )
        case .fxCostErosion(_, let fxCost, let gross, let rate):
            let percent = (fxCost / gross) * 100
            return ChipBanterItem(
                text: "Ouch. That \(rate * 100)% foreign transaction fee just ate \(String(format: "%.0f", percent))% of your rewards. Still the best math, but hurts to watch.",
                mood: .shocked,
                tag: "FX EROSION"
            )
        case .capNearlyExhausted:
            return ChipBanterItem(
                text: "Careful, you're scraping the bottom of this category's monthly cap. I might have to tag in your backup card soon.",
                mood: .wink,
                tag: "CAP WARNING"
            )
        case .valuationSensitive(_, let declared, let breakeven, _, let direction):
            let condition = direction == .below ? "drops below" : "goes above"
            return ChipBanterItem(
                text: "I picked this assuming your points are worth \(String(format: "%.2f", declared))¢. If their value \(condition) \(String(format: "%.2f", breakeven))¢, my math flips entirely.",
                mood: .cool,
                tag: "MATH CHECK"
            )
        case .marginalWinnerSuppressed(_, let advantage):
            return ChipBanterItem(
                text: "There's actually a card that beats your default by $\(String(format: "%.2f", advantage)), but it's not worth the hassle. I kept your usual card on top.",
                mood: .wink,
                tag: "CLOSE ENOUGH"
            )
        }
    }
}

/// An Apple Intelligence & Deadpool-inspired 4th-wall breaking interactive companion card.
/// Chip physically pops out of the card frame, knocks on the iPhone glass, and speaks directly to the user.
struct ChipCompanionHeaderCard: View {
    let statusText: String
    let subtitle: String
    var insights: [ChipInsight] = []
    /// Quips that jump the queue — a broken subsystem outranks any joke or engine insight.
    var pinnedBanter: [ChipBanterItem] = []
    /// Quips that take their turn in the ordinary rotation rather than demanding attention.
    var rotationBanter: [ChipBanterItem] = []
    var onSearchTap: (() -> Void)? = nil
    var activeSearchText: String = ""
    /// Where Chip should be looking — the owner's focus, not his own idle schedule.
    var gaze: ChipGaze = .wandering
    /// The face Chip falls back to between reactions. Late at night that is not `.cool`.
    var restingMood: ChipMood = .cool
    @Binding var externalReactionText: String?
    @Binding var externalIsBubblePresented: Bool
    /// A binding, not a value: whoever sets the tag cannot know when Chip moves on, so the card
    /// has to be able to clear it. As a plain value it stuck, and every later quip — Costco
    /// rules, DCC warnings — kept wearing the tag of whichever easter egg fired first.
    @Binding var externalReactionTag: String?

    @State private var quipIndex: Int = 0
    @State private var internalIsBubblePresented: Bool = false
    @State private var isGlowPulsing: Bool = false
    @State private var isOverclocked: Bool = false
    @State private var currentMood: ChipMood? = nil
    @State private var glassKnockTrigger: Int = 0
    @State private var pokeCount: Int = 0
    @State private var specialReactionText: String? = nil
    @State private var lastPokeTimestamp: Date = Date.distantPast
    @State private var rapidPokeStreak: Int = 0
    @State private var lastPinnedTag: String? = nil
    @State private var autoExpandedTag: String? = nil

    private var isBubblePresented: Bool {
        externalIsBubblePresented || internalIsBubblePresented
    }

    private var isCurrentlyOverclocked: Bool {
        isOverclocked || activeDisplayText.contains("OVERCLOCKING")
    }

    /// What Chip's face is doing right now: a live reaction if he has one, otherwise the search
    /// field, otherwise whatever the current banter or time of day says he should look like.
    private var effectiveMood: ChipMood {
        if isCurrentlyOverclocked { return .calculating }
        if let currentMood { return currentMood }
        if let searchMood = ChipEasterEgg.match(activeSearchText)?.mood { return searchMood }
        return currentBanter.mood
    }

    private var activeDisplayText: String {
        externalReactionText ?? specialReactionText ?? currentBanter.text
    }

    private var activeTagText: String {
        ChipBubbleTag.resolve(
            externalTag: externalReactionTag,
            reactionText: externalReactionText ?? specialReactionText,
            fallback: currentBanter.tag
        )
    }

    private var banterQueue: ChipBanterQueue {
        ChipBanterQueue(
            pinned: pinnedBanter,
            insights: insights.map { ChipInsightFormatter.format($0) },
            standing: staticBanterList,
            rotation: rotationBanter
        )
    }

    /// The quip currently on deck. Never a raw subscript — see `ChipBanterQueue`.
    private var currentBanter: ChipBanterItem {
        banterQueue.item(at: quipIndex)
            ?? ChipBanterItem(text: statusText.isEmpty ? subtitle : statusText, mood: restingMood, tag: "CHIP")
    }

    private var currentBubbleTag: String {
        activeTagText
    }

    /// Opens Chip's bubble on its own when something is genuinely broken.
    ///
    /// A collapsed bubble is the right default for jokes and tips — but the empty-wallet advisory
    /// is a new owner's first minute in the app, and advice they have to tap a mascot to discover
    /// is advice most of them never see. Only pinned advisories qualify, only once each, and a
    /// dismissal sticks.
    private func autoExpandForPinnedAdvisoryIfNeeded() {
        guard let tag = pinnedBanter.first?.tag, tag != autoExpandedTag else { return }
        autoExpandedTag = tag
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            internalIsBubblePresented = true
        }
    }

    private func dismissBubble() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        withAnimation(.spring(response: 0.30, dampingFraction: 0.75)) {
            externalIsBubblePresented = false
            internalIsBubblePresented = false
            externalReactionText = nil
            externalReactionTag = nil
            specialReactionText = nil
            currentMood = currentBanter.mood
        }
    }

    private let staticBanterList: [ChipBanterItem] = [
        ChipBanterItem(
            text: "Hey you holding the iPhone! Yeah, you. Stop scrolling—Amex Cobalt earns 5x on this meal, so don't touch that debit card.",
            mood: .cool,
            tag: "4TH WALL BREAK"
        ),
        ChipBanterItem(
            text: "Baby's first credit card? BMO CashBack Mastercard. Humble beginnings, but look at us now: master point strategists.",
            mood: .cool,
            tag: "ORIGIN LORE"
        ),
        ChipBanterItem(
            text: "If you ever take away my Amex Cobalt, I will personally rewrite my firmware. 5x on groceries & dining is sacred in Canada.",
            mood: .celebrating,
            tag: "HOLY GRAIL"
        ),
        ChipBanterItem(
            text: "Most regretted card? Amex Platinum. That $799 annual fee still gives me digital nightmares unless you literally sleep in airport lounges.",
            mood: .shocked,
            tag: "FEE TRAUMA"
        ),
        ChipBanterItem(
            text: "Best coffee spot? Error 404: this copilot runs on matcha. Routing you to the nearest bubble tea spot instead!",
            mood: .wink,
            tag: "ENERGY CHECK"
        ),
        ChipBanterItem(
            text: "Ow! Did you just poke my forehead? There's 0.8mm of Ceramic Shield glass between us, but I still felt that!",
            mood: .shocked,
            tag: "PHYSICS CHECK"
        ),
        ChipBanterItem(
            text: "I'm literally living inside your screen running 4,000 interchange algorithms a second just so you can fly for free. You're welcome.",
            mood: .knock,
            tag: "CHIP LIVE"
        ),
        ChipBanterItem(
            text: "PUT THE COBALT DOWN! 🚨 Costco Canada is strictly Mastercard-only. If you tap an Amex here, prepare for the register walk of shame. Switch to your Rogers or BMO Mastercard!",
            mood: .denied,
            tag: "COSTCO TRAP"
        ),
        ChipBanterItem(
            text: "Battery dipping low? Quick, tap Apple Pay before the screen goes black — we've got multipliers to rescue!",
            mood: .alert,
            tag: "BATTERY CO-PILOT"
        ),
        ChipBanterItem(
            text: "Who approved this gorgeous golden chassis? Look at my circuit traces. I look fantastic today.",
            mood: .celebrating,
            tag: "CHASSIS DRIP"
        ),
        ChipBanterItem(
            text: "Look at us: you, me, and a 5% multiplier on dining. Best cinematic duo since Deadpool & Wolverine.",
            mood: .cool,
            tag: "REWARDS DUO"
        ),
        ChipBanterItem(
            text: "Fun fact: I can see your battery percentage and your credit score. Don't worry, your secret's safe with me.",
            mood: .wink,
            tag: "DEVICE SYNC"
        ),
        ChipBanterItem(
            text: "Hey, look down at that search bar below me. Go ahead, type a merchant. I'll do all the heavy math while you take the glory.",
            mood: .knock,
            tag: "RADAR CO-PILOT"
        ),
        ChipBanterItem(
            text: "Loblaws & No Frills don't take Amex—tap your PC Financial or Visa before you hold up the entire checkout line!",
            mood: .alert,
            tag: "MERCHANT RULE"
        ),
        ChipBanterItem(
            text: "I'm breaking the 4th wall right now because your cash back strategy is an absolute cinematic masterpiece.",
            mood: .celebrating,
            tag: "MAXIMUM EFFORT"
        )
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Leading: 3D Animated Chip Mascot on Fluid-Glow Pedestal
            chipMascotStage

            // Trailing: Tag, Headline Insight Text, and Action Controls
            VStack(alignment: .leading, spacing: 7) {
                headerTagRow

                headlineTextSection

                if let action = currentBanter.action, externalReactionText == nil, specialReactionText == nil {
                    callToActionButton(action)
                }

                interactiveActionsRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(cardBackground)
        .contentShape(Rectangle())
        .simultaneousGesture(horizontalSwipeGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activeTagText), \(activeDisplayText)")
        .accessibilityAction(named: "Next Quip") { advanceQuip() }
        .accessibilityAction(named: "Previous Quip") { previousQuip() }
        .onAppear {
            isGlowPulsing = true
            currentMood = currentBanter.mood
            lastPinnedTag = pinnedBanter.first?.tag
            autoExpandForPinnedAdvisoryIfNeeded()
            #if canImport(UIKit)
            UIDevice.current.isBatteryMonitoringEnabled = true
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            triggerDizzyShakeAction()
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            let state = UIDevice.current.batteryState
            if state == .charging || state == .full {
                triggerBatteryChargingAction()
            }
        }
        #endif
        .onChange(of: insights) {
            quipIndex = 0
            currentMood = currentBanter.mood
        }
        .onChange(of: pinnedBanter.first?.tag) { _, newTag in
            guard newTag != lastPinnedTag else { return }
            lastPinnedTag = newTag
            quipIndex = 0
            currentMood = currentBanter.mood
            autoExpandForPinnedAdvisoryIfNeeded()
        }
    }

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                // Only trigger if horizontal movement dominates vertical movement and exceeds threshold
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 30 else { return }
                
                if horizontal < 0 {
                    advanceQuip()
                } else {
                    previousQuip()
                }
            }
    }

    // MARK: - Subviews

    private var chipMascotStage: some View {
        Button {
            pokeChipAction()
        } label: {
            ZStack {
                // Soft Apple Intelligence Aurora Fluid Glow Halo
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.55, blue: 0.15).opacity(0.50),
                                Color(red: 0.95, green: 0.25, blue: 0.70).opacity(0.35),
                                Color(red: 0.20, green: 0.75, blue: 1.0).opacity(0.25),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 36
                        )
                    )
                    .frame(width: 68, height: 68)
                    .scaleEffect(isGlowPulsing ? 1.15 : 0.88)
                    .opacity(isGlowPulsing ? 0.95 : 0.60)
                    .blur(radius: 5)
                    .animation(
                        .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                        value: isGlowPulsing
                    )

                // High-End Frosted Pedestal Disc (anchors Chip visually on screen)
                Circle()
                    .fill(Color(.tertiarySystemFill).opacity(0.45))
                    .frame(width: 58, height: 58)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.65),
                                        Color.orange.opacity(0.35),
                                        Color.cyan.opacity(0.30)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: Color.orange.opacity(0.12), radius: 6, x: 0, y: 3)

                // 3D Mascot View
                ChipMascotView(
                    mood: effectiveMood,
                    size: 46,
                    isWaving: true,
                    enable3DTilt: true,
                    gaze: gaze,
                    isOverclocked: isCurrentlyOverclocked,
                    onTap: {
                        pokeChipAction()
                    },
                    onLongPress: {
                        triggerOverclockingAction()
                    }
                )
                .frame(width: 54, height: 54)
            }
            .frame(width: 66, height: 66)
        }
        .buttonStyle(.plain)
    }

    private var headerTagRow: some View {
        HStack(spacing: 6) {
            // Category / Insight Tag Capsule
            HStack(spacing: 4) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.orange)

                Text(activeTagText)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.orange)
                    .tracking(0.8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Color.orange.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.8)
            )

            Spacer(minLength: 4)

            // Mascot Status / 4th-Wall Badge
            HStack(spacing: 4.5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5.5, height: 5.5)
                    .shadow(color: Color.green.opacity(0.8), radius: 2)

                Text("CHIP")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill).opacity(0.8), in: Capsule())
        }
    }

    private var headlineTextSection: some View {
        Text(activeDisplayText)
            .font(.system(size: 13.5, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .id(activeDisplayText)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func callToActionButton(_ action: ChipBanterAction) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            action.perform()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 11, weight: .bold))
                Text(action.label)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var interactiveActionsRow: some View {
        HStack(spacing: 6) {
            // Subtle swipe affordance indicator
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .bold))
                Text("Swipe")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.tertiary)
            .padding(.leading, 4)

            Spacer(minLength: 2)

            // Next Quip / Tip Button
            Button {
                advanceQuip()
            } label: {
                HStack(spacing: 3) {
                    Text("Next")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9.5, weight: .bold))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    private var cardBackground: some View {
        ZStack {
            // Frosted Base
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))

            // Apple Intelligence Iridescent Ambient Fluid Glow
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.12),
                            Color.pink.opacity(0.08),
                            Color.purple.opacity(0.06),
                            Color.cyan.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // 3D Glass Rim
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.75),
                            Color.orange.opacity(0.40),
                            Color.pink.opacity(0.30),
                            Color.cyan.opacity(0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        }
        .shadow(color: Color.orange.opacity(0.09), radius: 14, x: 0, y: 5)
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    /// Chip's deepest cut. Both routes here — the 1.8s hold and the five-poke streak — are
    /// deliberate gestures, which is the only place the founder is named by name; nothing a
    /// stranger can trip over by typing a merchant should introduce them to him.
    private static let founderProtocolDialogue = "FOUNDER PROTOCOL UNLOCKED!\nEngineered by Zubair Muwwakil in Canada to rescue Canadians from 1x multiplier traps and brutal interchange fees. Maximum effort!"

    private func triggerFounderProtocol(moodResetAfter delay: TimeInterval) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
            externalReactionText = nil
            externalReactionTag = nil
            currentMood = .celebrating
            internalIsBubblePresented = true
            specialReactionText = Self.founderProtocolDialogue
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentMood = currentBanter.mood
            }
        }
    }

    private static let overclockingDialogue = "⚡️ OVERCLOCKING ENGINE: Simulating 50,000 reward strategies across Visa, Mastercard, and Amex..."

    private func triggerOverclockingAction() {
        // Heavy rigid haptic rumble pattern
        let rigid = UIImpactFeedbackGenerator(style: .rigid)
        rigid.prepare()
        rigid.impactOccurred(intensity: 1.0)
        for step in 1...4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.08) {
                rigid.impactOccurred(intensity: 1.0)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            let heavy = UIImpactFeedbackGenerator(style: .heavy)
            heavy.impactOccurred(intensity: 1.0)
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
            isOverclocked = true
            externalReactionText = nil
            externalReactionTag = nil
            currentMood = .calculating
            internalIsBubblePresented = true
            specialReactionText = Self.overclockingDialogue
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isOverclocked = false
                currentMood = currentBanter.mood
            }
        }
    }

    private static let dizzyDialogue = "Woah woah woah! Who spiked the gyroscope?! I'm an EMV micro-chip, not a snowglobe!"

    private func triggerDizzyShakeAction() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()
        impact.impactOccurred()
        for step in 1...2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.1) {
                impact.impactOccurred(intensity: 0.8)
            }
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
            externalReactionText = nil
            externalReactionTag = nil
            currentMood = .dizzy
            internalIsBubblePresented = true
            specialReactionText = Self.dizzyDialogue
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentMood = currentBanter.mood
            }
        }
    }

    private static let batteryChargingDialogue = "⚡ Pure 24-karat grid voltage detected! Optimal EMV conductivity restored."

    private func triggerBatteryChargingAction() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.prepare()
        impact.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            impact.impactOccurred()
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
            externalReactionText = nil
            externalReactionTag = nil
            currentMood = .charging
            internalIsBubblePresented = true
            specialReactionText = Self.batteryChargingDialogue
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentMood = currentBanter.mood
            }
        }
    }

    private func advanceQuip() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
            externalReactionText = nil
            externalReactionTag = nil
            specialReactionText = nil
            quipIndex = banterQueue.advanced(from: quipIndex)
            currentMood = currentBanter.mood
        }
    }

    private func previousQuip() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
            externalReactionText = nil
            externalReactionTag = nil
            specialReactionText = nil
            quipIndex = banterQueue.retreated(from: quipIndex)
            currentMood = currentBanter.mood
        }
    }

    private func pokeChipAction() {
        pokeCount += 1
        let now = Date()
        if now.timeIntervalSince(lastPokeTimestamp) < 1.4 {
            rapidPokeStreak += 1
        } else {
            rapidPokeStreak = 1
        }
        lastPokeTimestamp = now

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // 5-Tap Rapid Streak: Founder Protocol Easter Egg!
        if rapidPokeStreak >= 5 {
            rapidPokeStreak = 0
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)
            triggerFounderProtocol(moodResetAfter: 4.0)
            return
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
            externalReactionText = nil
            externalReactionTag = nil
            currentMood = .shocked
            internalIsBubblePresented = true
            if pokeCount % 4 == 0 {
                specialReactionText = "*TAP TAP TAP* — Hey! Lionel! Just checking if the Ceramic Shield glass is clean. Now check those multipliers!"
                currentMood = .knock
            } else if pokeCount % 3 == 0 {
                specialReactionText = "HEY! That's my face! Do you go around poking cashiers like that too?!"
            } else if pokeCount % 2 == 0 {
                specialReactionText = "Okay buddy, one more poke and I'm setting your default multiplier to 0.5%!"
            } else {
                specialReactionText = "Ow! You hit my golden bevel rim! That's 24-karat vector art right there."
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentMood = currentBanter.mood
            }
        }
    }

    private func knockScreenGlassAction() {
        let rigid = UIImpactFeedbackGenerator(style: .rigid)
        rigid.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            rigid.impactOccurred(intensity: 0.9)
        }

        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
            externalReactionText = nil
            externalReactionTag = nil
            currentMood = .knock
            internalIsBubblePresented = true
            specialReactionText = "*TAP TAP TAP* — Hey! Lionel! Just checking if the Ceramic Shield glass is clean. Now check those multipliers!"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentMood = currentBanter.mood
            }
        }
    }
}

extension NSNotification.Name {
    static let deviceDidShake = NSNotification.Name("deviceDidShakeNotification")
}

#if canImport(UIKit)
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}
#endif
