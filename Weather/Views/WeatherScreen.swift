//
//  WeatherScreen.swift
//  Weather
//
//  The scrolling weather experience over the animated sky.
//

import SwiftUI

struct WeatherScreen: View {
    let bundle: WeatherBundle
    @Bindable var viewModel: WeatherViewModel
    @Binding var showSearch: Bool
    @Binding var showSettings: Bool
    @Binding var showRadar: Bool
    /// Room to leave at the foot for the floating city panel, which now lives
    /// above this screen in the carousel.
    var bottomInset: CGFloat = 0

    @State private var selectedDay: DayForecast?
    @State private var showAlerts = false
    @State private var topBarOpacity: Double = 1

    private var condition: WeatherCondition { bundle.current.condition }

    private var activeAlerts: [WeatherAlert] { bundle.alerts ?? [] }

    // Rain timing, the brief's prose, and today's rain likelihood are derived
    // once per reading by the view model; computing them here made every
    // frame of a city swipe re-walk the hourly series.
    private var nowcast: RainNowcast? { viewModel.nowcast }
    private var briefText: String { viewModel.briefText }
    private var rainLikelyToday: Bool { viewModel.rainLikelyToday }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(condition: condition,
                          now: Date(),
                          sunrise: bundle.today?.sunrise,
                          sunset: bundle.today?.sunset)

            ScrollView {
                // Lazy so the first frame only builds what's actually on screen.
                // The radar preview in particular stands up a whole MKMapView
                // and starts pulling tiles; below the fold, that shouldn't be
                // competing with the forecast for the launch.
                LazyVStack(spacing: 36) {
                    // The brief rides directly under the hero as one unit, so
                    // the first card arrives a comfortable scroll sooner.
                    VStack(spacing: 14) {
                        CurrentConditionsView(bundle: bundle,
                                              unit: viewModel.temperatureUnit,
                                              nowcastLine: nowcast?.sentence(timezone: bundle.timezone,
                                                                             voice: viewModel.voice))
                        if viewModel.showDailyBrief {
                            DailyBriefCard(text: briefText)
                        }
                    }
                    .padding(.bottom, -6)

                    ForEach(viewModel.cardOrder) { card in
                        homeCard(card)
                    }

                    // Editorial share affordance: a colophon line, not chrome.
                    ShareLink(item: ForecastShareCard(bundle: bundle),
                              preview: SharePreview(
                                "\(bundle.place.name): \(Fmt.tempDegree(bundle.current.temperature)), \(condition.description)")) {
                        HStack(spacing: 7) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .medium))
                            Text("Share today's page")
                                .font(.serif(.subheadline, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.8)
                        )
                        .contentShape(Capsule())
                    }
                    .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                    .padding(.top, 6)

                    Text(Fmt.updatedStamp(bundle.fetchedAt, timezone: bundle.timezone))
                        .font(.serif(.caption))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 4)

                    Text("Data from Open-Meteo, blending ECMWF, GFS & ICON models")
                        .font(.serif(.caption2))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await viewModel.reload()
                Haptics.success()
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                // Fade the top controls out the moment the page starts to scroll.
                let target = max(0, min(1, 1 - y / 30))
                if abs(target - topBarOpacity) > 0.01 {
                    withAnimation(.easeOut(duration: 0.18)) { topBarOpacity = target }
                }
            }
            // Reserve room for the floating controls without drawing them inside
            // the scroll view, so the progressive top blur can sit *beneath* the
            // (still-sharp) buttons.
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 44) }
            // And room at the foot for the city panel, so the last card can
            // always be scrolled clear of it.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: bottomInset)
            }

            // Content eases into a progressive blur at both screen edges: sharp in
            // the middle, dissolving softly into the status bar above and refracting
            // into the sky below (the bottom band hugs the rounded bezel corners).
            TopScrollBlur(maxRadius: 8, height: 72)
                .allowsHitTesting(false)

            BottomBezelBlur(maxRadius: 8, height: 96, middleDrop: 48)
                .allowsHitTesting(false)

            // Floating top controls, kept crisp above the blur.
            topBar

        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85),
                   value: bundle.place.id)
        .colorScheme(.dark)
        // Keep the rain Live Activity in step with the nowcast while the app
        // is in front (starting one requires foreground anyway).
        .onAppear { syncRainActivity() }
        .onChange(of: bundle.fetchedAt) { syncRainActivity() }
        .sheet(item: $selectedDay) { day in
            DayDetailView(day: day,
                          bundle: bundle,
                          unit: viewModel.temperatureUnit,
                          speedUnit: viewModel.speedUnit)
        }
        .sheet(isPresented: $showAlerts) {
            AlertDetailView(alerts: activeAlerts)
        }
    }

    private func syncRainActivity() {
        RainActivityManager.sync(
            nowcast: nowcast,
            bundle: bundle,
            usesInches: viewModel.precipUnit
                .apiValue(temperatureUnit: viewModel.temperatureUnit) == "inch")
    }

    /// One reorderable block of the main screen, in the user's chosen order.
    @ViewBuilder
    private func homeCard(_ card: WeatherViewModel.HomeCard) -> some View {
        switch card {
        case .hourly:
            HourlyForecastCard(bundle: bundle)
        case .trend:
            // The dedicated rain card rides with the trend chart; it only
            // appears when there's a real chance today, and when it does the
            // precip underlay is dropped from the trend so rain isn't shown twice.
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
                    showRadar = true
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

    private var topBar: some View {
        HStack {
            Button {
                showSearch = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityLabel("Locations")

            // An advisory takes the whole span between the controls, at the
            // same height and in the same family, rather than pushing the page
            // down or shrink-wrapping to its text.
            if !activeAlerts.isEmpty {
                AlertPill(alerts: activeAlerts) { showAlerts = true }
                    .padding(.horizontal, 10)
            } else {
                Spacer()
            }

            Button {
                showRadar = true
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityLabel("Precipitation radar")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "thermometer.variable.and.figure")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityLabel("Settings")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .opacity(topBarOpacity)
        .allowsHitTesting(topBarOpacity > 0.1)
    }
}
