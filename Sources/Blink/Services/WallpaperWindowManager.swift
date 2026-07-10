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

/// Everything the wallpaper scene needs from user settings.
struct WallpaperConfig: Equatable {
    var style: SharinganStyle = .classic
    var spinTrigger: WallpaperSpinTrigger = .idle
    var spinDuration: Double = 1.6
    var idleDelay: Double = 1.2
    /// Seconds of mouse stillness before the eyes drift fully shut.
    var dozeSeconds: Double = 60

    init(style: SharinganStyle = .classic,
         spinTrigger: WallpaperSpinTrigger = .idle,
         spinDuration: Double = 1.6,
         idleDelay: Double = 1.2,
         dozeSeconds: Double = 60) {
        self.style = style
        self.spinTrigger = spinTrigger
        self.spinDuration = spinDuration
        self.idleDelay = idleDelay
        self.dozeSeconds = dozeSeconds
    }

    init(from settings: PomodoroSettings) {
        style = settings.sharinganStyle
        spinTrigger = settings.wallpaperSpinTrigger
        spinDuration = settings.wallpaperSpinDuration
        idleDelay = settings.wallpaperIdleDelay
        dozeSeconds = settings.wallpaperDozeSeconds
    }
}

struct WallpaperEyesView: View {
    var config = WallpaperConfig()
    /// Headless previews can't host the AppKit tracker — disable it there.
    var trackingEnabled = true

    @StateObject private var mouse = WallpaperMouseState()
    @State private var spinAngle: Double = 0
    @State private var spinning = false
    @State private var clickMonitor: Any?
    /// Eyelids (per eye — sometimes one winks): occasional blinks while the
    /// mouse is active, and a slow doze (lids fully closed) once it has been
    /// still for a while. Everything animates via the shape's animatableData
    /// off the existing ticker — no continuous render loop needed.
    @State private var leftLid: CGFloat = 1
    @State private var rightLid: CGFloat = 1
    @State private var dozing = false
    @State private var nextBlink = Date().addingTimeInterval(.random(in: 2...5))
    /// Winks alternate sides: right, then left, then right…
    @State private var winkRightNext = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Seconds of stillness before the eyes start winking at the user.
    private let winkIdleDelay: TimeInterval = 6
    /// Seconds of stillness before the eyes drift fully shut (user setting).
    private var dozeDelay: TimeInterval { config.dozeSeconds }
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

                MoveEyeView(gaze: gaze(from: leftC), spin: spinAngle, size: eyeH,
                            style: config.style, openness: leftLid)
                    .position(leftC)
                MoveEyeView(gaze: gaze(from: rightC), spin: spinAngle, size: eyeH,
                            mirrored: true, style: config.style, openness: rightLid)
                    .position(rightC)

                if trackingEnabled {
                    WallpaperMouseTracker(state: mouse)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
        }
        .onReceive(ticker) { _ in
            updateEyelids()
            guard config.spinTrigger.spinsOnIdle else { return }
            let idle = Date().timeIntervalSince(mouse.lastMoved) > config.idleDelay
            if idle && !spinning {
                spinning = true
                withAnimation(.linear(duration: config.spinDuration).repeatForever(autoreverses: false)) {
                    spinAngle += 360
                }
            } else if !idle && spinning {
                stopContinuousSpin()
            }
        }
        .onAppear {
            guard trackingEnabled, config.spinTrigger.spinsOnClick else { return }
            // The wallpaper window ignores mouse events, so listen globally.
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
                clickBurst()
            }
        }
        .onDisappear {
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
            }
            clickMonitor = nil
        }
    }

    /// Eyelid state machine, driven by how long the mouse has been still:
    /// active → natural blinks (with an occasional wink); still for a few
    /// seconds → playful winks alternating right/left; still for a long
    /// while → the lids drift fully shut, snapping open on the next move.
    private func updateEyelids() {
        let stillFor = Date().timeIntervalSince(mouse.lastMoved)
        if stillFor > dozeDelay, !dozing {
            dozing = true
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.9)) {
                leftLid = 0
                rightLid = 0
            }
        } else if stillFor <= dozeDelay, dozing {
            dozing = false
            nextBlink = Date().addingTimeInterval(.random(in: 2...5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                leftLid = 1
                rightLid = 1
            }
        }
        guard !reduceMotion, !dozing, Date() >= nextBlink else { return }
        if stillFor > winkIdleDelay {
            // Idle: wink at the user — right, then left, then right…
            wink(hold: 0.45)
            nextBlink = Date().addingTimeInterval(.random(in: 2.5...4))
        } else {
            blinkOnce()
        }
    }

    /// A quick natural blink — or, now and then, an alternating-side wink.
    private func blinkOnce() {
        nextBlink = Date().addingTimeInterval(.random(in: 3.5...8))
        if Double.random(in: 0...1) < 0.3 {
            wink(hold: 0.4)
        } else {
            withAnimation(.easeIn(duration: 0.09)) {
                leftLid = 0
                rightLid = 0
            }
            reopen(after: 0.11)
        }
    }

    /// Close one eye (sides alternate), hold it, reopen.
    private func wink(hold: TimeInterval) {
        let right = winkRightNext
        winkRightNext.toggle()
        withAnimation(.easeIn(duration: 0.09)) {
            if right { rightLid = 0 } else { leftLid = 0 }
        }
        reopen(after: hold)
    }

    private func reopen(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.16)) {
                if !dozing {
                    leftLid = 1
                    rightLid = 1
                }
            }
        }
    }

    /// One accelerate→decelerate whirl (two full turns) per click.
    private func clickBurst() {
        if spinning { stopContinuousSpin() }
        withAnimation(.easeInOut(duration: max(0.6, config.spinDuration))) {
            spinAngle += 720
        }
    }

    private func stopContinuousSpin() {
        spinning = false
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            spinAngle = spinAngle.truncatingRemainder(dividingBy: 360)
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
    private var currentConfig = WallpaperConfig()

    var isActive: Bool { !windows.isEmpty }

    func setEnabled(_ enabled: Bool, config: WallpaperConfig = WallpaperConfig()) {
        if enabled, isActive, config != currentConfig {
            hide()
        }
        currentConfig = config
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
            window.contentView = NSHostingView(rootView: WallpaperEyesView(config: currentConfig))
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
