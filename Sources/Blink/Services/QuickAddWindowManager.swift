import AppKit
import SwiftUI
import BlinkCore

/// A small, centered "capture a task" panel summoned by a global hotkey. Type a
/// title, press Return to add it to the task store, Esc to dismiss.
@MainActor
final class QuickAddWindowManager: QuickAddController {
    static let shared = QuickAddWindowManager()
    private var panel: NSPanel?

    func showQuickAdd() {
        // Already open → just refocus it.
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let size = NSSize(width: 460, height: 118)
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true

        let view = QuickAddTaskView(
            onSubmit: { [weak self] title in
                TaskStore.shared.add(title: title)
                self?.hideQuickAdd()
            },
            onCancel: { [weak self] in self?.hideQuickAdd() }
        )
        panel.contentView = NSHostingView(rootView: view)

        // Center on the screen with the mouse (or the main screen).
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let x = frame.midX - size.width / 2
            let y = frame.midY + frame.height * 0.12
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
        }
        WindowAnimator.present(panel)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    func hideQuickAdd() {
        guard let panel else { return }
        self.panel = nil
        WindowAnimator.dismiss(panel) {
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }
}

/// Borderless panels can't become key by default — needed so the text field
/// accepts keystrokes.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct QuickAddTaskView: View {
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                TextField("Add a task…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit(submit)
            }
            HStack(spacing: 8) {
                Text("Return")
                    .keycap()
                Text("to add")
                    .quickHint()
                Spacer()
                Text("Esc")
                    .keycap()
                Text("to close")
                    .quickHint()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .onExitCommand(perform: onCancel)
        .onAppear { focused = true }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { onCancel(); return }
        onSubmit(trimmed)
    }
}

private extension Text {
    func keycap() -> some View {
        self.font(.system(.caption2, design: .rounded).weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.white.opacity(0.9))
    }
    func quickHint() -> some View {
        self.font(.system(.caption2, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
    }
}
