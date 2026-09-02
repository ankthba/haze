//
//  MacPanel.swift
//  HazeMac
//
//  The right-hand panel: Settings or the radar, beside the page, in the same
//  glass and serif as everything else. One button grows it to the whole page
//  and back; another closes it. Below a comfortable width the panel simply
//  takes the page, since a radar squeezed to a strip is no radar at all.
//

import SwiftUI
import AppKit

struct MacPanel: View {
    @Bindable var viewModel: WeatherViewModel
    @Bindable var windows: MacWindows
    let panel: MacWindows.Panel
    let isExpanded: Bool
    /// False when the window is too narrow for a column, so the expand
    /// control has nothing to offer.
    let canCollapse: Bool

    static let width: CGFloat = 460

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch panel {
            case .settings:
                SettingsView(viewModel: viewModel,
                             onClose: { windows.closePanel() },
                             onToggleExpand: canCollapse ? { windows.panelExpanded.toggle() } : nil,
                             isExpanded: isExpanded)
            case .radar:
                if let bundle = viewModel.bundle {
                    RadarView(place: bundle.place,
                              timezone: bundle.timezone,
                              accent: bundle.current.condition.accent,
                              isDay: bundle.current.isDay,
                              onClose: { windows.closePanel() },
                              onToggleExpand: canCollapse ? { windows.panelExpanded.toggle() } : nil,
                              isExpanded: isExpanded)
                        .id(bundle.place.id)
                }
            }
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.14)).frame(width: 0.6)
        }
        .background {
            // Escape closes the panel, like a sheet.
            Button("") { windows.closePanel() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        }
    }

}

// MARK: - Window chrome

/// Brings the traffic lights in from the corner onto the app's own top row,
/// level with the floating buttons. AppKit pins them to a 28pt title bar; a
/// title bar accessory makes that bar as tall as the row, and the buttons are
/// then placed by hand, again after every resize, since AppKit lays them out
/// afresh each time.
struct WindowChrome: NSViewRepresentable {
    /// The row the lights are centred in: 26pt from the top, like the buttons.
    static let titleRowHeight: CGFloat = 52
    static let lightsCenterFromTop: CGFloat = 26
    static let lightsLeading: CGFloat = 20

    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) {}

    final class ChromeView: NSView {
        private var configured: NSWindow?
        private var observers: [NSObjectProtocol] = []
        /// A ProMotion display only runs at 120Hz for windows that ask; this
        /// link exists to ask, and does nothing else.
        private var frameRateLink: CADisplayLink?

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            frameRateLink?.invalidate()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== configured else { return }
            configured = window
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)

            // Height for the row: an empty accessory hung under the title bar.
            let accessory = NSTitlebarAccessoryViewController()
            accessory.view = NSView(frame: NSRect(
                x: 0, y: 0, width: 0,
                height: WindowChrome.titleRowHeight - 28))
            accessory.layoutAttribute = .bottom
            window.addTitlebarAccessoryViewController(accessory)

            let names: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                NSWindow.didExitFullScreenNotification, NSWindow.didBecomeMainNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.placeLights(in: window) }
                })
            }
            placeLights(in: window)
            DispatchQueue.main.async { [weak self] in self?.placeLights(in: window) }

            let link = displayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            frameRateLink = link
        }

        @objc private func tick() {}

        override func layout() {
            super.layout()
            if let window { placeLights(in: window) }
        }

        private func placeLights(in window: NSWindow) {
            let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            let buttons = kinds.compactMap { window.standardWindowButton($0) }
            guard let container = buttons.first?.superview else { return }
            for (index, button) in buttons.enumerated() {
                let x = WindowChrome.lightsLeading + CGFloat(index) * 20
                let y = container.bounds.height - WindowChrome.lightsCenterFromTop
                    - button.frame.height / 2
                let origin = NSPoint(x: x, y: y)
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
        }
    }
}
