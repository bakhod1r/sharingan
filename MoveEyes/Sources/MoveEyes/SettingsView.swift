import SwiftUI

/// Foydalanuvchi sozlamalari (UserDefaults orqali saqlanadi).
enum Settings {
    static let spinEnabledKey = "spinEnabled"
    static let spinDurationKey = "spinDuration"   // bir to'la aylanish, soniya
    static let idleDelayKey = "idleDelay"         // aylanish boshlanishigacha kutish, soniya

    static var spinEnabled: Bool {
        UserDefaults.standard.object(forKey: spinEnabledKey) as? Bool ?? true
    }
    static var spinDuration: Double {
        let v = UserDefaults.standard.double(forKey: spinDurationKey)
        return v > 0 ? v : 1.6
    }
    static var idleDelay: Double {
        let v = UserDefaults.standard.double(forKey: idleDelayKey)
        return v > 0 ? v : 1.2
    }
}

struct SettingsView: View {
    @AppStorage(Settings.spinEnabledKey) private var spinEnabled = true
    @AppStorage(Settings.spinDurationKey) private var spinDuration = 1.6
    @AppStorage(Settings.idleDelayKey) private var idleDelay = 1.2

    var body: some View {
        Form {
            Section("Sharingan rotation") {
                Toggle("Spin when eyes are idle", isOn: $spinEnabled)

                Picker("Speed", selection: $spinDuration) {
                    Text("Slow").tag(2.8)
                    Text("Normal").tag(1.6)
                    Text("Fast").tag(0.9)
                }
                .pickerStyle(.segmented)
                .disabled(!spinEnabled)

                LabeledContent("Idle delay") {
                    HStack {
                        Slider(value: $idleDelay, in: 0.5...5, step: 0.5)
                        Text(String(format: "%.1f s", idleDelay))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!spinEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 220)
    }
}
