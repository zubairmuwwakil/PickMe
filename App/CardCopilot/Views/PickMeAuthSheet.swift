import SwiftUI
import ClerkKit
import ClerkKitUI

/// One authentication flow for onboarding, account settings, and sync.
/// Clerk owns credentials, verification, recovery, and dismissal after completion.
struct PickMeAuthSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var theme = ClerkTheme(
        colors: .init(primary: .blue, primaryForeground: .white, ring: .blue),
        design: .init(borderRadius: 14)
    )

    var body: some View {
        Group {
            if MoneyTalksConfiguration.isConfigured {
                AuthView(mode: .signInOrUp)
                    .clerkAppIconView { brandHeader }
                    .environment(\.clerkTheme, theme)
            } else {
                ContentUnavailableView(
                    "Sign-in unavailable",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("You can still use PickMe without an account.")
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Authentication stays optional while account requirements are pending.
            // Only an active session can dismiss this flow as a successful sign-in.
            if !ClerkSession.isSignedIn {
                guestFooter
            }
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ChipMascotView(
                    mood: .idle,
                    size: 40,
                    isWaving: true,
                    enable3DTilt: true
                )
                .accessibilityHidden(true)

                Image(systemName: "creditcard.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)

                Text("PickMe")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.blue)
            }

            Text("Sync PickMe with your In Unity account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    private var guestFooter: some View {
        VStack(spacing: 4) {
            Button("Not now") {
                dismiss()
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)

            Text("You can use PickMe without an account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(.background)
    }
}
