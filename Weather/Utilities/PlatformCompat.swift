//
//  PlatformCompat.swift
//  Weather
//
//  Small shims so the iOS-flavored UI also compiles cleanly on macOS/visionOS,
//  plus the handful of places where the Mac build wants a slightly different
//  answer (a title bar instead of a status bar, a pointer instead of a finger)
//  without every view growing its own #if.
//

import SwiftUI
import CoreLocation

enum Platform {
    #if os(macOS)
    static let isMac = true
    #else
    static let isMac = false
    #endif

    /// Room to leave above a page's first line, clear of the floating close
    /// button (and, on the iPhone, the status bar).
    static var sheetTopInset: CGFloat { 44 }

    /// Whether the Mac app shows the temperature in the menu bar.
    static let menuBarKey = "mac_menu_bar_enabled"
}

extension View {
    /// Inline navigation title on platforms that support it; no-op elsewhere.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS) || os(visionOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Grouped list styling that degrades gracefully off iOS.
    @ViewBuilder
    func groupedListStyle() -> some View {
        #if os(iOS) || os(visionOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    /// A Mac sheet sizes itself to its content, and the app's scrolling pages
    /// have no intrinsic size to offer, so they are given a comfortable page.
    /// No-op on iOS, where a sheet is always the whole screen.
    @ViewBuilder
    func macSheetFrame(width: CGFloat = 580, height: CGFloat = 760) -> some View {
        #if os(macOS)
        self.frame(minWidth: 480, idealWidth: width, minHeight: 540, idealHeight: height)
        #else
        self
        #endif
    }

    /// Capitalises each word while typing a place name; iOS keyboards only.
    @ViewBuilder
    func wordsAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.words)
        #else
        self
        #endif
    }

    /// The app's own switch on the Mac; the system's white-tinted one on the
    /// iPhone, where it already belongs.
    @ViewBuilder
    /// The app's own switch, on every platform. It used to be Mac-only, on
    /// the reasoning that the tinted system switch sat well enough on the
    /// sky; side by side with the Mac's glass it just read as a different
    /// app's control, so both wear the same one now.
    func hazeToggleStyle() -> some View {
        self.toggleStyle(HazeToggleStyle())
    }

    /// `containerRelativeFrame(.horizontal)` on the iPhone; on the Mac that
    /// measures the window, not the column, so a full-width frame stands in.
    @ViewBuilder
    func pinnedToContainerWidth() -> some View {
        #if os(macOS)
        self.frame(maxWidth: .infinity)
        #else
        self.containerRelativeFrame(.horizontal)
        #endif
    }

    /// A quiet lift under the pointer, so a row that opens something says so
    /// before it's clicked. Nothing on touch platforms, where hover doesn't exist.
    func hoverHighlight(cornerRadius: CGFloat = 12, bleed: CGFloat = 10,
                        enabled: Bool = true) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, bleed: bleed, enabled: enabled))
    }
}

private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    /// How far past the content's own edges the lift extends.
    let bleed: CGFloat
    let enabled: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(hovering && enabled ? 0.07 : 0))
                    .padding(.horizontal, -bleed)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
        #else
        content
        #endif
    }
}

extension CLAuthorizationStatus {
    /// Whether the app may ask for a fix. macOS has no "while using" tier;
    /// its single "authorized" state is spelled `authorizedAlways`.
    var isAuthorizedForApp: Bool {
        #if os(macOS)
        self == .authorizedAlways
        #else
        self == .authorizedWhenInUse || self == .authorizedAlways
        #endif
    }
}

// MARK: - Sheets

#if os(macOS)
/// The Mac shows the iPhone's sheets as cards in the window, over a blur of
/// the page, rather than as system sheets that dim everything behind them.
/// Whoever wants to show one hands it here; the window root draws it.
@MainActor
@Observable
final class CardPresenter {
    struct Card: Identifiable {
        let id = UUID()
        let content: AnyView
        /// Clears the presenting view's own state, which in turn clears the card.
        let onClose: () -> Void
    }

    private(set) var card: Card?

    func present<Content: View>(_ content: Content, onClose: @escaping () -> Void) {
        card = Card(content: AnyView(content), onClose: onClose)
    }

    /// Called when the card's owner has let go of it.
    func clear() { card = nil }

    /// The backdrop was clicked, or Escape pressed: ask the owner to let go.
    func dismissCurrent() { card?.onClose() }
}

private struct CardPresenterKey: EnvironmentKey {
    static let defaultValue: CardPresenter? = nil
}

extension EnvironmentValues {
    var cardPresenter: CardPresenter? {
        get { self[CardPresenterKey.self] }
        set { self[CardPresenterKey.self] = newValue }
    }
}
#endif

extension View {
    /// A sheet on the iPhone; a card over the blurred window on the Mac. The
    /// content gets a `close` to call from its own close button.
    func hazeSheet<Item: Identifiable, Page: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item, _ close: @escaping () -> Void) -> Page
    ) -> some View {
        modifier(HazeItemSheet(item: item, content: content))
    }

    func hazeSheet<Page: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping (_ close: @escaping () -> Void) -> Page
    ) -> some View {
        modifier(HazeBoolSheet(isPresented: isPresented, content: content))
    }
}

private struct HazeItemSheet<Item: Identifiable, Page: View>: ViewModifier {
    @Binding var item: Item?
    let content: (Item, _ close: @escaping () -> Void) -> Page
    #if os(macOS)
    @Environment(\.cardPresenter) private var presenter
    #endif

    func body(content base: Content) -> some View {
        #if os(macOS)
        base.onChange(of: item?.id) {
            if let item {
                presenter?.present(content(item) { self.item = nil }) { self.item = nil }
            } else {
                presenter?.clear()
            }
        }
        #else
        base.sheet(item: $item) { item in
            content(item) { self.item = nil }
        }
        #endif
    }
}

private struct HazeBoolSheet<Page: View>: ViewModifier {
    @Binding var isPresented: Bool
    let content: (_ close: @escaping () -> Void) -> Page
    #if os(macOS)
    @Environment(\.cardPresenter) private var presenter
    #endif

    func body(content base: Content) -> some View {
        #if os(macOS)
        base.onChange(of: isPresented) {
            if isPresented {
                presenter?.present(content { isPresented = false }) { isPresented = false }
            } else {
                presenter?.clear()
            }
        }
        #else
        base.sheet(isPresented: $isPresented) {
            content { isPresented = false }
        }
        #endif
    }
}
