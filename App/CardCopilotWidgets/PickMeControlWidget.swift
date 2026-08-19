import WidgetKit
import SwiftUI
import AppIntents

/// iOS 18+ Control Center & Lock Screen Quick Action button for PickMe.
@available(iOS 18.0, *)
public struct PickMeControlWidget: ControlWidget {
    public static let kind: String = "PickMeControlWidget"

    public init() {}

    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: WhichCardIntent()) {
                Label("PickMe Card", systemImage: "creditcard.fill")
            }
        }
        .displayName("Which Card?")
        .description("Instantly ask PickMe which card to use at checkout.")
    }
}
