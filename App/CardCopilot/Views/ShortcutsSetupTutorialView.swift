import CardCopilotCapture
import SwiftUI
import UIKit

// MARK: - Shortcuts Setup Step Definition

public enum ShortcutsTutorialStep: Int, CaseIterable, Identifiable {
    case intro = 0
    case openAutomationTab = 1
    case triggerAndRunImmediately = 2
    case addPickMeAction = 3
    case mapParameters = 4
    case liveVerification = 5
    case actionButtonBonus = 6

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .intro: return "Automated Tap Capture"
        case .openAutomationTab: return "1. Automation Tab"
        case .triggerAndRunImmediately: return "2. Run Immediately"
        case .addPickMeAction: return "3. Add PickMe Action"
        case .mapParameters: return "4. Map Variables"
        case .liveVerification: return "5. Test & Verify"
        case .actionButtonBonus: return "Action Button & Siri"
        }
    }

    public var shortTitle: String {
        switch self {
        case .intro: return "Start"
        case .openAutomationTab: return "Tab"
        case .triggerAndRunImmediately: return "Trigger"
        case .addPickMeAction: return "Action"
        case .mapParameters: return "Tokens"
        case .liveVerification: return "Verify"
        case .actionButtonBonus: return "Siri"
        }
    }
}

// MARK: - Main Interactive Tutorial View

public struct ShortcutsSetupTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: ShortcutsTutorialStep
    @State private var copiedActionName = false
    @State private var recentLogs: [WalletCaptureShortcutRunLog] = []
    @State private var isLoadingLogs = false

    public init(initialStep: ShortcutsTutorialStep = .intro) {
        _currentStep = State(initialValue: initialStep)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented Progress Pill Bar
                progressPillHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                // Swipeable Step Carousel
                TabView(selection: $currentStep) {
                    introSlide.tag(ShortcutsTutorialStep.intro)
                    openAutomationTabSlide.tag(ShortcutsTutorialStep.openAutomationTab)
                    triggerAndRunImmediatelySlide.tag(ShortcutsTutorialStep.triggerAndRunImmediately)
                    addPickMeActionSlide.tag(ShortcutsTutorialStep.addPickMeAction)
                    mapParametersSlide.tag(ShortcutsTutorialStep.mapParameters)
                    liveVerificationSlide.tag(ShortcutsTutorialStep.liveVerification)
                    actionButtonBonusSlide.tag(ShortcutsTutorialStep.actionButtonBonus)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentStep)

                Divider()

                // Persistent Sticky Bottom Command Bar
                bottomActionBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .medium))
                }

                ToolbarItem(placement: .principal) {
                    Text(currentStep.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: URL(string: "shortcuts://")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Shortcuts")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                    }
                }
            }
        }
        .task {
            await refreshLogs()
        }
    }

    // MARK: - Progress Pill Header

    private var progressPillHeader: some View {
        HStack(spacing: 6) {
            ForEach(ShortcutsTutorialStep.allCases) { step in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        currentStep = step
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Capsule()
                        .fill(
                            currentStep == step
                                ? Color.blue
                                : (step.rawValue < currentStep.rawValue
                                    ? Color.blue.opacity(0.4)
                                    : Color(.tertiarySystemFill))
                        )
                        .frame(height: 5)
                        .animation(.spring(response: 0.3), value: currentStep)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Slide 0: Intro / Superpower

    private var introSlide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero Icon Banner
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 140)

                    VStack(spacing: 12) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 52, height: 52)
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                            }

                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.secondary)

                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 52, height: 52)
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }

                        Text("Zero-Touch Apple Wallet Capture")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }

                Text("Why Set Up Automation?")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)

                VStack(spacing: 12) {
                    benefitRow(
                        icon: "sparkles",
                        color: .purple,
                        title: "Instant Better-Card Alerts",
                        description: "When you tap your card at a terminal, PickMe immediately checks if another card in your wallet earned more rewards."
                    )
                    benefitRow(
                        icon: "chart.bar.fill",
                        color: .blue,
                        title: "Live Spend-Cap Tracking",
                        description: "Automatically tracks your monthly category bonus caps without requiring bank logins or open editors."
                    )
                    benefitRow(
                        icon: "lock.shield.fill",
                        color: .green,
                        title: "100% Private & On-Device",
                        description: "Card evaluation runs completely offline on your iPhone. Your transactions are never sold or shared."
                    )
                }

                // Apple Disclaimer Note
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)

                    Text("Apple requires users to configure Personal Automations inside the Apple Shortcuts app. This visual walkthrough guides you through the 4 steps in under 60 seconds.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                .padding(14)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(20)
        }
    }

    // MARK: - Slide 1: Open Shortcuts & Automation Tab

    private var openAutomationTabSlide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepBadge(step: 1, title: "Open Automation Tab")

                Text("Open the **Apple Shortcuts** app on your iPhone, and switch to the **Automation** tab at the bottom.")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)

                // Simulated iOS Shortcuts App Tab Bar Mockup
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Personal Automation")
                                .font(.system(size: 17, weight: .bold))
                            Spacer()
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.blue)
                                .padding(6)
                                .background(Color.blue.opacity(0.12), in: Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.blue, lineWidth: 2)
                                        .scaleEffect(1.2)
                                        .opacity(0.8)
                                )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                        // Trigger Picker Item
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.purple)
                                    .frame(width: 32, height: 32)
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Transaction")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("When I tap any card or pass")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                    }
                    .background(Color(.systemBackground))

                    Divider()

                    // Tab Bar Mockup
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2")
                            Text("Shortcuts")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)

                        Spacer()

                        // Highlighted Automation Tab
                        VStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text("Automation")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.blue)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(Color.blue.opacity(0.15), in: Capsule())

                        Spacer()

                        VStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Gallery")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)

                // Key Advice
                VStack(alignment: .leading, spacing: 8) {
                    Label("**Do not use** the Shortcuts library tab.", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 13, weight: .medium))
                    Label("Tap **+** in the top right and select **Transaction** under the Wallet section.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(20)
        }
    }

    // MARK: - Slide 2: Trigger & Run Immediately

    private var triggerAndRunImmediatelySlide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepBadge(step: 2, title: "Choose 'Run Immediately'")

                Text("Configure the automation trigger. **This is the most critical setting** to ensure frictionless background capture.")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)

                // Simulated iOS Automation Options Mockup
                VStack(spacing: 12) {
                    // Trigger section
                    HStack {
                        Text("When")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Any Card")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    Divider()

                    // Execution Mode Radio Mockup
                    VStack(alignment: .leading, spacing: 10) {
                        // Bad Option: Run After Confirmation
                        HStack(spacing: 12) {
                            Image(systemName: "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Run After Confirmation")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text("Prompts you with a popup banner on every tap")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

                        // Good Option: Run Immediately
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Run Immediately")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.primary)
                                    Text("RECOMMENDED")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green, in: Capsule())
                                }
                                Text("Captures instantly in background without asking")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
                        )
                    }
                    .padding(.horizontal, 14)

                    Divider()

                    // Notify When Run Toggle Mockup
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notify When Run")
                                .font(.system(size: 13, weight: .medium))
                            Text("Turn OFF to avoid duplicate notifications")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemGray4))
                                .frame(width: 44, height: 26)
                            Circle()
                                .fill(.white)
                                .frame(width: 22, height: 22)
                                .padding(2)
                                .shadow(radius: 1)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)

                // Warning Callout
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 16))

                    Text("If you leave 'Run After Confirmation' selected, Apple will ask you to confirm the automation on every payment, defeating automatic tap tracking.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(20)
        }
    }

    // MARK: - Slide 3: Add PickMe Action & Copy Helper

    private var addPickMeActionSlide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepBadge(step: 3, title: "Add PickMe Action")

                Text("On the next screen, tap **Add Action** (or **New Blank Automation** $\\to$ **Add Action**), then search for PickMe.")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)

                // Quick Copy Pill Box
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTION NAME TO SEARCH:")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(0.6)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Wallet Purchase to In Unity")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("From the PickMe app")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            UIPasteboard.general.string = "Send Wallet Purchase to In Unity"
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.3)) {
                                copiedActionName = true
                            }
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation { copiedActionName = false }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: copiedActionName ? "checkmark" : "doc.on.doc.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(copiedActionName ? "Copied!" : "Copy")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(copiedActionName ? .green : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                copiedActionName ? Color.green.opacity(0.15) : Color.blue,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }

                // Simulated Search Screen Mockup
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text("Send Wallet Purchase")
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))

                    // Action Search Result Card
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 36, height: 36)
                            Image(systemName: "creditcard.and.123")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Wallet Purchase to In Unity")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("PickMe • Saves transaction and syncs")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.blue)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            }
            .padding(20)
        }
    }

    // MARK: - Slide 4: Map Parameters (The Visual Matrix)

    private var mapParametersSlide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepBadge(step: 4, title: "Connect Transaction Variables")

                Text("Apple Shortcuts passes transaction data through **variables**. Tap each parameter field in the action and select its matching Shortcut variable.")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)

                // Interactive Token Mapping Table
                VStack(spacing: 10) {
                    HStack {
                        Text("PICKME PARAMETER")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("SELECT SHORTCUT INPUT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)

                    parameterMappingRow(
                        param: "Merchant",
                        icon: "building.2.fill",
                        color: .blue,
                        token: "Shortcut Input > Merchant"
                    )

                    parameterMappingRow(
                        param: "Amount",
                        icon: "dollarsign.circle.fill",
                        color: .green,
                        token: "Shortcut Input > Amount"
                    )

                    parameterMappingRow(
                        param: "Currency",
                        icon: "globe",
                        color: .purple,
                        token: "Shortcut Input > Currency Code"
                    )

                    parameterMappingRow(
                        param: "Card",
                        icon: "creditcard.fill",
                        color: .teal,
                        token: "Shortcut Input > Card or Pass"
                    )
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)

                // How to select in Shortcuts Explainer
                VStack(alignment: .leading, spacing: 8) {
                    Text("HOW TO MAP IN APPLE SHORTCUTS:")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(0.6)

                    HStack(alignment: .top, spacing: 10) {
                        Text("1")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.blue, in: Circle())
                        Text("Tap the empty field (e.g. **Merchant**).")
                            .font(.system(size: 13))
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Text("2")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.blue, in: Circle())
                        Text("On the popup keyboard bar, tap **Shortcut Input**.")
                            .font(.system(size: 13))
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Text("3")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.blue, in: Circle())
                        Text("Tap the blue **Shortcut Input** variable chip to change its property to **Merchant**.")
                            .font(.system(size: 13))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(20)
        }
    }

    // MARK: - Slide 5: Live Verification Lab

    private var liveVerificationSlide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepBadge(step: 5, title: "Test & Verify Setup")

                Text("Verify that your Apple Shortcuts automation connects cleanly to PickMe.")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)

                // Live Run Status Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("ON-DEVICE AUDIT LOG", systemImage: "waveform.path.ecg")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .tracking(0.6)

                        Spacer()

                        Button {
                            Task { await refreshLogs() }
                        } label: {
                            HStack(spacing: 4) {
                                if isLoadingLogs {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                Text("Check Logs")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.blue)
                        }
                    }

                    if let latest = recentLogs.first {
                        logReportView(latest)
                    } else {
                        // Empty state: waiting for test run
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.blue)
                            }

                            Text("No Shortcut Invocations Yet")
                                .font(.system(size: 15, weight: .bold, design: .rounded))

                            Text("Open Shortcuts and tap the **▶️ Play** button on your automation to send a test run, or make a test payment.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 10)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)

                // How to trigger test in Shortcuts
                VStack(alignment: .leading, spacing: 10) {
                    Text("HOW TO RUN A TEST NOW:")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(0.6)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 16))
                        Text("In Shortcuts, tap on your new automation and tap the **▶️ Play** button at the bottom.")
                            .font(.system(size: 13))
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.teal)
                            .font(.system(size: 16))
                        Text("Return here and tap **Check Logs** to confirm PickMe received the event.")
                            .font(.system(size: 13))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(20)
        }
    }

    // MARK: - Slide 6: Action Button & Siri (Bonus High-ROI)

    private var actionButtonBonusSlide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Badge
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 13))
                    Text("BONUS PRODUCTIVITY")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                }

                Text("Ask PickMe with Action Button & Siri")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("Beyond automatic transaction capture, you can instantly ask PickMe which card to use *before* paying using your iPhone’s Action Button or Siri.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)

                // Action Button Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 42, height: 42)
                            Image(systemName: "button.programmable")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.orange)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("iPhone Action Button")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text("Instant recommendation in 1 squeeze")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Open **iOS Settings** $\\to$ **Action Button**")
                            .font(.system(size: 13))
                        Text("2. Swipe to **Shortcut** and select **'Which Card in PickMe?'**")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                // Siri Phrases Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 42, height: 42)
                            Image(systemName: "mic.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.purple)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Siri Voice Shortcuts")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text("No setup needed — pre-registered")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        siriPhrasePill("“Hey Siri, which card in PickMe?”")
                        siriPhrasePill("“Hey Siri, open PickMe Radar”")
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(20)
        }
    }

    // MARK: - Log Report Diagnostic View

    @ViewBuilder
    private func logReportView(_ log: WalletCaptureShortcutRunLog) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let isComplete = log.input.merchantPresent && log.input.amountPresent && log.input.cardPresent

            HStack {
                Image(systemName: isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isComplete ? .green : .orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text(isComplete ? "Shortcut Connected Successfully" : "Incomplete Parameter Mapping")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(isComplete ? .green : .orange)
                    Text("Last invocation \(log.startedAt.formatted(date: .omitted, time: .standard))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // Field checklist
            VStack(spacing: 6) {
                fieldStatusRow(name: "Merchant", isPresent: log.input.merchantPresent)
                fieldStatusRow(name: "Amount", isPresent: log.input.amountPresent)
                fieldStatusRow(name: "Currency", isPresent: log.input.currencyPresent)
                fieldStatusRow(name: "Card or Pass", isPresent: log.input.cardPresent)
            }

            if !isComplete {
                Button {
                    withAnimation { currentStep = .mapParameters }
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "wrench.and.screwdriver.fill")
                        Text("Review Step 4 (Token Mapping)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private func fieldStatusRow(name: String, isPresent: Bool) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: isPresent ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isPresent ? .green : .red)
                Text(isPresent ? "Detected" : "Missing")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isPresent ? .green : .red)
            }
        }
    }

    // MARK: - Persistent Sticky Bottom Action Bar

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            // Previous Step Button
            if currentStep.rawValue > 0 {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if let prev = ShortcutsTutorialStep(rawValue: currentStep.rawValue - 1) {
                            currentStep = prev
                        }
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Back")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            // Primary Contextual Action Button
            primaryActionButton
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch currentStep {
        case .intro:
            Button {
                advanceStep()
            } label: {
                primaryButtonLabel(title: "Start Setup Walkthrough", icon: "arrow.right")
            }
            .buttonStyle(.plain)

        case .openAutomationTab:
            HStack(spacing: 8) {
                Link(destination: URL(string: "shortcuts://")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.app.fill")
                        Text("Open Shortcuts")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    advanceStep()
                } label: {
                    primaryButtonLabel(title: "Next", icon: "chevron.right")
                }
                .buttonStyle(.plain)
            }

        case .triggerAndRunImmediately:
            Button {
                advanceStep()
            } label: {
                primaryButtonLabel(title: "Next: Add PickMe Action", icon: "chevron.right")
            }
            .buttonStyle(.plain)

        case .addPickMeAction:
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = "Send Wallet Purchase to In Unity"
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation { copiedActionName = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { copiedActionName = false }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copiedActionName ? "checkmark" : "doc.on.doc.fill")
                        Text(copiedActionName ? "Copied!" : "Copy Name")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(copiedActionName ? .green : .blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        copiedActionName ? Color.green.opacity(0.12) : Color.blue.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    advanceStep()
                } label: {
                    primaryButtonLabel(title: "Next: Map Variables", icon: "chevron.right")
                }
                .buttonStyle(.plain)
            }

        case .mapParameters:
            Button {
                advanceStep()
            } label: {
                primaryButtonLabel(title: "Next: Test & Verify", icon: "chevron.right")
            }
            .buttonStyle(.plain)

        case .liveVerification:
            HStack(spacing: 8) {
                Link(destination: URL(string: "shortcuts://")!) {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                        Text("Open Shortcuts")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    advanceStep()
                } label: {
                    primaryButtonLabel(title: "Action Button Bonus", icon: "chevron.right")
                }
                .buttonStyle(.plain)
            }

        case .actionButtonBonus:
            Button {
                dismiss()
            } label: {
                primaryButtonLabel(title: "Done", icon: "checkmark")
            }
            .buttonStyle(.plain)
        }
    }

    private func advanceStep() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if let next = ShortcutsTutorialStep(rawValue: currentStep.rawValue + 1) {
                currentStep = next
            }
        }
    }

    private func primaryButtonLabel(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Spacer()
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.vertical, 13)
        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.blue.opacity(0.25), radius: 8, x: 0, y: 3)
    }

    // MARK: - Reusable UI Helper Components

    private func stepBadge(step: Int, title: String) -> some View {
        HStack(spacing: 8) {
            Text("\(step)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue, in: Circle())

            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
                .tracking(0.6)
        }
    }

    private func benefitRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func parameterMappingRow(param: String, icon: String, color: Color, token: String) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                Text(param)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .frame(width: 105, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.tertiary)

            Spacer()

            // Token Pill
            HStack(spacing: 4) {
                Image(systemName: "bolt.badge.automatic.fill")
                    .font(.system(size: 10))
                Text(token)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.blue.opacity(0.12), in: Capsule())
        }
        .padding(10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private func siriPhrasePill(_ phrase: String) -> some View {
        HStack {
            Image(systemName: "quote.bubble.fill")
                .foregroundStyle(.purple)
                .font(.system(size: 12))
            Text(phrase)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(10)
        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func refreshLogs() async {
        isLoadingLogs = true
        defer { isLoadingLogs = false }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let store = try? WalletCaptureShortcutRunLogStore(documentsDirectory: documents) else { return }
        if let items = try? await store.records() {
            recentLogs = items
        }
    }
}

// MARK: - Compatibility Sheet Wrapper

/// Backwards compatibility alias ensuring existing call sites continue to work.
public struct ShortcutsSetupGuideSheet: View {
    let initialStep: ShortcutsTutorialStep

    public init(initialStep: ShortcutsTutorialStep = .intro) {
        self.initialStep = initialStep
    }

    public var body: some View {
        ShortcutsSetupTutorialView(initialStep: initialStep)
    }
}
