import AppKit
import SwiftUI
import BlinkCore

// Explicit AppKit entry point. A SwiftUI `@main App` with MenuBarExtra proved
// unreliable to register at runtime under the CLI toolchain (no full Xcode), so
// the app bootstraps NSApplication directly and does its setup in AppDelegate.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
