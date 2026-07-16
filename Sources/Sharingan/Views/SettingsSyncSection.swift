import SwiftUI
import SharinganCore

/// Settings → General → "iCloud sync". Master toggle (opt-in, default OFF),
/// a status line straight off CloudSyncEngine.status, a Sync Now button, the
/// timer-mirror toggle, and one honest line about what travels.
///
/// Toggling off stops the engine and deletes NOTHING — not locally, not in
/// iCloud; turning it back on resumes from the saved sync state.
struct SettingsSyncSection: View {
    @ObservedObject var engine: CloudSyncEngine
    @AppStorage(CloudSyncEngine.syncEnabledKey) private var syncEnabled = false
    @AppStorage(SharinganCoordinator.timerMirrorDefaultsKey) private var timerMirror = true
    @AppStorage(CloudSyncEngine.syncRetryMaxMinutesKey)
    private var retryMaxMinutes = CloudSyncEngine.defaultRetryMaxMinutes

    /// How long, at most, to wait between retries of a push the server keeps
    /// rejecting — the ceiling the exponential backoff flattens out at.
    private let retryOptions = [1, 2, 5, 10, 15]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("iCloud sync").dsSectionLabel()
                .padding(.leading, 6)
            SettingsCard {
                ToggleRow(title: "Sync with iCloud", isOn: Binding(
                    get: { syncEnabled },
                    set: { on in
                        syncEnabled = on
                        if on {
                            engine.start()
                            SettingsSync.start()
                        } else {
                            engine.stop()
                            SettingsSync.stop()
                        }
                    }))

                HStack(spacing: 12) {
                    Text("Status")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Text(statusLabel)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.dsSecondary)
                    Button("Sync Now") { engine.syncNow() }
                        .buttonStyle(.pressableSubtle)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .disabled(!canSyncNow)
                        .opacity(canSyncNow ? 1 : 0.4)
                }
                .frame(minHeight: 24)

                if syncEnabled {
                    ToggleRow(title: "Mirror timer across Macs", isOn: $timerMirror)
                    Text("Starting, pausing, or finishing a session on one Mac does the same on the others. Turn this off to sync tasks without sharing the timer.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Text("Retry at most every")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                        Picker("", selection: Binding(
                            get: { retryMaxMinutes },
                            set: { m in
                                retryMaxMinutes = m
                                engine.setRetryCapMinutes(m)
                            })) {
                            ForEach(retryOptions, id: \.self) { m in
                                Text(m == 1 ? "1 minute" : "\(m) minutes").tag(m)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .frame(minHeight: 24)
                    Text("How long, at most, to wait between retries when iCloud keeps rejecting a change. Shorter recovers faster; longer is gentler on battery and quota.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text("Syncs tasks, categories, tags, templates, focus statistics, settings, and the active timer through your private iCloud database. Nothing is shared with anyone else.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusLabel: String {
        syncEnabled ? engine.status.label() : "Off"
    }

    private var canSyncNow: Bool {
        if case .idle = engine.status { return syncEnabled }
        return false
    }
}
