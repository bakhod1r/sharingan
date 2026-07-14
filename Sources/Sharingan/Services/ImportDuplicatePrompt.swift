import AppKit
import SharinganCore

/// The one question every document-import path asks when some of the pasted
/// tasks already exist: skip them (default) or add them again as copies.
@MainActor
enum ImportDuplicatePrompt {

    /// Shows the blocking prompt and inserts the duplicates on consent.
    /// No-ops when the import produced no duplicates. (No `.shared` default:
    /// a MainActor-isolated default argument trips Swift 6.)
    static func resolve(_ result: TaskStore.DocumentImport, store: TaskStore) {
        guard !result.duplicates.isEmpty else { return }
        let n = result.duplicates.count
        let alert = NSAlert()
        alert.messageText = n == 1
            ? "1 task already exists"
            : "\(n) tasks already exist"
        alert.informativeText = "Tasks with the same title are already on your list. "
            + "Skip them, or add them again as copies?"
        alert.addButton(withTitle: "Skip Duplicates")   // Return = the safe default
        alert.addButton(withTitle: "Add Anyway")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            store.insertAll(result.duplicates)
        }
    }
}
