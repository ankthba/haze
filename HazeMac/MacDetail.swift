//
//  MacDetail.swift
//  HazeMac
//
//  The page. On a wide window it's a spread: the hero (date, place, the big
//  numeral, the brief, the next sun events) holds the left page while the cards
//  scroll on the right, so the temperature never scrolls away from you. In a
//  narrower window it folds back into the single column the iPhone uses. The
//  floating controls at the top are the iPhone's: the locations button (here
//  it folds the column away), the advisory pill, radar, and settings.
//

import SwiftUI

struct MacDetail: View {
    @Bindable var viewModel: WeatherViewModel
    @Bindable var windows: MacWindows

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var selectedDay: DayForecast?

    private var alerts: [WeatherAlert] { viewModel.bundle?.alerts ?? [] }

    var body: some View {
        ZStack(alignment: .top) {
            switch viewModel.phase {
            case .idle where viewModel.bundle == nil,
                 .loading where viewModel.bundle == nil:
                MacLoadingView()
            case .failed(let message) where viewModel.bundle == nil:
                MacErrorView(message: message) {
                    Task { await viewModel.bootstrap() }
                } onSearch: {
                    windows.requestSearchFocus()
                }
            default:
                if let bundle = viewModel.bundle {
                    MacWeatherPage(bundle: bundle, viewModel: viewModel, windows: windows,
                                   selectedDay: $selectedDay)
                        .transition(.opacity)
                } else {
                    MacLoadingView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: viewModel.bundle?.place.id)
        .overlay(alignment: .top) {
            // Content dissolves up into the top controls instead of sliding
            // under a hard edge, the same soft edge the iPhone has at its
            // status bar; the buttons stay crisp above it.
            TopScrollBlur(maxRadius: 8, height: 72)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) { topBar }
        .navigationTitle(viewModel.bundle?.place.name ?? "Haze")
        .sheet(item: $selectedDay) { day in
            if let bundle = viewModel.bundle {
                DayDetailView(day: day, bundle: bundle,
                              unit: viewModel.temperatureUnit,
                              speedUnit: viewModel.speedUnit)
            }
        }
    }

    /// The iPhone's floating top controls, in the same glass, one per job.
    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap()
                windows.sidebarVisible.toggle()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(CardButtonStyle())
            .help(windows.sidebarVisible ? "Hide locations (⌃⌘S)" : "Show locations (⌃⌘S)")
            .accessibilityLabel("Locations")

            // An advisory takes the whole span between the controls, at the
            // same height and in the same family, rather than pushing the page
            // down or shrink-wrapping to its text.
            if !alerts.isEmpty {
                AlertPill(alerts: alerts) { windows.showAlerts = true }
                    .padding(.horizontal, 10)
            } else {
                Spacer()
            }

            Button {
                Haptics.tap()
                openWindow(id: MacWindows.radarWindowID)
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(CardButtonStyle())
            .disabled(viewModel.bundle == nil)
            .help("Precipitation radar (⇧⌘R)")
            .accessibilityLabel("Precipitation radar")

            Button {
                Haptics.tap()
                openSettings()
            } label: {
                Image(systemName: "thermometer.variable.and.figure")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(CardButtonStyle())
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }
}

// MARK: - The page

struct MacWeatherPage: View {
    let bundle: WeatherBundle
    @Bindable var viewModel: WeatherViewModel
    @Bindable var windows: MacWindows
    @Binding var selectedDay: DayForecast?

    @Environment(\.openWindow) private var openWindow

    /// Narrower than this and the spread folds into one column.
    private static let spreadMinimumWidth: CGFloat = 900
    private static let heroWidth: CGFloat = 400
    private static let columnMaxWidth: CGFloat = 620

    private var condition: WeatherCondition { bundle.current.condition }
    private var nowcast: RainNowcast? { viewModel.nowcast }
    private var rainLikelyToday: Bool { viewModel.rainLikelyToday }

    /// Height of the floating controls' row, kept clear at the top of the page.
    static let topInset: CGFloat = 62

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= Self.spreadMinimumWidth {
                spread
            } else {
                column
            }
        }
        .colorScheme(.dark)
    }

    // MARK: Spread

    private var spread: some View {
        HStack(spacing: 0) {
            hero
                .frame(width: Self.heroWidth)

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(width: 0.6)
                .padding(.vertical, 48)

            ScrollView {
                LazyVStack(spacing: 36) {
                    cards
                    colophon(showsStamp: false)
                }
                .frame(maxWidth: Self.columnMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 44)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top) { Color.clear.frame(height: Self.topInset) }
        }
    }

    /// The left page: everything the iPhone puts above the fold, held still.
    private var hero: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            CurrentConditionsView(bundle: bundle,
                                  unit: viewModel.temperatureUnit,
                                  nowcastLine: nowcast?.sentence(timezone: bundle.timezone,
                                                                 voice: viewModel.voice))
            if viewModel.showDailyBrief {
                DailyBriefCard(text: viewModel.briefText)
            }

            Spacer(minLength: 0)

            // The next sunset and sunrise, each half a door to the sun page.
            BottomStatusBar(bundle: bundle,
                            homeSummary: nil,
                            onReturnHome: {},
                            onSunTap: { kind in windows.openSun(kind) })

            Text(Fmt.updatedStamp(bundle.fetchedAt, timezone: bundle.timezone))
                .font(.serif(.caption))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 32)
        .padding(.top, Self.topInset)
        .padding(.bottom, 26)
    }

    // MARK: Column

    private var column: some View {
        ScrollView {
            LazyVStack(spacing: 36) {
                VStack(spacing: 14) {
                    CurrentConditionsView(bundle: bundle,
                                          unit: viewModel.temperatureUnit,
                                          nowcastLine: nowcast?.sentence(timezone: bundle.timezone,
                                                                         voice: viewModel.voice))
                    if viewModel.showDailyBrief {
                        DailyBriefCard(text: viewModel.briefText)
                    }
                    BottomStatusBar(bundle: bundle,
                                    homeSummary: nil,
                                    onReturnHome: {},
                                    onSunTap: { kind in windows.openSun(kind) })
                        .padding(.top, 10)
                }
                .padding(.bottom, -6)

                cards
                colophon(showsStamp: true)
            }
            .frame(maxWidth: Self.columnMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top) { Color.clear.frame(height: Self.topInset) }
    }

    // MARK: Cards

    private var cards: some View {
        ForEach(viewModel.cardOrder) { card in
            homeCard(card)
        }
    }

    /// One reorderable block of the page, in the user's chosen order; the same
    /// set the iPhone shows.
    @ViewBuilder
    private func homeCard(_ card: WeatherViewModel.HomeCard) -> some View {
        switch card {
        case .hourly:
            HourlyForecastCard(bundle: bundle)
        case .trend:
            if viewModel.showTrendCard {
                TemperatureTrendCard(bundle: bundle, accent: condition.accent,
                                     showPrecip: !rainLikelyToday)
            }
            if rainLikelyToday {
                PrecipChanceCard(bundle: bundle)
            }
        case .daily:
            DailyForecastCard(bundle: bundle, accent: condition.accent) { day in
                selectedDay = day
            }
        case .radar:
            if viewModel.showRadarPreview {
                RadarPreviewCard(place: bundle.place,
                                 accent: condition.accent,
                                 isDay: bundle.current.isDay) {
                    openWindow(id: MacWindows.radarWindowID)
                }
            }
        case .details:
            DetailsSection(bundle: bundle,
                           unit: viewModel.temperatureUnit,
                           speedUnit: viewModel.speedUnit,
                           showWindCompass: viewModel.showWindCompass,
                           showSunCard: viewModel.showSunCard,
                           voice: viewModel.voice)
        }
    }

    /// The page's small print. The spread already stamps the update time
    /// under the hero, so only the column repeats it.
    private func colophon(showsStamp: Bool) -> some View {
        VStack(spacing: 8) {
            if showsStamp {
                Text(Fmt.updatedStamp(bundle.fetchedAt, timezone: bundle.timezone))
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text("Data from Open-Meteo, blending ECMWF, GFS & ICON models")
                .font(.serif(.caption2))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 6)
    }
}
