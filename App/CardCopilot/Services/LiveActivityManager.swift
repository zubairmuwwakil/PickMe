import ActivityKit
import CardCopilotEngine
import Foundation
import SwiftUI

/// Tells the owner's "not now" apart from our own cleanup.
///
/// Extracted from the observer so it can be tested: `Activity` cannot be constructed in a test
/// process, but this decision is the part that was wrong.
enum LiveActivityDismissalPolicy {
    /// `.ended` and `.dismissed` are sequential states, not alternatives. `.ended` means the
    /// activity is over but still on screen; `.dismissed` means it is no longer on screen. Our own
    /// `endActivity(dismissalPolicy: .immediate)` therefore walks `.active → .ended → .dismissed`
    /// in about a second, as does a system expiry — so watching for `.dismissed` alone counts
    /// every geofence exit and every activity swap as a swipe the owner never made.
    ///
    /// Having seen `.ended` first is what distinguishes those from a swipe of a live card. The
    /// cost is that swiping an already-ended card is not recorded; that is the generous direction,
    /// and it is unobservable anyway once iOS has terminated the process.
    static func isOwnerDismissal(after observed: [ActivityState],
                                 observing state: ActivityState) -> Bool {
        state == .dismissed && !observed.contains(.ended)
    }
}

/// Records acceptance of a request, never a claim that the owner saw the activity.
public enum LiveActivityRequestOutcome: String, Codable, Sendable {
    case notRequested, accepted, disabled, dismissed, failed
}

/// Manages Live Activities for ambient arrivals and checkout recommendations.
@MainActor
public final class LiveActivityManager: ObservableObject {
    public static let shared = LiveActivityManager()

    @Published public private(set) var currentActivityId: String?

    /// The region whose visit owns the activity on screen, so a dismissal can be attributed.
    private var visitKey: String?

    /// Called on the main actor with the visit key when the owner swipes the card away.
    /// `AmbientLocationService` wires this to `AmbientVisitStore`.
    public var onDismissal: (@MainActor (String) -> Void)?

    private init() {}

    /// Starts a Live Activity for a merchant recommendation.
    @discardableResult
    public func startRecommendationActivity(merchantName: String,
                                           merchantLocation: String? = nil,
                                           cardName: String,
                                           cardId: String,
                                           multiplierHeadline: String,
                                           advantageDescription: String,
                                           categoryDisplayName: String,
                                           categoryIcon: String,
                                           isFork: Bool = false,
                                           tier: AmbientDeliveryTier = .interrupt,
                                           visitKey: String? = nil) -> LiveActivityRequestOutcome {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .disabled }

        // Ask the system, not this object: after a background relaunch `currentActivityId` is nil
        // while a real activity is still on the Lock Screen, and trusting it stacks a second card.
        if !Activity<CardCopilotActivityAttributes>.activities.isEmpty {
            endActivity()
        }

        let attributes = CardCopilotActivityAttributes(
            merchantName: merchantName,
            merchantLocation: merchantLocation
        )
        let initialContent = CardCopilotActivityAttributes.ContentState(
            recommendedCardName: cardName,
            recommendedCardId: cardId,
            multiplierHeadline: multiplierHeadline,
            advantageDescription: advantageDescription,
            categoryDisplayName: categoryDisplayName,
            categoryIcon: categoryIcon,
            isFork: isFork,
            tier: tier,
            timestamp: Date()
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialContent, staleDate: Date().addingTimeInterval(15 * 60)),
                pushType: nil
            )
            currentActivityId = activity.id
            self.visitKey = visitKey
            observeDismissal(of: activity, visitKey: visitKey)
            return .accepted
        } catch {
            return .failed
        }
    }

    /// Reports the owner swiping this activity away, and nothing else. See
    /// `LiveActivityDismissalPolicy` for why the whole state sequence has to be considered rather
    /// than just the arrival of `.dismissed`.
    ///
    /// This can only observe a dismissal while the process is alive. If iOS terminated the app
    /// first, the activity simply disappears from `Activity.activities` exactly as an ended one
    /// does, and the dismissal is unobservable — callers must treat "no flag" as "unknown",
    /// never as "not dismissed".
    private func observeDismissal(of activity: Activity<CardCopilotActivityAttributes>,
                                  visitKey: String?) {
        guard let visitKey else { return }
        Task { [weak self] in
            var observed: [ActivityState] = []
            for await state in activity.activityStateUpdates {
                if LiveActivityDismissalPolicy.isOwnerDismissal(after: observed, observing: state) {
                    await MainActor.run { self?.onDismissal?(visitKey) }
                    return
                }
                observed.append(state)
                if state == .dismissed { return }
            }
        }
    }

    /// Updates the current Live Activity with new state.
    public func updateActivity(cardName: String,
                               cardId: String,
                               multiplierHeadline: String,
                               advantageDescription: String,
                               categoryDisplayName: String,
                               categoryIcon: String,
                               isFork: Bool = false) {
        let updatedState = CardCopilotActivityAttributes.ContentState(
            recommendedCardName: cardName,
            recommendedCardId: cardId,
            multiplierHeadline: multiplierHeadline,
            advantageDescription: advantageDescription,
            categoryDisplayName: categoryDisplayName,
            categoryIcon: categoryIcon,
            isFork: isFork,
            timestamp: Date()
        )

        // Activity is not Sendable. Looking it up inside the detached task keeps the instance in
        // one isolation region instead of transferring a main-actor property into ActivityKit's
        // nonisolated async API (an error under the Swift 6.2 compiler in Xcode 26.6).
        Task.detached {
            guard let activity = Activity<CardCopilotActivityAttributes>.activities.first else {
                return
            }
            await activity.update(
                .init(state: updatedState, staleDate: Date().addingTimeInterval(15 * 60))
            )
        }
    }

    /// Ends every activity this app owns, whether or not this process started it.
    ///
    /// `currentActivityId` cannot be trusted here: the entry wake and the exit wake are separate
    /// process launches, and ActivityKit — not this object — owns the activity across them. The
    /// previous in-memory guard returned early after a relaunch and orphaned the card.
    public func endActivity(dismissalPolicy: ActivityUIDismissalPolicy = .immediate) {
        // Snapshot the IDs before detaching. `startRecommendationActivity` requests its
        // replacement immediately after this call; enumerating without a snapshot inside the
        // detached task could end that newly requested activity as well as the stale ones.
        let activityIDs = Set(Activity<CardCopilotActivityAttributes>.activities.map(\.id))
        currentActivityId = nil
        guard !activityIDs.isEmpty else { return }

        Task.detached {
            for activity in Activity<CardCopilotActivityAttributes>.activities
            where activityIDs.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: dismissalPolicy)
            }
        }
    }
}
