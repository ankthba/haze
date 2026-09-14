//
//  SettingsView.swift
//  Weather
//
//  Preferences: appearance (text size), units, time format, the voice the
//  forecast is written in, home-screen cards, radar behavior, haptics, and
//  where the forecast comes from (with the key Google's WeatherNext needs).
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Bindable var viewModel: WeatherViewModel
    /// Set when the page lives in the Mac's side panel: it then wears the
    /// radar's pinned header, with the panel's grow and close controls.
    var onClose: (() -> Void)? = nil
    var onToggleExpand: (() -> Void)? = nil
    var isExpanded = false

    @Bindable var prefs = UIPrefs.shared
    @Environment(\.dismiss) private var dismiss

    /// What the system has queued, and whether it will deliver any of it.
    @State private var pendingNotifications: [(id: String, fires: Date)] = []
    @State private var notificationsDenied = false
    @State private var testSent = false

    private var inPanel: Bool { onClose != nil }

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

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 20) {
                        Text("Settings")
                            .font(.serif(.largeTitle))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)

                        // Grouped by what each setting actually governs, in
                        // the order a reader meets them: the numbers on the
                        // page, then what the app says unprompted, then how
                        // the page looks, then how the app behaves, then the
                        // things you set once and forget.
                        groupHeading("Reading")
                        unitsCard
                        timeCard

                        groupHeading("Alerts")
                        notificationsCard
                            .id("notifications")

                        groupHeading("The page")
                        homeScreenCard
                        cardOrderCard
                        textSizeCard
                        accessibilityCard
                        voiceCard
                        #if os(iOS)
                        appIconCard
                        #endif

                        groupHeading("Behavior")
                        behaviorCard
                        #if os(macOS)
                        macCard
                        #endif

                        groupHeading("About")
                        sourceCard
                        aboutCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                    // Pin the content's width to the scroll container: without this
                    // a child with a wide intrinsic size (segmented pickers at large
                    // type) widens the content and the vertical scroller starts
                    // panning sideways. (On the Mac the "container" resolves to
                    // the window, which would spread a panel's content across
                    // the whole window; the glass controls there have no wide
                    // intrinsic size, so the plain frame is enough.)
                    .pinnedToContainerWidth()
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .top) {
                    Color.clear.frame(height: inPanel ? 58 : Platform.sheetTopInset)
                }
                // Screenshot/automation hook, a sibling of -openSettings.
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("-scrollToNotifications") {
                        proxy.scrollTo("notifications", anchor: .top)
                    }
                }
            }

            // Content dissolves into the status bar instead of colliding with it.
            TopScrollBlur(maxRadius: 8, height: 72)
                .allowsHitTesting(false)

            #if os(iOS)
            topBar
            #else
            if inPanel { panelHeader }
            #endif
        }
        .colorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    /// A quiet rule between groups of cards. Lowercase small serif rather
    /// than a boxed header: the cards are already the structure, this only
    /// says where one subject ends and the next begins.
    private func groupHeading(_ title: String) -> some View {
        Text(title)
            .font(.serif(.subheadline, italic: true))
            .foregroundStyle(.white.opacity(0.65))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
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

    /// The panel's controls, on the window's own top row; the page's title
    /// stays with the page below.
    private var panelHeader: some View {
        VStack {
            HStack(alignment: .top) {
                Spacer(minLength: 12)
                if let onToggleExpand {
                    Button {
                        Haptics.tap()
                        onToggleExpand()
                    } label: {
                        Image(systemName: isExpanded
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(CardButtonStyle())
                    .help(isExpanded ? "Back to a column" : "Fill the page")
                }
                Button {
                    Haptics.tap()
                    onClose?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(CardButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Close (Esc)")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.top, 7)
            Spacer()
        }
    }

    // MARK: - Cards

    private var textSizeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "textformat.size", title: "Text Size")
                SegmentedChoice(selection: $viewModel.textSize,
                                options: WeatherViewModel.TextSize.allCases.map { ($0.label, $0) })
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
                SegmentedChoice(selection: $viewModel.timeFormat,
                                options: [("Auto", .system), ("12-hour", .twelveHour),
                                          ("24-hour", .twentyFourHour)])
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
        .hazeToggleStyle()
        .tint(.white.opacity(0.35))
        .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
    }

    /// When the device-wide accessibility setting is on, the row shows as on
    /// and locks: the in-app toggle is an override for turning a behavior on,
    /// never a way to fight the system setting off.
    private func accessibilityToggle(_ label: String,
                                     isOn: Binding<Bool>,
                                     systemOn: Bool) -> some View {
        settingToggle(label,
                      isOn: systemOn ? .constant(true) : isOn)
            .disabled(systemOn)
    }

    #if os(iOS)
    private var appIconCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(systemImage: "app.badge", title: "App Icon")
                AppIconPicker()
            }
        }
    }
    #endif

    #if os(macOS)
    @AppStorage(Platform.menuBarKey) private var showsMenuBar = true

    /// What only a Mac can do: live in the menu bar.
    private var macCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(systemImage: "menubar.rectangle", title: "Menu Bar")

                settingToggle("Show the temperature in the menu bar", isOn: $showsMenuBar)

                Text("A glance without switching apps: the current reading, today's range, and the next few hours, one click away.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    #endif

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

    /// The register every composed sentence in the app is written in. The
    /// specimens underneath are the real thing, set the way the brief and a
    /// notification would set them, so the choice is made by reading rather
    /// than by guessing what "whimsy" means.
    private var voiceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(systemImage: "sparkles", title: "Voice")

                settingToggle("Whimsy mode", isOn: $viewModel.whimsyEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.voice.specimen)
                        .font(.serif(.callout, italic: true))
                        .foregroundStyle(.white.opacity(0.9))
                        .contentTransition(.opacity)
                    Text(viewModel.voice.notificationSpecimen)
                        .font(.serif(.caption, italic: true))
                        .foregroundStyle(.white.opacity(0.62))
                        .contentTransition(.opacity)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 0.6)
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.whimsyEnabled)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Sample, \(viewModel.voice.specimen) \(viewModel.voice.notificationSpecimen)")

                Text("Whimsy mode rewrites the daily brief, the rain timing line, the sunrise and sunset verdicts, and every notification with a bit more charm in it. The forecast itself never changes, and severe-weather advisories always read plainly.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var unitsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                CardLabel(systemImage: "ruler", title: "Units")

                unitRow("Temperature") {
                    SegmentedChoice(selection: $viewModel.temperatureUnit,
                                    options: [("°F", .fahrenheit), ("°C", .celsius)])
                        .sensoryFeedback(.selection, trigger: viewModel.temperatureUnit)
                }
                unitRow("Wind") {
                    SegmentedChoice(selection: $viewModel.speedUnit,
                                    options: [("mph", .mph), ("km/h", .kmh), ("m/s", .ms)])
                        .sensoryFeedback(.selection, trigger: viewModel.speedUnit)
                }
                unitRow("Precipitation") {
                    SegmentedChoice(selection: $viewModel.precipUnit,
                                    options: [("Auto", .auto), ("in", .inch), ("mm", .mm)])
                        .sensoryFeedback(.selection, trigger: viewModel.precipUnit)
                }
                unitRow("Pressure") {
                    SegmentedChoice(selection: $viewModel.pressureUnit,
                                    options: [("hPa", .hPa), ("inHg", .inHg)])
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
        }
    }

    private var notificationsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(systemImage: "bell", title: "Notifications")

                // Every toggle below is a lie while the system says no, and
                // nothing else in the app would ever tell the reader that.
                if notificationsDenied {
                    permissionWarning
                }

                settingToggle("Rain & advisories", isOn: $viewModel.notificationsEnabled)
                Divider().overlay(Color.white.opacity(0.12))

                settingToggle("Morning digest", isOn: $viewModel.morningDigestEnabled)
                if viewModel.morningDigestEnabled {
                    HStack {
                        Text("Arrives at")
                            .font(.serif(.subheadline, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        HazeTimePicker(date: $viewModel.digestTime,
                                       timeFormat: viewModel.timeFormat)
                    }
                }
                Divider().overlay(Color.white.opacity(0.12))

                settingToggle("Golden-hour heads-up", isOn: $viewModel.goldenHourEnabled)
                Divider().overlay(Color.white.opacity(0.12))

                settingToggle("Sunset alerts", isOn: $viewModel.sunsetAlertEnabled)
                if viewModel.sunsetAlertEnabled {
                    sunAlertOptions(lead: $viewModel.sunsetAlertLeadMinutes,
                                    gate: $viewModel.sunsetAlertGate)
                }
                Divider().overlay(Color.white.opacity(0.12))

                settingToggle("Sunrise alerts", isOn: $viewModel.sunriseAlertEnabled)
                if viewModel.sunriseAlertEnabled {
                    sunAlertOptions(lead: $viewModel.sunriseAlertLeadMinutes,
                                    gate: $viewModel.sunriseAlertGate)

                    // Midsummer sunrises are early enough that a lead time
                    // alone will wake you in the small hours.
                    settingToggle("Never before a set time",
                                  isOn: $viewModel.sunriseEarliestEnabled)
                    if viewModel.sunriseEarliestEnabled {
                        HStack {
                            Text("Not before")
                                .font(.serif(.subheadline, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            HazeTimePicker(date: $viewModel.sunriseEarliestTime,
                                           timeFormat: viewModel.timeFormat)
                        }
                    }

                    // A heads-up forty-five minutes before sunrise is no use
                    // if you are asleep; this one arrives while there is still
                    // time to set an alarm.
                    settingToggle("Tell me the evening before",
                                  isOn: $viewModel.sunriseEveningEnabled)
                    if viewModel.sunriseEveningEnabled {
                        HStack {
                            Text("Arrives at")
                                .font(.serif(.subheadline, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            HazeTimePicker(date: $viewModel.sunriseEveningTime,
                                           timeFormat: viewModel.timeFormat)
                        }
                    }
                }

                Text("Sun alerts arrive ahead of the event, and only when its rating clears the bar you set. Great skies are rare; that's what makes the alert worth having. An alert that would land before your set time is skipped rather than moved, since one arriving after the sunrise it announces is no use. The evening heads-up describes the next morning, so there is still time to set an alarm.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(Color.white.opacity(0.12))
                notificationDiagnostics
            }
        }
        .task { await refreshNotificationState() }
    }

    // MARK: - Notification plumbing

    /// Proof the chain works, and a look at what is actually queued. Without
    /// this every setting above can only be tested by waiting for dawn.
    private var notificationDiagnostics: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scheduled")
                    .font(.serif(.subheadline, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button {
                    Task {
                        testSent = await NotificationPlanner.sendTest()
                        await refreshNotificationState()
                    }
                } label: {
                    Text(testSent ? "Sent" : "Send a test")
                        .font(.serif(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(GlassSurface(shape: Capsule(), frost: 0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .disabled(notificationsDenied)
                .opacity(notificationsDenied ? 0.4 : 1)
            }

            if pendingNotifications.isEmpty {
                Text("Nothing queued right now.")
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pendingNotifications, id: \.id) { item in
                        HStack {
                            Text(Self.scheduledName(item.id))
                            Spacer()
                            Text(Self.scheduledWhen(item.fires))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .font(.serif(.caption))
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
    }

    private var permissionWarning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are switched off for Haze in system settings, so nothing below will arrive.")
                #if os(iOS)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: url) {
                        Text("Open Settings")
                            .font(.serif(.caption, weight: .medium))
                            .underline()
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                #endif
            }
        }
        .font(.serif(.caption))
        .foregroundStyle(.white.opacity(0.8))
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The scheduled ids are internal strings; these are what they mean.
    private static func scheduledName(_ id: String) -> String {
        switch id {
        case "morning-digest": "Morning digest"
        case "golden-hour": "Golden hour"
        case "sunset-alert": "Sunset"
        case "sunrise-alert": "Sunrise"
        case "sunrise-evening": "Tomorrow's sunrise"
        case "haze-test": "Test"
        default: id
        }
    }

    /// "7:30 AM" for today, "Tomorrow 7:30 AM" beyond it: almost everything
    /// queued here fires tomorrow, and a bare time reads as today.
    private static func scheduledWhen(_ date: Date) -> String {
        let time = Fmt.time(date, timezone: .current)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return time }
        if cal.isDateInTomorrow(date) { return "Tomorrow \(time)" }
        return "\(Fmt.weekday(date, timezone: .current)) \(time)"
    }

    private func refreshNotificationState() async {
        pendingNotifications = await NotificationPlanner.pending()
        notificationsDenied = await NotificationPlanner.authorizationStatus() == .denied
    }

    /// Lead-time and quality-bar controls, shown while an alert is on. The
    /// menus wear the app's serif rather than the system picker chrome.
    private func sunAlertOptions(lead: Binding<Int>,
                                 gate: Binding<SunQuality.AlertGate>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            optionRow("Heads-up", value: Self.leadLabel(lead.wrappedValue)) {
                Picker("Heads-up", selection: lead) {
                    ForEach([10, 15, 20, 30, 45, 60, 90, 120], id: \.self) { minutes in
                        Text(Self.leadLabel(minutes)).tag(minutes)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: lead.wrappedValue)

            optionRow("Only when", value: gate.wrappedValue.label) {
                Picker("Only when", selection: gate) {
                    ForEach(SunQuality.AlertGate.allCases) { gate in
                        Text(gate.label).tag(gate)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: gate.wrappedValue)
        }
        .padding(.leading, 2)
    }

    private static func leadLabel(_ minutes: Int) -> String {
        switch minutes {
        case 60: "1 hour before"
        case 90: "90 min before"
        case 120: "2 hours before"
        default: "\(minutes) min before"
        }
    }

    private func optionRow(_ label: String, value: String,
                           @ViewBuilder picker: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.serif(.subheadline, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Menu {
                picker()
            } label: {
                HStack(spacing: 5) {
                    Text(value)
                        .font(.serif(.subheadline, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(0.6)
                }
                .foregroundStyle(.white)
                .contentShape(Rectangle())
            }
        }
    }

    private var behaviorCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                CardLabel(systemImage: "gearshape", title: "Behavior")

                settingToggle("Start from my location", isOn: $viewModel.useDeviceLocation)
                Divider().overlay(Color.white.opacity(0.12))
                settingToggle("Radar plays automatically", isOn: $viewModel.radarAutoplay)
                Divider().overlay(Color.white.opacity(0.12))
                settingToggle(Platform.isMac ? "Trackpad feedback" : "Haptic feedback",
                              isOn: $viewModel.hapticsEnabled)
                Divider().overlay(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Refresh while open")
                        .font(.serif(.subheadline, weight: .medium))
                        .foregroundStyle(.white)
                    SegmentedChoice(selection: $viewModel.refreshMinutes,
                                    options: [("5 min", 5), ("15 min", 15),
                                              ("30 min", 30), ("1 hr", 60)])
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

    /// Where the forecast comes from. Google's WeatherNext is opt-in and, unless
    /// the build ships a key of its own, needs the reader's: the field lives
    /// here so the choice, the key, and the attribution Google asks for sit
    /// together. The control and blurb follow the choice; the rows and the
    /// Google credit describe what is actually feeding the app, so with
    /// WeatherNext chosen and no key they read Open-Meteo, and the caption
    /// under the key field says why. When a key is present but Google turned
    /// the request down, Google's own message sits under the field, so the
    /// reader fixing the key can see what was objected to.
    private var sourceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                CardLabel(systemImage: "antenna.radiowaves.left.and.right", title: "Data")

                // A one-option picker is worse than none, so the control only
                // appears when there is a real choice to make.
                if WeatherNextFeature.isEnabled {
                    unitRow("Forecast source") {
                        SegmentedChoice(selection: $viewModel.forecastSource,
                                        options: ForecastSource.selectable.map { ($0.label, $0) })
                            .sensoryFeedback(.selection, trigger: viewModel.forecastSource)
                    }
                }

                VStack(spacing: 10) {
                    sourceRow(label: "Source", value: viewModel.effectiveSource.sourceName)
                    Divider().overlay(Color.white.opacity(0.12))
                    sourceRow(label: "Models", value: viewModel.effectiveSource.modelsName)
                }

                if WeatherNextFeature.isEnabled,
                   viewModel.forecastSource == .weatherNext, !WeatherNextKey.isBuiltIn {
                    weatherNextKeySection
                } else if let notice = weatherNextNotice {
                    // With the key built in there is no field to sit under,
                    // so the reason follows the rows describing the source.
                    sourceNoticeRow(notice)
                }

                Text(viewModel.forecastSource.blurb)
                    .font(.serif(.caption))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                if WeatherNextFeature.isEnabled, viewModel.forecastSource == .weatherNext {
                    // Google meters the hourly pages against a daily quota,
                    // and a unit change used to refetch everything; this is
                    // the reader's warning about the first and reassurance
                    // about the second.
                    Text("Hourly forecasts cost the most, ten calls a refresh, because Google serves them a day at a time. Haze reuses Google's last answer for the refresh interval, so changing units or relaunching in that window costs nothing.")
                        .font(.serif(.caption))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.effectiveSource == .weatherNext {
                    // Google's attribution policy asks for this line, verbatim.
                    Text("Includes weather data from Google")
                        .font(.serif(.caption))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The key field and its guidance, shown while WeatherNext is chosen and
    /// the build carries no key of its own.
    private var weatherNextKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            weatherNextKeyField

            if let notice = weatherNextNotice {
                sourceNoticeRow(notice)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("A Google Maps Platform key with the Weather API enabled is required.")
                if let url = URL(string: "https://developers.google.com/maps/documentation/weather/get-api-key") {
                    Link(destination: url) {
                        Text("Get a key")
                            .font(.serif(.caption, weight: .medium))
                            .underline()
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                if weatherNextKeyMissing {
                    Text("Using Classic Haze until a key is added.")
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .font(.serif(.caption))
            .foregroundStyle(.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `WeatherNextKey` reads UserDefaults, which a view cannot observe, so
    /// the view model's copy of the key is consulted first: that read is what
    /// makes the caption follow the typing. `WeatherNextKey` then gives the
    /// verdict, since it also knows about a key shipped in the Info.plist.
    private var weatherNextKeyMissing: Bool {
        viewModel.weatherNextKeyOverride.isEmpty && !WeatherNextKey.isConfigured
    }

    /// Why the page differs from the WeatherNext choice: a fallback to Classic
    /// Haze, or hours borrowed from Open-Meteo while Google's quota is spent.
    /// The service composes the sentence, so it is shown verbatim. Only while
    /// WeatherNext is still the choice: once the reader switches back, a
    /// stale reason has nothing left to explain.
    private var weatherNextNotice: String? {
        guard WeatherNextFeature.isEnabled,
              viewModel.forecastSource == .weatherNext else { return nil }
        return viewModel.bundle?.sourceNotice
    }

    private func sourceNoticeRow(_ notice: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
            Text(notice)
                .font(.serif(.caption))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white.opacity(0.75))
    }

    /// The search bar's glass around a plain field. A key is pasted, not
    /// typed, so the iPhone keyboard's word helpers are switched off.
    private var weatherNextKeyField: some View {
        HStack(spacing: 10) {
            Image(systemName: "key")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            weatherNextKeyTextField

            if !viewModel.weatherNextKeyOverride.isEmpty {
                Button {
                    viewModel.weatherNextKeyOverride = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the key")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(GlassSurface(shape: Capsule(), frost: 0.18, blurRadius: 14))
    }

    private var weatherNextKeyTextField: some View {
        let field = TextField("", text: $viewModel.weatherNextKeyOverride,
                              prompt: Text("Google API key")
                                .foregroundStyle(.white.opacity(0.45)))
            .foregroundStyle(.white)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .submitLabel(.done)
        #if canImport(UIKit)
        return field
            .textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
        #else
        return field
        #endif
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
