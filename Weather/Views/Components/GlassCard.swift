//
//  GlassCard.swift
//  Weather
//
//  Shared Liquid Glass container + small typographic helpers for a classy,
//  editorial feel (serif display type over frosted glass).
//

import SwiftUI

/// A soft, clean translucent panel — a quiet tint over the sky with a hairline
/// edge. Deliberately flat (no heavy glass blur) so it reads as paper laid on
/// the gradient rather than a floating glass slab.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 26
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        // Box removed: content sits directly on the sky — no frosted panel,
        // border, shadow, or inset — aligned to the screen's margin.
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Circular icon button finished in the same frosted card material — a frosted
/// base, a top-lit white tint, and a gradient rim-light — so the top-bar controls
/// read as part of the same family as the cards.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .light)
                        .opacity(0.18)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.20), .white.opacity(0.05)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .white.opacity(0.08)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            )
            .clipShape(Circle())
            .shadow(color: .black.opacity(configuration.isPressed ? 0.10 : 0.18),
                    radius: configuration.isPressed ? 4 : 8,
                    y: configuration.isPressed ? 2 : 4)
            .overlay {
                // Pressed-in look: a bright rim around a darker well, so the
                // surface reads as concave — like a physical button pushed in.
                // It fades in quickly under the finger and is confined to the
                // button itself (nothing changes outside the circle).
                GeometryReader { geo in
                    let r = min(geo.size.width, geo.size.height) / 2
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: .black.opacity(0.16), location: 0.0),
                                    .init(color: .black.opacity(0.06), location: 0.5),
                                    .init(color: .clear, location: 0.74),
                                    .init(color: .white.opacity(0.20), location: 1.0)
                                ],
                                center: .center, startRadius: 0, endRadius: r
                            )
                        )
                }
                .opacity(configuration.isPressed ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            }
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.5),
                       value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.85),
                             trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// Editorial section header: a small-caps tracked title with a leading symbol.
struct CardLabel: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .medium))
            Text(title.uppercased())
                .font(.system(.caption, weight: .medium))
                .tracking(2.0)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.bottom, 4)
    }
}

// MARK: - Serif typography (Instrument Serif)

extension Font {
    /// Instrument Serif at an explicit point size, scaling for Dynamic Type
    /// relative to the given text style.
    static func serif(size: CGFloat, relativeTo style: Font.TextStyle = .body,
                      italic: Bool = false) -> Font {
        .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular",
                size: size, relativeTo: style)
    }

    /// Instrument Serif sized to match a Dynamic Type text style.
    static func serif(_ style: Font.TextStyle, italic: Bool = false) -> Font {
        serif(size: pointSize(for: style), relativeTo: style, italic: italic)
    }

    private static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:  34
        case .title:       28
        case .title2:      22
        case .title3:      20
        case .headline:    17
        case .body:        17
        case .callout:     16
        case .subheadline: 15
        case .footnote:    13
        case .caption:     12
        case .caption2:    11
        @unknown default:  17
        }
    }
}

extension View {
    /// Serif display style used for temperatures, day names, and headlines.
    /// (Instrument Serif is single-weight, so `weight` is accepted for call-site
    /// compatibility but has no visual effect.)
    func serifDisplay(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        self.font(.serif(size: size))
    }
}

/// Previously added a soft shadow under white type; now a no-op for a flatter,
/// cleaner look (kept so call sites don't need to change).
struct SkyReadable: ViewModifier {
    func body(content: Content) -> some View { content }
}

extension View {
    func skyReadable() -> some View { modifier(SkyReadable()) }
}
