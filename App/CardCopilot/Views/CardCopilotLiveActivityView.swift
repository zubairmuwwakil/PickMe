import SwiftUI
import WidgetKit
import ActivityKit

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

                HStack(spacing: 6) {
                    Text("Pay with")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(context.state.recommendedCardName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
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
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
    }
}
