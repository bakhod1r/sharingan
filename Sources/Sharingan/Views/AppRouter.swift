import SwiftUI
import SharinganCore

/// The main window's navigation sections. Top-level so both the window and the
/// menu-bar popover can drive selection through `AppRouter`.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case timer, tasks, week, stats, report, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .timer:    return "Pomodoro"
        case .tasks:    return "Tasks"
        case .week:     return "Week"
        case .stats:    return "Progress"
        case .report:   return "Report"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .timer:    return "timer"
        case .tasks:    return "checklist"
        case .week:     return "calendar"
        case .stats:    return "chart.line.uptrend.xyaxis"
        case .report:   return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }
}

/// Shared navigation state so the menu-bar popover can open the main window on a
/// specific section (e.g. the gear jumps straight to Settings).
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var section: AppSection = .timer

    // One-shot deep-links into the Tasks list, set by the sidebar and consumed
    // (reset to nil/false) by TasksView when it applies them.
    @Published var pendingTaskFilter: TaskFilter?
    @Published var pendingTaskCategory: String?
    @Published var pendingTaskTag: String?
    @Published var pendingTaskPriority: TaskPriority?
    @Published var focusTaskSearch = false
    /// One-shot "scroll to and flash this task" — set by task rows outside the
    /// main window (the notch island), consumed by TasksView like the filters.
    @Published var pendingRevealTaskID: UUID?
    /// One-shot "open the bulk-import sheet" — set by File ▸ Import Tasks…,
    /// consumed by TasksView like the filters.
    @Published var openTaskImport = false

    /// Bumped whenever Settings is (re)opened from outside — the sidebar row,
    /// the menu-bar gear — so SettingsView pops any open sub-page back to the
    /// category list. A counter (not a flag) so every tap fires onChange.
    @Published private(set) var settingsPopToRoot = 0

    /// Open the Settings section at its root category list, even if a
    /// sub-page is currently showing.
    func openSettings() {
        settingsPopToRoot += 1
        section = .settings
    }

    /// Jump to the Tasks section with an optional smart filter and at most one
    /// narrowing dimension (category / tag / priority).
    func openTasks(filter: TaskFilter? = nil, category: String? = nil,
                   tag: String? = nil, priority: TaskPriority? = nil,
                   focusSearch: Bool = false) {
        pendingTaskFilter = filter
        pendingTaskCategory = category
        pendingTaskTag = tag
        pendingTaskPriority = priority
        focusTaskSearch = focusSearch
        section = .tasks
    }

    /// Jump to the Tasks section landed on one specific task: the list clears
    /// whatever would hide it, scrolls the row to centre and flashes it.
    func revealTask(_ id: UUID) {
        pendingRevealTaskID = id
        section = .tasks
    }
}
