import Foundation

/// Owner-supplied deployment values. Leave these as `nil` until the dedicated MoneyTalks Clerk
/// application is ready; checkout intentionally remains fully functional in that state.
enum MoneyTalksConfiguration {
    static let apiBaseURL: URL? = nil
    static let clerkPublishableKey: String? = nil

    static var isConfigured: Bool {
        apiBaseURL != nil && clerkPublishableKey?.hasPrefix("pk_") == true
    }
}
