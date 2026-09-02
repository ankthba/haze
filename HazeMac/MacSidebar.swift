//
//  MacSidebar.swift
//  HazeMac
//
//  The locations column, drawn the way the iPhone's Locations page is drawn:
//  the app's glass capsule for search, serif rows on the sky, hairlines between
//  them, and a ringed location badge for your own place. Typing turns the rows
//  into results; ⌘1 to ⌘9 jump; the context menu reorders and removes.
//

import SwiftUI

struct MacSidebar: View {
    @Bindable var viewModel: WeatherViewModel
    let summaries: PlaceSummaries
    @Bindable var windows: MacWindows

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    /// Room for the window's traffic lights, which sit over this column.
    private static let titleBarHeight: CGFloat = 40

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var showsResults: Bool { trimmedQuery.count >= 2 }

    private var selected: SidebarItem? {
        if viewModel.isShowingDeviceLocation { return .currentLocation }
        return viewModel.selectedPlace.map { .place($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.titleBarHeight)

            searchField
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if showsResults {
                        resultRows
                    } else {
                        currentLocationRow
                        sectionLabel("My Locations")
                        savedRows
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        // A breath darker than the page, so the column reads as the margin
        // of the spread; the hairline is the fold.
        .background(Color.black.opacity(0.10))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.12)).frame(width: 0.6)
        }
        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
        .onChange(of: windows.searchFocusRequest) { searchFocused = true }
    }

    // MARK: - Search

    /// The iPhone's search capsule, verbatim in spirit: glass, a magnifier,
    /// and a clear button that appears with the first letter.
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            TextField("", text: $query,
                      prompt: Text("Search for a city or airport")
                        .foregroundStyle(.white.opacity(0.45)))
                .textFieldStyle(.plain)
                .font(.serif(.subheadline))
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onSubmit {
                    if let first = results.first { pick(first) }
                    else { scheduleSearch(query, immediately: true) }
                }
                .onExitCommand {
                    query = ""
                    searchFocused = false
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(GlassSurface(shape: Capsule(), frost: 0.18, blurRadius: 14))
        .clipShape(Capsule())
    }

    // MARK: - Rows

    private var currentLocationRow: some View {
        let denied = viewModel.locationManager.isDenied
        let name = viewModel.locationManager.lastKnownPlace?.name ?? "Current Location"
        let summary: PlaceSummaries.Summary? = {
            if viewModel.isShowingDeviceLocation, let bundle = viewModel.bundle {
                return .init(temperature: bundle.current.temperature, code: bundle.current.code,
                             isDay: bundle.current.isDay, fetchedAt: bundle.fetchedAt)
            }
            if let device = viewModel.deviceSummary {
                return .init(temperature: device.temperature, code: device.condition.code,
                             isDay: device.condition.isDay, fetchedAt: device.fetchedAt)
            }
            return nil
        }()
        return Button {
            Haptics.tap()
            Task { await viewModel.useCurrentLocation() }
        } label: {
            SidebarRow(name: name,
                       subtitle: denied ? "Location is off" : "Your location",
                       summary: summary,
                       isSelected: selected == .currentLocation,
                       badge: .location)
        }
        .buttonStyle(.plain)
        .disabled(denied)
        .opacity(denied ? 0.5 : 1)
        .accessibilityLabel(denied ? "Location is off" : "Use current location")
    }

    @ViewBuilder
    private var savedRows: some View {
        if viewModel.savedPlaces.isEmpty {
            Text("Search above to add a city.")
                .font(.serif(.caption, italic: true))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        ForEach(Array(viewModel.savedPlaces.enumerated()), id: \.element.id) { index, place in
            Button {
                Haptics.tap()
                Task { await viewModel.select(place) }
            } label: {
                SidebarRow(name: place.name, subtitle: place.subtitle,
                           summary: summaries.summary(for: place),
                           isSelected: selected == .place(place.id),
                           badge: .none)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Move Up") { viewModel.moveSavedPlace(from: [index], to: index - 1) }
                    .disabled(index == 0)
                Button("Move Down") { viewModel.moveSavedPlace(from: [index], to: index + 2) }
                    .disabled(index == viewModel.savedPlaces.count - 1)
                Divider()
                Button("Remove \(place.name)", role: .destructive) { remove(place) }
            }
            if index < viewModel.savedPlaces.count - 1 {
                hairline
            }
        }
    }

    @ViewBuilder
    private var resultRows: some View {
        sectionLabel("Results")
        if isSearching && results.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching…")
                    .font(.serif(.caption, italic: true))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        } else if results.isEmpty {
            Text("No matches found.")
                .font(.serif(.caption, italic: true))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        ForEach(Array(results.enumerated()), id: \.element.id) { index, place in
            Button {
                pick(place)
            } label: {
                SidebarRow(name: place.name, subtitle: place.subtitle, summary: nil,
                           isSelected: false,
                           badge: .flag(place.flag),
                           isSaved: viewModel.isSaved(place))
            }
            .buttonStyle(.plain)
            if index < results.count - 1 {
                hairline
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.serif(.footnote, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private var hairline: some View {
        Rectangle()
            .fill(.white.opacity(0.10))
            .frame(height: 0.5)
            .padding(.horizontal, 12)
    }

    // MARK: - Actions

    private func pick(_ place: Place) {
        Haptics.tap()
        query = ""
        results = []
        searchFocused = false
        Task { await viewModel.select(place) }
    }

    private func remove(_ place: Place) {
        let wasShowing = viewModel.selectedPlace?.id == place.id && !viewModel.isShowingDeviceLocation
        viewModel.removeSavedPlace(place)
        guard wasShowing else { return }
        // The page shouldn't keep showing a city that's no longer in the list.
        if let next = viewModel.savedPlaces.first {
            Task { await viewModel.select(next) }
        } else if !viewModel.locationManager.isDenied {
            Task { await viewModel.useCurrentLocation() }
        }
    }

    private func scheduleSearch(_ text: String, immediately: Bool = false) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            if !immediately { try? await Task.sleep(for: .milliseconds(280)) }
            guard !Task.isCancelled else { return }
            let found = await viewModel.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }
}

// MARK: - Row

private struct SidebarRow: View {
    enum Badge {
        case none
        /// The ringed location glyph the iPhone's bottom bar wears.
        case location
        case flag(String)
    }

    let name: String
    let subtitle: String
    let summary: PlaceSummaries.Summary?
    let isSelected: Bool
    var badge: Badge = .none
    var isSaved = false

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        HStack(spacing: 12) {
            leading
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.serif(.body, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.serif(.caption))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if let summary {
                Text(Fmt.tempDegree(summary.temperature))
                    .font(.serif(.title3))
                    .foregroundStyle(.white)
            } else if isSaved {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            if isSelected {
                GlassSurface(shape: shape, frost: 0.14)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .hoverHighlight(cornerRadius: 14, bleed: 0, enabled: !isSelected)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var leading: some View {
        switch badge {
        case .location:
            Image(systemName: "location.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(GlassSurface(shape: Circle()))
                .clipShape(Circle())
        case .flag(let flag):
            Text(flag.isEmpty ? "📍" : flag)
                .font(.system(size: 17))
        case .none:
            if let summary {
                Image(systemName: summary.condition.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 17))
            } else {
                Image(systemName: "mappin")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
