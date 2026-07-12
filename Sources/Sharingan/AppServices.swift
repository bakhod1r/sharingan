import Foundation
import SharinganCore

/// UI-side access point to the app's single `SharinganCoordinator` — set once at
/// launch by the AppDelegate. Views that can't be handed the coordinator
/// through their initializers (they're constructed by generic hosts several
/// layers away) reach shared services like the focus queue through here.
@MainActor
enum AppServices {
    static weak var coordinator: SharinganCoordinator?

    /// Preview/detached fallback so views always have a queue to observe.
    private static let orphanQueue = FocusQueue()

    /// The one focus queue the coordinator advances after each focus session.
    static var focusQueue: FocusQueue {
        coordinator?.focusQueue ?? orphanQueue
    }
}
