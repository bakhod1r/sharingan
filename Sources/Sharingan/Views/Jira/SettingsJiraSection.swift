import SwiftUI
import SharinganCore

struct SettingsJiraSection: View {
    @ObservedObject var jira: JiraService

    @AppStorage(JiraService.siteURLDefaultsKey) private var siteURL = ""
    @AppStorage(JiraService.emailDefaultsKey) private var email = ""
    @AppStorage(JiraService.autoStartTransitionDefaultsKey) private var autoStartTransition = false
    @AppStorage(JiraService.doneBehaviorDefaultsKey) private var doneBehaviorRaw = JiraDoneBehavior.prompt.rawValue
    @AppStorage(JiraService.autoCompleteLocalDefaultsKey) private var autoCompleteLocal = false
    @AppStorage(JiraService.worklogSyncDefaultsKey) private var worklogSync = true
    @AppStorage(JiraService.pushEstimateDefaultsKey) private var pushEstimate = false
    @AppStorage(JiraService.pollMinutesDefaultsKey) private var pollMinutes = 15

    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Section("Jira Cloud") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("https://your-site.atlassian.net", text: $siteURL)
                        .textFieldStyle(DarkGlassFieldStyle())
                    TextField("Email", text: $email)
                        .textFieldStyle(DarkGlassFieldStyle())
                    SecureField(jira.isConnected ? "API token (leave blank to keep current one)" : "API token",
                                text: $token)
                        .textFieldStyle(DarkGlassFieldStyle())

                    HStack(spacing: 10) {
                        Button(jira.isConnected ? "Reconnect" : "Connect") {
                            Task {
                                let success = await jira.connect(siteURLString: siteURL,
                                                                 email: email,
                                                                 apiToken: token)
                                if success { token = "" }
                            }
                        }
                        .buttonStyle(.glass)
                        .disabled(jira.isWorking || siteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Disconnect") { jira.disconnect() }
                            .buttonStyle(.pressableSubtle)
                            .disabled(!jira.isConnected && siteURL.isEmpty && email.isEmpty)

                        Spacer()

                        Text(jira.status.label)
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(jira.isConnected ? Color.green : Color.dsSecondary)
                    }

                    if let host = jira.siteHost {
                        Text("Site: \(host)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if let message = jira.lastErrorMessage, !jira.isConnected {
                        Text(message)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Sync behavior") {
                ToggleRow(title: "Auto-start In Progress transition",
                          isOn: $autoStartTransition)
                ToggleRow(title: "Mark local task done when Jira reaches Done",
                          isOn: $autoCompleteLocal)
                ToggleRow(title: "Sync worklogs from pomodoros",
                          isOn: $worklogSync)
                ToggleRow(title: "Push local estimate back to Jira",
                          isOn: $pushEstimate)

                HStack(spacing: 12) {
                    Text("Done behavior")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Picker("", selection: $doneBehaviorRaw) {
                        ForEach(JiraDoneBehavior.allCases) { behavior in
                            Text(behavior.label).tag(behavior.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                HStack(spacing: 12) {
                    Text("Poll Jira every")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Text("\(pollMinutes) min")
                        .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.dsSecondary)
                    DSStepper(value: $pollMinutes, range: 5...120)
                }
                .frame(minHeight: 24)

                Text("This first pass wires authentication and the settings surface. Issue sync, transitions, and worklog delivery land on the next milestones.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
