import SwiftUI

@main
struct MoveEyesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("MoveEyes") {
            ContentView()
                .frame(minWidth: 480, minHeight: 360)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 600)

        SwiftUI.Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            renderSnapshot(
                to: args[i + 1],
                mouse: i + 3 < args.count
                    ? CGPoint(x: Double(args[i + 2]) ?? 400, y: Double(args[i + 3]) ?? 300)
                    : nil
            )
            NSApp.terminate(nil)
            return
        }
        if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
            renderIcon(to: args[i + 1])
            NSApp.terminate(nil)
            return
        }
        if let i = args.firstIndex(of: "--menuicon"), i + 1 < args.count {
            if let img = Self.menuBarIcon(),
               let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: args[i + 1]))
            }
            NSApp.terminate(nil)
            return
        }
        // .app sifatida ochilganda default — wallpaper rejimi
        // (oddiy oyna uchun --window bilan ishga tushiriladi)
        let fromBundle = Bundle.main.bundlePath.hasSuffix(".app")
        if args.contains("--wallpaper") || (fromBundle && !args.contains("--window")) {
            NSApp.setActivationPolicy(.accessory)
            setupStatusItem()
            makeWallpaper(attempt: 0)
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Oynani ish stoli (wallpaper) darajasiga tushiradi: butun ekranni
    /// qoplaydi, ikonkalar ostida turadi, sichqonchaga xalaqit bermaydi.
    @MainActor
    private func makeWallpaper(attempt: Int) {
        guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
            // SwiftUI oynasi hali yaratilmagan bo'lishi mumkin — qayta urinamiz
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.makeWallpaper(attempt: attempt + 1)
                }
            }
            return
        }
        window.styleMask = [.borderless]
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.hasShadow = false
        if let screen = NSScreen.main {
            window.setFrame(screen.frame, display: true)
        }
        window.orderFrontRegardless()
    }

    /// Menyu-bar uchun premium Sharingan belgisi: kichik o'lchamda ham
    /// aniq ko'rinadigan qizil iris + 3 tomoe (retina masshtabida chiziladi).
    @MainActor
    private static func menuBarIcon() -> NSImage? {
        let pt: CGFloat = 18
        let view = IrisView(diameter: pt - 2)
            .frame(width: pt, height: pt)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let cg = renderer.cgImage else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: pt, height: pt))
        image.isTemplate = false   // rangli qolishi uchun (template emas)
        return image
    }

    /// Wallpaper rejimida sozlamalar va chiqish uchun menyu-bar belgisi.
    @MainActor
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = Self.menuBarIcon() {
            item.button?.image = icon
            item.button?.imagePosition = .imageOnly
        } else {
            item.button?.title = "👁"
        }
        let menu = NSMenu()
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit MoveEyes",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        item.menu = menu
        statusItem = item
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "MoveEyes Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Oynasiz, ekran-ruxsatlarisiz kadr chizish — vizual tekshiruv uchun.
    @MainActor
    private func renderSnapshot(to path: String, mouse point: CGPoint?) {
        let state = MouseState()
        state.location = point
        let view = ContentView(mouse: state, trackingEnabled: false)
            .frame(width: 800, height: 600)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("snapshot render failed\n".utf8))
            return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
    }

    /// 1024×1024 dastur ikonkasi: to'q yumaloq kvadrat ustida bitta ko'z.
    @MainActor
    private func renderIcon(to path: String) {
        let state = MouseState()
        let view = ZStack {
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.11, blue: 0.12),
                            Color(red: 0.04, green: 0.045, blue: 0.05),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 832, height: 832)
            EyeView(
                size: CGSize(width: 620, height: 295),
                mirrored: false,
                eyeCenter: .zero,
                mouse: state
            )
        }
        .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("icon render failed\n".utf8))
            return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
