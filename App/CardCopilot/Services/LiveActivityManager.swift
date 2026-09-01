import ActivityKit
import Foundation
import SwiftUI

/// Manages Live Activities for ambient arrivals and checkout recommendations.
@MainActor
public final class LiveActivityManager: ObservableObject {
    public static let shared = LiveActivityManager()

    @Published public private(set) var currentActivityId: String?

    private init() {}

    /// Starts a Live Activity for a merchant recommendation.
    public func startRecommendationActivity(merchantName: String,
                                           merchantLocation: String? = nil,
                                           cardName: String,
                                           cardId: String,
                                           multiplierHeadline: String,
                                           advantageDescription: String,
                                           categoryDisplayName: String,
                                           categoryIcon: String,
                                           isFork: Bool = false) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

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
            timestamp: Date()
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialContent, staleDate: Date().addingTimeInterval(15 * 60)),
                pushType: nil
            )
            currentActivityId = activity.id
        } catch {
            // Live activities request may fail if suppressed or rate-limited by OS
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
