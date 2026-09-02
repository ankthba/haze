//
//  MacRadarWindow.swift
//  HazeMac
//
//  The radar in a window of its own, so it can sit beside the forecast or fill
//  a display. It follows whichever place the main window is showing; changing
//  city restarts the timeline for the new one.
//

import SwiftUI

struct MacRadarWindow: View {
    let viewModel: WeatherViewModel

    var body: some View {
        Group {
            if let bundle = viewModel.bundle {
                RadarView(place: bundle.place,
                          timezone: bundle.timezone,
                          accent: bundle.current.condition.accent,
                          isDay: bundle.current.isDay)
                    .id(bundle.place.id)
            } else {
                ZStack {
                    Color(hex: 0x0A0E14).ignoresSafeArea()
                    Text("Open a forecast first.")
                        .font(.serif(.title3, italic: true))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .preferredColorScheme(.dark)
    }
}

/// The Settings scene: the same page as the iPhone's, in a window that ⌘,
/// opens. Scrolling content has no size of its own, so the window is told one.
struct MacSettingsWindow: View {
    let viewModel: WeatherViewModel

    var body: some View {
        SettingsView(viewModel: viewModel)
            .frame(minWidth: 540, idealWidth: 600, minHeight: 620, idealHeight: 820)
            .preferredColorScheme(.dark)
    }
}
