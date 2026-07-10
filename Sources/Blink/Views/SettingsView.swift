import SwiftUI
import AppKit
import BlinkCore

struct SettingsView: View {
    @ObservedObject var timer: PomodoroTimer
    @Binding var settings: PomodoroSettings
    @State private var editingInstructionDirection: String?
    @State private var openCategory: SettingsCategory?
    @State private var searchText = ""

    var body: some View {
        ZStack {
            if let cat = openCategory {
                categoryPage(cat)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                rootList
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.26), value: openCategory)
    }

    // MARK: - Root: category list (macOS System Settings style)

    private var rootList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                rootHeader
                searchField
                if filteredCategories.isEmpty {
                    Text("No settings match “\(searchText)”.")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 8)
                } else {
                    SettingsCard {
                        ForEach(filteredCategories) { cat in
                            categoryRow(cat)
                        }
                    }
                }
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    /// Categories matching the search query (all when the query is empty).
    private var filteredCategories: [SettingsCategory] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsCategory.allCases }
        return SettingsCategory.allCases.filter { $0.matches(q) }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.5))
            TextField("Search settings", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.pressableSubtle)
                .foregroundStyle(.white.opacity(0.4))
            }
        }
        .font(.system(.body, design: .rounded))
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(.white.opacity(0.10), lineWidth: 1))
        .frame(maxWidth: 600)
    }

    /// The real app icon (same asset the main-window sidebar uses), so the app
    /// presents one brand mark instead of an eye glyph here and the icon there.
    private var appIcon: Image {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let ns = NSImage(contentsOf: url) {
            return Image(nsImage: ns)
        }
        return Image(systemName: "eye.fill")
    }

    private var rootHeader: some View {
        VStack(spacing: 10) {
            appIcon
                .resizable()
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            Text("Settings")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text("Tune your focus sessions, breaks, and eye-care.")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 6)
    }

    // MARK: - Category detail page

    private func categoryPage(_ cat: SettingsCategory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                categoryHeader(cat)
                categorySections(cat)
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    private func categoryHeader(_ cat: SettingsCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { openCategory = nil } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                    Text("Settings").font(.system(.callout, design: .rounded).weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.85))
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)

            HStack(spacing: 12) {
                Image(systemName: cat.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cat.tint.gradient))
                Text(cat.title)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryRow(_ cat: SettingsCategory) -> some View {
        Button { openCategory = cat } label: {
            HStack(spacing: 12) {
                Image(systemName: cat.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(cat.tint.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(cat.title)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(.white)
                    Text(cat.subtitle)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
    }

    @ViewBuilder
    private func categorySections(_ cat: SettingsCategory) -> some View {
        switch cat {
        case .timer:
                Section("Timer mode") {
                    Picker("Mode", selection: $settings.timerMode) {
                        ForEach(TimerMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Theme", selection: $settings.theme) {
                        ForEach(BlinkTheme.allCases, id: \.self) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    

                    Picker("Time format", selection: $settings.timeFormat) {
                        ForEach(TimeDisplayFormat.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    

                    ToggleRow(title: "Flash at 5 seconds left",
                              isOn: $settings.flashAtFiveSecLeft)
                }

                Section("Durations") {
                    StepperRow(title: "Focus",
                               value: Binding(get: { settings.focusMinutes },
                                              set: { settings.focusMinutes = $0 }),
                               unit: "min")
                    StepperRow(title: "Short break",
                               value: Binding(get: { settings.shortBreakMinutes },
                                              set: { settings.shortBreakMinutes = $0 }),
                               unit: "min")
                    StepperRow(title: "Long break",
                               value: Binding(get: { settings.longBreakMinutes },
                                              set: { settings.longBreakMinutes = $0 }),
                               unit: "min")
                    StepperRow(title: "Long break every",
                               value: Binding(get: { settings.longBreakEvery },
                                              set: { settings.longBreakEvery = $0 }),
                               unit: "pomodoros")
                }

                Section("Tasks") {
                    ToggleRow(title: "Require a task to start focus",
                              isOn: $settings.requireTaskForFocus)
                    Text("A focus pomodoro won't start until you pick a task. The quick-add hotkey (below, in Global shortcuts) pops up a capture window.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    StepperRow(title: "Daily pomodoro goal",
                               value: $settings.dailyPomodoroGoal,
                               unit: "🍅",
                               range: 0...20)
                    Text("Shows a progress bar in the menu bar. Set to 0 to hide.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Section("Repeat") {
                    ToggleRow(title: "Repeat enabled",
                              isOn: $settings.repeatConfig.enabled)
                    if settings.repeatConfig.enabled {
                        ToggleRow(title: "Endless (repeat forever)",
                                  isOn: $settings.repeatConfig.endless)
                        if !settings.repeatConfig.endless {
                            StepperRow(title: "Repeat count",
                                       value: Binding(
                                           get: { settings.repeatConfig.count },
                                           set: { settings.repeatConfig.count = $0 }),
                                       unit: "×")
                        }
                        StepperRow(title: "Delay",
                                   value: Binding(
                                       get: { Int(settings.repeatConfig.delaySeconds / 60) },
                                       set: { settings.repeatConfig.delaySeconds = TimeInterval($0) * 60 }),
                                   unit: "min")
                    }
                }

                Section("Floating timer") {
                    ToggleRow(title: "Floating timer (while running)",
                              isOn: $settings.floatingTimerEnabled)
                    if settings.floatingTimerEnabled {
                        ToggleRow(title: "Compact size",
                                  isOn: $settings.floatingCompact)
                        ToggleRow(title: "Always on top",
                                  isOn: $settings.floatingAlwaysOnTop)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Opacity: \(Int(settings.floatingOpacity * 100))%")
                                .font(.system(.caption, design: .rounded).weight(.medium))
                            Slider(value: $settings.floatingOpacity, in: 0.3...1.0)
                                
                        }
                        Text("Drag the floating timer to reposition — its spot is remembered.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

        case .breaks:
                Section("Break message") {
                    TextField("Break message text",
                              text: $settings.breakMessage, axis: .vertical)
                        .textFieldStyle(DarkGlassFieldStyle())
                        .lineLimit(2...4)
                }

                Section("Break") {
                    ToggleRow(title: "Block screen during break",
                              isOn: $settings.blockScreenDuringBreak)
                    ToggleRow(title: "Show \"Exit break\" button",
                              isOn: $settings.showExitBreakButton)
                }

                Section("Break ambience") {
                    ToggleRow(title: "Ambience sound during break",
                              isOn: $settings.ambienceEnabled)
                    Picker("Ambience", selection: $settings.ambienceSound) {
                        ForEach(BreakAmbienceService.Ambience.allCases, id: \.rawValue) { a in
                            Label(a.label, systemImage: a.systemImage).tag(a.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    HStack(spacing: 8) {
                        Button("Preview") {
                            BreakAmbienceService.shared.preview(
                                BreakAmbienceService.Ambience(rawValue: settings.ambienceSound) ?? .rain
                            )
                        }
                        .buttonStyle(.bordered)
                        Button("Stop") { BreakAmbienceService.shared.stop() }
                            .buttonStyle(.bordered)
                    }
                }

                Section("Screen brightness") {
                    ToggleRow(title: "Dim screen on break",
                              isOn: $settings.brightnessDimEnabled)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dim level: \(settings.brightnessDimPercent)%")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                        Slider(value: Binding(
                                get: { Double(settings.brightnessDimPercent) },
                                set: { settings.brightnessDimPercent = Int($0) }
                              ), in: 5...95)
                            
                    }
                    ToggleRow(title: "Smooth transition",
                              isOn: $settings.brightnessSmooth)
                }

        case .focus:
                Section("App blocking") {
                    ToggleRow(title: "Block distracting apps on break",
                              isOn: $settings.appBlockerSettings.enabled)
                    ToggleRow(title: "Also block during focus session",
                              isOn: $settings.blockAppsDuringFocus)
                    ToggleRow(title: "Force quit (not just hide)",
                              isOn: $settings.appBlockerSettings.killOnFrontmost)
                    ForEach($settings.appBlockerSettings.blockedApps) { $app in
                        HStack(spacing: 8) {
                            Image(systemName: "app.dashed")
                                .foregroundStyle(.white.opacity(app.isEnabled ? 0.85 : 0.35))
                            Text(app.name)
                                .foregroundStyle(.white.opacity(app.isEnabled ? 1 : 0.5))
                                .strikethrough(!app.isEnabled, color: .white.opacity(0.4))
                            Spacer()
                            // Remove this app from the list entirely.
                            Button {
                                settings.appBlockerSettings.blockedApps.removeAll { $0.id == app.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .buttonStyle(.pressableSubtle)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                            .help("Remove from list")
                            // Pause/resume blocking without losing the entry.
                            Toggle("", isOn: $app.isEnabled)
                                .tint(.green)
                                
                                .labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                    Button {
                        // Re-seed any preset apps that were removed, without
                        // touching the user's other entries or their enabled state.
                        for preset in BlockedApp.presets
                        where !settings.appBlockerSettings.blockedApps.contains(where: { $0.bundleID == preset.bundleID }) {
                            settings.appBlockerSettings.blockedApps.append(preset)
                        }
                    } label: {
                        Label("Restore default apps", systemImage: "arrow.counterclockwise.circle.fill")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                    }
                    .buttonStyle(.pressableSubtle)
                }

                Section("Reminders (posture / water / custom)") {
                    ToggleRow(title: "Reminders enabled",
                              isOn: $settings.reminderSettings.enabled)
                    ToggleRow(title: "Only during focus phase",
                              isOn: $settings.reminderSettings.duringFocusOnly)
                    ForEach($settings.reminderSettings.reminders) { $item in
                        ReminderRow(item: $item)
                    }
                    Button {
                        settings.reminderSettings.reminders.append(
                            .init(kind: .custom, intervalMinutes: 45,
                                  message: "Custom reminder")
                        )
                    } label: {
                        Label("Add reminder", systemImage: "plus.circle.fill")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                    }
                    .buttonStyle(.pressableSubtle)
                }

        case .eyeCare:
                Section("Eye exercise sequence") {
                    ToggleRow(title: "20-20-20 rule",
                              isOn: $settings.exerciseSettings.twentyRuleEnabled)
                    ToggleRow(title: "Gaze exercise",
                              isOn: $settings.exerciseSettings.gazeEnabled)
                    ToggleRow(title: "Blink exercise",
                              isOn: $settings.exerciseSettings.blinkEnabled)

                    StepperRow(title: "Exercise rounds",
                               value: Binding(get: { settings.exerciseSettings.rounds },
                                              set: { settings.exerciseSettings.rounds = max(1, $0) }),
                               unit: "×")

                    Button {
                        BreakWindowManager.shared.presentPreview(timer: timer) {
                            BreakWindowManager.shared.dismissAll()
                        }
                    } label: {
                        Label("Preview break screen", systemImage: "eye.fill")
                            .font(.system(.callout, design: .rounded).weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Step hold scale: \(String(format: "%.2f", settings.exerciseSettings.stepHoldScale))×")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                        Slider(value: $settings.exerciseSettings.stepHoldScale,
                               in: 0.5...2.0)
                            
                    }
                    Text("Step length in seconds: \(String(format: "%.0f", settings.exerciseSettings.scaledHold(4)))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))

                    if let selected = editingInstructionDirection {
                        instructionEditor(for: selected)
                    }
                    StepsInstructionEditor(
                        instructions: $settings.ttsSettings.instructions,
                        onSelect: { editingInstructionDirection = $0 }
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Kalib interval: \(Int(settings.ttsSettings.kalibIntervalSeconds))s")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                        Slider(value: $settings.ttsSettings.kalibIntervalSeconds,
                               in: 0...60)
                            
                    }
                }

                Section("Camera & Vision") {
                    ToggleRow(title: "Eye tracking via camera",
                              isOn: $settings.cameraEyeTrackingEnabled)
                    if settings.cameraEyeTrackingEnabled {
                        Text("Works during breaks only. Alerts when blink rate is low.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }

        case .sharingan:
                Section("Iris style") {
                    HStack {
                        Spacer()
                        MoveEyePair(direction: "center", gaze: .center,
                                    eyeSize: 54, style: settings.sharinganStyle)
                        Spacer()
                    }
                    .padding(.vertical, 6)

                    HStack {
                        Text("Sharingan eye")
                            .font(.system(.body, design: .rounded))
                        Spacer()
                        MoveIrisView(diameter: 26, style: settings.sharinganStyle)
                        Picker("", selection: $settings.sharinganStyle) {
                            ForEach(SharinganStyle.allCases) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    Text("Used everywhere the eyes appear: break screen and desktop wallpaper.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Section("Desktop wallpaper") {
                    ToggleRow(title: "Show eyes on the desktop",
                              isOn: $settings.eyesWallpaperEnabled)
                    Text("Live wallpaper: the eyes sit under your desktop icons and always follow the mouse.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))

                    HStack {
                        Text("Sharingan spin")
                            .font(.system(.body, design: .rounded))
                        Spacer()
                        Picker("", selection: $settings.wallpaperSpinTrigger) {
                            ForEach(WallpaperSpinTrigger.allCases) { t in
                                Text(t.label).tag(t)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }

                    if settings.wallpaperSpinTrigger != .off {
                        HStack {
                            Text("Spin speed")
                                .font(.system(.body, design: .rounded))
                            Spacer()
                            Picker("", selection: $settings.wallpaperSpinDuration) {
                                Text("Slow").tag(2.8)
                                Text("Normal").tag(1.6)
                                Text("Fast").tag(0.9)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 210)
                        }
                    }

                    if settings.wallpaperSpinTrigger.spinsOnIdle {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Idle delay: \(String(format: "%.1f", settings.wallpaperIdleDelay))s")
                                .font(.system(.caption, design: .rounded).weight(.medium))
                            Slider(value: $settings.wallpaperIdleDelay, in: 0.5...5, step: 0.5)
                        }
                    }
                }
                .onChange(of: settings.eyesWallpaperEnabled) { on in
                    WallpaperWindowManager.shared.setEnabled(on, config: WallpaperConfig(from: settings))
                }
                .onChange(of: settings.wallpaperSpinTrigger) { _ in refreshWallpaper() }
                .onChange(of: settings.wallpaperSpinDuration) { _ in refreshWallpaper() }
                .onChange(of: settings.wallpaperIdleDelay) { _ in refreshWallpaper() }
                .onChange(of: settings.sharinganStyle) { _ in refreshWallpaper() }

        case .general:
                Section("Auto-start") {
                    ToggleRow(title: "Auto-start focus",
                              isOn: $settings.autoStartFocus)
                    ToggleRow(title: "Auto-start break",
                              isOn: $settings.autoStartBreak)
                    ToggleRow(title: "Launch at login",
                              isOn: $settings.launchAtLogin)
                    if !LaunchAtLoginService.shared.isSupported {
                        Text("Login item works only when running the packaged Blink.app.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notifications") {
                    ToggleRow(title: "Notify 5 minutes left",
                              isOn: $settings.notifyFiveMinLeft)
                }

                Section("Sound") {
                    ToggleRow(title: "Alarm sound enabled",
                              isOn: $settings.alarmSoundEnabled)
                    Picker("Alarm sound", selection: $settings.alarmSound) {
                        ForEach(AlarmSoundService.Sound.allCases, id: \.rawValue) { s in
                            Text(s.label).tag(s.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    
                }

        case .voice:
                Section("Voice guidance (TTS)") {
                    ToggleRow(title: "Spoken instructions",
                              isOn: $settings.ttsSettings.enabled)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice rate: \(String(format: "%.2f", settings.ttsRate))")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                        Slider(value: $settings.ttsRate, in: 0...1)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice pitch: \(String(format: "%.2f", settings.ttsPitch))")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                        Slider(value: $settings.ttsPitch, in: 0.5...1.5)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Global kalib pool")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                        ForEach(settings.ttsSettings.globalKalib.indices, id: \.self) { idx in
                            HStack {
                                TextField("Reminder", text: Binding(
                                    get: { settings.ttsSettings.globalKalib[idx] },
                                    set: { settings.ttsSettings.globalKalib[idx] = $0 }
                                ))
                                .textFieldStyle(DarkGlassFieldStyle())
                                if settings.ttsSettings.globalKalib.count > 1 {
                                    Button {
                                        settings.ttsSettings.globalKalib.remove(at: idx)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red.opacity(0.85))
                                    }
                                    .buttonStyle(.pressableSubtle)
                                }
                            }
                        }
                        Button {
                            settings.ttsSettings.globalKalib.append("")
                        } label: {
                            Label("Add reminder", systemImage: "plus.circle.fill")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                        }
                        .buttonStyle(.pressableSubtle)
                    }
                }

        case .shortcuts:
                Section("Global shortcuts") {
                    ToggleRow(title: "Global keyboard shortcuts",
                              isOn: $settings.globalShortcutsEnabled)
                    shortcutLegend
                }
        }
    }

    /// Groups of settings, shown as drill-down rows on the root Settings screen.
    enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
        case timer, breaks, focus, eyeCare, sharingan, general, voice, shortcuts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .timer:     return "Timer"
            case .breaks:    return "Breaks"
            case .focus:     return "Focus & Blocking"
            case .eyeCare:   return "Eye Care"
            case .sharingan: return "Sharingan Eyes"
            case .general:   return "General"
            case .voice:     return "Voice Guidance"
            case .shortcuts: return "Shortcuts"
            }
        }
        var subtitle: String {
            switch self {
            case .timer:     return "Durations, mode, repeat, floating timer"
            case .breaks:    return "Break screen, ambience, brightness"
            case .focus:     return "App blocking, reminders"
            case .eyeCare:   return "Exercises, camera tracking"
            case .sharingan: return "Iris style, desktop wallpaper, spin"
            case .general:   return "Auto-start, sound, notifications"
            case .voice:     return "Spoken instructions"
            case .shortcuts: return "Global keyboard shortcuts"
            }
        }
        var icon: String {
            switch self {
            case .timer:     return "timer"
            case .breaks:    return "cup.and.saucer.fill"
            case .focus:     return "hand.raised.fill"
            case .eyeCare:   return "eye.fill"
            case .sharingan: return "eye.circle.fill"
            case .general:   return "gearshape.fill"
            case .voice:     return "waveform"
            case .shortcuts: return "keyboard.fill"
            }
        }
        var tint: Color {
            switch self {
            case .timer:     return .blue
            case .breaks:    return .teal
            case .focus:     return .indigo
            case .eyeCare:   return .green
            case .sharingan: return .red
            case .general:   return Color(white: 0.5)
            case .voice:     return .orange
            case .shortcuts: return .purple
            }
        }

        /// Extra search terms so a query finds a category by the settings it holds
        /// (e.g. "float" or "opacity" → Timer).
        var keywords: [String] {
            switch self {
            case .timer:
                return ["duration", "minutes", "pomodoro", "focus length", "mode",
                        "countdown", "count up", "repeat", "endless", "floating",
                        "float", "opacity", "always on top", "compact"]
            case .breaks:
                return ["break", "message", "ambience", "rain", "forest", "white noise",
                        "brightness", "dim", "screen", "exit"]
            case .focus:
                return ["app", "block", "blocker", "distraction", "reminder",
                        "posture", "water", "stand"]
            case .eyeCare:
                return ["eye", "exercise", "camera", "vision", "gaze",
                        "blink", "20-20-20"]
            case .sharingan:
                return ["sharingan", "iris", "style", "tomoe", "mangekyou",
                        "wallpaper", "desktop", "spin", "eyes", "follow", "mouse"]
            case .general:
                return ["auto-start", "auto start", "sound", "alarm", "chime",
                        "notification", "launch at login", "startup"]
            case .voice:
                return ["tts", "voice", "speak", "spoken", "announcement", "rate", "pitch"]
            case .shortcuts:
                return ["keyboard", "hotkey", "shortcut", "global", "quick add"]
            }
        }

        /// Whether this category matches a lowercased search query.
        func matches(_ query: String) -> Bool {
            let hay = ([title, subtitle] + keywords).joined(separator: " ").lowercased()
            return hay.contains(query)
        }
    }

    private func instructionEditor(for direction: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spoken instruction: \(direction)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
            HStack {
                TextField("Instruction", text: Binding(
                    get: { settings.ttsSettings.instruction(forDirection: direction)?.text ?? "" },
                    set: { settings.ttsSettings.updateInstruction(text: $0, forDirection: direction) }
                ))
                .textFieldStyle(DarkGlassFieldStyle())
                Button {
                    editingInstructionDirection = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.pressableSubtle)
            }
        }
    }

    private var shortcutLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(GlobalShortcut.allCases, id: \.self) { sh in
                ShortcutRecorderRow(
                    title: sh.label,
                    binding: effectiveBinding(sh),
                    isCustom: settings.shortcutBindings[sh.rawValue] != nil,
                    onCapture: { combo in
                        settings.shortcutBindings[sh.rawValue] = combo
                    },
                    onReset: {
                        settings.shortcutBindings[sh.rawValue] = nil
                    })
                .foregroundStyle(.white.opacity(0.85))
                .disabled(!settings.globalShortcutsEnabled)
                .opacity(settings.globalShortcutsEnabled ? 1 : 0.5)
            }
            Text("Click a combo, then press the new keys (needs at least one modifier). Esc cancels.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassRounded(DS.Radius.lg, material: .thin)
    }

    /// Wallpaper yoqilgan bo'lsa, yangi sozlamalar bilan qayta quradi.
    private func refreshWallpaper() {
        guard settings.eyesWallpaperEnabled else { return }
        WallpaperWindowManager.shared.setEnabled(true, config: WallpaperConfig(from: settings))
    }

    private func effectiveBinding(_ sh: GlobalShortcut) -> ShortcutBinding {
        if let b = settings.shortcutBindings[sh.rawValue], b.isValid { return b }
        return sh.defaultBinding
    }

    private func Section<C: View>(_ title: LocalizedStringKey,
                                  @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).dsSectionLabel()
                .padding(.leading, 6)
            SettingsCard { content() }
        }
    }
}

struct StepsInstructionEditor: View {
    @Binding var instructions: [TTSInstruction]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(instructions) { ins in
                    Button {
                        onSelect(ins.direction)
                    } label: {
                        Text(ins.direction.replacingOccurrences(of: "_", with: " "))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .glassCapsule(material: .regular)
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
        }
    }
}

private struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let unit: String
    var range: ClosedRange<Int> = 1...600

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Text("\(value) \(unit)")
                .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.dsSecondary)
            DSStepper(value: $value, range: range)
        }
        .frame(minHeight: 24)
    }
}

/// A glass +/- stepper that matches the app instead of the stock AppKit widget.
struct DSStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...600
    var step: Int = 1

    var body: some View {
        HStack(spacing: 0) {
            button("minus") { value = max(range.lowerBound, value - step) }
                .disabled(value <= range.lowerBound)
            Rectangle().fill(Color.dsHairline).frame(width: 1, height: 18)
            button("plus") { value = min(range.upperBound, value + step) }
                .disabled(value >= range.upperBound)
        }
        .background(Capsule().fill(Color.dsFill))
        .overlay(Capsule().stroke(Color.dsHairline, lineWidth: 1))
        .clipShape(Capsule())
    }

    private func button(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
    }
}