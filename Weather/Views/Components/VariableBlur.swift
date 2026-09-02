//
//  VariableBlur.swift
//  Weather
//
//  A true progressive (variable-radius) blur of whatever sits behind the view,
//  the same `variableBlur` CAFilter the system uses for its soft scroll/toolbar
//  edges. The blur radius ramps along a gradient so content genuinely refracts
//  and dissolves into the background instead of being cut off by a hard line or
//  covered by a flat frosted scrim.
//
//  UIKit and AppKit each wrap the same Core Animation backdrop machinery:
//  UIVisualEffectView on the iPhone, NSVisualEffectView on the Mac. Both are
//  handed the filter the same way, by swapping it onto the backdrop layer and
//  hushing the material's own tint, so the glass reads identically on both.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - Filters

/// The private Core Animation filters behind the system's own blurs, built
/// once per use. The keys are the same on every Apple platform.
private enum BackdropFilters {
    static func make(type: String) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
              let filter = filterClass.perform(NSSelectorFromString("filterWithType:"),
                                               with: type)?
                .takeUnretainedValue() as? NSObject
        else { return nil }
        return filter
    }

    static func gaussian(radius: CGFloat) -> NSObject? {
        guard let blur = make(type: "gaussianBlur") else { return nil }
        blur.setValue(radius, forKey: "inputRadius")
        blur.setValue(true, forKey: "inputNormalizeEdges")
        return blur
    }

    static func variable(radius: CGFloat, mask: CGImage) -> NSObject? {
        guard let blur = make(type: "variableBlur") else { return nil }
        blur.setValue(radius, forKey: "inputRadius")
        blur.setValue(mask, forKey: "inputMaskImage")
        blur.setValue(true, forKey: "inputNormalizeEdges")
        return blur
    }

    /// Grayscale gradient mask: opaque (full blur) at the active edge → clear
    /// (no blur) at the opposite edge. The ramp follows a *smoothstep* curve so
    /// the blur eases in with zero slope at the sharp end: no perceptible hard
    /// line where it begins, just a gradual dissolve into more blur.
    /// Rasterizing the ramp means standing up a SwiftUI render pass, and it's
    /// the same four images forever, so each direction is drawn once and kept.
    private static var maskCache: [VariableBlurView.Direction: CGImage] = [:]

    static func gradientMask(direction: VariableBlurView.Direction) -> CGImage? {
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

#if canImport(UIKit)

// MARK: - UIKit

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
        guard let mask = BackdropFilters.gradientMask(direction: direction),
              let variableBlur = BackdropFilters.variable(radius: maxRadius, mask: mask)
        else { return }

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
}

/// A constant-radius blur of whatever sits behind the view, with no tint or
/// vibrancy wash of its own. Clip it to a shape and layer the usual tints on
/// top: the surface keeps its exact look but content behind it becomes
/// illegible. (SwiftUI materials can't do this at partial opacity: fading a
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
        guard let blur = BackdropFilters.gaussian(radius: radius) else { return }

        // Drive the backdrop layer with a plain gaussian and drop the tint/
        // vibrancy subviews so only the blur remains; the caller's own tint
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

#else

// MARK: - AppKit

/// AppKit's NSVisualEffectView owns a properly wired backdrop layer (a bare
/// CABackdropLayer hosted by hand draws nothing on the Mac). It also rewrites
/// that layer's filters and tint every time it updates, so the app's filter
/// is re-installed after each `updateLayer`, which is the last word AppKit
/// has, and the material's own tint and vibrancy layers are silenced.
@MainActor
private enum EffectViewBackdrop {
    static func install(_ filter: NSObject?, in view: NSVisualEffectView) {
        guard let filter, let root = view.layer, let backdrop = find(in: root) else { return }
        if let current = backdrop.filters?.first as? NSObject, current === filter,
           backdrop.filters?.count == 1 { return }
        backdrop.filters = [filter]
        for sublayer in backdrop.sublayers ?? [] { sublayer.opacity = 0 }
        for sibling in backdrop.superlayer?.sublayers ?? [] where sibling !== backdrop {
            sibling.opacity = 0
        }
        if let scale = view.window?.backingScaleFactor {
            backdrop.setValue(scale, forKey: "scale")
        }
    }

    private static func find(in layer: CALayer) -> CALayer? {
        if String(describing: type(of: layer)).contains("Backdrop") { return layer }
        for sublayer in layer.sublayers ?? [] {
            if let found = find(in: sublayer) { return found }
        }
        return nil
    }
}

/// The shared bones of both Mac blur views: a within-window effect view that
/// never takes a click and re-asserts its filter whenever AppKit redraws.
class BackdropEffectView: NSVisualEffectView {
    var filter: NSObject? {
        didSet { EffectViewBackdrop.install(filter, in: self) }
    }

    init() {
        super.init(frame: .zero)
        blendingMode = .withinWindow
        material = .hudWindow
        state = .active
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// Decoration only; never in the way of a click.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        super.updateLayer()
        EffectViewBackdrop.install(filter, in: self)
    }

    override func layout() {
        super.layout()
        EffectViewBackdrop.install(filter, in: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        EffectViewBackdrop.install(filter, in: self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        EffectViewBackdrop.install(filter, in: self)
    }
}

struct VariableBlurView: NSViewRepresentable {
    /// The edge the blur is strongest at; it fades to sharp toward the opposite side.
    enum Direction: Hashable { case top, bottom, leading, trailing }

    var maxRadius: CGFloat = 16
    var direction: Direction = .bottom
    /// Where along the band (0 at the strong edge, 1 at the far edge) the view
    /// itself starts fading out, so the far edge dissolves instead of ending
    /// on a line. SwiftUI's masks don't reach into a hosted AppKit view, so
    /// the fade is a layer mask of its own.
    var fadeFrom: CGFloat = 0.55

    func makeNSView(context: Context) -> VariableBlurNSView {
        VariableBlurNSView(maxRadius: maxRadius, direction: direction, fadeFrom: fadeFrom)
    }

    func updateNSView(_ view: VariableBlurNSView, context: Context) {
        view.update(maxRadius: maxRadius, direction: direction, fadeFrom: fadeFrom)
    }
}

final class VariableBlurNSView: BackdropEffectView {
    private var maxRadius: CGFloat
    private var direction: VariableBlurView.Direction
    private var fadeFrom: CGFloat
    private let fade = CAGradientLayer()

    init(maxRadius: CGFloat, direction: VariableBlurView.Direction, fadeFrom: CGFloat) {
        self.maxRadius = maxRadius
        self.direction = direction
        self.fadeFrom = fadeFrom
        super.init()
        filter = Self.filter(radius: maxRadius, direction: direction)
        applyFade()
    }

    private static func filter(radius: CGFloat, direction: VariableBlurView.Direction) -> NSObject? {
        guard let mask = BackdropFilters.gradientMask(direction: direction) else { return nil }
        return BackdropFilters.variable(radius: radius, mask: mask)
    }

    func update(maxRadius: CGFloat, direction: VariableBlurView.Direction, fadeFrom: CGFloat) {
        if maxRadius != self.maxRadius || direction != self.direction {
            self.maxRadius = maxRadius
            self.direction = direction
            filter = Self.filter(radius: maxRadius, direction: direction)
        }
        if fadeFrom != self.fadeFrom {
            self.fadeFrom = fadeFrom
            applyFade()
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        CATransaction.commit()
    }

    /// The alpha fade runs the same way as the blur ramp: solid at the strong
    /// edge, gone at the far edge.
    private func applyFade() {
        let (start, end): (CGPoint, CGPoint)
        switch direction {
        case .top:      (start, end) = (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
        case .bottom:   (start, end) = (CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0))
        case .leading:  (start, end) = (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))
        case .trailing: (start, end) = (CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5))
        }
        fade.startPoint = start
        fade.endPoint = end
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, NSNumber(value: Double(fadeFrom)), 1]
        fade.frame = bounds
        layer?.mask = fade
    }
}

/// A constant-radius blur of whatever sits behind the view, with no tint or
/// vibrancy wash of its own. Clip it to a shape and layer the usual tints on
/// top: the surface keeps its exact look but content behind it becomes
/// illegible.
struct BackdropBlurView: NSViewRepresentable {
    var radius: CGFloat = 14

    func makeNSView(context: Context) -> BackdropBlurNSView {
        BackdropBlurNSView(radius: radius)
    }

    func updateNSView(_ view: BackdropBlurNSView, context: Context) {
        view.update(radius: radius)
    }
}

final class BackdropBlurNSView: BackdropEffectView {
    private var radius: CGFloat

    init(radius: CGFloat) {
        self.radius = radius
        super.init()
        filter = BackdropFilters.gaussian(radius: radius)
    }

    func update(radius: CGFloat) {
        guard radius != self.radius else { return }
        self.radius = radius
        filter = BackdropFilters.gaussian(radius: radius)
    }
}

#endif

// MARK: - Bands

/// A bottom-pinned progressive blur whose TOP edge curves to hug the device's
/// rounded bottom bezels: the band is tallest at the left/right corners and dips
/// lower (shorter) toward the horizontal center, a soft concave-up arc. The blur
/// intensity ramp is provided by `VariableBlurView`; this view only shapes WHERE
/// the band exists by masking with `BezelArcShape`. A Mac window has no bezel
/// to hug, so there the band is a straight fade.
struct BottomBezelBlur: View {
    var maxRadius: CGFloat = 9
    var height: CGFloat = 96        // band height at the corners (tallest)
    var middleDrop: CGFloat = 26    // how much SHORTER the band is at the horizontal center

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            #if os(macOS)
            VariableBlurView(maxRadius: maxRadius, direction: .bottom, fadeFrom: 0.5)
                .frame(height: height - middleDrop)
            #else
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
            #endif
        }
        .ignoresSafeArea()
    }
}

/// A top-pinned progressive blur: strongest right at the top of the screen and
/// easing to perfectly sharp lower down, so content dissolves up into the status
/// bar / notch (or, on the Mac, the window's toolbar) instead of sliding under
/// a hard edge. Mirrors `BottomBezelBlur` but kept as a straight band.
struct TopScrollBlur: View {
    var maxRadius: CGFloat = 8
    var height: CGFloat = 72

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            VariableBlurView(maxRadius: maxRadius, direction: .top, fadeFrom: 0.55)
                .frame(height: height)
            #else
            VariableBlurView(maxRadius: maxRadius, direction: .top)
                .frame(height: height)
                // Alpha-fade the band's lower third so the effect dissolves to
                // nothing; without this the effect view's frame edge shows as
                // a faint hard line over busy content, even with the radius ramp.
                .mask(
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.55),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                )
            #endif
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
    /// cleanly over the flat card surface; a backdrop blur has nothing to bite
    /// on there, so it would just look like a frosted bar.
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
