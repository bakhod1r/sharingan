import SwiftUI
import AppKit
import BlinkCore

// MARK: - Global mouse position (polled — works without extra permissions)

final class WallpaperMouseState: ObservableObject {
    @Published var location: CGPoint?
    @Published var lastMoved = Date.distantPast
}

struct WallpaperMouseTracker: NSViewRepresentable {
    let state: WallpaperMouseState

    func makeNSView(context: Context) -> WallpaperTrackerNSView {
        let view = WallpaperTrackerNSView()
        view.state = state
        return view
    }

    func updateNSView(_ nsView: WallpaperTrackerNSView, context: Context) {}
}

final class WallpaperTrackerNSView: NSView {
    weak var state: WallpaperMouseState?
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

// MARK: - Wallpaper scene: two big eyes that follow the cursor

struct WallpaperEyesView: View {
    var style: SharinganStyle = .classic
    @StateObject private var mouse = WallpaperMouseState()
    @State private var spinAngle: Double = 0
    @State private var spinning = false
    private let ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let eyeH = min(w * 0.13, h * 0.24)
            let leftC = CGPoint(x: w * 0.32, y: h * 0.52)
            let rightC = CGPoint(x: w * 0.68, y: h * 0.52)

            ZStack {
                // dark gray backdrop with a soft black "face" shadow low-center
                Color(red: 0.075, green: 0.082, blue: 0.088)
                Ellipse()
                    .fill(Color.black.opacity(0.68))
                    .frame(width: w * 0.85, height: h * 0.55)
                    .blur(radius: 60)
                    .position(x: w / 2, y: h * 0.68)

                MoveEyeView(gaze: gaze(from: leftC), spin: spinAngle, size: eyeH, style: style)
                    .position(leftC)
                MoveEyeView(gaze: gaze(from: rightC), spin: spinAngle, size: eyeH, mirrored: true, style: style)
                    .position(rightC)

                WallpaperMouseTracker(state: mouse)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
        .onReceive(ticker) { _ in
            let idle = Date().timeIntervalSince(mouse.lastMoved) > 1.2
            if idle && !spinning {
                spinning = true
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    spinAngle += 360
                }
            } else if !idle && spinning {
                spinning = false
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    spinAngle = spinAngle.truncatingRemainder(dividingBy: 360)
                }
            }
        }
    }

    private func gaze(from center: CGPoint) -> GazeDirection {
        guard let m = mouse.location else { return .center }
        let reach: CGFloat = 500
        return GazeDirection(
            dx: Double((m.x - center.x) / reach),
            dy: Double((m.y - center.y) / reach)
        )
    }
}

// MARK: - Manager

/// Puts the MoveEyes scene on the desktop as a live wallpaper: one borderless
/// window per screen at desktop level (under the icons), on every Space,
/// transparent to mouse clicks.
@MainActor
final class WallpaperWindowManager {
    static let shared = WallpaperWindowManager()
    private init() {}

    private var windows: [NSWindow] = []
    private var currentStyle: SharinganStyle = .classic

    var isActive: Bool { !windows.isEmpty }

    func setEnabled(_ enabled: Bool, style: SharinganStyle = .classic) {
        if enabled, isActive, style != currentStyle {
            hide()
        }
        currentStyle = style
        enabled ? show() : hide()
    }

    private func show() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isMovable = false
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WallpaperEyesView(style: currentStyle))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    private func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}
