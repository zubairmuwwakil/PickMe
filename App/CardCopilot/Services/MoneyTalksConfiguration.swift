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
