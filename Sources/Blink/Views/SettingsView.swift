import SwiftUI
import AppKit
import BlinkCore

struct SettingsView: View {
    @ObservedObject var timer: PomodoroTimer
    @Binding var settings: PomodoroSettings
    @State private var editingInstructionDirection: String?
    @State private var openCategory: SettingsCategory?

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
                SettingsCard {
                    categoryRow(.timer)
                    categoryRow(.breaks)
                    categoryRow(.focus)
                    categoryRow(.eyeCare)
                    categoryRow(.general)
                    categoryRow(.voice)
                    categoryRow(.shortcuts)
                }
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    private var rootHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "eye.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: timer.settings.theme.gradient,
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
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
                    .tint(.white)

                    Picker("Time format", selection: $settings.timeFormat) {
                        ForEach(TimeDisplayFormat.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)

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

                Section("Repeat") {
                    ToggleRow(title: "Repeat enabled",
                              isOn: $settings.repeatConfig.enabled)
                    if settings.repeatConfig.enabled {
                        StepperRow(title: "Repeat count",
                                   value: Binding(
                                       get: { settings.repeatConfig.count },
                                       set: { settings.repeatConfig.count = $0 }),
                                   unit: "×")
                        StepperRow(title: "Delay",
                                   value: Binding(
                                       get: { Int(settings.repeatConfig.delaySeconds / 60) },
                                       set: { settings.repeatConfig.delaySeconds = TimeInterval($0) * 60 }),
                                   unit: "min")
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
                    ToggleRow(title: "Floating timer (while running)",
                              isOn: $settings.floatingTimerEnabled)
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
                    .tint(.white)
                    HStack(spacing: 8) {
                        Button("Preview") {
                            BreakAmbienceService.shared.preview(
                                BreakAmbienceService.Ambience(rawValue: settings.ambienceSound) ?? .rain
                            )
                        }
                        .buttonStyle(.bordered).tint(.white)
                        Button("Stop") { BreakAmbienceService.shared.stop() }
                            .buttonStyle(.bordered).tint(.white)
                    }
                }

                Section("Screen brightness") {
                    ToggleRow(title: "Dim screen on break",
                              isOn: $settings.brightnessDimEnabled)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dim level: \(settings.brightnessDimPercent)%")
                            .font(.caption.weight(.medium))
                        Slider(value: Binding(
                                get: { Double(settings.brightnessDimPercent) },
                                set: { settings.brightnessDimPercent = Int($0) }
                              ), in: 5...95)
                            .tint(.white)
                    }
                    ToggleRow(title: "Smooth transition",
                              isOn: $settings.brightnessSmooth)
                }

        case .focus:
                Section("App blocking (during break)") {
                    ToggleRow(title: "Block distracting apps on break",
                              isOn: $settings.appBlockerSettings.enabled)
                    ToggleRow(title: "Force quit (not just hide)",
                              isOn: $settings.appBlockerSettings.killOnFrontmost)
                    ForEach($settings.appBlockerSettings.blockedApps) { $app in
                        HStack {
                            Image(systemName: "app.dashed")
                                .foregroundStyle(.white.opacity(0.85))
                            Text(app.name).foregroundStyle(.white)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { settings.appBlockerSettings.blockedApps.contains(app) },
                                set: { on in
                                    if !on, let idx = settings.appBlockerSettings.blockedApps.firstIndex(of: app) {
                                        settings.appBlockerSettings.blockedApps.remove(at: idx)
                                    } else if on, !settings.appBlockerSettings.blockedApps.contains(app) {
                                        settings.appBlockerSettings.blockedApps.append(app)
                                    }
                                }
                            ))
                            .tint(.white)
                            .labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }
                    Button {
                        let preset = BlockedApp.presets[0]
                        if !settings.appBlockerSettings.blockedApps.contains(preset) {
                            settings.appBlockerSettings.blockedApps.append(preset)
                        }
                    } label: {
                        Label("Reset presets", systemImage: "arrow.counterclockwise.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
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
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
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

                    HStack {
                        Text("Sharingan eye")
                            .font(.system(.body, design: .rounded))
                        Spacer()
                        Image(nsImage: sharinganThumb(settings.sharinganStyle))
                            .resizable().frame(width: 26, height: 26)
                        Picker("", selection: $settings.sharinganStyle) {
                            ForEach(SharinganStyle.allCases) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(.white)
                        .fixedSize()
                    }

                    Button {
                        BreakWindowManager.shared.presentPreview(timer: timer) {
                            BreakWindowManager.shared.dismissAll()
                        }
                    } label: {
                        Label("Preview break screen", systemImage: "eye.fill")
                            .font(.system(.callout, design: .rounded).weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Step hold scale: \(String(format: "%.2f", settings.exerciseSettings.stepHoldScale))×")
                            .font(.caption.weight(.medium))
                        Slider(value: $settings.exerciseSettings.stepHoldScale,
                               in: 0.5...2.0)
                            .tint(.white)
                    }
                    Text("Step length in seconds: \(String(format: "%.0f", settings.exerciseSettings.scaledHold(4)))")
                        .font(.caption2)
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
                            .font(.caption.weight(.medium))
                        Slider(value: $settings.ttsSettings.kalibIntervalSeconds,
                               in: 0...60)
                            .tint(.white)
                    }
                }

                Section("Camera & Vision") {
                    ToggleRow(title: "Eye tracking via camera",
                              isOn: $settings.cameraEyeTrackingEnabled)
                    if settings.cameraEyeTrackingEnabled {
                        Text("Works during breaks only. Alerts when blink rate is low.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }

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
                            .font(.caption2)
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
                    .tint(.white)
                }

        case .voice:
                Section("Voice guidance (TTS)") {
                    ToggleRow(title: "Spoken instructions",
                              isOn: $settings.ttsSettings.enabled)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice rate: \(String(format: "%.2f", settings.ttsRate))")
                            .font(.caption.weight(.medium))
                        Slider(value: $settings.ttsRate, in: 0...1).tint(.white)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice pitch: \(String(format: "%.2f", settings.ttsPitch))")
                            .font(.caption.weight(.medium))
                        Slider(value: $settings.ttsPitch, in: 0.5...1.5).tint(.white)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Global kalib pool")
                            .font(.caption.weight(.medium))
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
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Button {
                            settings.ttsSettings.globalKalib.append("")
                        } label: {
                            Label("Add reminder", systemImage: "plus.circle.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
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
        case timer, breaks, focus, eyeCare, general, voice, shortcuts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .timer:     return "Timer"
            case .breaks:    return "Breaks"
            case .focus:     return "Focus & Blocking"
            case .eyeCare:   return "Eye Care"
            case .general:   return "General"
            case .voice:     return "Voice Guidance"
            case .shortcuts: return "Shortcuts"
            }
        }
        var subtitle: String {
            switch self {
            case .timer:     return "Durations, mode, repeat"
            case .breaks:    return "Break screen, ambience, brightness"
            case .focus:     return "App blocking, reminders"
            case .eyeCare:   return "Exercises, camera tracking"
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
            case .general:   return Color(white: 0.5)
            case .voice:     return .orange
            case .shortcuts: return .purple
            }
        }
    }

    private func instructionEditor(for direction: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spoken instruction: \(direction)")
                .font(.caption.weight(.semibold))
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
                .buttonStyle(.plain)
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
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .glassRounded(18, material: .thin)
        .padding(14)
    }

    private func effectiveBinding(_ sh: GlobalShortcut) -> ShortcutBinding {
        if let b = settings.shortcutBindings[sh.rawValue], b.isValid { return b }
        return sh.defaultBinding
    }

    private func sharinganThumb(_ style: SharinganStyle) -> NSImage {
        SharinganAssets.image(style)
            ?? NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)
            ?? NSImage()
    }

    private func Section<C: View>(_ title: LocalizedStringKey,
                                  @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
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
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let unit: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Text("\(value) \(unit)")
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            Stepper("", value: $value, in: 1...600)
                .labelsHidden()
        }
        .frame(minHeight: 24)
    }
}