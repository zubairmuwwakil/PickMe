import WidgetKit
import SwiftUI
import ActivityKit

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

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.recommendedCardName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                        if !context.state.multiplierHeadline.isEmpty {
                            Text(context.state.multiplierHeadline)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.teal)
                        }
                    }
                    .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if !context.state.advantageDescription.isEmpty {
                            Text("\(context.state.advantageDescription) advantage vs default")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Text("Tap to pay")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.categoryIcon.isEmpty ? "creditcard.fill" : context.state.categoryIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.state.recommendedCardName.prefix(6))
                    .font(.caption.weight(.bold).monospaced())
                    .foregroundStyle(.teal)
            } minimal: {
                Image(systemName: "creditcard.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.blue)
            }
        }
    }
}
