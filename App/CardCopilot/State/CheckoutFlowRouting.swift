import Foundation
import CardCopilotStore

/// What a merchant-finding operation produced, independent of what the UI should do about it.
///
/// `CopilotSession` returns this rather than setting navigation directly. Without the split,
/// the session would have to import the router and the router would have to know about MapKit,
/// which is how the previous single object ended up owning everything.
enum FlowOutcome: Equatable {
    case found([NearbyMerchant])
    /// `query` is nil for a nearby scan, and the search text for a manual search.
    case nothingFound(query: String?)
    case locationDenied
    case failed(String)
}

/// Maps an outcome onto the step the owner should see.
///
/// Pure and free of SwiftUI on purpose, in the same spirit as `WelcomeGatewayContent.resolve`.
/// This is the decision that used to be spread across three `async` view methods.
enum CheckoutFlowRouting {
    static func step(for outcome: FlowOutcome) -> CheckoutStep {
        switch outcome {
        case .found(let merchants):
            return .confirming(merchants)
        case .nothingFound(let query):
            if let query {
                return .failed("Nothing found for “\(query)”.")
            }
            return .failed("No merchants found nearby — try manual search.")
        case .locationDenied:
            // Apple guideline 5.1.1: the manual path must stand on its own, so a declined
            // permission returns to idle rather than to an error the owner cannot clear.
            return .idle
        case .failed(let message):
            return .failed(message)
        }
    }
}
