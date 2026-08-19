//
//  Pick_MeLiveActivity.swift
//  Pick Me
//
//  Created by Zubair Muwwakil on 2026-08-19.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct Pick_MeAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct Pick_MeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Pick_MeAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension Pick_MeAttributes {
    fileprivate static var preview: Pick_MeAttributes {
        Pick_MeAttributes(name: "World")
    }
}

extension Pick_MeAttributes.ContentState {
    fileprivate static var smiley: Pick_MeAttributes.ContentState {
        Pick_MeAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: Pick_MeAttributes.ContentState {
         Pick_MeAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: Pick_MeAttributes.preview) {
   Pick_MeLiveActivity()
} contentStates: {
    Pick_MeAttributes.ContentState.smiley
    Pick_MeAttributes.ContentState.starEyes
}
