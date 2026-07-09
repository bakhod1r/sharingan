import AppKit
import SwiftUI
import BlinkCore

// Explicit AppKit entry point. A SwiftUI `@main App` with MenuBarExtra proved
// unreliable to register at runtime under the CLI toolchain (no full Xcode), so
// the app bootstraps NSApplication directly and does its setup in AppDelegate.
// Headless icon render: `Blink --render-icon <path>` writes the 1024px app
// icon PNG and exits (used by Scripts/make-icon.sh, no GUI needed).
if let i = CommandLine.arguments.firstIndex(of: "--render-icon"),
   i + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated { IconRenderer.renderAppIcon(to: out) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
