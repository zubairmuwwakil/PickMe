import SwiftUI
import ClerkKit
import ClerkKitUI
import CardCopilotEngine
import CardCopilotStore

/// The You / Account & Settings hub: Profile, Cloud Sync, Ambient Intelligence,
/// Wallet Customization, Privacy Architecture, and App Preferences.
struct YouHubView: View {
    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @Environment(SyncCoordinator.self) private var sync
    @Environment(CopilotEnvironment.self) private var environment

    @AppStorage("enableHaptics") private var enableHaptics = true
    @State private var accountDetailIsPresented = false
    @State private var authIsPresented = false
    @State private var eraseIsPresented = false
    @State private var didErase = false

    private static let privacyPolicyURL = URL(string: "https://moneytalks.zubairmuwwakil.com/privacy")!

    private var isSignedIn: Bool {
        MoneyTalksConfiguration.isConfigured && Clerk.shared.user != nil
    }

    private var accountEmail: String? {
        Clerk.shared.user?.primaryEmailAddress?.emailAddress
    }

    private var userInitials: String {
        guard let email = accountEmail, !email.isEmpty else { return "U" }
        let prefix = email.split(separator: "@").first ?? ""
        let components = prefix.split(separator: ".")
        if components.count >= 2 {
            let first = components[0].prefix(1).uppercased()
            let second = components[1].prefix(1).uppercased()
            return "\(first)\(second)"
        }
        return String(prefix.prefix(2)).uppercased()
    }

    private var walletCardsCount: Int {
        environment.graph?.walletCards.count ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section 1: Profile & Cloud Identity Hero
                profileHero

                // Section 2: Intelligence & Automation
                intelligenceSection

                // Section 3: Wallet & Strategy
                walletStrategySection

                // Section 4: Privacy & Local Data (Apple Privacy Highlight)
                privacyAndDataSection

                // Section 5: App Preferences & Experience
                preferencesSection

                // Section 6: Apple-style Footer
                footerSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 96) // Inset for floating glass nav
        }
        .navigationTitle("Account & Settings")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $accountDetailIsPresented) {
            AccountDetailSheet(
                accountEmail: accountEmail,
                onSignOut: {
                    Task { await environment.signOut(session: session, router: router) }
                },
                onDeleteAccount: { erase in
                    try await environment.deleteAccount(
                        eraseLocalHistory: erase,
                        session: session,
                        router: router
                    )
                }
            )
        }
        .sheet(isPresented: $authIsPresented) {
            PickMeAuthSheet {
                authIsPresented = false
            }
        }
        .confirmationDialog("Erase this iPhone's history?", isPresented: $eraseIsPresented, titleVisibility: .visible) {
            Button("Erase On-Device History", role: .destructive) {
                triggerHaptic()
                environment.eraseLocalHistory(session: session)
                didErase = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your prediction log, purchase confirmations, and cached merchant locations from this iPhone. Your account and cloud sync are unaffected.")
        }
    }

    // MARK: - Section 1: Profile Hero

    @ViewBuilder
    private var profileHero: some View {
        if isSignedIn {
            Button {
                triggerHaptic()
                accountDetailIsPresented = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color(red: 0.1, green: 0.45, blue: 0.95)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 54, height: 54)
                            .shadow(color: Color.blue.opacity(0.22), radius: 6, x: 0, y: 3)

                        Text(userInitials)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(accountEmail ?? "PickMe Account")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 0.13, green: 0.77, blue: 0.37))
                                .frame(width: 7, height: 7)

                            Text("Connected to PickMe Cloud")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                )
            }
            .buttonStyle(SettingsRowPressStyle())
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 48, height: 48)

                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Guest Mode")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Private on-device checkout active")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        triggerHaptic()
                        authIsPresented = true
                    } label: {
                        Text("Sign In")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Text("Sign in to sync cap limits across your devices and enable automated Apple Wallet Shortcuts capture.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            )
        }
    }

    // MARK: - Section 2: Intelligence & Automation

    private var intelligenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("INTELLIGENCE & AUTOMATION")

            groupedContainer {
                // Arrival Alerts
                Button {
                    triggerHaptic()
                    router.push(.ambientSetup)
                } label: {
                    settingsRow(
                        icon: environment.ambientEnabled ? "location.fill" : "location",
                        iconBackground: .green,
                        title: "Arrival Alerts",
                        subtitle: environment.ambientEnabled
                            ? "\(environment.ambientDiagnostics.fired) fired · \(environment.ambientDiagnostics.suppressed) suppressed (7d)"
                            : "Automatic store arrival notifications",
                        trailingContent: {
                            statusPill(
                                text: environment.ambientEnabled ? "Active" : "Off",
                                isPositive: environment.ambientEnabled
                            )
                        }
                    )
                }
                .buttonStyle(SettingsRowPressStyle())

                rowDivider

                // Learned Merchants
                Button {
                    triggerHaptic()
                    router.push(.learnedMerchants)
                } label: {
                    settingsRow(
                        icon: "building.2.crop.circle.fill",
                        iconBackground: .orange,
                        title: "Learned Merchants",
                        subtitle: "Patronage memory & arrival confidence"
                    )
                }
                .buttonStyle(SettingsRowPressStyle())

                rowDivider

                // Sync & Wallet Capture
                Button {
                    triggerHaptic()
                    router.push(.sync)
                } label: {
                    settingsRow(
                        icon: sync.syncIssue == nil ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill",
                        iconBackground: sync.syncIssue == nil ? .blue : .orange,
                        title: "Sync & Wallet Capture",
                        subtitle: syncSubtitle,
                        trailingContent: {
                            if sync.syncIssue != nil {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.system(size: 14))
                            }
                        }
                    )
                }
                .buttonStyle(SettingsRowPressStyle())
            }
        }
    }

    // MARK: - Section 3: Wallet & Strategy

    private var walletStrategySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("WALLET & REWARDS")

            groupedContainer {
                // Value Recovered & Scoreboard
                Button {
                    triggerHaptic()
                    router.push(.dashboard)
                } label: {
                    settingsRow(
                        icon: "sparkles",
                        iconBackground: .blue,
                        title: "Value Recovered",
                        subtitle: valueRecoveredSubtitle,
                        trailingContent: {
                            HStack(spacing: 6) {
                                Text(String(format: "$%.2f", session.valueRecoveredCad))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)

                                if let confirmed = session.metrics?.confirmedCount, confirmed > 0 {
                                    Text("\(min(confirmed, 30))/30")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color(.tertiarySystemFill), in: Capsule())
                                }
                            }
                        }
                    )
                }
                .buttonStyle(SettingsRowPressStyle())

                rowDivider

                // Edit Cards & Multipliers
                Button {
                    triggerHaptic()
                    router.push(.walletSetup)
                } label: {
                    settingsRow(
                        icon: "creditcard.fill",
                        iconBackground: .indigo,
                        title: "Cards & Multipliers",
                        subtitle: "Configure cards, Tangerine categories & defaults",
                        trailingContent: {
                            if walletCardsCount > 0 {
                                Text("\(walletCardsCount) cards")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
                            }
                        }
                    )
                }
                .buttonStyle(SettingsRowPressStyle())

                rowDivider

                // Valuation Sandbox
                Button {
                    triggerHaptic()
                    router.push(.valuationSandbox)
                } label: {
                    settingsRow(
                        icon: "slider.horizontal.3",
                        iconBackground: .teal,
                        title: "Valuation Sandbox",
                        subtitle: "Point valuations, thresholds & return formulas"
                    )
                }
                .buttonStyle(SettingsRowPressStyle())
            }
        }
    }

    // MARK: - Section 4: Privacy & Local Data

    private var privacyAndDataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("PRIVACY & LOCAL DATA")

            groupedContainer {
                // Privacy Policy Link
                Link(destination: Self.privacyPolicyURL) {
                    settingsRow(
                        icon: "hand.raised.fill",
                        iconBackground: .purple,
                        title: "Privacy Architecture",
                        subtitle: "100% on-device matching · Zero location tracking",
                        isExternalLink: true
                    )
                }
                .buttonStyle(SettingsRowPressStyle())

                rowDivider

                // Erase On-Device History
                Button {
                    triggerHaptic()
                    eraseIsPresented = true
                } label: {
                    settingsRow(
                        icon: "trash.fill",
                        iconBackground: .red,
                        title: "Erase On-Device History",
                        subtitle: didErase ? "Erased successfully" : "Clear predictions, confirmations & cached places",
                        isDestructive: true
                    )
                }
                .buttonStyle(SettingsRowPressStyle())
            }
        }
    }

    // MARK: - Section 5: App Preferences & Experience

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("PREFERENCES")

            groupedContainer {
                // Haptic Feedback Toggle
                HStack(spacing: 12) {
                    squircleIcon(name: "iphone.gen3.radiowaves.left.and.right", background: .gray)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Haptic Feedback")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Tactile response on recommendations & taps")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $enableHaptics)
                        .labelsHidden()
                        .onChange(of: enableHaptics) { _, newValue in
                            if newValue {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                            }
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Section 6: Footer

    private var footerSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Private by Design · On-Device Intelligence")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text("PickMe for iOS · Version 1.0 (Build 42)")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Helper Views & Components

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
            .padding(.top, 4)
    }

    private func groupedContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 1.5)
        )
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 56)
    }

    private func squircleIcon(name: String, background: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [background, background.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .shadow(color: background.opacity(0.25), radius: 3, x: 0, y: 1.5)

            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func settingsRow<Trailing: View>(
        icon: String,
        iconBackground: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isDestructive: Bool = false,
        isExternalLink: Bool = false,
        @ViewBuilder trailingContent: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            squircleIcon(name: icon, background: iconBackground)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(isDestructive ? Color.red : Color.primary)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            trailingContent()

            Image(systemName: isExternalLink ? "arrow.up.right" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func settingsRow(
        icon: String,
        iconBackground: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isDestructive: Bool = false,
        isExternalLink: Bool = false
    ) -> some View {
        settingsRow(
            icon: icon,
            iconBackground: iconBackground,
            title: title,
            subtitle: subtitle,
            isDestructive: isDestructive,
            isExternalLink: isExternalLink,
            trailingContent: { EmptyView() }
        )
    }

    private func statusPill(text: String, isPositive: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                isPositive ? Color(red: 0.13, green: 0.77, blue: 0.37) : Color.gray,
                in: Capsule()
            )
    }

    private var syncSubtitle: LocalizedStringKey {
        if let issue = sync.syncIssue {
            return LocalizedStringKey(issue.message)
        } else if let lastSyncedAt = sync.lastSyncedAt {
            return "Last synced: \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"
        } else {
            return "Sync wallet state and cap progress across devices"
        }
    }

    private var valueRecoveredSubtitle: LocalizedStringKey {
        if session.pendingValueCad > 0 {
            return LocalizedStringKey(String(format: "$%.2f confirmed (+$%.2f pending)", session.valueRecoveredCad, session.pendingValueCad))
        } else {
            return "Track net reward gains & experiment calibration"
        }
    }

    private func triggerHaptic() {
        guard enableHaptics else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

/// A subtle touch feedback press style.
private struct SettingsRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.tertiarySystemFill) : Color.clear)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
