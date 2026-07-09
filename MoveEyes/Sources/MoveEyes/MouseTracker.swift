import AppKit
import SwiftUI

/// Global sichqoncha pozitsiyasini oyna-kontent (top-left origin) koordinatalarida
/// har kadrda o'qib turadi — oynadan tashqarida ham ishlaydi.
final class MouseState: ObservableObject {
    @Published var location: CGPoint?
    @Published var lastMoved = Date.distantPast
}

struct MouseTrackerView: NSViewRepresentable {
    let state: MouseState

    func makeNSView(context: Context) -> TrackerNSView {
        let view = TrackerNSView()
        view.state = state
        return view
    }

    func updateNSView(_ nsView: TrackerNSView, context: Context) {}
}

final class TrackerNSView: NSView {
    weak var state: MouseState?
    private var timer: Timer?

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        guard window != nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let window, let state else { return }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = convert(inWindow, from: nil)
        if state.location != local {
            state.location = local
            state.lastMoved = Date()
        }
    }

    deinit {
        timer?.invalidate()
    }
}
