//
//  VariableBlur.swift
//  Weather
//
//  A true progressive (variable-radius) blur of whatever sits behind the view —
//  the same `variableBlur` CAFilter the system uses for its soft scroll/toolbar
//  edges. The blur radius ramps along a gradient so content genuinely refracts
//  and dissolves into the background instead of being cut off by a hard line or
//  covered by a flat frosted scrim.
//

import SwiftUI
import UIKit

struct VariableBlurView: UIViewRepresentable {
    /// The edge the blur is strongest at; it fades to sharp toward the opposite side.
    enum Direction: Hashable { case top, bottom, leading, trailing }

    var maxRadius: CGFloat = 16
    var direction: Direction = .bottom

    func makeUIView(context: Context) -> VariableBlurUIView {
        VariableBlurUIView(maxRadius: maxRadius, direction: direction)
    }

    func updateUIView(_ uiView: VariableBlurUIView, context: Context) {
        uiView.update(maxRadius: maxRadius, direction: direction)
    }
}

final class VariableBlurUIView: UIVisualEffectView {
    private var maxRadius: CGFloat
    private var direction: VariableBlurView.Direction

    init(maxRadius: CGFloat, direction: VariableBlurView.Direction) {
        self.maxRadius = maxRadius
        self.direction = direction
        super.init(effect: UIBlurEffect(style: .regular))
        isUserInteractionEnabled = false
        applyFilter()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(maxRadius: CGFloat, direction: VariableBlurView.Direction) {
        guard maxRadius != self.maxRadius || direction != self.direction else { return }
        self.maxRadius = maxRadius
        self.direction = direction
        applyFilter()
    }

    private func applyFilter() {
        // The system's variable-blur filter lives on CAFilter.
        guard
            let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
            let variableBlur = filterClass.perform(NSSelectorFromString("filterWithType:"),
                                                   with: "variableBlur")?
                .takeUnretainedValue() as? NSObject,
            let mask = Self.gradientMask(direction: direction)
        else { return }

        variableBlur.setValue(maxRadius, forKey: "inputRadius")
        variableBlur.setValue(mask, forKey: "inputMaskImage")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")

        // Drive the backdrop layer with the variable blur, and drop the tint/vibrancy
        // subviews so we get a clean blur with no gray wash over the content.
        if let backdropLayer = subviews.first?.layer {
            backdropLayer.filters = [variableBlur]
        }
        for subview in subviews.dropFirst() {
            subview.alpha = 0
        }
    }

    /// Keep the blur crisp across screen scale / trait changes (the layer filters
    /// get reset when moving between windows).
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window else { return }
        subviews.first?.layer.setValue(window.screen.scale, forKey: "scale")
        applyFilter()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyFilter()
    }

    /// Grayscale gradient mask: opaque (full blur) at the active edge → clear
    /// (no blur) at the opposite edge. The ramp follows a *smoothstep* curve so
    /// the blur eases in with zero slope at the sharp end — no perceptible hard
    /// line where it begins, just a gradual dissolve into more blur.
    /// Rasterizing the ramp means standing up a SwiftUI render pass, and it's
    /// the same four images forever — so each direction is drawn once and kept.
    /// (Every scrim in the app re-applies its filter on appearance and on any
    /// trait change, which used to redraw this each time.)
    private static var maskCache: [VariableBlurView.Direction: CGImage] = [:]

    private static func gradientMask(direction: VariableBlurView.Direction) -> CGImage? {
        if let cached = maskCache[direction] { return cached }
        let image = renderGradientMask(direction: direction)
        if let image { maskCache[direction] = image }
        return image
    }

    private static func renderGradientMask(direction: VariableBlurView.Direction) -> CGImage? {
        let (start, end): (UnitPoint, UnitPoint)
        switch direction {
        case .bottom:   (start, end) = (.top, .bottom)
        case .top:      (start, end) = (.bottom, .top)
        case .leading:  (start, end) = (.trailing, .leading)
        case .trailing: (start, end) = (.leading, .trailing)
        }

        let stops: [Gradient.Stop] = (0...16).map { i in
            let t = Double(i) / 16
            let eased = t * t * (3 - 2 * t) // smoothstep: gentle onset, gentle finish
            return Gradient.Stop(color: .black.opacity(eased), location: CGFloat(t))
        }

        let gradient = LinearGradient(stops: stops, startPoint: start, endPoint: end)
            .frame(width: 128, height: 256)

        let renderer = ImageRenderer(content: gradient)
        renderer.scale = 1
        return renderer.cgImage
    }
}

/// A constant-radius blur of whatever sits behind the view, with no tint or
/// vibrancy wash of its own. Clip it to a shape and layer the usual tints on
/// top: the surface keeps its exact look but content behind it becomes
/// illegible. (SwiftUI materials can't do this at partial opacity — fading a
/// material fades its blur too.)
struct BackdropBlurView: UIViewRepresentable {
    var radius: CGFloat = 14

    func makeUIView(context: Context) -> BackdropBlurUIView {
        BackdropBlurUIView(radius: radius)
    }

    func updateUIView(_ uiView: BackdropBlurUIView, context: Context) {
        uiView.update(radius: radius)
    }
}

final class BackdropBlurUIView: UIVisualEffectView {
    private var radius: CGFloat

    init(radius: CGFloat) {
        self.radius = radius
        super.init(effect: UIBlurEffect(style: .regular))
        isUserInteractionEnabled = false
        applyFilter()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(radius: CGFloat) {
        guard radius != self.radius else { return }
        self.radius = radius
        applyFilter()
    }

    private func applyFilter() {
        guard
            let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
            let blur = filterClass.perform(NSSelectorFromString("filterWithType:"),
                                           with: "gaussianBlur")?
                .takeUnretainedValue() as? NSObject
        else { return }

        blur.setValue(radius, forKey: "inputRadius")
        blur.setValue(true, forKey: "inputNormalizeEdges")

        // Drive the backdrop layer with a plain gaussian and drop the tint/
        // vibrancy subviews so only the blur remains — the caller's own tint
        // layers sit on top unchanged.
        if let backdropLayer = subviews.first?.layer {
            backdropLayer.filters = [blur]
        }
        for subview in subviews.dropFirst() {
            subview.alpha = 0
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window else { return }
        subviews.first?.layer.setValue(window.screen.scale, forKey: "scale")
        applyFilter()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyFilter()
    }
}

/// A bottom-pinned progressive blur whose TOP edge curves to hug the device's
/// rounded bottom bezels: the band is tallest at the left/right corners and dips
/// lower (shorter) toward the horizontal center, a soft concave-up arc. The blur
/// intensity ramp is provided by `VariableBlurView`; this view only shapes WHERE
/// the band exists by masking with `BezelArcShape`.
struct BottomBezelBlur: View {
    var maxRadius: CGFloat = 9
    var height: CGFloat = 96        // band height at the corners (tallest)
    var middleDrop: CGFloat = 26    // how much SHORTER the band is at the horizontal center

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VariableBlurView(maxRadius: maxRadius, direction: .bottom)
                .frame(height: height)
                .mask {
                    // Feather the curved top edge so the blur dissolves along the
                    // whole bezel arc (including the corners) instead of stopping
                    // on a hard line. The bottom/side feather is off-screen.
                    BezelArcShape(middleDrop: middleDrop)
                        .fill(.black)
                        .blur(radius: 9)
                }
        }
        .ignoresSafeArea()
    }
}

/// A top-pinned progressive blur: strongest right at the top of the screen and
/// easing to perfectly sharp lower down, so content dissolves up into the status
/// bar / notch instead of sliding under a hard edge. Mirrors `BottomBezelBlur`
/// but kept as a straight band (the notch already breaks the top symmetry).
struct TopScrollBlur: View {
    var maxRadius: CGFloat = 8
    var height: CGFloat = 72

    var body: some View {
        VStack(spacing: 0) {
            VariableBlurView(maxRadius: maxRadius, direction: .top)
                .frame(height: height)
                // Alpha-fade the band's lower third so the effect dissolves to
                // nothing — without this the effect view's frame edge shows as
                // a faint hard line over busy content, even with the radius ramp.
                .mask(
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.55),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                )
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
    }
}

/// Fills from a curved top edge down to the bottom. The top edge sits at y=0 at
/// the left/right edges and dips down to y=`middleDrop` at the horizontal center,
/// following a smooth cosine arc so it reads as a soft bezel hug rather than a V.
struct BezelArcShape: Shape {
    var middleDrop: CGFloat = 26

    var animatableData: CGFloat {
        get { middleDrop }
        set { middleDrop = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            let w = rect.width
            let h = rect.height
            let drop = min(middleDrop, h)

            path.move(to: CGPoint(x: 0, y: 0))

            // Walk the cosine arc across the top edge: highest (y=0) at the
            // corners, lowest (y=drop) at the center.
            let steps = max(Int(w / 2), 1)
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = t * w
                // (1 - cos(2πt)) / 2 is 0 at the edges and 1 at the center.
                let y = drop * (1 - cos(t * 2 * .pi)) / 2
                path.addLine(to: CGPoint(x: x, y: y))
            }

            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.closeSubpath()
        }
    }
}

extension View {
    /// Softly fades the leading & trailing edges of a horizontal strip so items
    /// dissolve in and out rather than clipping at a hard line. A mask reads
    /// cleanly over the flat card surface — a backdrop blur has nothing to bite
    /// on there, so it just looks like a frosted bar.
    func horizontalFadeEdges(_ inset: CGFloat = 28) -> some View {
        mask {
            GeometryReader { geo in
                let frac = min(max(inset / max(geo.size.width, 1), 0), 0.5)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: frac),
                        .init(color: .black, location: 1 - frac),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
        }
    }
}
