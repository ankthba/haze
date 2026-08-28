//
//  WeatherWidgetBundle.swift
//  WeatherWidget
//

import WidgetKit
import SwiftUI

@main
struct WeatherWidgetBundle: WidgetBundle {
    init() { WidgetFonts.register() }

    var body: some Widget {
        WeatherWidget()
        RainLiveActivity()
    }
}
