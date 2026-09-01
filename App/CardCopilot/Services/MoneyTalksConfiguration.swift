import CardCopilotStore
import ClerkKit
import Foundation
import Security

/// Clerk persists its session in Keychain during `configure`. In a simulator artifact built with
/// signing disabled, that call traps inside ClerkKit with `errSecMissingEntitlement` before PickMe
/// can show even its offline checkout. Probe the same capability first and keep that build in the
/// supported offline-only mode instead of launching a dependency that cannot initialize.
enum ClerkStartupPolicy {
    static func permitsConfiguration(for keychainStatus: OSStatus) -> Bool {
        keychainStatus == errSecSuccess || keychainStatus == errSecItemNotFound
    }

    static func keychainStatus() -> OSStatus {
        let service = "\(Bundle.main.bundleIdentifier ?? "ca.pickme.cardcopilot").clerk-startup-probe"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "availability",
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil)
    }
}

/// Owner-supplied deployment values. Leave these as `nil` until the dedicated MoneyTalks Clerk
/// application is ready; checkout intentionally remains fully functional in that state.
enum MoneyTalksConfiguration {
    static let apiBaseURL: URL? = URL(string: "https://inunity.ca/")
    static let clerkPublishableKey: String? = "pk_live_Y2xlcmsuaW51bml0eS5jYSQ"

    /// Evaluated once for the process. A missing entitlement cannot heal without installing a new
    /// build, while a valid signed build should not repeatedly hit Keychain during view rendering.
    private static let hasUsableKeychain = ClerkStartupPolicy.permitsConfiguration(
        for: ClerkStartupPolicy.keychainStatus())

    static var isConfigured: Bool {
        apiBaseURL != nil && clerkPublishableKey?.hasPrefix("pk_") == true && hasUsableKeychain
    }
}

/// The only safe way to read the signed-in account.
///
/// `Clerk.shared` is a landmine: it calls `fatalError` rather than returning `nil` when
/// `Clerk.configure` was never called. `CardCopilotApp.init` only configures Clerk when
/// `MoneyTalksConfiguration.isConfigured`, and that is false whenever the Keychain probe fails —
/// which is every `CODE_SIGNING_ALLOWED=NO` build, including the whole `xcodebuild test` suite.
/// Reading `Clerk.shared` directly therefore killed the test host before a single test ran, and
/// would trap any owner running an offline-only build the moment one of these paths was touched.
///
/// `nil` here means "no signed-in account", which is the honest answer for an unconfigured build:
/// checkout is designed to work fully signed out, so every caller already handles it.
@MainActor
enum ClerkSession {
    static var currentUserID: String? {
        guard MoneyTalksConfiguration.isConfigured else { return nil }
        return Clerk.shared.user?.id
    }

    static var currentUser: User? {
        guard MoneyTalksConfiguration.isConfigured else { return nil }
        return Clerk.shared.user
    }

    static var isSignedIn: Bool { currentUserID != nil }

    /// Token provider for `MoneyTalksAPIClient`. Throws instead of trapping when Clerk is absent,
    /// so an unconfigured build fails the request rather than the process.
    static func token() async throws -> String? {
        guard MoneyTalksConfiguration.isConfigured else {
            throw MoneyTalksAPIError.unavailableConfiguration
        }
        return try await Clerk.shared.auth.getToken()
    }
}
