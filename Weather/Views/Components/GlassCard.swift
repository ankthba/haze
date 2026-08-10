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

/// The app's signature frosted surface, defined once so every control shares
/// it: real backdrop blur clipped to the shape, a light frost, a *diagonal*
/// sheen (so wide shapes keep dimension instead of reading as a flat slab),
/// an inner shade pooling at the bottom for depth, a soft specular glow just
/// under the top rim, and a rim that catches light at the top *and* bottom
/// edges the way glass actually does.
struct GlassSurface<S: InsettableShape>: View {
    var shape: S
    /// Frost strength; prominent controls use a higher value.
    var frost: Double = 0.10
    var blurRadius: CGFloat = 12

    var body: some View {
        ZStack {
            BackdropBlurView(radius: blurRadius)
                .clipShape(shape)

            shape.fill(.ultraThinMaterial)
                .environment(\.colorScheme, .light)
                .opacity(UIPrefs.shared.reduceTransparency ? max(frost, 0.6) : frost)

            // Light falls from the top-leading corner and washes across,
            // rather than a straight top-to-bottom fade.
            shape.fill(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.16), location: 0),
                    .init(color: .white.opacity(0.05), location: 0.45),
                    .init(color: .white.opacity(0.02), location: 1)
                ], startPoint: .topLeading, endPoint: .bottom)
            )

            // Faint shade pooling along the bottom edge grounds the surface.
            // The onset is eased through intermediate stops so the shade
            // gathers imperceptibly instead of starting on a visible line.
            shape.fill(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.008), location: 0.64),
                    .init(color: .black.opacity(0.025), location: 0.76),
                    .init(color: .black.opacity(0.05), location: 0.88),
                    .init(color: .black.opacity(0.08), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            )

            // Soft specular glow just inside the top rim.
            shape.strokeBorder(.white.opacity(0.45), lineWidth: 1.2)
                .blur(radius: 1.8)
                .mask(
                    shape.fill(
                        LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .clear, location: 0.35)
                        ], startPoint: .top, endPoint: .bottom)
                    )
                )
        }
        .overlay(
            // Rim-light that wraps: brightest on top, faint along the sides,
            // and catching again along the bottom edge.
            shape.strokeBorder(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.55), location: 0),
                    .init(color: .white.opacity(0.12), location: 0.4),
                    .init(color: .white.opacity(0.10), location: 0.75),
                    .init(color: .white.opacity(0.30), location: 1)
                ], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8
            )
        )
    }
}

/// Full-sheet rendition of the signature material, for sub-page sheets: the
/// screen beneath shows through a deep blur carrying the same frost, diagonal
/// sheen, and eased bottom shade as `GlassSurface` (no rim; the sheet's own
/// rounded edges do the clipping), plus a dark scrim so white type stays
/// comfortably readable over whatever glows through.
struct GlassSheetBackground: View {
    var body: some View {
        ZStack {
            BackdropBlurView(radius: 18)

            Color.black.opacity(0.30)

            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .light)
                .opacity(UIPrefs.shared.reduceTransparency ? 0.6 : 0.10)

            LinearGradient(stops: [
                .init(color: .white.opacity(0.10), location: 0),
                .init(color: .white.opacity(0.03), location: 0.45),
                .init(color: .white.opacity(0.01), location: 1)
            ], startPoint: .topLeading, endPoint: .bottom)

            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.5),
                .init(color: .black.opacity(0.008), location: 0.64),
                .init(color: .black.opacity(0.025), location: 0.76),
                .init(color: .black.opacity(0.05), location: 0.88),
                .init(color: .black.opacity(0.08), location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// Circular icon button finished in the same frosted card material — a frosted
/// base, a top-lit white tint, and a gradient rim-light — so the top-bar controls
/// read as part of the same family as the cards.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(GlassSurface(shape: Circle()))
            .clipShape(Circle())
            .shadow(color: .black.opacity(configuration.isPressed ? 0.04 : 0.08),
                    radius: configuration.isPressed ? 6 : 12,
                    y: configuration.isPressed ? 1 : 2)
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

/// Small "Open ↗" affordance for a card header, signalling the card opens a
/// fuller page when tapped. Pairs with `CardLabel` in an `HStack`.
struct OpenBadge: View {
    var label: String = "Open"

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
            Image(systemName: "arrow.up.right")
        }
        .font(.serif(.caption, weight: .semibold))
        .foregroundStyle(.white.opacity(0.6))
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
            Text(title)
                .font(.serif(.footnote, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.bottom, 4)
    }
}

// MARK: - Serif typography (EB Garamond, lining figures)

extension Font {
    /// EB Garamond at an explicit point size, scaling for Dynamic Type
    /// relative to the given text style. The bundled faces have lining
    /// figures frozen in ("LF") so numerals sit full-height.
    static func serif(size: CGFloat, relativeTo style: Font.TextStyle = .body,
                      italic: Bool = false, weight: Font.Weight = .regular) -> Font {
        .custom(faceName(italic: italic, weight: weight),
                size: size, relativeTo: style)
    }

    /// EB Garamond sized to match a Dynamic Type text style.
    static func serif(_ style: Font.TextStyle, italic: Bool = false,
                      weight: Font.Weight = .regular) -> Font {
        serif(size: pointSize(for: style), relativeTo: style,
              italic: italic, weight: weight)
    }

    private static func faceName(italic: Bool, weight: Font.Weight) -> String {
        if italic { return "EBGaramondLF-Italic" }
        var weight = weight
        // Accessibility Bold Text: everything steps up one weight. (Reading the
        // observable here registers a dependency in any body that uses .serif.)
        if UIPrefs.shared.boldText {
            weight = weight == .regular ? .medium : .semibold
        }
        if weight == .semibold || weight == .bold || weight == .heavy || weight == .black {
            return "EBGaramondLF-SemiBold"
        }
        if weight == .medium { return "EBGaramondLF-Medium" }
        return "EBGaramondLF-Regular"
    }

    /// Instrument Serif, kept solely for oversized display numerals (the hero
    /// temperature) where Garamond's proportions feel too bookish.
    static func displaySerif(size: CGFloat) -> Font {
        .custom("InstrumentSerif-Regular", size: size, relativeTo: .largeTitle)
    }

    /// Garamond's x-height runs ~15% smaller than the system font's, so these
    /// sizes are scaled up from the system defaults for optical parity — a
    /// Garamond caption should *read* as large as an SF caption, not measure
    /// the same.
    private static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:  36
        case .title:       30
        case .title2:      24
        case .title3:      21
        case .headline:    19
        case .body:        19
        case .callout:     17
        case .subheadline: 16
        case .footnote:    14
        case .caption:     13
        case .caption2:    12
        @unknown default:  19
        }
    }
}

extension View {
    /// Serif display style used for temperatures, day names, and headlines.
    func serifDisplay(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        self.font(.serif(size: size, weight: weight))
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
