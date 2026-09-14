//
//  MacStates.swift
//  HazeMac
//
//  What the page shows before there's a forecast: the wordmark breathing on
//  the window's sky while the first fetch is out, and a quiet apology with a
//  way forward when it fails.
//

import SwiftUI

struct MacLoadingView: View {
    /// Which forecast the fetch is out for, so the credit at the foot names
    /// it before the page does.
    let source: ForecastSource

    @State private var breathe = false

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                Spacer()

                Text("haze°")
                    .font(.displaySerif(size: 96))
                    .foregroundStyle(.white)
                    .opacity(breathe ? 1 : 0.82)
                    .animation(UIPrefs.shared.reduceMotion
                               ? nil
                               : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                               value: breathe)

                Text("Gathering the skies…")
                    .font(.serif(.title3, italic: true))
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                Text(source.attributionLine)
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 18)
            }
        }
        .onAppear { breathe = true }
    }
}

struct MacErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onSearch: () -> Void

    var body: some View {
        ZStack {
            // The sky deepens under bad news.
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Couldn't load weather")
                    .font(.serif(.title2))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.serif(.subheadline))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                HStack(spacing: 12) {
                    Button(action: onRetry) {
                        Text("Try again")
                            .font(.serif(.body, weight: .medium))
                            // The prominent pill takes the white tint, and
                            // the label would otherwise be white on white.
                            .foregroundStyle(Color(hex: 0x0B1020))
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    Button(action: onSearch) {
                        Text("Search a city")
                            .font(.serif(.body, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }
                .tint(.white)
                .padding(.top, 6)
            }
        }
        .colorScheme(.dark)
    }
}
