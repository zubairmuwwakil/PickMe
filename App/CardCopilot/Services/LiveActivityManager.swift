import ActivityKit
import Foundation
import SwiftUI

/// Manages Live Activities for ambient arrivals and checkout recommendations.
@MainActor
public final class LiveActivityManager: ObservableObject {
    public static let shared = LiveActivityManager()

    @Published public private(set) var currentActivityId: String?

    private var currentActivity: Activity<CardCopilotActivityAttributes>?

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

        // End any existing activity first
        if currentActivity != nil {
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
            currentActivity = activity
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
        guard let currentActivity else { return }
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

        Task {
            await currentActivity.update(
                .init(state: updatedState, staleDate: Date().addingTimeInterval(15 * 60))
            )
        }
    }

    /// Ends the current Live Activity.
    public func endActivity(dismissalPolicy: ActivityUIDismissalPolicy = .immediate) {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: dismissalPolicy)
        }
        self.currentActivity = nil
        self.currentActivityId = nil
    }
}
