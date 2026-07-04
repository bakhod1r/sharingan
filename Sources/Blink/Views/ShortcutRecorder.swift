import SwiftUI
import Carbon.HIToolbox
import BlinkCore

/// A row that shows a shortcut's current combo and lets the user re-record it.
struct ShortcutRecorderRow: View {
    let title: String
    let binding: ShortcutBinding
    let isCustom: Bool
    let onCapture: (ShortcutBinding) -> Void
    let onReset: () -> Void

    @State private var recording = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(.body, design: .rounded))
            Spacer()
            Button(recording ? "Press keys…" : binding.displayString) {
                recording.toggle()
            }
            .buttonStyle(.bordered)
            .frame(minWidth: 96)
            .tint(recording ? .accentColor : nil)

            Button {
                recording = false
                onReset()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Reset to default")
            .disabled(!isCustom)
            .opacity(isCustom ? 1 : 0.3)
        }
        .background(
            KeyCaptureView(recording: $recording,
                           onCombo: { combo in
                               recording = false
                               onCapture(combo)
                           },
                           onCancel: { recording = false })
        )
    }
}

/// Invisible AppKit bridge that installs a local key-down monitor while recording.
private struct KeyCaptureView: NSViewRepresentable {
    @Binding var recording: Bool
    let onCombo: (ShortcutBinding) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView { context.coordinator.view }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCombo = onCombo
        context.coordinator.onCancel = onCancel
        context.coordinator.setRecording(recording)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        let view = NSView()
        var onCombo: ((ShortcutBinding) -> Void)?
        var onCancel: (() -> Void)?
        private var monitor: Any?

        func setRecording(_ on: Bool) {
            if on, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handle(event)
                    return nil // swallow the key while recording
                }
            } else if !on, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        private func handle(_ event: NSEvent) {
            // Escape cancels recording without changing the binding.
            if event.keyCode == UInt16(kVK_Escape) {
                onCancel?()
                return
            }
            let mods = Self.carbonModifiers(event.modifierFlags)
            // Require at least one modifier so we don't hijack plain typing globally.
            guard mods != 0 else { return }
            onCombo?(ShortcutBinding(keyCode: UInt32(event.keyCode), modifiers: mods))
        }

        static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
            var m: UInt32 = 0
            if flags.contains(.control) { m |= UInt32(controlKey) }
            if flags.contains(.option)  { m |= UInt32(optionKey) }
            if flags.contains(.shift)   { m |= UInt32(shiftKey) }
            if flags.contains(.command) { m |= UInt32(cmdKey) }
            return m
        }

        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }
    }
}
