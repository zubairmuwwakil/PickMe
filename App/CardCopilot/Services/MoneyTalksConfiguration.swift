import Foundation

/// Owner-supplied deployment values. Leave these as `nil` until the dedicated MoneyTalks Clerk
/// application is ready; checkout intentionally remains fully functional in that state.
enum MoneyTalksConfiguration {
    static let apiBaseURL: URL? = URL(string: "https://moneytalks.zubairmuwwakil.com/")
    static let clerkPublishableKey: String? = "pk_live_Y2xlcmsubW9uZXl0YWxrcy56dWJhaXJtdXd3YWtpbC5jb20k"

    static var isConfigured: Bool {
        apiBaseURL != nil && clerkPublishableKey?.hasPrefix("pk_") == true
    }
}
