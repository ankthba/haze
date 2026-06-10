//
//  SettingsView.swift
//  Weather
//
//  Unit preferences.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: WeatherViewModel
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

            ScrollView {
                VStack(spacing: 20) {
                    Text("Settings")
                        .font(.serif(.largeTitle))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)

                    temperatureCard
                    windCard
                    sourceCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top) { topBar }
        }
        .colorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    // MARK: - Top bar

    private var topBar: some View {
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
    }

    // MARK: - Cards

    private var temperatureCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "thermometer.medium", title: "Temperature")
                Picker("Units", selection: $viewModel.temperatureUnit) {
                    Text("Fahrenheit °F").tag(TemperatureUnit.fahrenheit)
                    Text("Celsius °C").tag(TemperatureUnit.celsius)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .sensoryFeedback(.selection, trigger: viewModel.temperatureUnit)
            }
        }
    }

    private var windCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "wind", title: "Wind Speed")
                Picker("Units", selection: $viewModel.speedUnit) {
                    Text("mph").tag(SpeedUnit.mph)
                    Text("km/h").tag(SpeedUnit.kmh)
                    Text("m/s").tag(SpeedUnit.ms)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .sensoryFeedback(.selection, trigger: viewModel.speedUnit)
            }
        }
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

                Text("Open-Meteo blends leading national forecast models and picks the best fit for each location — no single-source bias.")
                    .font(.caption)
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
        .font(.system(.subheadline, weight: .medium))
    }
}
