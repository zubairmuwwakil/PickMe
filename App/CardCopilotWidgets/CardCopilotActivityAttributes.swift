import ActivityKit
import CardCopilotEngine
import Foundation

/// Activity attributes describing a checkout recommendation Live Activity on the Lock Screen
/// and in the Dynamic Island.
public struct CardCopilotActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var recommendedCardName: String
        public var recommendedCardId: String
        public var multiplierHeadline: String
        public var advantageDescription: String
        public var categoryDisplayName: String
        public var categoryIcon: String
        public var isFork: Bool
        /// Which delivery tier produced this activity. The view needs it because a `presence`
        /// activity deliberately carries no card: it exists to say PickMe is here and to invite
        /// the owner to identify a merchant we could not resolve.
        public var tier: AmbientDeliveryTier
        public var timestamp: Date

        public init(recommendedCardName: String,
                    recommendedCardId: String,
                    multiplierHeadline: String,
                    advantageDescription: String,
                    categoryDisplayName: String,
                    categoryIcon: String,
                    isFork: Bool = false,
                    tier: AmbientDeliveryTier = .interrupt,
                    timestamp: Date = Date()) {
            self.recommendedCardName = recommendedCardName
            self.recommendedCardId = recommendedCardId
            self.multiplierHeadline = multiplierHeadline
            self.advantageDescription = advantageDescription
            self.categoryDisplayName = categoryDisplayName
            self.categoryIcon = categoryIcon
            self.isFork = isFork
            self.tier = tier
            self.timestamp = timestamp
        }
    }

    public var merchantName: String
    public var merchantLocation: String?

    public init(merchantName: String, merchantLocation: String? = nil) {
        self.merchantName = merchantName
        self.merchantLocation = merchantLocation
    }
}
