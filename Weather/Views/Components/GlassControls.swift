//
//  GlassControls.swift
//  Weather
//
//  Settings controls in the app's own material. On the iPhone the system's
//  switch and segmented picker, tinted white, already sit well on the sky; on
//  the Mac they arrive as a checkbox and a bordered control, which read as
//  another app's. These wear the same glass as the buttons and cards.
//

import SwiftUI

/// A switch: a glass capsule track that frosts over when on, and a white knob.
struct HazeToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Button {
                Haptics.tap()
                configuration.isOn.toggle()
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(.white.opacity(configuration.isOn ? 0.5 : 0.12))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                        .padding(3)
                }
                .frame(width: 46, height: 26)
                .background(GlassSurface(shape: Capsule(), frost: 0.08))
                .clipShape(Capsule())
                .animation(UIPrefs.shared.reduceMotion ? nil
                           : .spring(response: 0.25, dampingFraction: 0.8),
                           value: configuration.isOn)
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
        }
    }
}

/// A row of choices in one glass capsule, the chosen one frosted. The system
/// segmented picker on the iPhone; the app's own on the Mac.
struct SegmentedChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(label: String, value: Value)]

    var body: some View {
        #if os(macOS)
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let chosen = option.value == selection
                Button {
                    guard !chosen else { return }
                    Haptics.selection()
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.serif(.subheadline, weight: chosen ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(chosen ? 1 : 0.7))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if chosen {
                                Capsule().fill(.white.opacity(0.22))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.6))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(GlassSurface(shape: Capsule(), frost: 0.08))
        .clipShape(Capsule())
        .animation(UIPrefs.shared.reduceMotion ? nil
                   : .spring(response: 0.25, dampingFraction: 0.85),
                   value: selection)
        #else
        Picker("", selection: $selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        #endif
    }
}
