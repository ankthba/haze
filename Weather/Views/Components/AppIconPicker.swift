//
//  AppIconPicker.swift
//  Weather
//
//  Alternate home-screen icons: the wordmark under each of the app's own sky
//  palettes. A Settings row of four swatches, current one ringed.
//

import SwiftUI
import UIKit

enum AppIconOption: String, CaseIterable, Identifiable {
    case day, dusk, night, dawn

    var id: String { rawValue }

    /// nil = the primary icon; anything else is an alternate asset name.
    var assetName: String? {
        switch self {
        case .day:   nil
        case .dusk:  "AppIconDusk"
        case .night: "AppIconNight"
        case .dawn:  "AppIconDawn"
        }
    }

    var label: String {
        switch self {
        case .day: "Day"
        case .dusk: "Dusk"
        case .night: "Night"
        case .dawn: "Dawn"
        }
    }

    /// Swatch colours mirroring SkyPalette's phases, so the picker reads as the
    /// app's own sky even before the icon changes.
    var swatch: [Color] {
        let hexes: [UInt]
        switch self {
        case .day:   hexes = SkyPalette.clearPalette(.day)
        case .dusk:  hexes = SkyPalette.clearPalette(.dusk)
        case .night: hexes = SkyPalette.clearPalette(.night)
        case .dawn:  hexes = SkyPalette.clearPalette(.dawn)
        }
        return hexes.map { Color(hex: $0) }
    }

    static var current: AppIconOption {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.assetName == name } ?? .day
    }
}

struct AppIconPicker: View {
    @State private var selection = AppIconOption.current
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ForEach(AppIconOption.allCases) { option in
                    Button {
                        Haptics.tap()
                        apply(option)
                    } label: {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: option.swatch,
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(height: 54)
                            .overlay(
                                Text("haze")
                                    .font(.serif(size: 17, weight: .medium))
                                    .foregroundStyle(.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(.white.opacity(selection == option ? 0.95 : 0.2),
                                                  lineWidth: selection == option ? 2 : 0.8)
                            )
                            .accessibilityLabel("\(option.label) icon")
                            .accessibilityAddTraits(selection == option ? [.isSelected] : [])
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(failed
                 ? "This icon couldn't be set."
                 : "Choose the sky the app wears on your home screen.")
                .font(.serif(.caption))
                .foregroundStyle(.white.opacity(0.75))
        }
        .onAppear { selection = AppIconOption.current }
    }

    private func apply(_ option: AppIconOption) {
        guard option != selection else { return }
        // Nothing to do if the device doesn't support alternates.
        guard UIApplication.shared.supportsAlternateIcons else {
            failed = true
            return
        }
        UIApplication.shared.setAlternateIconName(option.assetName) { error in
            Task { @MainActor in
                if error == nil {
                    selection = option
                    failed = false
                } else {
                    failed = true
                }
            }
        }
    }
}
