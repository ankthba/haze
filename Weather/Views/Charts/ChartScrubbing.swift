//
//  ChartScrubbing.swift
//  Weather
//
//  Drag-to-inspect support for the Swift Charts in the app. Touching and dragging
//  across a chart snaps a selection to the nearest hourly point under the finger
//  (with a soft haptic tick on each new value) and clears it when the touch lifts.
//

import SwiftUI
import Charts
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The readout above the scrub line: a solid white card with the figures set
/// in black on top of it.
///
/// Two earlier attempts are worth recording so they aren't tried again. It
/// began as frosted glass, which is the usual chart-tooltip convention and
/// went dark and heavy over the chart's pale blues. Replacing the surface with
/// a soft dark halo on the glyphs fixed the weight but not the problem: on the
/// darker backgrounds of the detail sheets the halo smeared into a grey smudge
/// behind the text.
///
/// The halo was doing the work a background should do. So the readout carries
/// its own opaque ground and stops depending on what is behind it — the same
/// reading on a bright day sky, a night sky, or a sub-sheet, with no shadow to
/// fry against any of them.
struct ScrubReadout: View {
    let value: String
    var caption: String? = nil
    var detail: String? = nil
    /// Deep enough to hold its own against black on white. The old default was
    /// the pale blue used over the sky, which on this card is nearly invisible.
    var detailColor: Color = Color(hex: 0x1C6CA8)

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.displaySerif(size: 30))
                .foregroundStyle(.black)
            if let caption {
                Text(caption)
                    .font(.serif(.caption2))
                    .foregroundStyle(.black.opacity(0.62))
            }
            if let detail {
                Text(detail)
                    .font(.serif(.caption2))
                    .foregroundStyle(detailColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(shape.fill(.white))
        .clipShape(shape)
        .fixedSize()
    }
}

extension View {
    /// Adds drag-to-scrub interaction to a chart of `HourPoint`s, updating
    /// `selection` to the nearest point under the finger — but only for mostly
    /// *horizontal* drags, so vertical drags scroll the page as normal.
    func chartScrub(points: [HourPoint], selection: Binding<HourPoint?>) -> some View {
        modifier(ChartScrubModifier(points: points, selection: selection))
    }
}

private struct ChartScrubModifier: ViewModifier {
    let points: [HourPoint]
    @Binding var selection: HourPoint?

    func body(content: Content) -> some View {
        content.chartOverlay { proxy in
            GeometryReader { geo in
                HorizontalScrubView(
                    onChange: { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let x = location.x - geo[plotFrame].origin.x
                        guard let date = proxy.value(atX: x, as: Date.self) else { return }
                        let nearest = points.min {
                            abs($0.date.timeIntervalSince(date))
                                < abs($1.date.timeIntervalSince(date))
                        }
                        if nearest?.id != selection?.id {
                            Haptics.selection()
                        }
                        selection = nearest
                    },
                    onEnd: { selection = nil }
                )
            }
        }
    }
}


#if canImport(UIKit)

/// A UIKit pan recognizer that only *begins* on mostly-horizontal drags. Vertical
/// drags never start it, so the touch passes straight through to the enclosing
/// ScrollView and the page scrolls normally — the reliable way to mix horizontal
/// scrubbing with vertical scrolling.
private struct HorizontalScrubView: UIViewRepresentable {
    let onChange: (CGPoint) -> Void
    let onEnd: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onEnd = onEnd
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange, onEnd: onEnd) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChange: (CGPoint) -> Void
        var onEnd: () -> Void

        init(onChange: @escaping (CGPoint) -> Void, onEnd: @escaping () -> Void) {
            self.onChange = onChange
            self.onEnd = onEnd
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began, .changed:
                onChange(gesture.location(in: gesture.view))
            case .ended, .cancelled, .failed:
                onEnd()
            default:
                break
            }
        }

        // Begin only when the drag is more horizontal than vertical. Returning
        // false leaves the gesture to the ScrollView, so vertical scrolling works.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer, let view = pan.view else {
                return false
            }
            let velocity = pan.velocity(in: view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

#else

/// The Mac reads a chart under the pointer. A tracking area reports every
/// movement over the plot, dragging works the same way, and the readout clears
/// the moment the pointer leaves. Wheel scrolling passes through untouched.
private struct HorizontalScrubView: NSViewRepresentable {
    let onChange: (CGPoint) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> ScrubTrackingView {
        let view = ScrubTrackingView()
        view.onChange = onChange
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: ScrubTrackingView, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
    }

    final class ScrubTrackingView: NSView {
        var onChange: ((CGPoint) -> Void)?
        var onEnd: (() -> Void)?

        /// Top-left origin, like the SwiftUI geometry the chart proxy speaks.
        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil))
        }

        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseDragged(with event: NSEvent) { report(event) }
        override func mouseDown(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { onEnd?() }
        override func mouseUp(with event: NSEvent) {
            // A click that ends outside the plot leaves nothing behind.
            if !bounds.contains(convert(event.locationInWindow, from: nil)) { onEnd?() }
        }

        private func report(_ event: NSEvent) {
            onChange?(convert(event.locationInWindow, from: nil))
        }
    }
}

#endif
