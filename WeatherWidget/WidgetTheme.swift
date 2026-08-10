//
//  WidgetTheme.swift
//  WeatherWidget
//
//  Shared look for the widget: EB Garamond registration + helper, and the
//  pastel "frosted card" background that mirrors the app's GlassCard so the
//  widget reads as the same matte, dimensional surface.
//

import SwiftUI
import CoreText

// MARK: - Fonts

enum WidgetFonts {
    /// Register the bundled EB Garamond faces inside the widget process so
    /// `Font.custom` can find them (the Info.plist is auto-generated). Tries the
    /// bundle root and a `Fonts` subdirectory so it works however the resources
    /// land in the .appex.
    static func register() {
        for name in ["EBGaramondLF-Regular", "EBGaramondLF-Italic",
                     "InstrumentSerif-Regular"] {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            guard let url else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// EB Garamond (lining figures) at a fixed size (falls back to the system
    /// serif if the custom face somehow isn't registered).
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "EBGaramondLF-Italic" : "EBGaramondLF-Regular", size: size)
    }

    /// Instrument Serif, used solely for the temperature numerals to match the
    /// app's hero temperature.
    static func displaySerif(_ size: CGFloat) -> Font {
        .custom("InstrumentSerif-Regular", size: size)
    }
}

// MARK: - Pastel frosted background

/// A soft, pastel, matte rendition of the sky — the widget equivalent of the
/// app's GlassCard: the conditions gradient lightened toward white, with a
/// top-lit sheen and a faint bottom shade for a gently dimensional, 3D feel.
struct WidgetCardBackground: View {
    let hexes: [UInt]

    /// Blend a hex color toward white for a subtle, card-like softening — kept
    /// light so the widget still matches the app's actual sky colours.
    private func pastel(_ hex: UInt, _ amount: Double = 0.16) -> Color {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        return Color(.sRGB,
                     red: r + (1 - r) * amount,
                     green: g + (1 - g) * amount,
                     blue: b + (1 - b) * amount)
    }

    /// The conditions colors lightened to pastel and spread evenly as gradient
    /// stops, so the wash flows smoothly top-to-bottom.
    private var pastelStops: [Gradient.Stop] {
        let colors = hexes
        guard colors.count > 1 else {
            return [.init(color: pastel(colors.first ?? 0x6FA8DC), location: 0),
                    .init(color: pastel(colors.first ?? 0x6FA8DC), location: 1)]
        }
        var stops: [Gradient.Stop] = []
        let lastIndex = Double(colors.count - 1)
        for (i, hex) in colors.enumerated() {
            stops.append(.init(color: pastel(hex), location: Double(i) / lastIndex))
        }
        return stops
    }

    var body: some View {
        ZStack {
            // Pastel conditions gradient — the soft, washed base.
            LinearGradient(gradient: Gradient(stops: pastelStops),
                           startPoint: .top, endPoint: .bottom)

            // Whisper of a diagonal frosted sheen → a gentle 3D lift like GlassCard.
            LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.0)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            // Very soft rim of light easing far down from the top (no hard band).
            LinearGradient(stops: [
                .init(color: .white.opacity(0.16), location: 0.0),
                .init(color: .white.opacity(0.04), location: 0.22),
                .init(color: .clear, location: 0.55)
            ], startPoint: .top, endPoint: .bottom)

            // Faint shade pooling low for the gentlest depth.
            LinearGradient(stops: [
                .init(color: .clear, location: 0.7),
                .init(color: .black.opacity(0.04), location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
        }
        .saturation(0.96)
    }
}
