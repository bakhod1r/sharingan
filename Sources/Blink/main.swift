import AppKit
import SwiftUI
import BlinkCore

print("STEP 1: main started")

let app = NSApplication.shared
print("STEP 2: NSApplication.shared")

let delegate = AppDelegate()
app.delegate = delegate
print("STEP 3: delegate created")

app.setActivationPolicy(.accessory)
print("STEP 4: activation policy set")

app.run()
print("STEP 5: app.run() returned (should not happen)")
