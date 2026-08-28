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
import UIKit

/// The little floating readout shown above the scrub line, finished in the same
/// frosted glass as the app's buttons and panels. (An earlier build used a solid
/// slab because SwiftUI *materials* re-snapshot their blur and flickered while
/// dragging; GlassSurface blurs via a live CAFilter backdrop instead, which
/// samples continuously and moves smoothly.) A soft inner shade keeps the white
/// figures legible even over the brightest part of a day sky.
struct ScrubReadout: View {
    let value: String
    var caption: String? = nil
    var detail: String? = nil
    var detailColor: Color = Color(hex: 0x9FD6FF)

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.serif(.title3))
                .foregroundStyle(.white)
            if let caption {
                Text(caption)
                    .font(.serif(.caption2))
                    .foregroundStyle(.white.opacity(0.75))
            }
            if let detail {
                Text(detail)
                    .font(.serif(.caption2))
                    .foregroundStyle(detailColor)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        // Exactly the surface the top-bar buttons wear — same frost, same live
        // backdrop blur, same rim light. Nothing layered on top: an earlier
        // darkening wash made it read as a different material.
        .background(GlassSurface(shape: shape))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
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
