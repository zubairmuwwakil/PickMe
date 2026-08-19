import ActivityKit
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
        public var timestamp: Date

        public init(recommendedCardName: String,
                    recommendedCardId: String,
                    multiplierHeadline: String,
                    advantageDescription: String,
                    categoryDisplayName: String,
                    categoryIcon: String,
                    isFork: Bool = false,
                    timestamp: Date = Date()) {
            self.recommendedCardName = recommendedCardName
            self.recommendedCardId = recommendedCardId
            self.multiplierHeadline = multiplierHeadline
            self.advantageDescription = advantageDescription
            self.categoryDisplayName = categoryDisplayName
            self.categoryIcon = categoryIcon
            self.isFork = isFork
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
