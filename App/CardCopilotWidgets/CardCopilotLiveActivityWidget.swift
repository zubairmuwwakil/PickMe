import WidgetKit
import SwiftUI
import ActivityKit
import CardCopilotEngine

public struct CardCopilotLiveActivityWidget: Widget {
    public let kind: String = "CardCopilotLiveActivityWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: CardCopilotActivityAttributes.self) { context in
            // Lock Screen Banner presentation
            CardCopilotLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.categoryIcon.isEmpty ? "creditcard.fill" : context.state.categoryIcon)
                            .font(.headline)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.merchantName)
                                .font(.system(size: 14, weight: .bold))
                                .lineLimit(1)
                            Text(context.state.categoryDisplayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 8)
                }

                // Every card-naming region below is guarded on the tier. A `presence` state exists
                // *because* the merchant could not be identified: it carries an empty card name,
                // so rendering it unguarded left a blank slot under a "PickMe Optimal" badge —
                // a confidence claim about a shop PickMe cannot name, which is the exact failure
                // the presence tier was introduced to prevent.
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if context.state.tier == .presence {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(context.state.recommendedCardName)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.blue)
                            if !context.state.multiplierHeadline.isEmpty {
                                Text(context.state.multiplierHeadline)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.teal)
                            }
                        }
                    }
                    .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.state.tier == .presence {
                            Text(String(localized: "ambient.activity.presence.body",
                                        defaultValue: "Tap to tell PickMe which shop this is."))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        } else {
                            if !context.state.advantageDescription.isEmpty {
                                Text("\(context.state.advantageDescription) advantage vs default")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Label("PickMe Optimal", systemImage: "sparkles")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.categoryIcon.isEmpty ? "creditcard.fill" : context.state.categoryIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.blue)
            } compactTrailing: {
                if context.state.tier == .presence {
                    Image(systemName: "questionmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                } else {
                    Text(context.state.recommendedCardName.prefix(6))
                        .font(.caption.weight(.bold).monospaced())
                        .foregroundStyle(.teal)
                }
            } minimal: {
                Image(systemName: context.state.categoryIcon.isEmpty ? "creditcard.fill" : context.state.categoryIcon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.blue)
            }
            // Matches the Lock Screen banner: only `presence` has a question to route. Kept as a
            // literal because this extension cannot see `AmbientDeepLink`; `AmbientDeepLinkTests`
            // pins the string so the two cannot drift apart silently.
            .widgetURL(context.state.tier == .presence
                       ? URL(string: "pickme://arrival/identify") : nil)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}
