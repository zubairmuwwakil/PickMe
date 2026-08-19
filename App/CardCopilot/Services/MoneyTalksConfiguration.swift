import Foundation

/// Owner-supplied deployment values. Leave these as `nil` until the dedicated MoneyTalks Clerk
/// application is ready; checkout intentionally remains fully functional in that state.
enum MoneyTalksConfiguration {
    static let apiBaseURL: URL? = URL(string: "https://inunity.ca/")
    static let clerkPublishableKey: String? = "pk_live_Y2xlcmsuaW51bml0eS5jYSQ"

    static var isConfigured: Bool {
        apiBaseURL != nil && clerkPublishableKey?.hasPrefix("pk_") == true
    }
}
