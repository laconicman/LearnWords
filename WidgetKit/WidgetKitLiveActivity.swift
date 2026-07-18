//
//  WidgetKitLiveActivity.swift
//  WidgetKit
//
//  Created by Paul Buktab on 7/18/26.
//  Copyright © 2026 Paul. All rights reserved.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct WidgetKitAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct WidgetKitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WidgetKitAttributes.self) { context in
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

extension WidgetKitAttributes {
    fileprivate static var preview: WidgetKitAttributes {
        WidgetKitAttributes(name: "World")
    }
}

extension WidgetKitAttributes.ContentState {
    fileprivate static var smiley: WidgetKitAttributes.ContentState {
        WidgetKitAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: WidgetKitAttributes.ContentState {
         WidgetKitAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: WidgetKitAttributes.preview) {
   WidgetKitLiveActivity()
} contentStates: {
    WidgetKitAttributes.ContentState.smiley
    WidgetKitAttributes.ContentState.starEyes
}
