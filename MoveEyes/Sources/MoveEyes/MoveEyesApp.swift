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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        NSApp.setActivationPolicy(.regular)
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
