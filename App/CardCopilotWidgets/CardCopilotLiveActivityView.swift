import SwiftUI
import WidgetKit
import ActivityKit
import CardCopilotEngine

/// SwiftUI Live Activity and Dynamic Island view presentations for PickMe checkout advice.
public struct CardCopilotLiveActivityView: View {
    let context: ActivityViewContext<CardCopilotActivityAttributes>

    public init(context: ActivityViewContext<CardCopilotActivityAttributes>) {
        self.context = context
    }

    public var body: some View {
        lockScreenBanner
    }

    private var lockScreenBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: context.state.categoryIcon.isEmpty ? "creditcard.fill" : context.state.categoryIcon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(context.attributes.merchantName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(context.state.categoryDisplayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // A `presence` state reached the Lock Screen precisely because the merchant could
                // not be identified. It carries no card, and must not invent one.
                if context.state.tier == .presence {
                    Text(String(localized: "ambient.activity.presence.body",
                                defaultValue: "Tap to tell PickMe which shop this is."))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 6) {
                        Text("Pay with")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(context.state.recommendedCardName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                    }
                }

                if !context.state.multiplierHeadline.isEmpty {
                    Text(context.state.multiplierHeadline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.teal)
                }
            }

            Spacer()

            if !context.state.advantageDescription.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.state.advantageDescription)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("advantage")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
    }
}
