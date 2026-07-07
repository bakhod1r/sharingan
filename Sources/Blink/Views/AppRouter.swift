import SwiftUI

/// The main window's navigation sections. Top-level so both the window and the
/// menu-bar popover can drive selection through `AppRouter`.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case timer, tasks, week, stats, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .timer:    return "Timer"
        case .tasks:    return "Tasks"
        case .week:     return "Week"
        case .stats:    return "Stats"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .timer:    return "timer"
        case .tasks:    return "checklist"
        case .week:     return "calendar"
        case .stats:    return "chart.bar"
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
}
