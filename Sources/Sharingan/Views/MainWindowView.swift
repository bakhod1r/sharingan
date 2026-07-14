import SwiftUI
import SharinganCore

/// Full "desktop app" window with a CleanMyMac-style sidebar. Coexists with the
/// menu bar extra — opened from the menu bar's "Open window" button.
struct MainWindowView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    @ObservedObject private var router = AppRouter.shared
    /// Sidebar row the pointer is hovering, for a subtle highlight.
    @State private var hoveredNav: AppSection?
    /// Inline "new category" popover state (sidebar Categories +).
    @State private var showAddCategory = false
    @State private var newCatName = ""
    @State private var newCatColor = TaskCategory.palette[0]
    /// Priority level whose name/color editor popover is open.
    @State private var editingPriority: TaskPriority?
    /// Inline "new priority level" popover state (sidebar Priority +).
    @State private var showAddPriority = false
    @State private var newPrioName = ""
    @State private var newPrioColor = TaskCategory.palette[0]
    /// Category whose editor popover is open, and the rename draft.
    @State private var editingCategory: String?
    @State private var editCatName = ""
    /// Tag whose icon/color editor popover is open.
    @State private var editingTag: String?
    /// Inline "new tag" popover state (sidebar Tags +).
    @State private var showAddTag = false
    @State private var newTagName = ""
    /// Sidebar filter row under the pointer — reveals its edit pencil.
    @State private var hoveredRowKey: String?
    /// Accordion state of the sidebar groups, persisted across launches.
    @AppStorage("sidebar.collapsed.categories") private var catsCollapsed = false
    @AppStorage("sidebar.collapsed.tags") private var tagsCollapsed = false
    @AppStorage("sidebar.collapsed.priority") private var prioCollapsed = false

    private var accent: Color { timer.settings.theme.accent }

    typealias Section = AppSection
    private var section: Section {
        get { router.section }
        nonmutating set { router.section = newValue }
    }

    var body: some View {
        ZStack {
            windowBackground
            HStack(spacing: 0) {
                // Normal in-window glass sidebar with margins.
                sidebar
                    .frame(width: 232)
                    .padding(.leading, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(section)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity))
            }
            .animation(DS.Motion.gentle, value: section)
        }
        .frame(minWidth: 920, minHeight: 620)
        // One app accent: controls (pickers, toggles, sliders, menus) follow the
        // chosen theme instead of the stock system blue.
        .tint(timer.settings.theme.accent)
    }

    // MARK: - Sidebar (custom glass panel, CleanMyMac-style)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            addTaskButton
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    shortcutRow(icon: "magnifyingglass", title: "Search") {
                        router.openTasks(focusSearch: true)
                    }
                    shortcutRow(icon: "calendar.badge.exclamationmark", title: "Today",
                                count: tasks.count(.today), countTint: accent) {
                        router.openTasks(filter: .today)
                    }
                    shortcutRow(icon: "calendar", title: "Upcoming",
                                count: tasks.count(.upcoming)) {
                        router.openTasks(filter: .upcoming)
                    }
                    navRow(.timer)
                    navRow(.tasks)
                    navRow(.week)
                    navRow(.stats)
                    navRow(.report)
                    navRow(.settings)
                    categoriesSection
                    tagsSection
                    prioritySection
                }
            }
            Spacer(minLength: 12)
            sidebarFooter
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    // Faint theme tint so the panel reads as colored glass —
                    // the window color glows through, CleanMyMac-style.
                    RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                        .fill(timer.settings.theme.accent.opacity(0.14))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(
                    LinearGradient(colors: [Color.white.opacity(0.35),
                                            Color.white.opacity(0.08)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.38), radius: 28, x: 0, y: 14)
    }

    /// Todoist-style "Add task" at the very top of the sidebar — an accent
    /// plus-circle and bold accent label, opening the quick-capture panel.
    private var addTaskButton: some View {
        Button { QuickAddWindowManager.shared.showQuickAdd() } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(accent)
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 24, height: 24)
                .shadow(color: accent.opacity(0.5), radius: 5, y: 2)
                Text("Add task")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(accent)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
        // Leave room for the traffic-light buttons over the hidden title bar.
        .padding(.top, 34)
        .padding(.bottom, 6)
    }

    /// Todoist's "My Projects" analog: every category with its open-task count.
    /// "+" adds a custom category; a custom category's context menu deletes it.
    @ViewBuilder
    private var categoriesSection: some View {
        let counts = Dictionary(grouping: tasks.tasks.filter { !$0.isDone },
                                by: \.category).mapValues(\.count)
        sectionHeader("Categories", collapsed: $catsCollapsed,
                      addHelp: "New category") {
            showAddCategory = true
        }
        .popover(isPresented: $showAddCategory, arrowEdge: .trailing) {
            addCategoryPopover
        }
        if !catsCollapsed {
            ForEach(tasks.allCategories) { cat in
                categoryRow(cat, count: counts[cat.name] ?? 0)
            }
        }
    }

    private var addCategoryPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New category").dsSectionLabel()
            TextField("Name", text: $newCatName)
                .textFieldStyle(DarkGlassFieldStyle())
                .frame(width: 180)
                .onSubmit(commitNewCategory)
            HStack(spacing: 6) {
                ForEach(TaskCategory.palette, id: \.self) { hex in
                    Button { newCatColor = hex } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white.opacity(newCatColor == hex ? 0.9 : 0),
                                                     lineWidth: 2))
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
            Button("Add", action: commitNewCategory)
                .disabled(newCatName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
    }

    private func commitNewCategory() {
        guard tasks.addCategory(name: newCatName, colorHex: newCatColor) != nil else { return }
        newCatName = ""
        showAddCategory = false
    }

    /// Precreate a tag with no color UI — per-tag icon/color live on the
    /// row's own editor popover (`tagEditorPopover`) once the tag exists.
    private var addTagPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New tag").dsSectionLabel()
            TextField("Name", text: $newTagName)
                .textFieldStyle(DarkGlassFieldStyle())
                .frame(width: 180)
                .onSubmit(commitNewTag)
            Button("Add", action: commitNewTag)
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
    }

    private func commitNewTag() {
        guard tasks.addCustomTag(newTagName) else { return }
        newTagName = ""
        showAddTag = false
    }

    /// Todoist-style shortcut row: not a section of its own, just a deep-link
    /// into Tasks (search focus / smart filter). Count badge optional.
    private func shortcutRow(icon: String, title: String, count: Int = 0,
                             countTint: Color? = nil,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 20, alignment: .center)
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(countTint ?? .white.opacity(0.45))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
    }

    /// Category row: Todoist-style "#" mark, a hover pencil opening the editor
    /// (rename for custom categories, recolor for all, delete for custom).
    private func categoryRow(_ cat: TaskCategory, count: Int) -> some View {
        let key = "cat:\(cat.name)"
        return Button { router.openTasks(category: cat.name) } label: {
            HStack(spacing: 11) {
                Text("#")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(hex: cat.colorHex))
                    .frame(width: 20, alignment: .center)
                Text(cat.name)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(count > 0 ? 0.75 : 0.45))
                    .lineLimit(1)
                Spacer()
                if hoveredRowKey == key {
                    editPencil {
                        editCatName = ""
                        editingCategory = cat.name
                    }
                } else if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
        .onHover { inside in
            if inside { hoveredRowKey = key }
            else if hoveredRowKey == key { hoveredRowKey = nil }
        }
        .popover(isPresented: Binding(
            get: { editingCategory == cat.name },
            set: { if !$0 { editingCategory = nil } }
        ), arrowEdge: .trailing) {
            categoryEditorPopover(cat)
        }
    }

    /// Rename (custom only) + color editor for a category, with
    /// delete-and-reassign at the bottom for custom categories.
    private func categoryEditorPopover(_ cat: TaskCategory) -> some View {
        let custom = tasks.isCustomCategory(cat.name)
        return VStack(alignment: .leading, spacing: 10) {
            Text("#\(cat.name)").dsSectionLabel()
            if custom {
                TextField(cat.name, text: $editCatName)
                    .textFieldStyle(DarkGlassFieldStyle())
                    .frame(width: 180)
                    .onSubmit {
                        if tasks.renameCategory(cat.name, to: editCatName) {
                            editingCategory = nil
                        }
                    }
            }
            HStack(spacing: 6) {
                ForEach(TaskCategory.palette, id: \.self) { hex in
                    Button {
                        tasks.setColor(for: cat.name, colorHex: hex)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(
                                .white.opacity(tasks.color(for: cat.name) == hex ? 0.9 : 0),
                                lineWidth: 2))
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
            HStack {
                Spacer()
                if custom {
                    Button(role: .destructive) {
                        tasks.deleteCategory(cat.name)
                        editingCategory = nil
                    } label: {
                        Text("Delete category")
                            .foregroundStyle(.red.opacity(0.9))
                    }
                } else {
                    Text("Preset — rename & delete unavailable")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .font(.system(.caption, design: .rounded))
        }
        .padding(14)
    }

    /// Todoist's "Labels": free-form tags across all tasks, most-used first.
    /// Clicking narrows the Tasks list; the context menu deletes the label
    /// everywhere. Tags are born by typing #tag when adding/editing a task.
    @ViewBuilder
    private var tagsSection: some View {
        let open = tasks.tasks.filter { !$0.isDone }
        let counts: [String: Int] = open.reduce(into: [:]) { acc, t in
            for tag in t.tags { acc[tag, default: 0] += 1 }
        }
        // Cap the busy frequency-ordered list, but never hide precreated
        // custom tags (they sit at the tail of allTags and a plain cap
        // would swallow a tag the user just added via "+").
        let names = tasks.allTags.prefix(8 + tasks.customTags.count)
        sectionHeader("Tags", collapsed: $tagsCollapsed,
                      addHelp: "New tag") {
            showAddTag = true
        }
        .popover(isPresented: $showAddTag, arrowEdge: .trailing) {
            addTagPopover
        }
        if !tagsCollapsed {
            if names.isEmpty {
                Text("Type #tag when adding a task")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 18).padding(.bottom, 4)
            } else {
                ForEach(Array(names), id: \.self) { tag in
                    tagRow(tag, count: counts[tag] ?? 0)
                }
            }
        }
    }

    /// Tag row: custom icon + color, a hover pencil opening the style editor.
    private func tagRow(_ tag: String, count: Int) -> some View {
        let key = "tag:\(tag)"
        let tint = timer.settings.tagColorHex(tag).map { Color(hex: $0) } ?? accent
        return Button { router.openTasks(tag: tag) } label: {
            HStack(spacing: 11) {
                Image(systemName: timer.settings.tagIcon(tag))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20, alignment: .center)
                Text(tag)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(count > 0 ? 0.75 : 0.45))
                    .lineLimit(1)
                Spacer()
                if hoveredRowKey == key {
                    editPencil { editingTag = tag }
                } else if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
        .onHover { inside in
            if inside { hoveredRowKey = key }
            else if hoveredRowKey == key { hoveredRowKey = nil }
        }
        .popover(isPresented: Binding(
            get: { editingTag == tag },
            set: { if !$0 { editingTag = nil } }
        ), arrowEdge: .trailing) {
            tagEditorPopover(tag)
        }
    }

    /// Icon + color editor for a tag, with delete-everywhere at the bottom.
    /// A precreated custom tag with 0 uses also gets a separate, non-
    /// destructive "Remove tag" — unlike "Delete label" (which strips the tag
    /// off every task), it only drops the precreated placeholder itself.
    private func tagEditorPopover(_ tag: String) -> some View {
        let totalUses = tasks.tasks.reduce(0) { $0 + ($1.tags.contains(tag) ? 1 : 0) }
        let isRemovableCustom = totalUses == 0
            && tasks.customTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        return VStack(alignment: .leading, spacing: 10) {
            Text("@\(tag)").dsSectionLabel()
            HStack(spacing: 5) {
                ForEach(TagStyle.iconChoices, id: \.self) { icon in
                    Button {
                        var s = timer.settings.tagStyles[tag] ?? TagStyle()
                        s.icon = icon == "at" ? nil : icon
                        timer.settings.tagStyles[tag] = s.isEmpty ? nil : s
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 11))
                            .foregroundStyle(timer.settings.tagIcon(tag) == icon
                                             ? Color.accentColor : .white.opacity(0.7))
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(
                                    timer.settings.tagIcon(tag) == icon ? 0.14 : 0.05)))
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
            HStack(spacing: 6) {
                ForEach(TaskCategory.palette, id: \.self) { hex in
                    Button {
                        var s = timer.settings.tagStyles[tag] ?? TagStyle()
                        s.colorHex = hex
                        timer.settings.tagStyles[tag] = s
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(
                                .white.opacity(timer.settings.tagColorHex(tag) == hex ? 0.9 : 0),
                                lineWidth: 2))
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
            HStack {
                if timer.settings.tagStyles[tag] != nil {
                    Button("Reset") { timer.settings.tagStyles[tag] = nil }
                }
                Spacer()
                Button(role: .destructive) {
                    timer.settings.tagStyles[tag] = nil
                    tasks.removeTag(tag)
                    editingTag = nil
                } label: {
                    Text("Delete label")
                        .foregroundStyle(.red.opacity(0.9))
                }
            }
            .font(.system(.caption, design: .rounded))
            if isRemovableCustom {
                HStack {
                    Button {
                        tasks.removeCustomTag(tag)
                        editingTag = nil
                    } label: {
                        Text("Remove tag")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .font(.system(.caption2, design: .rounded))
            }
        }
        .padding(14)
    }

    /// The little hover pencil shared by editable sidebar rows.
    private func editPencil(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .help("Edit")
    }

    /// Every priority level, always visible; zero-count rows render dimmed. The
    /// four built-ins (P1–P4) are fixed; "+" adds a custom level ABOVE P1 and a
    /// custom row's context menu deletes it. Each level's display name and flag
    /// color are editable via the row's hover pencil.
    @ViewBuilder
    private var prioritySection: some View {
        let open = tasks.tasks.filter { !$0.isDone }
        sectionHeader("Priority", collapsed: $prioCollapsed,
                      addHelp: "New priority level") {
            showAddPriority = true
        }
        .popover(isPresented: $showAddPriority, arrowEdge: .trailing) {
            addPriorityPopover
        }
        if !prioCollapsed {
            ForEach(TaskPriority.levels(custom: timer.settings.customPriorityLevels)) { p in
                priorityRow(p, count: open.filter { $0.priority == p }.count)
            }
        }
    }

    private var addPriorityPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New priority level").dsSectionLabel()
            TextField("Name", text: $newPrioName)
                .textFieldStyle(DarkGlassFieldStyle())
                .frame(width: 180)
                .onSubmit(commitNewPriority)
            HStack(spacing: 6) {
                ForEach(TaskCategory.palette, id: \.self) { hex in
                    Button { newPrioColor = hex } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white.opacity(newPrioColor == hex ? 0.9 : 0),
                                                     lineWidth: 2))
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
            Button("Add", action: commitNewPriority)
                .disabled(newPrioName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
    }

    /// Adds a custom level above P1: next rawValue is one past the current max
    /// (built-ins cap at 3), stored with the required name + color override.
    private func commitNewPriority() {
        let name = newPrioName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let raw = (timer.settings.customPriorityLevels.max() ?? 3) + 1
        timer.settings.customPriorityLevels.append(raw)
        timer.settings.priorityNames[String(raw)] = name
        timer.settings.priorityColors[String(raw)] = newPrioColor
        newPrioName = ""
        newPrioColor = TaskCategory.palette[0]
        showAddPriority = false
    }

    /// Deletes a custom level: its tasks fall back to `.none`, and the level's
    /// rawValue + name/color overrides are dropped. Built-ins can't be deleted.
    private func deletePriorityLevel(_ p: TaskPriority) {
        guard p.rawValue > 3 else { return }
        tasks.reassignPriority(from: p, to: .none)
        timer.settings.customPriorityLevels.removeAll { $0 == p.rawValue }
        timer.settings.priorityNames[String(p.rawValue)] = nil
        timer.settings.priorityColors[String(p.rawValue)] = nil
        if editingPriority == p { editingPriority = nil }
    }

    private func priorityRow(_ p: TaskPriority, count: Int) -> some View {
        let key = "prio:\(p.rawValue)"
        return Button { router.openTasks(priority: p) } label: {
            HStack(spacing: 11) {
                Image(systemName: p == .none ? "flag.slash" : "flag.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(timer.settings.priorityColorHex(p)
                        .map { Color(hex: $0) } ?? .secondary)
                    .frame(width: 20, alignment: .center)
                Text(timer.settings.priorityName(p))
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(count > 0 ? 0.75 : 0.45))
                    .lineLimit(1)
                Spacer()
                if hoveredRowKey == key {
                    editPencil { editingPriority = p }
                } else if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
        .onHover { inside in
            if inside { hoveredRowKey = key }
            else if hoveredRowKey == key { hoveredRowKey = nil }
        }
        .popover(isPresented: Binding(
            get: { editingPriority == p },
            set: { if !$0 { editingPriority = nil } }
        ), arrowEdge: .trailing) {
            editPriorityPopover(p)
        }
        .contextMenu {
            Button { editingPriority = p } label: {
                Label("Edit…", systemImage: "pencil")
            }
            if p.rawValue > 3 {
                Divider()
                Button(role: .destructive) { deletePriorityLevel(p) } label: {
                    Label("Delete level", systemImage: "trash")
                }
            }
        }
    }

    private func editPriorityPopover(_ p: TaskPriority) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit \(p == .none ? "P4" : timer.settings.priorityShortLabel(p))").dsSectionLabel()
            TextField(p.menuLabel, text: Binding(
                get: { timer.settings.priorityNames[String(p.rawValue)] ?? "" },
                set: { timer.settings.priorityNames[String(p.rawValue)] =
                        $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(DarkGlassFieldStyle())
            .frame(width: 180)
            HStack(spacing: 6) {
                ForEach(TaskCategory.palette, id: \.self) { hex in
                    Button {
                        timer.settings.priorityColors[String(p.rawValue)] = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(
                                .white.opacity(timer.settings.priorityColorHex(p) == hex ? 0.9 : 0),
                                lineWidth: 2))
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
            HStack {
                if timer.settings.priorityNames[String(p.rawValue)] != nil
                    || timer.settings.priorityColors[String(p.rawValue)] != nil {
                    Button("Reset to default") {
                        timer.settings.priorityNames[String(p.rawValue)] = nil
                        timer.settings.priorityColors[String(p.rawValue)] = nil
                    }
                    .font(.system(.caption, design: .rounded))
                }
                Spacer()
            }
            Text("Empty name = default. Applies everywhere flags show.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(14)
    }

    /// Shared row shape for category/tag entries: colored text mark + name +
    /// trailing count, Todoist-style.
    private func filterRow(mark: String, markTint: Color, title: String,
                           count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Text(mark)
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(markTint)
                    .frame(width: 20, alignment: .center)
                Text(title)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(count > 0 ? 0.75 : 0.45))
                    .lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
    }

    /// A small glass status card pinned to the bottom of the sidebar — today's
    /// focus count and the current streak, so the panel closes on a live signal
    /// instead of empty space (the way Todoist parks account/karma at the foot).
    private var sidebarFooter: some View {
        let today = timer.stats.completedTodayCount()
        let streak = timer.stats.streak.currentStreak
        return HStack(spacing: 0) {
            footerStat(icon: "target", tint: accent, value: today, label: "Today")
            Divider().frame(height: 28).overlay(Color.white.opacity(0.12))
            footerStat(icon: "flame.fill", tint: .orange, value: streak, label: "Streak")
        }
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    private func footerStat(icon: String, tint: Color, value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: value)
                Text("\(value)")
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(DS.Motion.snappy, value: value)
            }
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String,
                               collapsed: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            sidebarHeaderLabel(title)
            Spacer()
            collapseChevron(collapsed.wrappedValue)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(collapsed) }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 5)
    }

    /// Rotating accordion indicator shared by all sidebar group headers.
    private func collapseChevron(_ collapsed: Bool) -> some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.45))
            .rotationEffect(.degrees(collapsed ? -90 : 0))
    }

    private func toggle(_ collapsed: Binding<Bool>) {
        withAnimation(DS.Motion.gentle) {
            collapsed.wrappedValue.toggle()
        }
    }

    /// Todoist-style sidebar group label: sentence case at row size, instead
    /// of the app-wide 10 pt uppercase `dsSectionLabel` (too small next to
    /// 13 pt rows).
    private func sidebarHeaderLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
    }

    /// Section header with a trailing "+" action (e.g. Categories → new).
    private func sectionHeader(_ title: String, collapsed: Binding<Bool>,
                               addHelp: String,
                               onAdd: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            sidebarHeaderLabel(title)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .help(addHelp)
            collapseChevron(collapsed.wrappedValue)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(collapsed) }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 5)
    }

    /// Sidebar badge count per section: open tasks for Tasks, still-unscheduled
    /// tasks for Week (the board's backlog). Zero hides the badge.
    private func badgeCount(for s: Section) -> Int {
        switch s {
        case .tasks: return tasks.tasks.filter { !$0.isDone }.count
        case .week:  return tasks.unscheduledTasks.count
        default:     return 0
        }
    }

    private func navRow(_ s: Section) -> some View {
        let selected = section == s
        let hovered = hoveredNav == s
        let badge = badgeCount(for: s)
        return Button {
            // Settings routes through the router helper so re-selecting the
            // row while a sub-page is open pops back to the category list.
            if s == .settings { router.openSettings() }
            else { section = s }
        } label: {
            HStack(spacing: 11) {
                // Icon glows in the theme accent when the row is selected, so the
                // active section reads instantly (Todoist-style accent selection).
                Image(systemName: s.icon)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? accent
                                     : (hovered ? Color.white.opacity(0.85) : .white.opacity(0.55)))
                    .frame(width: 20, alignment: .center)
                Text(s.title)
                    .font(.system(.body, design: .rounded).weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : .white.opacity(0.7))
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(.caption2, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(selected ? accent : .white.opacity(0.5))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(selected ? accent.opacity(0.18)
                                                   : Color.white.opacity(0.08)))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(selected ? accent.opacity(0.20)
                          : (hovered ? Color.white.opacity(0.06) : .clear))
            )
            // A slim accent bar marks the selected row, like a sidebar cursor.
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(accent)
                        .frame(width: 3, height: 16)
                        .padding(.leading, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
        .onHover { inside in
            if inside { hoveredNav = s }
            else if hoveredNav == s { hoveredNav = nil }
        }
        .animation(DS.Motion.hover, value: selected)
        .animation(DS.Motion.hover, value: hovered)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .timer:
            TimerDetailView(timer: timer)
        case .tasks:
            detailScaffold(title: "Tasks") {
                TasksView(timer: timer, embeddedInScroll: true)
            }
        case .week:
            // Full-width — the 7-day board manages its own horizontal layout
            // rather than the width-capped scaffold used by the other sections.
            WeeklyBoardView(timer: timer)
                .padding(.horizontal, 28)
                .padding(.top, 32)
                .padding(.bottom, 24)
        case .stats:
            detailScaffold(title: "Progress") {
                VStack(spacing: 20) {
                    StatsSummaryView(stats: timer.stats,
                                     focusMinutes: timer.settings.focusMinutes,
                                     accent: timer.settings.theme.accent,
                                     dailyGoal: timer.settings.dailyPomodoroGoal)
                    StreakBadgeView(streak: timer.stats.streak)
                    StatsChartView(stats: timer.stats, accent: timer.settings.theme.accent)
                    StatsExtrasView(stats: timer.stats,
                                    accent: timer.settings.theme.accent)
                }
            }
        case .report:
            detailScaffold(title: "Report") {
                ReportView(timer: timer)
            }
        case .settings:
            SettingsView(timer: timer, settings: $timer.settings)
        }
    }

    /// Shared detail chrome: a section title and a centered, width-capped body
    /// so content never stretches edge-to-edge on wide windows.
    private func detailScaffold<C: View>(title: String,
                                         @ViewBuilder content: () -> C) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                content()
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 32)
        }
    }

    /// Deep, colored gradient that fills the whole window, tinted by the theme
    /// and darkened for text contrast. The recipe lives in `ThemeWindowWash`,
    /// shared with the notch island so the two stay 1:1.
    private var windowBackground: some View {
        ThemeWindowWash(theme: timer.settings.theme)
            .ignoresSafeArea()
    }
}

/// Large, centered timer view for the main window.
private struct TimerDetailView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    @State private var showTaskPicker = false

    var body: some View {
        let remaining = max(0, timer.remainingSeconds)
        let total = timer.totalSeconds
        let progress = total > 0 ? 1 - remaining / total : 0

        VStack(spacing: 32) {
            Spacer(minLength: 12)

            ZStack {
                CountdownRing(progress: progress,
                              colors: timer.phase.gradient,
                              lineWidth: 20)
                    .frame(width: 300, height: 300)
                VStack(spacing: 8) {
                    Text(timer.settings.timeFormat.string(remaining))
                        .font(.dsTimer(76))
                        .foregroundStyle(.white)
                    if timer.isIdleAtFocus {
                        ringKindPicker
                    } else {
                        Label(timer.phase.label, systemImage: timer.phase.systemImage)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .animation(DS.Motion.snappy, value: timer.isIdleAtFocus)
            }

            // Tappable task selector — pick a task before focusing. Sized to
            // read as a primary control that matches the timer's scale.
            Button {
                showTaskPicker = true
            } label: {
                let active = tasks.activeTask
                Label(active?.title ?? "Choose a task",
                      systemImage: active != nil ? "target" : "plus.circle.fill")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(active != nil ? .white : .white.opacity(0.85))
                    .lineLimit(1)
                    .padding(.horizontal, 26).padding(.vertical, 14)
                    .frame(minWidth: 240)
                    .glassCapsule(material: .regular)
            }
            .buttonStyle(.pressableSubtle)

            Spacer(minLength: 12)

            // Primary CleanMyMac-style glowing run button, flanked by
            // subtle secondary controls.
            HStack(alignment: .center, spacing: 28) {
                GlassIconButton(systemImage: "forward.end.fill", label: "Skip",
                                action: { timer.skip() })

                CircularRunButton(isRunning: timer.isRunning,
                                  colors: timer.phase.gradient,
                                  action: runTapped)

                GlassIconButton(systemImage: "arrow.counterclockwise", label: "Reset",
                                tint: .red.opacity(0.95),
                                action: { timer.stop() })
            }
        }
        .padding(EdgeInsets(top: 40, leading: 40, bottom: 50, trailing: 40))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showTaskPicker) {
            TaskPickerSheet(timer: timer)
        }
    }

    /// Small / Normal / Big switch inside the ring — idle only. Mirrors the
    /// sidebar selector (same applyKind semantics); while idle a tap also
    /// refreshes the countdown to the new focus length.
    private var ringKindPicker: some View {
        let accent = timer.settings.theme.accent
        let active = timer.settings.config(for: timer.settings.activeKind)
        return VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(PomodoroKind.allCases) { kind in
                    let selected = timer.settings.activeKind == kind
                    let cfg = timer.settings.config(for: kind)
                    Button {
                        timer.applyKind(kind)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 10, weight: .semibold))
                            Text(kind.label)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(selected ? accent.opacity(0.26)
                                                            : Color.white.opacity(0.07)))
                        .overlay(Capsule().stroke(selected ? accent.opacity(0.65) : Color.clear,
                                                  lineWidth: 1))
                        .foregroundStyle(selected ? accent : Color.white.opacity(0.7))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressableSubtle)
                    .help("\(kind.label): \(cfg.focusMinutes) min focus, \(cfg.breakMinutes) min break")
                }
            }
            Text("\(active.focusMinutes)′ + \(active.breakMinutes)′")
                .font(.system(size: 11, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .animation(DS.Motion.snappy, value: timer.settings.activeKind)
    }

    /// Big run button: if a task is already active, just toggle the timer.
    /// Otherwise, prompt the user to pick a task first.
    private func runTapped() {
        if timer.isRunning || tasks.activeTask != nil || !timer.settings.requireTaskForFocus {
            timer.toggle()
        } else {
            // No task and the rule is on — make the user pick one first.
            showTaskPicker = true
        }
    }
}
