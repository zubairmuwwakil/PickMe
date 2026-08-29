import SwiftUI
import ClerkKit
import ClerkKitUI
import CardCopilotEngine
import CardCopilotStore

/// The You / Account hub: Profile, Cloud Sync Center, Ambient Alerts, Privacy & App Settings.
struct YouHubView: View {
    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @Environment(SyncCoordinator.self) private var sync
    @Environment(CopilotEnvironment.self) private var environment

    @State private var deleteIsPresented = false
    @State private var eraseIsPresented = false
    @State private var signOutIsPresented = false
    @State private var didErase = false

    private static let privacyPolicyURL = URL(string: "https://moneytalks.zubairmuwwakil.com/privacy")!

    private var isSignedIn: Bool {
        MoneyTalksConfiguration.isConfigured && Clerk.shared.user != nil
    }

    private var accountEmail: String? {
        Clerk.shared.user?.primaryEmailAddress?.emailAddress
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Section 1: User Profile Header
                profileCard

                // Section 2: Sync & Multi-Device
                syncCard

                // Section 3: Ambient Intelligence
                ambientCard

                // Section 4: Wallet & Data Management
                walletAndDataSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 90) // Inset for floating glass nav
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .confirmationDialog("Sign out of Inunity?", isPresented: $signOutIsPresented, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await environment.signOut(session: session, router: router) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signing out stops cap and feedback sync. Checkout continues to work offline with your on-device history.")
        }
        .confirmationDialog("Erase this iPhone's history?", isPresented: $eraseIsPresented, titleVisibility: .visible) {
            Button("Erase History", role: .destructive) {
                environment.eraseLocalHistory(session: session)
                didErase = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your on-device prediction log, confirmations, and merchant locations. It cannot be undone.")
        }
    }

    private var profileCard: some View {
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
                    .frame(width: 48, height: 48)

                Image(systemName: "person.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                if isSignedIn {
                    Text(accountEmail ?? "Inunity Account")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(red: 0.13, green: 0.77, blue: 0.37))
                            .frame(width: 7, height: 7)
                        Text("Connected to Inunity Cloud")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Guest Mode")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Offline on-device checkout")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSignedIn {
                Button("Sign Out") {
                    signOutIsPresented = true
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
            } else {
                Button { router.push(.sync) } label: {
                    Text("Sign In")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
        )
    }

    private var syncCard: some View {
        Button { router.push(.sync) } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: sync.syncIssue == nil ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(sync.syncIssue == nil ? .blue : .orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync & Wallet Capture")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let syncIssue = sync.syncIssue {
                        Text(syncIssue.message)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else if let lastSyncedAt = sync.lastSyncedAt {
                        Text("Last synced: \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Sync wallet state and cap progress across devices")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var ambientCard: some View {
        Button { router.push(.ambientSetup) } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(environment.ambientEnabled ? Color.green.opacity(0.14) : Color.gray.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: environment.ambientEnabled ? "location.circle.fill" : "location.circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(environment.ambientEnabled ? .green : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Arrival Alerts")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(environment.ambientEnabled ? "Active" : "Off")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(environment.ambientEnabled ? Color(red: 0.13, green: 0.77, blue: 0.37) : Color.gray, in: Capsule())
                    }

                    Text(environment.ambientEnabled
                         ? "\(environment.ambientDiagnostics.fired) fired · \(environment.ambientDiagnostics.suppressed) suppressed (last 7d)"
                         : "Set up automatic on-device store arrival alerts")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var walletAndDataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preferences & Privacy")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                // Edit Wallet Cards
                Button { router.push(.walletSetup) } label: {
                    preferenceRow(
                        icon: "creditcard",
                        iconColor: .blue,
                        title: "Edit Cards & Account Setup",
                        subtitle: "Configure cards, Tangerine categories, and default preferences"
                    )
                }
                .buttonStyle(.plain)

                // Privacy Policy Link
                Link(destination: Self.privacyPolicyURL) {
                    preferenceRow(
                        icon: "hand.raised.fill",
                        iconColor: .purple,
                        title: "Privacy Policy",
                        subtitle: "How on-device data and optional cloud sync are handled"
                    )
                }
                .buttonStyle(.plain)

                // Erase Local History
                Button {
                    eraseIsPresented = true
                } label: {
                    preferenceRow(
                        icon: "trash",
                        iconColor: .orange,
                        title: "Erase On-Device History",
                        subtitle: didErase ? "Erased successfully" : "Clear predictions, confirmations and cached locations"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func preferenceRow(
        icon: String,
        iconColor: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
        )
    }
}
