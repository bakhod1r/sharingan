import SwiftUI
import AppKit
import SharinganCore

struct SettingsView: View {
    @ObservedObject var timer: PomodoroTimer
    @Binding var settings: PomodoroSettings

    /// Normally the view opens on the category list. `--render-dev-preview`
    /// deep-links straight to a category page (with its Advanced accordion
    /// already down) so the headless renderer can photograph a page a user would
    /// otherwise have to click into.
    init(timer: PomodoroTimer, settings: Binding<PomodoroSettings>,
         initialCategory: SettingsCategory? = nil,
         initialAdvancedExpanded: Bool = false) {
        self.timer = timer
        self._settings = settings
        self._openCategory = State(initialValue: initialCategory)
        self._advancedExpanded = State(initialValue: initialAdvancedExpanded)
    }

    @ObservedObject private var dndService = DNDShortcutService.shared
    @ObservedObject private var router = AppRouter.shared
    @State private var editingInstructionDirection: String?
    @State private var openCategory: SettingsCategory?
    @State private var searchText = ""
    /// "Due soon" pre-reminder offset in minutes (0 = off); read by TaskStore
    /// when it schedules deadline notifications.
    @AppStorage(TaskStore.preReminderDefaultsKey) private var preReminderMinutes = 10
    /// Whether the trailing "Advanced settings" accordion is expanded on the
    /// currently-open category page. Resets to collapsed on every page switch.
    @State private var advancedExpanded = false
    /// Is there a display with a real camera housing attached? The notch
    /// section is rendered *disabled* rather than hidden when there isn't —
    /// a greyed "Notch" with a reason tells the user something true about their
    /// Mac; a section that simply isn't there reads as a broken app.
    ///
    /// `NotchWindowManager.hudScreen()` is the single source of truth (a top
    /// safe-area inset *and* both auxiliary top areas). Settings asks the same
    /// question the window manager places the panel from, so the two can never
    /// disagree about whether this Mac has a notch.
    @State private var hasNotch = false
    /// Which import-template flavor the Tasks page previews (0 = MD, 1 = JSON).
    @State private var importTemplateFormat = 0
    /// The full installed-app catalog sheet for the blocker.
    @State private var showBlockAppPicker = false
    /// Brief "Copied!" feedback after the template copy button.
    @State private var templateCopied = false

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
        .animation(DS.Motion.gentle, value: openCategory)
        // Sidebar "Settings" (or the menu-bar gear) re-selected while a
        // sub-page is open → pop back to the category list.
        .onChange(of: router.settingsPopToRoot) { openCategory = nil }
        .onChange(of: openCategory) { advancedExpanded = false }
        .onAppear { hasNotch = NotchWindowManager.hudScreen() != nil }
        // Plugging in a notched display, or booting with the lid shut and then
        // opening it, changes the answer while this window is up.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification)) { _ in
            hasNotch = NotchWindowManager.hudScreen() != nil
        }
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

    /// Root-list categories: all of them normally; when searching, only the
    /// ones matching the query.
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

    private var rootHeader: some View {
        VStack(spacing: 10) {
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
                if cat.hasAdvancedRows {
                    Button {
                        withAnimation(DS.Motion.gentle) { advancedExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .rotationEffect(.degrees(advancedExpanded ? 90 : 0))
                            Text("Advanced settings")
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(.white.opacity(0.75))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableSubtle)
                    .padding(.top, 4)

                    if advancedExpanded {
                        advancedSections(cat)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
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
        Button {
            openCategory = cat
        } label: {
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

    // MARK: - Notch

    /// Every notch control, greyed and inert as one block.
    ///
    /// Two reasons they go dead, and the copy distinguishes them: this Mac has
    /// no camera housing (there is deliberately no synthetic pill — see
    /// `NotchScreenMetrics.cutout` — so there is nothing to configure), or the
    /// HUD is simply switched off. The master toggle passes `requiresHUD: false`
    /// so it survives the second case; nothing survives the first.
    @ViewBuilder
    private func notchControls<C: View>(requiresHUD: Bool = true,
                                        @ViewBuilder content: () -> C) -> some View {
        let live = hasNotch && (!requiresHUD || settings.notchHUDEnabled)
        VStack(alignment: .leading, spacing: 7) { content() }
            .disabled(!live)
            .opacity(live ? 1 : 0.45)
    }

    /// Why the section above is grey. Rendered at full strength — the controls
    /// are the part that is disabled, the reason has to stay readable.
    @ViewBuilder
    private var notchUnavailableNote: some View {
        if !hasNotch {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "macbook")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text("This Mac has no notch. The HUD needs a MacBook with a camera housing.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1))
        }
    }

    /// One DND shortcut: editable name + Test button + last-run status.
    @ViewBuilder
    private func dndShortcutRow(label: String, name: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .frame(width: 84, alignment: .leading)
            TextField("Shortcut name", text: name)
                .textFieldStyle(DarkGlassFieldStyle())
            switch dndService.lastResult[name.wrappedValue
                .trimmingCharacters(in: .whitespaces)] {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Shortcut ran successfully")
            case .failure(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Failed: \(msg)")
            case nil:
                EmptyView()
            }
            Button("Test") { dndService.run(name.wrappedValue) }
                .buttonStyle(.pressableSubtle)
                .font(.system(.caption, design: .rounded).weight(.semibold))
        }
    }

    @ViewBuilder
    private func categorySections(_ cat: SettingsCategory) -> some View {
        switch cat {
        case .timer:
                Section("Pomodoro sizes") {
                    Text("Three gears: Small for quick wins, Normal for the classic rhythm, Big for deep work. Each task or subtask can pick its own.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Grid(horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Color.clear.frame(width: 1, height: 1)
                            ForEach(["Focus", "Break", "Long break"], id: \.self) { h in
                                Text(h)
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        ForEach(PomodoroKind.allCases) { kind in
                            GridRow {
                                Label(kind.label, systemImage: kind.systemImage)
                                    .font(.system(.callout, design: .rounded).weight(.medium))
                                    .foregroundStyle(.white)
                                    .labelStyle(.titleAndIcon)
                                    .gridColumnAlignment(.leading)
                                kindCell(kind, \.focusMinutes)
                                kindCell(kind, \.breakMinutes)
                                longBreakCell(kind)
                            }
                        }
                    }
                }

                Section("Long break") {
                    StepperRow(title: "Long break every",
                               value: Binding(get: { settings.longBreakEvery },
                                              set: { settings.longBreakEvery = $0 }),
                               unit: "pomodoros")
                }

                Section("Floating widget") {
                    ToggleRow(title: "Floating widget",
                              isOn: $settings.dockWidgetEnabled)
                    Text("A draggable pill — active task, time left, and Start / Stop / Reset. Docks flush above the Dock by default.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))

                    if settings.dockWidgetEnabled {
                        GlassSegmentedPicker(selection: $settings.dockWidgetSize,
                                             cases: FloatingWidgetSize.allCases) { $0.label }

                        ToggleRow(title: "Expand on hover",
                                  isOn: $settings.dockWidgetExpandOnHover)
                        Text("Rests compact — ring and time only — and springs open under the pointer, like the Dock's now-playing widgets.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Opacity: \(Int(settings.dockWidgetOpacity * 100))%")
                                .font(.system(.caption, design: .rounded).weight(.medium))
                            Slider(value: $settings.dockWidgetOpacity, in: 0.3...1.0)
                        }
                    }
                }

                Section("Today panel") {
                    ToggleRow(title: "Today panel on desktop",
                              isOn: $settings.showTodayPanel)
                    Text("Keeps today's tasks and the timer visible on your desktop.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Section("Menu bar") {
                    ToggleRow(title: "Show menu bar icon",
                              isOn: $settings.showMenuBarIcon)
                    Text("If a crowded menu bar has pushed the icon under the notch, turning this on moves it back next to the system icons.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    ToggleRow(title: "Show countdown in menu bar",
                              isOn: $settings.showMenuBarCountdown)
                }

        case .notch:
                Section("Notch HUD") {
                    // The master switch is the only control that stays live
                    // when the HUD is off — but not when the Mac has no notch,
                    // where there is nothing to switch on.
                    notchControls(requiresHUD: false) {
                        ToggleRow(title: "Show the notch HUD",
                                  isOn: $settings.notchHUDEnabled)
                    }
                    Text("A black island around the camera housing: the countdown and progress while a session runs, today's tasks and quick actions when you hover it.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))

                    // The ears follow the master switch (not `requiresHUD: false`):
                    // there is nothing to shape when the island is off.
                    notchControls {
                        HStack {
                            Text("Ears")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Picker("", selection: $settings.notchEars) {
                                ForEach(NotchEarsMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .glassMenu()
                            .fixedSize()
                        }
                        Text("The ears are the strips beside the notch: the countdown on the left, the task on the right. They sit in the menu bar row, so they can cover your app's menus and status items — dropping one gives those pixels back, clicks included. The progress line stays either way.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    notchUnavailableNote
                }

        case .tasks:
                Section("Tasks") {
                    ToggleRow(title: "Require a task to start focus",
                              isOn: $settings.requireTaskForFocus)
                    Text("A focus pomodoro won't start until you pick a task. The quick-add hotkey (in Global shortcuts) pops up a capture window.")
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

                Section("Analytics") {
                    Picker("App tracking", selection: $settings.appTrackingMode) {
                        ForEach(AppTrackingMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                    .glassMenu()
                    Text("Records which app is frontmost during focus for the Analytics → Apps breakdown. App-level only — no window titles, no Accessibility permission, stored on your Mac. Turn off to record nothing.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Section("Due reminders") {
                    Picker("Due pre-reminder", selection: $preReminderMinutes) {
                        Text("Off").tag(0)
                        Text("5 min before").tag(5)
                        Text("10 min before").tag(10)
                        Text("30 min before").tag(30)
                        Text("60 min before").tag(60)
                    }
                    .pickerStyle(.menu)
                    .glassMenu()
                    Text("A “Due soon” notification ahead of each task's due time, on top of the one at the deadline itself.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Section("Import template") {
                    Text("Copy a template, fill it in (or have an AI write it), then paste it into Tasks → \(Image(systemName: "square.and.arrow.down")) — every task feature is covered: priority, category, project, tags, due, planned day, estimate, repeat, pomodoro size, subtasks, notes. Dropping a .md/.json file on the task list works too.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    GlassSegmentedPicker(selection: $importTemplateFormat,
                                        options: [(0, "Markdown"), (1, "JSON")])
                    ScrollView {
                        Text(importTemplateFormat == 0
                             ? TaskImportParser.markdownTemplate
                             : TaskImportParser.jsonTemplate)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 150)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.25)))
                    Button {
                        let text = importTemplateFormat == 0
                            ? TaskImportParser.markdownTemplate
                            : TaskImportParser.jsonTemplate
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        templateCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            templateCopied = false
                        }
                    } label: {
                        Label(templateCopied ? "Copied!" : "Copy template",
                              systemImage: templateCopied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
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
                    .glassMenu()

                    HStack(spacing: 8) {
                        Button("Preview") {
                            BreakAmbienceService.shared.preview(
                                BreakAmbienceService.Ambience(rawValue: settings.ambienceSound) ?? .rain
                            )
                        }
                        .buttonStyle(.glass)
                        Button("Stop") { BreakAmbienceService.shared.stop() }
                            .buttonStyle(.glass)
                    }
                }

        case .focus:
                Section("App blocking") {
                    ToggleRow(title: "Block distracting apps on break",
                              isOn: $settings.appBlockerSettings.enabled)
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
                    HStack(spacing: 14) {
                        // The whole installed-app catalog, not just presets.
                        Button {
                            showBlockAppPicker = true
                        } label: {
                            Label("Add apps…", systemImage: "plus.circle.fill")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                        }
                        .buttonStyle(.pressableSubtle)
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
                    .sheet(isPresented: $showBlockAppPicker) {
                        BlockAppPickerSheet(blocker: $settings.appBlockerSettings)
                            .environment(\.colorScheme, .dark)
                    }
                }

                Section("Reminders (posture / water / custom)") {
                    ToggleRow(title: "Reminders enabled",
                              isOn: $settings.reminderSettings.enabled)
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
                                    eyeSize: 54, style: settings.sharinganStyle,
                                    rightStyle: settings.sharinganStyleRight,
                                    evolves: false)
                        Spacer()
                    }
                    .padding(.vertical, 6)

                    HStack {
                        Text(settings.sharinganStyleRight == nil ? "Sharingan eye"
                                                                 : "Left eye")
                            .font(.system(.body, design: .rounded))
                        Spacer()
                        SpinningIrisSwatch(style: settings.sharinganStyle)
                        Picker("", selection: $settings.sharinganStyle) {
                            ForEach(SharinganStyle.allCases) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .glassMenu()
                        .fixedSize()
                    }
                    Text("Used everywhere the mark appears: break screen, desktop wallpaper, the menu-bar icon and the Dock icon.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Section("Break screen") {
                    HStack {
                        Text("Background")
                            .font(.system(.body, design: .rounded))
                        Spacer()
                        breakBackgroundSwatch(settings.breakBackgroundStyle)
                        Picker("", selection: $settings.breakBackgroundStyle) {
                            ForEach(BreakBackgroundStyle.allCases) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .glassMenu()
                        .fixedSize()
                    }
                    Text("One flat tone across the whole break screen. Graphite matches the design video; Slate is a touch lighter.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))

                    Button {
                        BreakWindowManager.shared.presentPreview(timer: timer) {
                            BreakWindowManager.shared.dismissAll()
                        }
                    } label: {
                        Label("Preview break screen", systemImage: "eye.fill")
                            .font(.system(.callout, design: .rounded).weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }

                // Kept always-visible: this .onChange chain re-applies the
                // wallpaper config, so it must stay observing even when the
                // Advanced accordion (which holds the wallpaper motion
                // details) is collapsed.
                Section("Desktop wallpaper") {
                    ToggleRow(title: "Show eyes on the desktop",
                              isOn: $settings.eyesWallpaperEnabled)
                    Text("Live wallpaper: the eyes sit under your desktop icons and always follow the mouse.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .onChange(of: settings.eyesWallpaperEnabled) { _, on in
                    WallpaperWindowManager.shared.setEnabled(on, config: WallpaperConfig(from: settings))
                }
                .onChange(of: settings.wallpaperSpinTrigger) { refreshWallpaper() }
                .onChange(of: settings.wallpaperSpinDuration) { refreshWallpaper() }
                .onChange(of: settings.wallpaperIdleDelay) { refreshWallpaper() }
                .onChange(of: settings.wallpaperDozeSeconds) { refreshWallpaper() }
                .onChange(of: settings.sharinganStyle) { refreshWallpaper() }
                .onChange(of: settings.sharinganStyleRight) { refreshWallpaper() }

        case .general:
                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(SharinganTheme.allCases, id: \.self) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .glassMenu()

                    ToggleRow(title: "Spin the Sharingan",
                              isOn: $settings.animateIcon)
                    Text("The tomoe rotate slowly in the menu bar and Dock. Pauses when macOS Reduce Motion is on.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Section("Auto-start") {
                    ToggleRow(title: "Auto-start focus",
                              isOn: $settings.autoStartFocus)
                    ToggleRow(title: "Auto-start break",
                              isOn: $settings.autoStartBreak)
                    ToggleRow(title: "Launch at login",
                              isOn: $settings.launchAtLogin)
                    if !LaunchAtLoginService.shared.isSupported {
                        Text("Login item works only when running the packaged Sharingan.app.")
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
                    .glassMenu()

                }

                Section("Updates") {
                    ToggleRow(title: "Check for updates automatically",
                              isOn: Binding(
                                get: { UpdaterService.shared.automaticallyChecksForUpdates },
                                set: { UpdaterService.shared.automaticallyChecksForUpdates = $0 }))
                    HStack(spacing: 12) {
                        Text("Version")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                        Text(appVersion)
                            .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.dsSecondary)
                        Button("Check Now…") { UpdaterService.shared.checkForUpdates(nil) }
                            .buttonStyle(.glass)
                    }
                    .frame(minHeight: 24)
                    if !UpdaterService.shared.isAvailable {
                        Text("Updates work only when running the packaged Sharingan.app.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!UpdaterService.shared.isAvailable)

                // The engine exists whenever the app delegate ran (always in
                // the real app); previews/renders without one just omit the
                // section rather than crashing on a dummy.
                if let engine = AppServices.syncEngine {
                    SettingsSyncSection(engine: engine)
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
                                // SwiftUI keeps stale index bindings alive briefly
                                // after a row is removed — an unguarded subscript
                                // here crashes on deleting the last row.
                                TextField("Reminder", text: Binding(
                                    get: {
                                        let pool = settings.ttsSettings.globalKalib
                                        return pool.indices.contains(idx) ? pool[idx] : ""
                                    },
                                    set: {
                                        guard settings.ttsSettings.globalKalib.indices.contains(idx) else { return }
                                        settings.ttsSettings.globalKalib[idx] = $0
                                    }
                                ))
                                .textFieldStyle(DarkGlassFieldStyle())
                                if settings.ttsSettings.globalKalib.count > 1 {
                                    Button {
                                        guard settings.ttsSettings.globalKalib.indices.contains(idx) else { return }
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

    /// Rows shown only inside the "Advanced settings" accordion at the
    /// bottom of a category page. Empty for General, Voice, and Shortcuts
    /// (`SettingsCategory.hasAdvancedRows == false` for those, so the
    /// accordion never renders and these cases are unreachable in practice).
    @ViewBuilder
    private func advancedSections(_ cat: SettingsCategory) -> some View {
        switch cat {
        case .timer:
                Section("Timer mode") {
                    GlassSegmentedPicker(selection: $settings.timerMode,
                                         cases: TimerMode.allCases) { $0.label }

                    Picker("Time format", selection: $settings.timeFormat) {
                        ForEach(TimeDisplayFormat.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .glassMenu()

                    ToggleRow(title: "Flash at 5 seconds left",
                              isOn: $settings.flashAtFiveSecLeft)
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

        case .notch:
                // No `notchUnavailableNote` here: the Simple tier's "Notch HUD"
                // section already carries it, next to the master toggle it
                // explains, and both sections are on this same page — printing it
                // twice reads as a bug. This section just comes up disabled.
                Section("Notch HUD details") {
                    if hasNotch && !settings.notchHUDEnabled {
                        Text("Turn the notch HUD on to configure it.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    notchControls {
                        ToggleRow(title: "Announce session and break changes",
                                  isOn: $settings.notchLiveActivity)
                        Text("A two-second banner in the island when a session finishes or a break begins.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))

                        Divider().overlay(Color.dsHairline)

                        Text("What the panel shows")
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                        ToggleRow(title: "Timer and controls",
                                  isOn: $settings.notchShowTimerControls)
                        ToggleRow(title: "Today's tasks",
                                  isOn: $settings.notchShowTasks)
                        StepperRow(title: "Task rows",
                                   value: $settings.notchTaskRows,
                                   unit: "rows",
                                   range: NotchContentConfig.taskRowRange)
                            .disabled(!settings.notchShowTasks)
                            .opacity(settings.notchShowTasks ? 1 : 0.5)
                        ToggleRow(title: "Quick actions",
                                  isOn: $settings.notchShowQuickActions)
                        ToggleRow(title: "Blocking and streak strip",
                                  isOn: $settings.notchShowStatusStrip)
                        ToggleRow(title: "Sharingan iris on the ears",
                                  isOn: $settings.notchShowIris)
                        Text("A slowly spinning Sharingan iris on each ear either side of the notch, in your chosen eye styles.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("The island is sized to fit exactly what you leave on, so switching a section off gives that black back to your screen rather than emptying it.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

        case .tasks:
                Section("Planning") {
                    ToggleRow(title: "Week starts on Monday",
                              isOn: $settings.weekStartsOnMonday)
                    Text("Applies to the weekly board and the menu bar Week tab.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Section("Estimates & badges") {
                    StepperRow(title: "Default subtask estimate",
                               value: $settings.defaultSubtaskEstimate,
                               unit: "🍅",
                               range: 0...8)
                    Text("Applied to newly added steps. Set to 0 for no estimate.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    ToggleRow(title: "Show pomodoro badges",
                              isOn: $settings.showPomodoroBadges)
                    Text("The 🍅 done/estimate chips on task and subtask rows.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    ToggleRow(title: "Deadlines as countdown",
                              isOn: $settings.deadlineAsCountdown)
                    Text(settings.deadlineAsCountdown
                         ? "Board cards count down to the deadline — “2d 4h left”."
                         : "Board cards show the deadline itself — “Fri 14:30”.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Section("Trash") {
                    StepperRow(title: "Auto-delete after",
                               value: $settings.trashRetentionDays,
                               unit: settings.trashRetentionDays == 1 ? "day" : "days",
                               range: 0...365)
                    Text(settings.trashRetentionDays == 0
                         ? "Deleted tasks stay in the Trash until you remove them by hand."
                         : "Deleted tasks are permanently removed \(settings.trashRetentionDays) day\(settings.trashRetentionDays == 1 ? "" : "s") after they land in the Trash. Set to 0 to keep them forever.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

        case .breaks:
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
                    ToggleRow(title: "Warm colors on break",
                              isOn: $settings.nightShiftBreakEnabled)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Warmth: \(Int(settings.nightShiftBreakStrength * 100))%")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                        Slider(value: $settings.nightShiftBreakStrength, in: 0.1...1.0)
                    }
                    Text("Warms screen colors during breaks (uses Night Shift).")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

        case .focus:
                Section("App blocking extras") {
                    ToggleRow(title: "Also block during focus session",
                              isOn: $settings.blockAppsDuringFocus)
                    ToggleRow(title: "Force quit (not just hide)",
                              isOn: $settings.appBlockerSettings.killOnFrontmost)
                }

                Section("Do Not Disturb") {
                    ToggleRow(title: "Turn on Focus during focus sessions",
                              isOn: $settings.dndEnabled)
                    if settings.dndEnabled {
                        dndShortcutRow(label: "On shortcut",
                                       name: $settings.dndShortcutOn)
                        dndShortcutRow(label: "Off shortcut",
                                       name: $settings.dndShortcutOff)
                        Button {
                            NSWorkspace.shared.open(URL(string: "shortcuts://")!)
                        } label: {
                            Label("Open Shortcuts app",
                                  systemImage: "arrow.up.forward.app")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                        }
                        .buttonStyle(.pressableSubtle)
                        Text("Create two shortcuts with these names: one sets a Focus (e.g. Do Not Disturb) on, the other turns it off. Sharingan runs them when a focus session starts and ends.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Section("Reminder details") {
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
                Section("Exercise tuning") {
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

                Section("Camera") {
                    if settings.cameraEyeTrackingEnabled {
                        ToggleRow(title: "Strict exercise validation",
                                  isOn: $settings.strictExerciseValidation)
                        Text("A step won't advance until the camera confirms the movement (gaze directions and blinks). Off = auto-advance after a grace period.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    } else {
                        Text("Enable camera eye tracking to configure validation.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

        case .sharingan:
                Section("Iris details") {
                    ToggleRow(title: "Different style per eye",
                              isOn: Binding(
                                get: { settings.sharinganStyleRight != nil },
                                set: { on in
                                    settings.sharinganStyleRight =
                                        on ? settings.sharinganStyle : nil
                                }))

                    if let right = settings.sharinganStyleRight {
                        HStack {
                            Text("Right eye")
                                .font(.system(.body, design: .rounded))
                            Spacer()
                            SpinningIrisSwatch(style: right)
                            Picker("", selection: Binding(
                                get: { settings.sharinganStyleRight ?? settings.sharinganStyle },
                                set: { settings.sharinganStyleRight = $0 })) {
                                ForEach(SharinganStyle.allCases) { s in
                                    Text(s.label).tag(s)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .glassMenu()
                            .fixedSize()
                        }
                    }
                }

                Section("Break screen effects") {
                    HStack {
                        Text("Pattern animation")
                            .font(.system(.body, design: .rounded))
                        Spacer()
                        Picker("", selection: $settings.breakPatternTransition) {
                            ForEach(PatternTransitionSpeed.allCases) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }
                    Text("The pattern whirls open at break start and whirls shut as the break ends.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))

                    if settings.breakPatternTransition != .off {
                        ToggleRow(title: "Mixed patterns",
                                  isOn: $settings.breakPatternMixed)
                        Text("On: the pattern evolves through the whole chain during the break — 1 tomoe → 2 → 3 → Mangekyō… Off: only your selected style.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    HStack {
                        Text("Pattern spin")
                            .font(.system(.body, design: .rounded))
                        Spacer()
                        Picker("", selection: $settings.breakPatternSpinSeconds) {
                            Text("Off").tag(0.0)
                            Text("Slow").tag(12.0)
                            Text("Normal").tag(8.0)
                            Text("Fast").tag(4.0)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }
                    Text("Continuous rotation of the iris pattern while the break runs.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Section("Wallpaper motion") {
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
                        .glassMenu()
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Close eyes after: \(Int(settings.wallpaperDozeSeconds))s of stillness")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                        Slider(value: $settings.wallpaperDozeSeconds, in: 10...300, step: 10)
                    }
                    Text("When the mouse hasn't moved for this long, the eyes doze off; they wake on the first move.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }

        case .general, .voice, .shortcuts:
                EmptyView()
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

    /// Small color preview of a break background.
    private func breakBackgroundSwatch(_ style: BreakBackgroundStyle) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(red: style.color.r, green: style.color.g, blue: style.color.b))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .frame(width: 44, height: 28)
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

    /// One table cell: minutes value + compact stepper for a kind's field.
    private func kindCell(_ kind: PomodoroKind,
                          _ field: WritableKeyPath<PomodoroKindConfig, Int>) -> some View {
        let binding = Binding<Int>(
            get: { settings.config(for: kind)[keyPath: field] },
            set: { v in
                var c = settings.config(for: kind)
                c[keyPath: field] = v
                settings.setConfig(c, for: kind)
            })
        return VStack(spacing: 3) {
            Text("\(binding.wrappedValue) min")
                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.dsSecondary)
            DSStepper(value: binding)
        }
        .frame(maxWidth: .infinity)
    }

    /// Long-break cell: per-size override, falling back to the global value.
    private func longBreakCell(_ kind: PomodoroKind) -> some View {
        let binding = Binding<Int>(
            get: { settings.config(for: kind).longBreakMinutes ?? settings.longBreakMinutes },
            set: { v in
                var c = settings.config(for: kind)
                c.longBreakMinutes = v
                settings.setConfig(c, for: kind)
            })
        return VStack(spacing: 3) {
            Text("\(binding.wrappedValue) min")
                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.dsSecondary)
            DSStepper(value: binding)
        }
        .frame(maxWidth: .infinity)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
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
/// Small, slowly whirling iris shown next to the style pickers — every eye
/// in the app breathes, even the 26 pt swatches.
struct SpinningIrisSwatch: View {
    var style: SharinganStyle
    @State private var angle = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MoveIrisView(diameter: 26, spin: angle, style: style)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}

/// Category accent color — view-layer concern, so it stays out of Core.
private extension SettingsCategory {
    var tint: Color {
        switch self {
        case .timer:     return .blue
        case .notch:     return .cyan
        case .tasks:     return .mint
        case .breaks:    return .teal
        case .focus:     return .indigo
        case .eyeCare:   return .green
        case .sharingan: return .red
        case .general:   return Color(white: 0.5)
        case .voice:     return .orange
        case .shortcuts: return .purple
        }
    }
}
