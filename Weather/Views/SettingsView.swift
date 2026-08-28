//
//  SettingsView.swift
//  Weather
//
//  Preferences: appearance (text size), units, time format, home-screen cards,
//  radar behavior, haptics, and data provenance.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: WeatherViewModel
    @Bindable var prefs = UIPrefs.shared
    @Environment(\.dismiss) private var dismiss

    // Sky derived from the current data, with safe fallbacks for a nil bundle.
    private var skyCondition: WeatherCondition {
        viewModel.bundle?.current.condition ?? WeatherCondition(code: 1, isDay: true)
    }
    private var skySunrise: Date? { viewModel.bundle?.today?.sunrise }
    private var skySunset: Date? { viewModel.bundle?.today?.sunset }

    var body: some View {
        ZStack {
            SkyBackground(condition: skyCondition,
                          now: Date(),
                          sunrise: skySunrise,
                          sunset: skySunset)

            ScrollView(.vertical) {
                VStack(spacing: 20) {
                    Text("Settings")
                        .font(.serif(.largeTitle))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)

                    textSizeCard
                    appIconCard
                    accessibilityCard
                    unitsCard
                    timeCard
                    cardOrderCard
                    homeScreenCard
                    behaviorCard
                    sourceCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
                // Pin the content's width to the scroll container: without this
                // a child with a wide intrinsic size (segmented pickers at large
                // type) widens the content and the vertical scroller starts
                // panning sideways.
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top) { Color.clear.frame(height: 44) }

            // Content dissolves into the status bar instead of colliding with it.
            TopScrollBlur(maxRadius: 8, height: 72)
                .allowsHitTesting(false)

            topBar
        }
        .colorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack {
            HStack {
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
            Spacer()
        }
    }

    // MARK: - Cards

    private var textSizeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "textformat.size", title: "Text Size")
                Picker("Text Size", selection: $viewModel.textSize) {
                    ForEach(WeatherViewModel.TextSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .sensoryFeedback(.selection, trigger: viewModel.textSize)

                Text("Scales every word and number in the app.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var timeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "clock", title: "Time Format")
                Picker("Time Format", selection: $viewModel.timeFormat) {
                    Text("Auto").tag(TimeFormat.system)
                    Text("12-hour").tag(TimeFormat.twelveHour)
                    Text("24-hour").tag(TimeFormat.twentyFourHour)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .sensoryFeedback(.selection, trigger: viewModel.timeFormat)
            }
        }
    }

    private var cardOrderCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(systemImage: "arrow.up.arrow.down", title: "Card Order")

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.cardOrder.enumerated()), id: \.element) { index, card in
                        HStack(spacing: 12) {
                            Image(systemName: card.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 24)

                            Text(card.title)
                                .font(.serif(.subheadline, weight: .medium))
                                .foregroundStyle(.white)

                            Spacer()

                            orderButton("chevron.up", disabled: index == 0) {
                                viewModel.moveCard(card, up: true)
                            }
                            orderButton("chevron.down",
                                        disabled: index == viewModel.cardOrder.count - 1) {
                                viewModel.moveCard(card, up: false)
                            }
                        }
                        .padding(.vertical, 8)

                        if index < viewModel.cardOrder.count - 1 {
                            Divider().overlay(Color.white.opacity(0.12))
                        }
                    }
                }

                Text("Arrange the main screen top to bottom.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func orderButton(_ symbol: String, disabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(disabled ? 0.2 : 0.7))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var homeScreenCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(systemImage: "rectangle.grid.1x2", title: "Home Screen")

                settingToggle("Daily brief", isOn: $viewModel.showDailyBrief)
                Divider().overlay(Color.white.opacity(0.12))
                settingToggle("72-hour trend chart", isOn: $viewModel.showTrendCard)
                Divider().overlay(Color.white.opacity(0.12))
                settingToggle("Radar preview", isOn: $viewModel.showRadarPreview)
                Divider().overlay(Color.white.opacity(0.12))
                settingToggle("Wind compass", isOn: $viewModel.showWindCompass)
                Divider().overlay(Color.white.opacity(0.12))
                settingToggle("Sunrise & sunset", isOn: $viewModel.showSunCard)

                Text("Hide the cards you don't reach for; the forecast itself always stays.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.serif(.subheadline, weight: .medium))
                .foregroundStyle(.white)
        }
        .tint(.white.opacity(0.35))
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }

    /// When the device-wide accessibility setting is on, the row shows as on
    /// and locks — the in-app toggle is an override for turning a behavior on,
    /// never a way to fight the system setting off.
    private func accessibilityToggle(_ label: String,
                                     isOn: Binding<Bool>,
                                     systemOn: Bool) -> some View {
        settingToggle(label,
                      isOn: systemOn ? .constant(true) : isOn)
            .disabled(systemOn)
    }

    private var appIconCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(systemImage: "app.badge", title: "App Icon")
                AppIconPicker()
            }
        }
    }

    private var accessibilityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(systemImage: "accessibility", title: "Accessibility")

                accessibilityToggle("Bold text",
                                    isOn: $prefs.boldTextOverride,
                                    systemOn: prefs.systemBoldText)
                Divider().overlay(Color.white.opacity(0.12))
                accessibilityToggle("Increase contrast",
                                    isOn: $prefs.increaseContrastOverride,
                                    systemOn: prefs.systemIncreaseContrast)
                Divider().overlay(Color.white.opacity(0.12))
                accessibilityToggle("Reduce transparency",
                                    isOn: $prefs.reduceTransparencyOverride,
                                    systemOn: prefs.systemReduceTransparency)
                Divider().overlay(Color.white.opacity(0.12))
                accessibilityToggle("Reduce motion",
                                    isOn: $prefs.reduceMotionOverride,
                                    systemOn: prefs.systemReduceMotion)

                Text("Bold text weights up all type; contrast deepens the sky behind it; transparency solidifies the frosted surfaces; motion stills the radar and pulsing icons. Device-wide accessibility settings apply automatically.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var unitsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                CardLabel(systemImage: "ruler", title: "Units")

                unitRow("Temperature") {
                    Picker("Temperature", selection: $viewModel.temperatureUnit) {
                        Text("°F").tag(TemperatureUnit.fahrenheit)
                        Text("°C").tag(TemperatureUnit.celsius)
                    }
                    .sensoryFeedback(.selection, trigger: viewModel.temperatureUnit)
                }
                unitRow("Wind") {
                    Picker("Wind", selection: $viewModel.speedUnit) {
                        Text("mph").tag(SpeedUnit.mph)
                        Text("km/h").tag(SpeedUnit.kmh)
                        Text("m/s").tag(SpeedUnit.ms)
                    }
                    .sensoryFeedback(.selection, trigger: viewModel.speedUnit)
                }
                unitRow("Precipitation") {
                    Picker("Precipitation", selection: $viewModel.precipUnit) {
                        Text("Auto").tag(PrecipUnit.auto)
                        Text("in").tag(PrecipUnit.inch)
                        Text("mm").tag(PrecipUnit.mm)
                    }
                    .sensoryFeedback(.selection, trigger: viewModel.precipUnit)
                }
                unitRow("Pressure") {
                    Picker("Pressure", selection: $viewModel.pressureUnit) {
                        Text("hPa").tag(PressureUnit.hPa)
                        Text("inHg").tag(PressureUnit.inHg)
                    }
                    .sensoryFeedback(.selection, trigger: viewModel.pressureUnit)
                }

                Text("Auto precipitation follows the temperature unit: inches with °F, millimetres with °C.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func unitRow(_ label: String,
                         @ViewBuilder picker: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.serif(.subheadline, weight: .medium))
                .foregroundStyle(.white)
            picker()
                .pickerStyle(.segmented)
                .labelsHidden()
        }
    }

    private var behaviorCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(systemImage: "gearshape", title: "Behavior")

                settingToggle("Start from my location", isOn: $viewModel.useDeviceLocation)
                Divider().overlay(Color.white.opacity(0.12))
                settingToggle("Rain & advisory notifications", isOn: $viewModel.notificationsEnabled)
                Divider().overlay(Color.white.opacity(0.12))
                settingToggle("Morning digest", isOn: $viewModel.morningDigestEnabled)
                if viewModel.morningDigestEnabled {
                    HStack {
                        Text("Arrives at")
                            .font(.serif(.subheadline, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        DatePicker("Digest time", selection: $viewModel.digestTime,
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .colorScheme(.dark)
                    }
                }
                Divider().overlay(Color.white.opacity(0.12))
                settingToggle("Golden-hour heads-up", isOn: $viewModel.goldenHourEnabled)
                Divider().overlay(Color.white.opacity(0.12))
                settingToggle("Radar plays automatically", isOn: $viewModel.radarAutoplay)
                Divider().overlay(Color.white.opacity(0.12))
                settingToggle("Haptic feedback", isOn: $viewModel.hapticsEnabled)
                Divider().overlay(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Refresh while open")
                        .font(.serif(.subheadline, weight: .medium))
                        .foregroundStyle(.white)
                    Picker("Refresh", selection: $viewModel.refreshMinutes) {
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 hr").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .sensoryFeedback(.selection, trigger: viewModel.refreshMinutes)
                }

                Text("When location is off, Haze opens with your first saved place.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var aboutCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "info.circle", title: "About")

                VStack(spacing: 10) {
                    sourceRow(label: "Version", value: appVersion)
                    Divider().overlay(Color.white.opacity(0.12))
                    sourceRow(label: "Typefaces", value: "EB Garamond · Instrument Serif")
                }

                Button {
                    Haptics.tap()
                    dismiss()
                    // Let the sheet settle before the intro takes over the screen.
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        viewModel.hasOnboarded = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                        Text("Replay the intro")
                            .font(.serif(.subheadline, weight: .medium))
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Text("Haze is designed and built by Aniketh Bandlamudi.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var sourceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "antenna.radiowaves.left.and.right", title: "Data")

                VStack(spacing: 10) {
                    sourceRow(label: "Source", value: "Open-Meteo")
                    Divider().overlay(Color.white.opacity(0.12))
                    sourceRow(label: "Models", value: "ECMWF · GFS · ICON")
                }

                Text("Open-Meteo blends leading national forecast models and picks the best fit for each location, with no single-source bias.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sourceRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
        }
        .font(.serif(.subheadline, weight: .medium))
    }
}
