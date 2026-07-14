import AppKit
import UniformTypeIdentifiers
import SharinganCore

/// The app's main menu — visible whenever the main window has flipped the app
/// to `.regular` (accessory apps show no menu bar otherwise). Started life as
/// a two-item shim that only existed so ⌘V/⌘C/⌘X/⌘A/⌘Z had an Edit menu to
/// route through; now it is a real menu bar: File (new task / import / CSV),
/// View (sections + search), Timer (start-pause / skip / ±time), Window, Help.
///
/// Everything dispatches through the same singletons the rest of the app uses
/// (`AppRouter`, `MainWindowManager`, `QuickAddWindowManager`, `TaskStore`),
/// so a menu action and its in-app counterpart cannot drift apart. Items that
/// target the delegate set `target:` explicitly — the delegate is not in the
/// responder chain.
extension AppDelegate {

    func installMainMenu() {
        let main = NSMenu()
        main.addItem(appMenuItem())
        main.addItem(fileMenuItem())
        main.addItem(editMenuItem())
        main.addItem(viewMenuItem())
        main.addItem(timerMenuItem())
        main.addItem(windowMenuItem())
        main.addItem(helpMenuItem())
        NSApp.mainMenu = main
    }

    // MARK: - Menus

    private func appMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(withTitle: "About Sharingan",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(menuOpenSettings), ","))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sharingan",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return wrapped(menu)
    }

    private func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Task…", #selector(menuNewTask), "n"))
        menu.addItem(item("Import Tasks…", #selector(menuImportTasks), "I"))
        menu.addItem(item("Export Tasks as CSV…", #selector(menuExportCSV), ""))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close Window",
                     action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return wrapped(menu)
    }

    /// Undo/Redo use string selectors — they live on NSResponder informally,
    /// not in a protocol AppKit exports.
    private func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All",
                     action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return wrapped(menu)
    }

    /// One row per main-window section (Settings has its own home in the app
    /// menu), ⌘1…⌘5 in sidebar order, plus Search Tasks.
    private func viewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "View")
        let sections: [AppSection] = [.timer, .tasks, .week, .stats, .report]
        for (i, section) in sections.enumerated() {
            let row = item(section.title, #selector(menuGoToSection(_:)), "\(i + 1)")
            row.tag = i
            menu.addItem(row)
        }
        menu.addItem(.separator())
        menu.addItem(item("Search Tasks", #selector(menuSearchTasks), "f"))
        return wrapped(menu)
    }

    private func timerMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Timer")
        menu.addItem(item("Start / Pause Focus", #selector(menuToggleTimer), "\r"))
        let skip = item("Skip Phase", #selector(menuSkipPhase), "\r")
        skip.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(skip)
        menu.addItem(.separator())
        menu.addItem(item("Add 5 Minutes", #selector(menuAddFive), "+"))
        menu.addItem(item("Remove 5 Minutes", #selector(menuRemoveFive), "-"))
        return wrapped(menu)
    }

    private func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize",
                     action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom",
                     action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item("Sharingan", #selector(menuShowMainWindow), "0"))
        // macOS appends the open-windows list to whatever menu is registered
        // here.
        NSApp.windowsMenu = menu
        return wrapped(menu)
    }

    private func helpMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Help")
        menu.addItem(item("Sharingan Website", #selector(menuOpenWebsite), ""))
        menu.addItem(item("What's New", #selector(menuOpenReleases), ""))
        NSApp.helpMenu = menu
        return wrapped(menu)
    }

    // MARK: - Actions

    @MainActor @objc private func menuOpenSettings() {
        MainWindowManager.shared.show()
        AppRouter.shared.openSettings()
    }

    /// The same floating quick-add panel the global hotkey opens — works with
    /// or without the main window.
    @MainActor @objc private func menuNewTask() {
        QuickAddWindowManager.shared.showQuickAdd()
    }

    @MainActor @objc private func menuImportTasks() {
        MainWindowManager.shared.show()
        AppRouter.shared.section = .tasks
        AppRouter.shared.openTaskImport = true
    }

    @MainActor @objc private func menuExportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sharingan-tasks.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? TaskStore.shared.csv().write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor @objc private func menuGoToSection(_ sender: NSMenuItem) {
        let sections: [AppSection] = [.timer, .tasks, .week, .stats, .report]
        guard sections.indices.contains(sender.tag) else { return }
        MainWindowManager.shared.show()
        AppRouter.shared.section = sections[sender.tag]
    }

    @MainActor @objc private func menuSearchTasks() {
        MainWindowManager.shared.show()
        AppRouter.shared.section = .tasks
        AppRouter.shared.focusTaskSearch = true
    }

    @MainActor @objc private func menuToggleTimer() { timer?.toggle() }
    @MainActor @objc private func menuSkipPhase() { timer?.skip() }
    @MainActor @objc private func menuAddFive() { timer?.addTime(5 * 60) }
    @MainActor @objc private func menuRemoveFive() { timer?.removeTime(5 * 60) }

    @MainActor @objc private func menuShowMainWindow() {
        MainWindowManager.shared.show()
    }

    @MainActor @objc private func menuOpenWebsite() {
        NSWorkspace.shared.open(URL(string: "https://bakhod1r.github.io/sharingan/")!)
    }

    @MainActor @objc private func menuOpenReleases() {
        NSWorkspace.shared.open(URL(string: "https://github.com/bakhod1r/Blink/releases")!)
    }

    // MARK: - Helpers

    /// A menu item targeted at the delegate (it is not in the responder
    /// chain, so first-responder dispatch would never find these actions).
    private func item(_ title: String, _ action: Selector,
                      _ key: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    private func wrapped(_ menu: NSMenu) -> NSMenuItem {
        let it = NSMenuItem()
        it.submenu = menu
        return it
    }
}
