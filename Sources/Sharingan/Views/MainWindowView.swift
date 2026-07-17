import SwiftUI
import SharinganCore

/// Full "desktop app" window with a CleanMyMac-style sidebar. Coexists with the
/// menu bar extra — opened from the menu bar's "Open window" button.
struct MainWindowView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject private var tasks = TaskStore.shared
    @ObservedObject private var router = AppRouter.shared
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
    /// The sidebar row under the pointer — drives every row's hover highlight
    /// and reveals a filter row's edit pencil.
    @State private var hoveredRowKey: String?
    /// Accordion state of the sidebar groups, persisted across launches.
    @AppStorage("sidebar.collapsed.categories") private var catsCollapsed = false
    @AppStorage("sidebar.collapsed.projects") private var projsCollapsed = false
    @AppStorage("sidebar.collapsed.tags") private var tagsCollapsed = false
    /// Inline "new project" popover state (sidebar Projects +).
    @State private var showAddProject = false
    @State private var newProjName = ""
    @State private var newProjColor = TaskCategory.palette[0]
    /// Project whose rename/recolor editor popover is open.
    @State private var editingProject: String?
    @State private var editProjName = ""
    @AppStorage("sidebar.collapsed.priority") private var prioCollapsed = false
    /// Sidebar squeezed to an icon rail, persisted across launches (⌘\ or the
    /// chevron). The panel never leaves — navigation stays reachable.
    @AppStorage("sidebar.rail") private var sidebarCollapsed = false
    /// Filter group whose rail flyout is open ("cats", "projs", "tags", "prio").
    @State private var railFlyout: String?
    /// Theme list popover, opened from the sidebar's foot.
    @State private var showThemePicker = false
    /// Pointer is over the collapse chevron — grows it out of the panel edge.
    @State private var toggleHovered = false

    /// Width of the sidebar in each mode; the rail fits a centered 20pt icon
    /// plus its tile padding.
    private var sidebarWidth: CGFloat { sidebarCollapsed ? 60 : 232 }

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
                    .frame(width: sidebarWidth)
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
            .animation(DS.Motion.rail, value: sidebarCollapsed)
            // Labels are clipped as the panel narrows instead of wrapping.
            .clipped()
        }
        .overlay(alignment: .leading) { sidebarToggle }
        .frame(minWidth: 920, minHeight: 620)
        // One app accent: controls (pickers, toggles, sliders, menus) follow the
        // chosen theme instead of the stock system blue.
        .tint(timer.settings.theme.accent)
    }

    // MARK: - Sidebar collapse

    /// A round glass chevron that rides the sidebar's outer edge — pointing
    /// back at the panel to squeeze it to a rail, out toward the window to open
    /// it again. It sits mid-height so it never collides with a section's
    /// title, and it travels with the panel on the same spring.
    private var sidebarToggle: some View {
        Button {
            sidebarCollapsed.toggle()
            railFlyout = nil
        } label: {
            Image(systemName: sidebarCollapsed ? "chevron.right" : "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(toggleHovered ? 1 : 0.8))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(
                            Color.white.opacity(toggleHovered ? 0.32 : 0.18), lineWidth: 1))
                        // The accent breathes through the glass on hover, so the
                        // control reads as live before it is clicked.
                        .overlay(Circle().fill(accent.opacity(toggleHovered ? 0.22 : 0)))
                )
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                .shadow(color: accent.opacity(toggleHovered ? 0.45 : 0), radius: 9)
                .scaleEffect(toggleHovered ? 1.12 : 1)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.pressableSubtle)
        .onHover { hovering in
            withAnimation(DS.Motion.hover) { toggleHovered = hovering }
        }
        .help(sidebarCollapsed ? "Expand sidebar (⌘\\)" : "Collapse sidebar (⌘\\)")
        .keyboardShortcut("\\", modifiers: .command)
        // Straddles the panel's outer edge in either mode.
        .padding(.leading, sidebarWidth + 4)
        .animation(DS.Motion.rail, value: sidebarCollapsed)
    }

    /// The rail has no room for a count, so a non-zero badge shrinks to a dot
    /// pinned to the icon's corner. Nothing is drawn in full mode.
    @ViewBuilder
    private func railDot(_ show: Bool, tint: Color? = nil) -> some View {
        if sidebarCollapsed && show {
            Circle()
                .fill(tint ?? accent)
                .frame(width: 6, height: 6)
                .offset(x: 4, y: -2)
        }
    }

    /// One hover surface behind every clickable sidebar row — nav, shortcuts,
    /// filters, the rail's group tiles and the theme foot alike — so the whole
    /// panel lights up the same way under the pointer instead of only the nav
    /// rows reacting. Pair it with `trackHover(_:)` on the row.
    private func rowSurface(_ key: String, selected: Bool = false) -> some View {
        let hovered = hoveredRowKey == key
        return RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(selected ? accent.opacity(0.20)
                  : (hovered ? Color.white.opacity(0.06) : .clear))
            .animation(DS.Motion.hover, value: hovered)
    }

    private func trackHover(_ inside: Bool, _ key: String) {
        if inside { hoveredRowKey = key }
        else if hoveredRowKey == key { hoveredRowKey = nil }
    }

    /// How a row's label enters and leaves as the panel opens and closes.
    /// Asymmetric on purpose: the text clears out fast and ahead of the width
    /// (so nothing is caught mid-squeeze), then drifts back in behind the
    /// panel's spring once there is room for it.
    private var railLabelReveal: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(x: -10))
                .animation(DS.Motion.rail.delay(0.10)),
            removal: .opacity
                .combined(with: .offset(x: -10))
                .animation(.easeOut(duration: 0.12)))
    }

    /// Shared chrome for one sidebar row's content: full mode lays the icon and
    /// its trailing detail out in a row; the rail keeps only the centered icon
    /// and hangs the name off a tooltip.
    @ViewBuilder
    private func rowShell<Icon: View, Trailing: View>(
        help: String,
        vpad: CGFloat = 9,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 11) {
            icon()
                .frame(width: 20, alignment: .center)
            if !sidebarCollapsed {
                trailing()
                    // Labels hold their full width and let the panel clip them,
                    // rather than re-wrapping on every frame of the squeeze.
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(railLabelReveal)
            }
        }
        .frame(maxWidth: .infinity, alignment: sidebarCollapsed ? .center : .leading)
        .padding(.horizontal, sidebarCollapsed ? 0 : 10)
        .padding(.vertical, vpad)
        .contentShape(Rectangle())
        .help(sidebarCollapsed ? help : "")
    }

    /// Hairline between the navigation rows and the filter groups below them —
    /// the one place the sidebar changes register, from "where do I go" to
    /// "what do I narrow to". Inset to the rows' own left edge.
    private var sidebarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
            .padding(.horizontal, sidebarCollapsed ? 12 : 10)
            .padding(.top, 10)
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
                    navRow(.analytics)
                    navRow(.report)
                    sidebarDivider
                    categoriesSection
                    projectsSection
                    tagsSection
                    prioritySection
                }
            }
            Spacer(minLength: 12)
            sidebarFooter
            themeButton
            navRow(.settings)
                .padding(.bottom, 10)
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
            rowShell(help: "Add task") {
                ZStack {
                    Circle().fill(accent)
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 24, height: 24)
                .shadow(color: accent.opacity(0.5), radius: 5, y: 2)
            } trailing: {
                Text("Add task")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(accent)
                Spacer()
            }
            .background(rowSurface("add"))
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
        .onHover { trackHover($0, "add") }
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
        if sidebarCollapsed {
            railGroupTile("cats", icon: "number", help: "Categories") {
                ForEach(tasks.allCategories) { cat in
                    categoryRow(cat, count: counts[cat.name] ?? 0)
                }
            }
        } else {
            sectionHeader("Categories", icon: "number", collapsed: $catsCollapsed,
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

    /// Projects — the second grouping axis, managed exactly like categories:
    /// "+" registers a project, a row click narrows the Tasks list, the hover
    /// pencil opens rename/recolor/delete.
    @ViewBuilder
    private var projectsSection: some View {
        let counts = Dictionary(grouping: tasks.tasks.filter { !$0.isDone && $0.project != nil },
                                by: { $0.project ?? "" }).mapValues(\.count)
        if sidebarCollapsed {
            railGroupTile("projs", icon: "folder", help: "Projects") {
                ForEach(tasks.allProjects) { proj in
                    projectRow(proj, count: counts[proj.name] ?? 0)
                }
            }
        } else {
            sectionHeader("Projects", icon: "folder", collapsed: $projsCollapsed,
                          addHelp: "New project") {
                showAddProject = true
            }
            .popover(isPresented: $showAddProject, arrowEdge: .trailing) {
                addProjectPopover
            }
            if !projsCollapsed {
                ForEach(tasks.allProjects) { proj in
                    projectRow(proj, count: counts[proj.name] ?? 0)
                }
            }
        }
    }

    private var addProjectPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New project").dsSectionLabel()
            TextField("Name", text: $newProjName)
                .textFieldStyle(DarkGlassFieldStyle())
                .frame(width: 180)
                .onSubmit(commitNewProject)
            HStack(spacing: 6) {
                ForEach(TaskCategory.palette, id: \.self) { hex in
                    Button { newProjColor = hex } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white.opacity(newProjColor == hex ? 0.9 : 0),
                                                     lineWidth: 2))
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
            Button("Add", action: commitNewProject)
                .disabled(newProjName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
    }

    private func commitNewProject() {
        guard tasks.addProject(name: newProjName, colorHex: newProjColor) != nil else { return }
        newProjName = ""
        showAddProject = false
    }

    /// Project row — mirrors `categoryRow`, but every project is user-owned so
    /// rename/delete are always available.
    private func projectRow(_ proj: TaskCategory, count: Int) -> some View {
        let key = "proj:\(proj.name)"
        return Button { router.openTasks(project: proj.name) } label: {
            HStack(spacing: 11) {
                Image(systemName: proj.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: proj.colorHex))
                    .frame(width: 20, alignment: .center)
                Text(proj.name)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(count > 0 ? 0.75 : 0.45))
                    .lineLimit(1)
                Spacer()
                if hoveredRowKey == key {
                    editPencil {
                        editProjName = ""
                        editingProject = proj.name
                    }
                } else if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(rowSurface(key))
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
        .onHover { inside in
            if inside { hoveredRowKey = key }
            else if hoveredRowKey == key { hoveredRowKey = nil }
        }
        .popover(isPresented: Binding(
            get: { editingProject == proj.name },
            set: { if !$0 { editingProject = nil } }
        ), arrowEdge: .trailing) {
            projectEditorPopover(proj)
        }
    }

    /// Rename + color editor for a project, with delete (tasks fall back to
    /// "no project") at the bottom.
    private func projectEditorPopover(_ proj: TaskCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(proj.name).dsSectionLabel()
            TextField(proj.name, text: $editProjName)
                .textFieldStyle(DarkGlassFieldStyle())
                .frame(width: 180)
                .onSubmit {
                    if tasks.renameProject(proj.name, to: editProjName) {
                        editingProject = nil
                    }
                }
            HStack(spacing: 6) {
                ForEach(TaskCategory.palette, id: \.self) { hex in
                    Button {
                        tasks.setProjectColor(proj.name, colorHex: hex)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(
                                .white.opacity(tasks.projectColor(proj.name) == hex ? 0.9 : 0),
                                lineWidth: 2))
                    }
                    .buttonStyle(.pressableSubtle)
                }
            }
            HStack {
                Spacer()
                Button(role: .destructive) {
                    tasks.deleteProject(proj.name)
                    editingProject = nil
                } label: {
                    Text("Delete project")
                        .foregroundStyle(.red.opacity(0.9))
                }
            }
            .font(.system(.caption, design: .rounded))
        }
        .padding(14)
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
        let key = "sc:\(title)"
        return Button(action: action) {
            rowShell(help: title) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(hoveredRowKey == key ? 0.85 : 0.55))
                    .overlay(alignment: .topTrailing) { railDot(count > 0, tint: countTint) }
            } trailing: {
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
            .background(rowSurface(key))
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
        .onHover { trackHover($0, key) }
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
            .background(rowSurface(key))
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
        if sidebarCollapsed {
            railGroupTile("tags", icon: "tag", help: "Tags") {
                ForEach(Array(names), id: \.self) { tag in
                    tagRow(tag, count: counts[tag] ?? 0)
                }
            }
        } else {
            sectionHeader("Tags", icon: "tag", collapsed: $tagsCollapsed,
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
            .background(rowSurface(key))
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
        if sidebarCollapsed {
            railGroupTile("prio", icon: "flag", help: "Priority") {
                ForEach(TaskPriority.levels(custom: timer.settings.customPriorityLevels)) { p in
                    priorityRow(p, count: open.filter { $0.priority == p }.count)
                }
            }
        } else {
            sectionHeader("Priority", icon: "flag", collapsed: $prioCollapsed,
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
            .background(rowSurface(key))
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

    /// A small glass status card pinned to the bottom of the sidebar — today's
    /// focus count and the current streak, so the panel closes on a live signal
    /// instead of empty space (the way Todoist parks account/karma at the foot).
    @ViewBuilder
    private var sidebarFooter: some View {
        let today = timer.stats.completedTodayCount()
        let streak = timer.stats.streak.currentStreak
        // The rail stacks the two stats and drops their captions — the icon
        // already says which is which at that width.
        let layout = sidebarCollapsed
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 0))
        layout {
            footerStat(icon: "target", tint: accent, value: today, label: "Today")
            if !sidebarCollapsed {
                Divider().frame(height: 28).overlay(Color.white.opacity(0.12))
            }
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

    /// Theme switcher parked under the stats card — the palette every surface
    /// reads off is one click away instead of buried in Settings → General.
    /// The swatch shows the live accent, so the row states the current theme
    /// even in the rail, where its name doesn't fit.
    private var themeButton: some View {
        Button { showThemePicker = true } label: {
            rowShell(help: "Theme — \(timer.settings.theme.label)", vpad: 7) {
                Circle()
                    .fill(LinearGradient(colors: timer.settings.theme.gradient,
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
            } trailing: {
                Text(timer.settings.theme.label)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .background(rowSurface("theme", selected: showThemePicker))
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
        .onHover { trackHover($0, "theme") }
        .popover(isPresented: $showThemePicker, arrowEdge: .trailing) {
            themePicker
        }
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Theme").dsSectionLabel().padding(.horizontal, 12).padding(.bottom, 4)
            ForEach(SharinganTheme.allCases, id: \.self) { theme in
                let current = timer.settings.theme == theme
                Button {
                    withAnimation(DS.Motion.gentle) { timer.settings.theme = theme }
                    showThemePicker = false
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(LinearGradient(colors: theme.gradient,
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                        Text(theme.label)
                            .font(.system(size: 13, design: .rounded)
                                .weight(current ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(current ? 1 : 0.75))
                        Spacer()
                        if current {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressableSubtle)
            }
        }
        .padding(.vertical, 10)
        .frame(width: 190)
    }

    private func footerStat(icon: String, tint: Color, value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: value)
                Text("\(value)")
                    .font(.system(sidebarCollapsed ? .callout : .title3,
                                  design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(DS.Motion.snappy, value: value)
            }
            if !sidebarCollapsed {
                Text(label)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .help(sidebarCollapsed ? label : "")
    }

    private func sectionHeader(_ title: String, icon: String,
                               collapsed: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            sidebarHeaderLabel(title, icon: icon)
            Spacer()
            collapseChevron(collapsed.wrappedValue)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(collapsed) }
        .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 5)
        .transition(.opacity)
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
    /// 13 pt rows). The icon shares the rows' 20pt gutter so headers and rows
    /// hang off one left edge — and it doubles as the group's rail tile.
    private func sidebarHeaderLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20, alignment: .center)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// Section header with a trailing "+" action (e.g. Categories → new).
    private func sectionHeader(_ title: String, icon: String,
                               collapsed: Binding<Bool>,
                               addHelp: String,
                               onAdd: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            sidebarHeaderLabel(title, icon: icon)
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
        .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 5)
        .transition(.opacity)
    }

    /// A filter group as one rail tile: the group's icon, opening its rows in a
    /// flyout beside the rail. Nothing else fits at 60pt, and hiding the groups
    /// outright would put the filters out of reach while collapsed.
    private func railGroupTile(_ key: String, icon: String, help: String,
                               @ViewBuilder rows: @escaping () -> some View) -> some View {
        Button { railFlyout = railFlyout == key ? nil : key } label: {
            rowShell(help: help) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(railFlyout == key ? 0.9 : 0.5))
            } trailing: { EmptyView() }
            .transition(.opacity)
            .background(rowSurface("rail:\(key)", selected: railFlyout == key))
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
        .onHover { trackHover($0, "rail:\(key)") }
        .popover(isPresented: Binding(
            get: { railFlyout == key },
            set: { if !$0 { railFlyout = nil } }
        ), arrowEdge: .trailing) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) { rows() }
                    .padding(.vertical, 10)
            }
            .frame(width: 210)
            .frame(maxHeight: 320)
        }
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
        let key = "nav:\(s.rawValue)"
        let hovered = hoveredRowKey == key
        let badge = badgeCount(for: s)
        return Button {
            // Settings routes through the router helper so re-selecting the
            // row while a sub-page is open pops back to the category list.
            if s == .settings { router.openSettings() }
            else { section = s }
        } label: {
            rowShell(help: s.title) {
                // Icon glows in the theme accent when the row is selected, so the
                // active section reads instantly (Todoist-style accent selection).
                Image(systemName: s.icon)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? accent
                                     : (hovered ? Color.white.opacity(0.85) : .white.opacity(0.55)))
                    .overlay(alignment: .topTrailing) { railDot(badge > 0) }
            } trailing: {
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
            .background(rowSurface(key, selected: selected))
            // A slim accent bar marks the selected row, like a sidebar cursor.
            // The rail is too narrow for it — there the filled tile carries the
            // selection on its own.
            .overlay(alignment: .leading) {
                if selected && !sidebarCollapsed {
                    Capsule().fill(accent)
                        .frame(width: 3, height: 16)
                        .padding(.leading, 2)
                }
            }
        }
        .buttonStyle(.pressableSubtle)
        .padding(.horizontal, 8)
        .onHover { trackHover($0, key) }
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
            // Full-width, like Week — the docked detail panel needs room
            // beside the list that the 640pt-capped scaffold can't give it.
            VStack(alignment: .leading, spacing: 18) {
                Text("Tasks")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                TasksView(timer: timer, embeddedInScroll: true)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 24)
        case .week:
            // Full-width — the 7-day board manages its own horizontal layout
            // rather than the width-capped scaffold used by the other sections.
            WeeklyBoardView(timer: timer)
                .padding(.horizontal, 28)
                .padding(.top, 32)
                .padding(.bottom, 24)
        case .analytics:
            // Full-width like Week — the heatmap and charts need the whole
            // window, not the 640pt-capped scaffold. Owns its own scroll.
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Analytics")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    AnalyticsView(timer: timer)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 32)
            }
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
                Label(tasks.activeFocusTitle ?? "Choose a task",
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
