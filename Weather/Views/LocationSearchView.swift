//
//  LocationSearchView.swift
//  Weather
//
//  Search + saved locations manager presented as a sheet.
//

import SwiftUI

struct LocationSearchView: View {
    @Bindable var viewModel: WeatherViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    // Sky derived from the current data, with safe fallbacks for a nil bundle.
    private var skyCondition: WeatherCondition {
        viewModel.bundle?.current.condition ?? WeatherCondition(code: 1, isDay: true)
    }
    private var skySunrise: Date? { viewModel.bundle?.today?.sunrise }
    private var skySunset: Date? { viewModel.bundle?.today?.sunset }

    private let rowBackground = Color.white.opacity(0.06)

    var body: some View {
        ZStack {
            SkyBackground(condition: skyCondition,
                          now: Date(),
                          sunrise: skySunrise,
                          sunset: skySunset)

            List {
                if query.isEmpty {
                    currentLocationButton
                    savedSection
                } else {
                    resultsSection
                }
            }
            .groupedListStyle()
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top) { topBar }
            .safeAreaInset(edge: .bottom) { searchBar }
        }
        .colorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .onChange(of: query) { _, newValue in
            scheduleSearch(newValue)
        }
    }

    // MARK: - Top bar (title + close) and bottom search

    private var topBar: some View {
        // Top-align so the close button sits in the corner at the same inset as
        // every other sub-page, regardless of the large title's height.
        HStack(alignment: .top) {
            Text("Locations")
                .font(.serif(.largeTitle))
                .foregroundStyle(.white)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(CardButtonStyle())
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var searchBar: some View {
        searchField
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(
                // A soft scrim so list rows reading under the field stay legible.
                LinearGradient(colors: [.clear, .black.opacity(0.16)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            TextField("", text: $query,
                      prompt: Text("Search for a city or airport")
                        .foregroundStyle(.white.opacity(0.45)))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)

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
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            ZStack {
                // The exact card recipe (light frosted material + white top-lit
                // tint), but at full strength instead of the cards' 0.18 — so it
                // tints with the time-of-day sky yet actually blurs what's behind
                // rather than being see-through.
                Capsule()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .light)
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.04)],
                                         startPoint: .top, endPoint: .bottom))
            }
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.08)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8)
        )
    }

    // MARK: - Sections

    private var currentLocationButton: some View {
        Section {
            Button {
                Haptics.tap()
                Task {
                    await viewModel.useCurrentLocation()
                    dismiss()
                }
            } label: {
                Label("Use Current Location", systemImage: "location.fill")
                    .foregroundStyle(.white)
            }
            .listRowBackground(rowBackground)
            .listRowSeparatorTint(.white.opacity(0.12))
        }
    }

    private var savedSection: some View {
        Section {
            if viewModel.savedPlaces.isEmpty {
                Text("Search above to add a location.")
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.subheadline)
                    .listRowBackground(rowBackground)
            }
            ForEach(viewModel.savedPlaces) { place in
                Button {
                    Haptics.tap()
                    Task {
                        await viewModel.select(place)
                        dismiss()
                    }
                } label: {
                    placeRow(place)
                }
                .listRowBackground(rowBackground)
                .listRowSeparatorTint(.white.opacity(0.12))
                .swipeActions {
                    Button(role: .destructive) {
                        viewModel.removeSavedPlace(place)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            // Press-and-hold a row to drag it into a new order.
            .onMove { offsets, destination in
                Haptics.tap()
                viewModel.moveSavedPlace(from: offsets, to: destination)
            }
        } header: {
            Text("My Locations")
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var resultsSection: some View {
        Section {
            if isSearching && results.isEmpty {
                HStack {
                    ProgressView()
                    Text("Searching…").foregroundStyle(.white.opacity(0.6))
                }
                .listRowBackground(rowBackground)
            } else if results.isEmpty {
                Text("No matches found.")
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.subheadline)
                    .listRowBackground(rowBackground)
            }
            ForEach(results) { place in
                Button {
                    Haptics.tap()
                    Task {
                        await viewModel.select(place)
                        dismiss()
                    }
                } label: {
                    placeRow(place)
                }
                .listRowBackground(rowBackground)
                .listRowSeparatorTint(.white.opacity(0.12))
            }
        }
    }

    private func placeRow(_ place: Place) -> some View {
        HStack(spacing: 12) {
            Text(place.flag.isEmpty ? "📍" : place.flag)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(.white)
                if !place.subtitle.isEmpty {
                    Text(place.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            if viewModel.isSaved(place) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            let found = await viewModel.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }
}
