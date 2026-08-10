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

    @State private var selectedDay: DayForecast?
    @State private var topBarOpacity: Double = 1

    private var condition: WeatherCondition { bundle.current.condition }

    /// True when there's a meaningful chance of rain during the rest of *today*.
    /// Drives both the dedicated rain card and de-duping the trend underlay.
    private var rainLikelyToday: Bool {
        let todays = bundle.upcomingHours.filter {
            Fmt.isToday($0.date, timezone: bundle.timezone)
        }
        let pool = todays.isEmpty ? bundle.upcomingHours : todays
        return (pool.map(\.precipitationProbability).max() ?? 0) >= 30
    }

    var body: some View {
        ZStack(alignment: .top) {
            SkyBackground(condition: condition,
                          now: Date(),
                          sunrise: bundle.today?.sunrise,
                          sunset: bundle.today?.sunset)

            ScrollView {
                VStack(spacing: 36) {
                    CurrentConditionsView(bundle: bundle, unit: viewModel.temperatureUnit)
                        .padding(.bottom, 14)

                    ForEach(viewModel.cardOrder) { card in
                        homeCard(card)
                    }

                    Text(Fmt.updatedStamp(bundle.fetchedAt, timezone: bundle.timezone))
                        .font(.serif(.caption))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 4)

                    Text("Data from Open-Meteo, blending ECMWF, GFS & ICON models")
                        .font(.serif(.caption2))
                        .foregroundStyle(.white.opacity(0.4))
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
        .colorScheme(.dark)
        .sheet(item: $selectedDay) { day in
            DayDetailView(day: day,
                          bundle: bundle,
                          unit: viewModel.temperatureUnit,
                          speedUnit: viewModel.speedUnit)
        }
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
                           showSunCard: viewModel.showSunCard)
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

            Spacer()

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
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .opacity(topBarOpacity)
        .allowsHitTesting(topBarOpacity > 0.1)
    }
}
