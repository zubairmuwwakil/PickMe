import Foundation

/// The links a Live Activity can hand back to the app.
///
/// A Live Activity tap opens the containing app, and without a `widgetURL` it opens to whatever
/// screen the owner was last on. The `presence` tier's whole payload is the sentence "Tap to tell
/// PickMe which shop this is" — an invitation the app could not honour, because nothing routed
/// that tap anywhere. Confirming a merchant is also the highest-value tap in the app: it promotes
/// the place up the confidence ladder and unlocks every future alert there.
enum AmbientDeepLink: Equatable {
    /// Start a checkout at the current location so the owner can pick which shop they are in.
    case identifyMerchant

    private static let scheme = "pickme"

    var url: URL {
        switch self {
        case .identifyMerchant:
            return URL(string: "\(Self.scheme)://arrival/identify")!
        }
    }

    /// Parsed rather than string-matched so a malformed or third-party URL cannot drive
    /// navigation. Returns `nil` for anything this app does not own.
    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch (url.host, url.path) {
        case ("arrival", "/identify"):
            self = .identifyMerchant
        default:
            return nil
        }
    }
}
