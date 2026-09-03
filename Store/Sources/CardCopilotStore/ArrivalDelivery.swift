import Foundation

/// What actually became of an arrival notification, between the gate approving one and
/// Notification Center holding it.
///
/// The app previously recorded one bit — "iOS accepted the request" — which cannot separate three
/// very different failures: the app never asked, iOS refused, and iOS accepted and the alert never
/// appeared. Those call for three different fixes, and the ambiguity between them is what opened
/// this investigation.
public enum ArrivalNotificationDelivery: String, Equatable, Sendable, Codable {
    /// The gate did not reach `.interrupt`. Nothing was asked of iOS — a policy decision, not a
    /// delivery failure, and counting it as one would blame the plumbing for the gate.
    case neverRequested
    /// `UNUserNotificationCenter.add` threw. The app asked and was refused.
    case requestFailed
    /// iOS accepted the request and the notification was not in Notification Center when sampled.
    /// **The outcome nothing could previously see.**
    case acceptedThenAbsent
    /// iOS accepted the request and the notification was there when sampled. The only outcome in
    /// which the owner had a real chance to see the alert.
    case acceptedAndPresent
}

/// Classifies one arrival's notification against what Notification Center is holding.
///
/// Pure and separate from the sampling, because the sampling needs `UNUserNotificationCenter` and
/// the classification is the part with four branches worth pinning.
///
/// A throw is checked before the identifier: if both are somehow present the request did not
/// succeed, and reading the identifier first would report a delivery that never happened.
public func arrivalNotificationDelivery(requestIdentifier: String?,
                                        requestFailed: Bool,
                                        deliveredIdentifiers: Set<String>)
-> ArrivalNotificationDelivery {
    if requestFailed { return .requestFailed }
    guard let requestIdentifier else { return .neverRequested }
    return deliveredIdentifiers.contains(requestIdentifier)
        ? .acceptedAndPresent : .acceptedThenAbsent
}
