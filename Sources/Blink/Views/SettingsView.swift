import SwiftUI
import BlinkCore

struct SettingsView: View {
    @ObservedObject var timer: PomodoroTimer
    @Binding var settings: PomodoroSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                Section("Taymer rejimi") {
                    Picker("Rejim", selection: $settings.timerMode) {
                        ForEach(TimerMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Tema", selection: $settings.theme) {
                        ForEach(BlinkTheme.allCases, id: \.self) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)

                    ToggleRow(title: "5 soniyada flesh",
                              isOn: $settings.flashAtFiveSecLeft)
                }

                Section("Vaqt") {
                    StepperRow(title: "Diqqat",
                               value: Binding(get: { settings.focusMinutes },
                                              set: { settings.focusMinutes = $0 }),
                               unit: "min")
                    StepperRow(title: "Qisqa tanaffus",
                               value: Binding(get: { settings.shortBreakMinutes },
                                              set: { settings.shortBreakMinutes = $0 }),
                               unit: "min")
                    StepperRow(title: "Uzun tanaffus",
                               value: Binding(get: { settings.longBreakMinutes },
                                              set: { settings.longBreakMinutes = $0 }),
                               unit: "min")
                    StepperRow(title: "Uzun tanaffus har",
                               value: Binding(get: { settings.longBreakEvery },
                                              set: { settings.longBreakEvery = $0 }),
                               unit: "pomodoro")
                }

                Section("Takrorlash") {
                    ToggleRow(title: "Takrorlash yoqilgan",
                              isOn: $settings.repeatConfig.enabled)
                    if settings.repeatConfig.enabled {
                        StepperRow(title: "Takrorlar soni",
                                   value: Binding(
                                       get: { settings.repeatConfig.count },
                                       set: { settings.repeatConfig.count = $0 }),
                                   unit: "×")
                        StepperRow(title: "Kutish",
                                   value: Binding(
                                       get: { Int(settings.repeatConfig.delaySeconds / 60) },
                                       set: { settings.repeatConfig.delaySeconds = TimeInterval($0) * 60 }),
                                   unit: "min")
                    }
                }

                Section("Avtomatik") {
                    ToggleRow(title: "Tanaffus avtomatik",
                              isOn: $settings.autoStartBreak)
                    ToggleRow(title: "Diqqat avtomatik",
                              isOn: $settings.autoStartFocus)
                }

                Section("Bildirishnomalar") {
                    ToggleRow(title: "5 daqiqa qoldi ogohlantirish",
                              isOn: $settings.notifyFiveMinLeft)
                }

                Section("Ko'rinish") {
                    ToggleRow(title: "Suzuvchi taymer",
                              isOn: $settings.floatingTimerEnabled)
                    ToggleRow(title: "Ekran bloklash (tanaffus)",
                              isOn: $settings.blockScreenDuringBreak)
                    ToggleRow(title: "Global klaviatura yorliqlari",
                              isOn: $settings.globalShortcutsEnabled)
                }

                Section("Sintez") {
                    ToggleRow(title: "Ovozli yo'riqnoma (TTS)",
                              isOn: $settings.ttsEnabled)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tezlik").font(.caption.weight(.medium))
                        Slider(value: $settings.ttsRate, in: 0...1)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pitch").font(.caption.weight(.medium))
                        Slider(value: $settings.ttsPitch, in: 0.5...1.5)
                    }
                }

                Section("Xabar") {
                    TextField("Tanaffus xabar matni",
                              text: $settings.breakMessage, axis: .vertical)
                        .textFieldStyle(DarkGlassFieldStyle())
                        .lineLimit(2...4)
                }

                shortcutLegend
            }
            .padding(24)
        }
        .frame(width: 440, height: 680)
        .liquidShadow(radius: 28)
        .glassRounded(28, material: .regular)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Yopish") { dismiss() }
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
            Text("Sozlamalar")
                .font(.system(.title2, design: .rounded).weight(.bold))
        }
    }

    private var shortcutLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Klaviatura yorliqlari")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
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