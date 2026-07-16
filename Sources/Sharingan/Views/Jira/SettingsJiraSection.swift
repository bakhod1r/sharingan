import SwiftUI
import SharinganCore

/// Settings → Integrations → "Jira Cloud".
///
/// There is no credential form here any more: Atlassian OAuth 2.0 (3LO) means
/// the only thing this view can do is send the user to their browser and report
/// what came back. Every state below is a real thing that happens — in
/// particular "connected but can't see any projects", which used to render as a
/// cheerful "Connected ✓" next to a permanently empty issue list.
struct SettingsJiraSection: View {
    @ObservedObject var jira: JiraService

    @AppStorage(JiraService.autoStartTransitionDefaultsKey) private var autoStartTransition = false
    @AppStorage(JiraService.doneBehaviorDefaultsKey) private var doneBehaviorRaw = JiraDoneBehavior.prompt.rawValue
    @AppStorage(JiraService.autoCompleteLocalDefaultsKey) private var autoCompleteLocal = false
    @AppStorage(JiraService.worklogSyncDefaultsKey) private var worklogSync = true
    @AppStorage(JiraService.pushEstimateDefaultsKey) private var pushEstimate = false
    @AppStorage(JiraService.pollMinutesDefaultsKey) private var pollMinutes = 15
    @AppStorage(JiraService.showTypeBadgeDefaultsKey) private var showTypeBadge = true
    @AppStorage(JiraBoardModel.boardIDDefaultsKey) private var boardID = 0
    @AppStorage(JiraNotifier.notifyNewAssignedDefaultsKey) private var notifyNewAssigned = true
    @AppStorage(JiraNotifier.notifyDueTodayDefaultsKey) private var notifyDueToday = true
    @AppStorage(JiraNotifier.notifySprintEndingDefaultsKey) private var notifySprintEnding = true

    @State private var showConvertConfirm = false
    @State private var convertStatus: String?
    /// Edited locally and committed on submit/blur: writing through on every
    /// keystroke would file half-typed JQL as the saved filter.
    @State private var jqlDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Jira Cloud").dsSectionLabel()
                    .padding(.leading, 6)
                SettingsCard {
                    accountRow
                    detailRows
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Sync behavior").dsSectionLabel()
                    .padding(.leading, 6)
                SettingsCard {
                    behaviorRows
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Advanced").dsSectionLabel()
                    .padding(.leading, 6)
                SettingsCard {
                    customJQLRow
                    defaultBoardRow
                }
            }
        }
        .onAppear { jqlDraft = jira.customJQL }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountRow: some View {
        HStack(spacing: 10) {
            primaryButton

            if jira.isConnected {
                Button("Disconnect") { jira.disconnect() }
                    .buttonStyle(.pressableSubtle)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .disabled(jira.isWorking)
            }

            Spacer(minLength: 8)

            if jira.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .progressViewStyle(.circular)
            }

            Text(jira.status.label)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch jira.status {
        case .notConfigured:
            EmptyView()
        case .reconsentRequired:
            Button("Log in again") { Task { await jira.connect() } }
                .buttonStyle(.glass)
                .disabled(jira.isWorking)
        case .connected, .noProjectAccess:
            EmptyView()
        default:
            Button("Log in with Atlassian") { Task { await jira.connect() } }
                .buttonStyle(.glass)
                .disabled(jira.isWorking)
        }
    }

    @ViewBuilder
    private var detailRows: some View {
        switch jira.status {
        case .notConfigured:
            note("Jira sign-in isn't available in this build of Sharingan — it was built without the Atlassian app credentials. Install a release build to connect.")

        case .chooseSite(let resources):
            note("Your Atlassian account can reach more than one site. Pick the one Sharingan should use.")
            ForEach(resources, id: \.id) { resource in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(resource.name)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.white)
                        Text(resource.url)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Use this site") { Task { await jira.selectSite(resource) } }
                        .buttonStyle(.pressableSubtle)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .disabled(jira.isWorking)
                }
                .frame(minHeight: 24)
            }

        case .noProjectAccess:
            siteRow
            note("Sharingan is signed in, but this Atlassian account can't browse any Jira project — so there is nothing for it to show. Ask a Jira admin to grant your account the “Browse Projects” permission, then reconnect.")

        case .reconsentRequired:
            note("Your Jira sign-in expired — Atlassian ends a session after 90 days without use, and it can also be revoked from your Atlassian account. Logging in again restores it. Your task links are untouched.")

        case .connected:
            siteRow
            projectRow
            directionRow
            syncRow
            if jira.syncMode == .twoWay {
                pushRow
                convertRow
            }
            categoryMapRow
            note("Sharingan reads and updates the Jira issues you link to tasks. It never sees your Atlassian password.")
                .task { await jira.refreshProjects() }

        default:
            if let message = jira.lastErrorMessage {
                note(message)
            }
        }
    }

    /// One Atlassian grant reaches every site the account can see, so switching
    /// is a pick, not a re-login. With a single site there is nothing to pick, so
    /// the row stays the plain read-only fact it always was.
    @ViewBuilder
    private var siteRow: some View {
        if jira.availableSites.count > 1 {
            HStack(spacing: 12) {
                Text("Site")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if jira.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                }
                Picker("", selection: siteSelection) {
                    ForEach(jira.availableSites, id: \.id) { site in
                        Text(URL(string: site.url)?.host ?? site.name).tag(site.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .glassMenu()
                .disabled(jira.isWorking)
            }
            .frame(minHeight: 24)
        } else if let host = jira.siteHost {
            HStack(spacing: 12) {
                Text("Site")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(host)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Color.dsSecondary)
            }
            .frame(minHeight: 24)
        }
    }

    /// Reads from the *active session*, never from the site list — the list says
    /// what could be selected, `activeSiteID` says what is.
    private var siteSelection: Binding<String> {
        Binding(get: { jira.activeSiteID ?? "" },
                set: { id in
                    guard let site = jira.availableSites.first(where: { $0.id == id }),
                          site.id != jira.activeSiteID else { return }
                    Task { await jira.switchSite(site) }
                })
    }

    /// Restricts the sync to one Jira project ("space"), or "All my issues".
    /// Scoping matters here: an account assigned across several projects pulls
    /// hundreds of issues otherwise.
    @ViewBuilder
    private var projectRow: some View {
        HStack(spacing: 12) {
            Text("Space")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Picker("", selection: projectSelection) {
                Text("All my issues").tag("")
                ForEach(jira.availableProjects, id: \.key) { project in
                    Text("\(project.name) (\(project.key))").tag(project.key)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .glassMenu()
            .disabled(jira.isWorking)
        }
        .frame(minHeight: 24)
    }

    /// "" is the sentinel for "no project chosen — sync everything assigned".
    private var projectSelection: Binding<String> {
        Binding(get: { jira.selectedProjectKey ?? "" },
                set: { jira.selectedProjectKey = $0.isEmpty ? nil : $0 })
    }

    /// One-way (Jira → Sharingan) or two-way. Local edits only queue for push
    /// in two-way mode; pull mode leaves Jira untouched.
    @ViewBuilder
    private var directionRow: some View {
        HStack(spacing: 12) {
            Text("Sync direction")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Picker("", selection: Binding(
                get: { jira.syncMode.rawValue },
                set: { jira.syncMode = JiraService.SyncMode(rawValue: $0) ?? .pull })) {
                Text("Jira → Sharingan").tag(JiraService.SyncMode.pull.rawValue)
                Text("Two-way").tag(JiraService.SyncMode.twoWay.rawValue)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .glassMenu()
        }
        .frame(minHeight: 24)
    }

    /// Maps a task category to the Jira project new issues are filed under, so
    /// "Create Jira issue" on a task in that category goes to the right project.
    @ViewBuilder
    private var categoryMapRow: some View {
        if !jira.availableProjects.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create issues in")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                ForEach(TaskStore.shared.allCategories) { category in
                    HStack(spacing: 12) {
                        Text(category.name)
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(Color.dsSecondary)
                        Spacer(minLength: 8)
                        Picker("", selection: projectBinding(for: category.name)) {
                            Text("Default space").tag("")
                            ForEach(jira.availableProjects, id: \.key) { p in
                                Text(p.key).tag(p.key)
                            }
                        }
                        .pickerStyle(.menu).labelsHidden().glassMenu()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func projectBinding(for category: String) -> Binding<String> {
        Binding(get: { jira.categoryProjectMap[category] ?? "" },
                set: { key in
                    var map = jira.categoryProjectMap
                    if key.isEmpty { map.removeValue(forKey: category) } else { map[category] = key }
                    jira.categoryProjectMap = map
                })
    }

    /// Drains the queued local edits. The count keeps the queue honest — a
    /// number that never reaches zero is how the user learns a push is stuck.
    @ViewBuilder
    private var pushRow: some View {
        HStack(spacing: 12) {
            Button("Push changes now") { Task { await jira.pushNow() } }
                .buttonStyle(.glass)
                .disabled(jira.isWorking || jira.pendingPushCount == 0)
            Spacer(minLength: 8)
            let pending = jira.pendingPushCount
            let failed = jira.failedPushItems.count
            if failed > 0 {
                Text("\(failed) couldn't be sent")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.9))
            } else {
                Text(pending == 0 ? "Nothing queued" : "\(pending) pending")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Color.dsSecondary)
            }
        }
        .frame(minHeight: 24)
    }

    /// Seeds existing local tasks into Jira in one shot. The outbox only ever
    /// carries *changes* to already-linked tasks, so a user whose tasks were
    /// never pushed sees "Nothing queued" — this is how those tasks get created.
    /// Bulk creation is team-visible, so it's gated behind a confirm alert.
    @ViewBuilder
    private var convertRow: some View {
        let unlinked = jira.unlinkedTasks().count
        HStack(spacing: 12) {
            Button("Convert existing tasks to Jira") { showConvertConfirm = true }
                .buttonStyle(.glass)
                .disabled(jira.isWorking || unlinked == 0)
            Spacer(minLength: 8)
            Text(convertStatus ?? (unlinked == 0
                ? "All tasks are in Jira"
                : "\(unlinked) task\(unlinked == 1 ? "" : "s") not in Jira"))
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color.dsSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minHeight: 24)
        .alert("Convert \(unlinked) task\(unlinked == 1 ? "" : "s") to Jira?",
               isPresented: $showConvertConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Convert") {
                Task {
                    convertStatus = nil
                    let created = await jira.pushUnlinkedTasks()
                    if let error = jira.lastErrorMessage, created == 0 {
                        convertStatus = error
                    } else {
                        convertStatus = "Created \(created) issue\(created == 1 ? "" : "s")"
                    }
                }
            }
        } message: {
            Text("This creates a Jira issue for each unlinked task. Everyone on the project can see them.")
        }
    }

    /// Pulls the issues assigned to me into the task list. The result of the
    /// last run stays visible so a sync that imported nothing still reads as
    /// "done", not "nothing happened".
    @ViewBuilder
    private var syncRow: some View {
        HStack(spacing: 12) {
            Button("Sync my issues") { Task { await jira.syncAssignedIssues() } }
                .buttonStyle(.glass)
                .disabled(jira.isWorking)
            if jira.isWorking {
                ProgressView().controlSize(.small).progressViewStyle(.circular)
            }
            Spacer(minLength: 8)
            if let sync = jira.lastSync {
                Text(sync.label)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(sync.failed ? Color.red.opacity(0.9) : Color.dsSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(minHeight: 24)
    }

    // MARK: - Behavior

    @ViewBuilder
    private var behaviorRows: some View {
        ToggleRow(title: "Auto-start In Progress transition",
                  isOn: $autoStartTransition)
        ToggleRow(title: "Mark local task done when Jira reaches Done",
                  isOn: $autoCompleteLocal)
        ToggleRow(title: "Sync worklogs from pomodoros",
                  isOn: $worklogSync)
        ToggleRow(title: "Push local estimate back to Jira",
                  isOn: $pushEstimate)
        ToggleRow(title: "Show issue key badge on tasks",
                  isOn: $showTypeBadge)

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

        ToggleRow(title: "Notify when an issue is assigned to me",
                  isOn: $notifyNewAssigned)
        ToggleRow(title: "Notify about issues due today",
                  isOn: $notifyDueToday)
        ToggleRow(title: "Notify when the sprint is ending",
                  isOn: $notifySprintEnding)
    }

    // MARK: - Advanced

    /// The escape hatch for filters the pickers above can't express — a saved
    /// team filter, a label, a sprint. It *replaces* the query rather than
    /// narrowing it, so the caption says so and the placeholder shows exactly
    /// what runs when the field is empty.
    @ViewBuilder
    private var customJQLRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom JQL")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white)
            TextField("", text: $jqlDraft, prompt: Text(effectiveJQLHint))
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.12)))
                .onSubmit { jira.customJQL = jqlDraft; jqlDraft = jira.customJQL }
            note("Replaces the query above — the space and “assigned to me” filter no longer apply. Leave empty to use the default. Example: assignee = currentUser() AND statusCategory != Done")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What a sync would ask for right now, as the placeholder — the empty field
    /// is not "no filter", and showing the real default is the only way to say
    /// what typing here replaces.
    private var effectiveJQLHint: String {
        guard let project = jira.selectedProjectKey else { return JiraService.assignedOpenJQL }
        return JiraService.assignedOpenJQL(project: project)
    }

    /// The board is picked on the board itself (Settings has no project context
    /// to list boards from without inventing a fetch), so this row only reports
    /// the remembered choice and offers to drop it.
    @ViewBuilder
    private var defaultBoardRow: some View {
        HStack(spacing: 12) {
            Text("Default board")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Text(boardID > 0 ? "Remembered" : "Always ask")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color.dsSecondary)
            if boardID > 0 {
                Button("Forget") { boardID = 0 }
                    .buttonStyle(.pressableSubtle)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
        }
        .frame(minHeight: 24)
        note("When a space has several boards, Sharingan asks once and reuses that board. Forgetting it makes it ask again.")
    }

    // MARK: - Bits

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusColor: Color {
        switch jira.status {
        case .connected: return .green
        case .noProjectAccess, .reconsentRequired: return .orange
        case .failed: return .red
        default: return Color.dsSecondary
        }
    }
}
