//
//  GlassControls.swift
//  Weather
//
//  Settings controls in the app's own material, on every platform. These were
//  Mac-only at first, since the system switch and segmented picker on the
//  iPhone at least take a tint; but a tinted system control beside the app's
//  own glass reads as a seam, and the Mac's versions were simply better. So
//  the phone wears them too, and there is one set of controls to maintain.
//
//  Everything here follows the same rules as the cards: a glass surface, a
//  frosted selection, white at varying opacity for hierarchy, the serif face,
//  and no animation when Reduce Motion is on.
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

/// A row of choices in one glass capsule, the chosen one frosted.
struct SegmentedChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(label: String, value: Value)]

    var body: some View {
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
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background {
                            if chosen {
                                Capsule().fill(.white.opacity(0.22))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.6))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(chosen ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(GlassSurface(shape: Capsule(), frost: 0.08))
        .clipShape(Capsule())
        .animation(UIPrefs.shared.reduceMotion ? nil
                   : .spring(response: 0.25, dampingFraction: 0.85),
                   value: selection)
    }
}

/// A time of day, in the app's own material rather than the system's compact
/// date picker (a grey capsule on iOS, a stepper field on the Mac, neither of
/// them ours). Hour and minute are separate menus, which is also the fastest
/// way to set a time that only ever needs five-minute resolution.
struct HazeTimePicker: View {
    @Binding var date: Date
    /// Follows the app's own 12/24-hour setting, not just the locale's.
    var timeFormat: TimeFormat = Fmt.timeFormat

    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private var uses24Hour: Bool {
        switch timeFormat {
        case .twelveHour: return false
        case .twentyFourHour: return true
        case .system:
            let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0,
                                                    locale: .current) ?? "h"
            return !template.contains("a")
        }
    }

    private var hour: Int { calendar.component(.hour, from: date) }
    private var minute: Int { calendar.component(.minute, from: date) }

    /// Minutes land on a five-minute grid: a digest at 7:32 is not a setting
    /// anyone wants, and the shorter menu is far quicker to use.
    private static let minuteStep = 5

    var body: some View {
        HStack(spacing: 6) {
            menu(label: hourLabel(hour)) {
                ForEach(hourOptions, id: \.self) { h in
                    Button(hourLabel(h)) { setHour(h) }
                }
            }
            Text(":")
                .font(.serif(.subheadline, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            menu(label: String(format: "%02d", minute)) {
                ForEach(Array(stride(from: 0, to: 60, by: Self.minuteStep)), id: \.self) { m in
                    Button(String(format: "%02d", m)) { setMinute(m) }
                }
            }
            if !uses24Hour {
                menu(label: hour < 12 ? "AM" : "PM") {
                    Button("AM") { setMeridiem(pm: false) }
                    Button("PM") { setMeridiem(pm: true) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Time")
        .accessibilityValue(Fmt.time(date, timezone: .current))
    }

    /// 0…23 on a 24-hour clock; dial numbers (12 first, then 1…11) otherwise.
    private var hourOptions: [Int] {
        uses24Hour ? Array(0..<24) : [12] + Array(1..<12)
    }

    /// The label for an hour in whichever clock is in use. The stored hour is
    /// always 0…23, so in 12-hour mode it is folded onto the dial to display.
    private func hourLabel(_ h: Int) -> String {
        if uses24Hour { return String(format: "%02d", h) }
        let onDial = h % 12
        return String(onDial == 0 ? 12 : onDial)
    }

    // MARK: - Setters
    //
    // Each menu owns exactly one component, and every path ends at `apply`
    // with an unambiguous hour of day. Folding the dial number and the
    // meridiem in one place was a bug: choosing "AM" at 3 PM read the current
    // half of the day back off the very value it was trying to change, and
    // left it at 3 PM.

    /// The hour menu. In 12-hour mode its values are dial numbers, so the
    /// half of the day already chosen is carried over.
    private func setHour(_ h: Int) {
        guard !uses24Hour else { return apply(hour: h, minute: minute) }
        let onDial = h % 12                     // 12 reads as 0
        apply(hour: hour >= 12 ? onDial + 12 : onDial, minute: minute)
    }

    private func setMinute(_ m: Int) {
        apply(hour: hour, minute: m)
    }

    /// The meridiem menu: keep the dial number, move the half of the day.
    private func setMeridiem(pm: Bool) {
        let onDial = hour % 12
        apply(hour: pm ? onDial + 12 : onDial, minute: minute)
    }

    private func apply(hour h: Int, minute m: Int) {
        Haptics.selection()
        if let updated = calendar.date(bySettingHour: min(max(h, 0), 23),
                                       minute: min(max(m, 0), 59),
                                       second: 0, of: date) {
            date = updated
        }
    }

    private func menu(label: String, @ViewBuilder content: () -> some View) -> some View {
        Menu {
            content()
        } label: {
            Text(label)
                .font(.serif(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 30)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(GlassSurface(shape: Capsule(), frost: 0.08))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.6))
                .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }
}
