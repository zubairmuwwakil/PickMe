import SwiftUI
import ClerkKit
import ClerkKitUI

enum WelcomeGatewayContent: Equatable {
    case authenticationChoice
    case restoringAccount
    case accountUnavailable(String?)
    case offlineOnly

    static func resolve(isConfigured: Bool, isSignedIn: Bool,
                        isPreparingAccount: Bool, syncIssueMessage: String?) -> Self {
        guard isConfigured else { return .offlineOnly }
        guard isSignedIn else { return .authenticationChoice }
        if isPreparingAccount { return .restoringAccount }
        return .accountUnavailable(syncIssueMessage)
    }

    func shouldPresentAuthentication(requested: Bool) -> Bool {
        requested && self == .authenticationChoice
    }
}

/// The first-launch gateway: allows returning users to sign in and restore their wallet,
/// new users to create an account for cloud sync, or privacy-conscious users to continue
/// completely offline with on-device storage.
struct WelcomeGatewayView: View {
    let isSignedIn: Bool
    let isPreparingAccount: Bool
    let syncIssueMessage: String?
    let onRetryAccountRestore: () -> Void
    let onContinuePrivately: () -> Void

    @State private var authIsPresented = false

    private var gatewayContent: WelcomeGatewayContent {
        .resolve(isConfigured: MoneyTalksConfiguration.isConfigured,
                 isSignedIn: isSignedIn,
                 isPreparingAccount: isPreparingAccount,
                 syncIssueMessage: syncIssueMessage)
    }

    private var authSheetIsPresented: Binding<Bool> {
        Binding(
            get: { gatewayContent.shouldPresentAuthentication(requested: authIsPresented) },
            set: { authIsPresented = gatewayContent.shouldPresentAuthentication(requested: $0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                // Header / Hero Branding
                VStack(spacing: 14) {
                    HStack(spacing: 18) {
                        ChipMascotView(
                            mood: .idle,
                            size: 68,
                            isWaving: true,
                            enable3DTilt: true
                        )

                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color(red: 0.1, green: 0.45, blue: 0.95)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 68, height: 68)
                                .shadow(color: Color.blue.opacity(0.35), radius: 12, x: 0, y: 6)

                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.top, 20)

                    VStack(spacing: 4) {
                        Text("Welcome to PickMe")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Pick the best card for every purchase, automatically maximizing your rewards and benefits.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }

                // Value Propositions
                VStack(spacing: 16) {
                    featureRow(
                        icon: "bolt.fill",
                        iconColor: .orange,
                        title: "Smart Card Recommendations",
                        subtitle: "Instant multiplier matching, advantage math, and certificate benefits at checkout."
                    )

                    featureRow(
                        icon: "lock.shield.fill",
                        iconColor: .green,
                        title: "100% On-Device Privacy",
                        subtitle: "Calculations run locally on your iPhone. Your financial choices never leave your device unless you choose to sync."
                    )

                    featureRow(
                        icon: "arrow.triangle.2.circlepath.icloud.fill",
                        iconColor: .blue,
                        title: "Optional Cloud Sync",
                        subtitle: "Sign in to keep cap limits in sync and connect Apple Wallet transaction shortcuts across devices."
                    )
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                // Actions Section
                VStack(spacing: 14) {
                    switch gatewayContent {
                    case .authenticationChoice:
                        authenticationActions
                    case .restoringAccount:
                        restoringAccountStatus
                    case .accountUnavailable(let message):
                        accountUnavailableStatus(message: message)
                    case .offlineOnly:
                        getStartedButton
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: authSheetIsPresented) {
            PickMeAuthSheet {
                authIsPresented = false
            }
        }
        .onChange(of: isSignedIn) { _, signedIn in
            if signedIn { authIsPresented = false }
        }
    }

    private var authenticationActions: some View {
        Group {
            Button {
                guard gatewayContent.shouldPresentAuthentication(requested: true) else { return }
                authIsPresented = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                    Text("Sign In or Create Account")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            continuePrivatelyButton

            Text("No account required to use PickMe. You can sign in anytime from Settings.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    private var restoringAccountStatus: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
                Text("Loading this account's wallet")
                    .font(.headline)
                Text("You're already signed in. PickMe is restoring your saved cards.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func accountUnavailableStatus(message: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Wallet not loaded", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.headline)
            Text(message ?? "You're already signed in, but PickMe has not loaded this account's wallet yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Retry", action: onRetryAccountRestore)
                .buttonStyle(.borderedProminent)
            continuePrivatelyButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var continuePrivatelyButton: some View {
        Button {
            onContinuePrivately()
        } label: {
            HStack(spacing: 6) {
                Text("Continue Privately")
                    .font(.headline)
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var getStartedButton: some View {
        Button {
            onContinuePrivately()
        } label: {
            HStack(spacing: 6) {
                Text("Get Started")
                    .font(.headline)
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func featureRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
