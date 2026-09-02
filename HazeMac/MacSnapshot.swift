//
//  MacSnapshot.swift
//  HazeMac
//
//  A development hook: launched with `-hazeSnapshot /path/to/out.png [seconds]`
//  (or `-hazeSnapshot -` to print the PNG as base64 on stdout, which is the
//  only way out of the sandbox), the app waits for its window to settle,
//  captures it, and quits. It's how the layout gets checked from a script, with nobody at the
//  keyboard. Debug builds only.
//

#if DEBUG

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum MacSnapshot {
    static func armIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-hazeSnapshot"),
              index + 1 < arguments.count else { return }
        let path = arguments[index + 1]
        let delay = index + 2 < arguments.count ? Double(arguments[index + 2]) ?? 5 : 5
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            capture(to: path)
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private static func capture(to path: String) {
        // The menu bar extra owns a tiny status window of its own; the main
        // window is simply the largest thing on screen.
        guard let window = NSApp.windows
                .filter({ $0.isVisible && $0.contentView != nil })
                .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        else { return }

        if ProcessInfo.processInfo.arguments.contains("-hazeDumpEffects"), let root = window.contentView {
            dumpEffectViews(in: root)
        }
        guard let image = renderedImage(window) else { return }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        if path == "-" {
            // The sandbox keeps the app's files to itself; stdout is the one
            // channel a script outside the container can always read.
            print("HAZE-SNAPSHOT-BEGIN")
            print((data as Data).base64EncodedString())
            print("HAZE-SNAPSHOT-END")
        } else {
            try? (data as Data).write(to: URL(fileURLWithPath: path))
        }
    }

    /// Prints every visual-effect view's layer tree with its filters, to check
    /// that the backdrop filter swap actually found a backdrop layer.
    @MainActor
    private static func dumpEffectViews(in view: NSView) {
        if let effect = view as? NSVisualEffectView, let layer = effect.layer {
            print("effect:", type(of: effect), effect.frame)
            dump(layer, depth: 1)
        }
        for sub in view.subviews { dumpEffectViews(in: sub) }
    }

    private static func dump(_ layer: CALayer, depth: Int) {
        let filters = (layer.filters ?? []).map { String(describing: $0) }
        print(String(repeating: "  ", count: depth), type(of: layer), "opacity:", layer.opacity,
              "filters:", filters, "mask:", layer.mask.map { String(describing: type(of: $0)) } ?? "-")
        for sub in layer.sublayers ?? [] { dump(sub, depth: depth + 1) }
    }

    /// The view hierarchy drawn into a bitmap. Backdrop blurs don't survive the
    /// trip (they only exist in the window server), so this checks layout, not glass.
    @MainActor
    private static func renderedImage(_ window: NSWindow) -> CGImage? {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }
}

#endif
