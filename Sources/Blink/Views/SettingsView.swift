import SwiftUI
import BlinkCore

struct SettingsView: View {
    @ObservedObject var timer: PomodoroTimer
    @Binding var settings: PomodoroSettings
    @Environment(\.dismiss) private var dismiss
    @State private var editingInstructionDirection: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

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

                Section("Break message") {
                    TextField("Break message text",
                              text: $settings.breakMessage, axis: .vertical)
                        .textFieldStyle(DarkGlassFieldStyle())
                        .lineLimit(2...4)
                }

                Section("Break tests") {
                    ToggleRow(title: "Block screen during break",
                              isOn: $settings.blockScreenDuringBreak)
                    ToggleRow(title: "Floating timer",
                              isOn: $settings.floatingTimerEnabled)
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

                Section("Eye exercise sequence") {
                    ToggleRow(title: "20-20-20 rule",
                              isOn: $settings.exerciseSettings.twentyRuleEnabled)
                    ToggleRow(title: "Gaze exercise",
                              isOn: $settings.exerciseSettings.gazeEnabled)
                    ToggleRow(title: "Blink exercise",
                              isOn: $settings.exerciseSettings.blinkEnabled)
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

                Section("Auto-start") {
                    ToggleRow(title: "Auto-start focus",
                              isOn: $settings.autoStartFocus)
                    ToggleRow(title: "Auto-start break",
                              isOn: $settings.autoStartBreak)
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

                Section("Global shortcuts") {
                    ToggleRow(title: "Global keyboard shortcuts",
                              isOn: $settings.globalShortcutsEnabled)
                    shortcutLegend
                }

                Section("iCloud sync") {
                    ToggleRow(title: "Sync settings & stats via iCloud",
                              isOn: $settings.syncEnabled)
                    HStack {
                        Image(systemName: syncStatusIcon)
                            .foregroundStyle(syncStatusColor)
                        Text("Status: \(SyncService.shared.status.rawValue)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Push") {
                            Task { await SyncService.shared.push(timer.settings,
                                                                  timer.stats) }
                        }
                        .buttonStyle(.bordered).tint(.white).disabled(!settings.syncEnabled)
                        Button("Pull") {
                            Task {
                                if let (s, st) = await SyncService.shared.pull() {
                                    timer.settings = s
                                    timer.applyRemoteStats(st)
                                }
                            }
                        }
                        .buttonStyle(.bordered).tint(.white).disabled(!settings.syncEnabled)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 480, height: 760)
        .liquidShadow(radius: 28)
        .glassRounded(28, material: .regular)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.white.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .glassCapsule()
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                StreakBadgeView(streak: timer.stats.streak)
                    .padding(.top, 4)
            }
        }
        .onDisappear {
            editingInstructionDirection = nil
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

    private var syncStatusIcon: String {
        switch SyncService.shared.status {
        case .idle:     return "checkmark.circle.fill"
        case .syncing:  return "arrow.triangle.2.circlepath"
        case .error:    return "exclamationmark.triangle.fill"
        case .disabled: return "icloud.slash"
        }
    }

    private var statusText: String {
        SyncService.shared.status.rawValue
    }

    private var syncStatusColor: Color {
        switch SyncService.shared.status {
        case .idle:     return .green
        case .syncing:  return .blue
        case .error:    return .red
        case .disabled: return .gray
        }
    }

    private var shortcutLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(GlobalShortcut.allCases, id: \.self) { sh in
                HStack {
                    Text(sh.label).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text(shortcutHint(sh))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .glassRounded(18, material: .thin)
        .padding(14)
    }

    private func shortcutHint(_ sh: GlobalShortcut) -> String {
        "⌃⌥\(sh.rawValue.uppercased())"
    }

    private func Section<C: View>(_ title: LocalizedStringKey,
                                  @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            VStack(spacing: 4) { content() }
                .glassRounded(18, material: .thin)
                .padding(8)
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
        HStack {
            Text(title).foregroundStyle(.white)
            Spacer()
            Stepper("\(value) \(unit)", value: $value, in: 1...600)
                .tint(.white)
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
    }
}