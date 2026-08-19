//
//  CardCopilotWidgetsBundle.swift
//  CardCopilotWidgets
//
//  Created by Zubair Muwwakil on 2026-08-19.
//

import WidgetKit
import SwiftUI

@main
struct CardCopilotWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CapTrackerWidget()
        QuickRecommendWidget()
        CardCopilotLiveActivityWidget()
        #if os(iOS)
        if #available(iOS 18.0, *) {
            PickMeControlWidget()
        }
        #endif
    }
}
