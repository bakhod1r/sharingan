import AppKit
import SwiftUI
import SharinganCore

// Explicit AppKit entry point. A SwiftUI `@main App` with MenuBarExtra proved
// unreliable to register at runtime under the CLI toolchain (no full Xcode), so
// the app bootstraps NSApplication directly and does its setup in AppDelegate.
// Headless icon render: `Sharingan --render-icon <path>` writes the 1024px app
// icon PNG and exits (used by Scripts/make-icon.sh, no GUI needed).
if let i = CommandLine.arguments.firstIndex(of: "--render-icon"),
   i + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated { IconRenderer.renderAppIcon(to: out) }
    exit(0)
}

// Headless preview of the 18pt menu-bar icon, upscaled for inspection:
// `Sharingan --render-menubar-icon <path>` (debug utility).
if let i = CommandLine.arguments.firstIndex(of: "--render-menubar-icon"),
   i + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated {
        if let img = MenuBarController.menuBarIcon(progress: 0.4, phase: .focus),
           let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 144, pixelsHigh: 144,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            img.draw(in: NSRect(x: 0, y: 0, width: 144, height: 144))
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: out))
        }
    }
    exit(0)
}

// Headless preview of all vector Sharingan iris styles (debug utility):
// `Sharingan --render-iris-grid <path>`.
if let i = CommandLine.arguments.firstIndex(of: "--render-iris-grid"),
   i + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated {
        let grid = LazyVGrid(columns: Array(repeating: GridItem(.fixed(150)), count: 5), spacing: 18) {
            ForEach(SharinganStyle.allCases) { style in
                VStack(spacing: 8) {
                    MoveIrisView(diameter: 110, style: style)
                    Text(style.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(24)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        let renderer = ImageRenderer(content: grid)
        renderer.scale = 2
        if let cg = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: out))
        }
    }
    exit(0)
}

// Headless preview of the wallpaper scene + break-screen eye pair:
// `Sharingan --render-eyes-preview <path>`.
if let i = CommandLine.arguments.firstIndex(of: "--render-eyes-preview"),
   i + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated {
        let preview = VStack(spacing: 0) {
            WallpaperEyesView(trackingEnabled: false)
                .frame(width: 1440, height: 620)
            ZStack {
                Color.black
                MoveEyePair(direction: "center", gaze: .center, eyeSize: 130)
            }
            .frame(width: 1440, height: 380)
        }
        let renderer = ImageRenderer(content: preview)
        renderer.scale = 1
        if let cg = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: out))
        }
    }
    exit(0)
}

// Headless frame-sequence renderer for the evolution animations:
// `Sharingan --render-anim-previews <outdir>` writes PNG frames per scenario
// (25 fps) into <outdir>/<scenario>/f%03d.png; assemble GIFs with ffmpeg.
// Drives the SAME PatternEvolution math the break screen runs, so what you
// see in the GIFs is exactly what ships.
if let i = CommandLine.arguments.firstIndex(of: "--render-anim-previews"),
   i + 1 < CommandLine.arguments.count {
    let outDir = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated {
        let fps = 25.0

        /// One eye pair frame with explicit animation inputs.
        struct PairFrame: View {
            var evolution: PatternEvolution
            var t: Double
            var spin: Double
            var lid: Double
            var eyeSize: CGFloat = 150

            var body: some View {
                let pf = evolution.frame(at: t)
                let openness = CGFloat(lid * pf.endFade)
                ZStack {
                    Color(red: 0.067, green: 0.075, blue: 0.078)
                    HStack(spacing: eyeSize * 0.42) {
                        MoveEyeView(gaze: .center, spin: spin, size: eyeSize,
                                    style: pf.left, openness: openness,
                                    emergence: pf.emergence, tomoeStage: pf.tomoeStage)
                        MoveEyeView(gaze: .center, spin: spin, size: eyeSize,
                                    mirrored: true, style: pf.right, openness: openness,
                                    emergence: pf.emergence, tomoeStage: pf.tomoeStage)
                    }
                }
                .frame(width: 820, height: 300)
            }
        }

        /// Scenario: duration + per-time animation inputs.
        struct Scenario {
            var name: String
            var seconds: Double
            var frame: (Double) -> (PatternEvolution, spin: Double, lid: Double)
        }

        // Step boundaries every stepGap seconds reproduce what the exercise
        // validator does when it advances a step.
        func montage(counts: [Int], stepGap: Double, transition: PatternTransitionSpeed = .normal)
            -> (Double) -> (PatternEvolution, spin: Double, lid: Double) {
            { t in
                var count = 0
                var phaseStart = 0.0
                var spin = 0.0
                for step in counts where t >= Double(step) * stepGap {
                    count = step
                    phaseStart = Double(step) * stepGap
                }
                for step in [0] + counts {
                    let start = step == 0 ? 1.1 : Double(step) * stepGap
                    spin += PatternEvolution.activationSpin(at: t, since: start)
                }
                let pe = PatternEvolution(transition: transition, appearStart: 0,
                                          phaseStart: phaseStart, evolutionCount: count)
                let lid = PatternEvolution.awakenOpenness(at: t, since: 0)
                return (pe, spin, lid)
            }
        }

        let scenarios: [Scenario] = [
            // 1. Break start: lids awaken, one tomoe whirls open.
            Scenario(name: "01-opening", seconds: 3.2, frame: montage(counts: [], stepGap: 0)),
            // 2. Tomoe awakening: 1 → 2 (spin + the new tomoe grows in).
            Scenario(name: "02-tomoe-1-to-2", seconds: 2.6) { t in
                let pe = PatternEvolution(transition: .normal, appearStart: -10,
                                          phaseStart: 0.5, evolutionCount: 1)
                return (pe, PatternEvolution.activationSpin(at: t, since: 0.5), 1)
            },
            // 3. Tomoe awakening: 2 → 3.
            Scenario(name: "03-tomoe-2-to-3", seconds: 2.6) { t in
                let pe = PatternEvolution(transition: .normal, appearStart: -10,
                                          phaseStart: 0.5, evolutionCount: 2)
                return (pe, PatternEvolution.activationSpin(at: t, since: 0.5), 1)
            },
            // 4. Mangekyō awakening: 3 tomoe collapse, the pinwheel whirls out.
            Scenario(name: "04-mangekyo-awakening", seconds: 3.0) { t in
                let pe = PatternEvolution(transition: .normal, appearStart: -10,
                                          phaseStart: 0.5, evolutionCount: 3)
                return (pe, PatternEvolution.activationSpin(at: t, since: 0.5), 1)
            },
            // 5. Mangekyō → Eternal (cross-family, deeper pattern).
            Scenario(name: "05-mangekyo-eternal", seconds: 3.0) { t in
                let pe = PatternEvolution(transition: .normal, appearStart: -10,
                                          phaseStart: 0.5, evolutionCount: 4)
                return (pe, PatternEvolution.activationSpin(at: t, since: 0.5), 1)
            },
            // 6. Break end: pattern folds into the pupil, lids close.
            Scenario(name: "06-closing", seconds: 2.4) { t in
                let pe = PatternEvolution(transition: .normal, appearStart: -10,
                                          phaseStart: -8, evolutionCount: 2,
                                          end: 1.9)
                return (pe, 0, 1)
            },
            // 7. Full awakening montage: 1 → 2 → 3 → Mangekyō → Eternal.
            Scenario(name: "07-full-evolution", seconds: 11.0,
                     frame: montage(counts: [1, 2, 3, 4], stepGap: 2.2)),
            // 8. Wallpaper: continuous spin ("Always"), perfect loop.
            Scenario(name: "08-wallpaper-spin", seconds: 1.6) { t in
                let pe = PatternEvolution(transition: .off)
                return (pe, t / 1.6 * 360, 1)
            },
        ]

        let fm = FileManager.default
        for sc in scenarios {
            let dir = "\(outDir)/\(sc.name)"
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let n = Int(sc.seconds * fps)
            for f in 0..<n {
                let t = Double(f) / fps
                let (pe, spin, lid) = sc.frame(t)
                let renderer = ImageRenderer(content: PairFrame(evolution: pe, t: t,
                                                                spin: spin, lid: lid))
                renderer.scale = 1
                if let cg = renderer.cgImage {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: String(format: "%@/f%03d.png", dir, f)))
                }
            }
            print("rendered \(sc.name): \(n) frames")
        }
    }
    exit(0)
}

// Headless preview of the full break screen (debug utility):
// `Sharingan --render-break-preview <path> [styleRawValue]`.
if let i = CommandLine.arguments.firstIndex(of: "--render-break-preview"),
   i + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated {
        let timer = PomodoroTimer()
        if i + 2 < CommandLine.arguments.count,
           let style = BreakBackgroundStyle(rawValue: CommandLine.arguments[i + 2]) {
            timer.settings.breakBackgroundStyle = style
        }
        let preview = BreakView(timer: timer, onTapSkip: {}, forceExit: true)
            .frame(width: 1440, height: 900)
        let renderer = ImageRenderer(content: preview)
        renderer.scale = 1
        if let cg = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: out))
        }
    }
    exit(0)
}

// Headless preview of iris gaze placement and eyelid morph (debug utility):
// `Sharingan --render-gaze-grid <path>`.
if let i = CommandLine.arguments.firstIndex(of: "--render-gaze-grid"),
   i + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated {
        let gazes: [(String, GazeDirection)] = [
            ("center", .center), ("left", .left), ("right", .right),
            ("up", .up), ("down", .down), ("up left", .upLeft),
            ("down right", .downRight),
        ]
        let lids: [CGFloat] = [1, 0.66, 0.33, 0]
        let grid = VStack(alignment: .leading, spacing: 14) {
            ForEach(gazes, id: \.0) { name, gaze in
                HStack(spacing: 18) {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 80, alignment: .trailing)
                    MoveEyeView(gaze: gaze, size: 72)
                    MoveEyeView(gaze: gaze, size: 72, mirrored: true)
                }
            }
            HStack(spacing: 18) {
                Text("blink")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 80, alignment: .trailing)
                ForEach(lids, id: \.self) { lid in
                    MoveEyeView(gaze: .center, size: 72, openness: lid)
                }
            }
        }
        .padding(24)
        .background(Color.black)
        let renderer = ImageRenderer(content: grid)
        renderer.scale = 2
        if let cg = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: out))
        }
    }
    exit(0)
}

// Headless renders for the marketing site (debug utility):
// `HOME=<throwaway> Sharingan --render-site-assets <outdir>` writes per-style
// iris PNGs (transparent, for the animated carousel) and real UI views seeded
// with sample tasks. Run with an overridden HOME so TaskStore.shared writes
// its SQLite into the throwaway, never the real user database.
if let i = CommandLine.arguments.firstIndex(of: "--render-site-assets"),
   i + 1 < CommandLine.arguments.count {
    let outDir = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated {
        let fm = FileManager.default
        for sub in ["iris", "anim-timer", "anim-tasks"] {
            try? fm.createDirectory(atPath: "\(outDir)/\(sub)", withIntermediateDirectories: true)
        }

        @MainActor func write(_ view: some View, to path: String, scale: CGFloat = 2) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path))
            }
        }

        // 1) Transparent iris per style — the site spins these with CSS.
        for style in SharinganStyle.allCases {
            write(MoveIrisView(diameter: 220, style: style),
                  to: "\(outDir)/iris/\(style.rawValue).png")
        }

        // 2) Seed sample tasks (isolated store — see HOME note above).
        let store = TaskStore.shared
        store.add(title: "Ship landing page v1", category: "Work", tags: ["launch"],
                  dueDate: Date(), estimatedPomodoros: 3, project: "Sharingan", priority: .high)
        store.add(title: "Review pull request #42", category: "Work", tags: ["code"],
                  dueDate: Date(), estimatedPomodoros: 1, priority: .medium)
        store.add(title: "Outline the weekly report", category: "Study", tags: ["writing"],
                  dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                  priority: .low)
        store.add(title: "30-minute run", category: "Health", tags: ["habit"],
                  recurrence: .daily, priority: .medium)
        store.add(title: "Read 20 pages", category: "Personal", priority: .none)
        if let first = store.tasks.first {
            store.addSubtask(first.id, title: "Write the hero copy")
            store.addSubtask(first.id, title: "Verify Lighthouse 100")
            store.activeTaskID = first.id
        }
        // cfprefsd leaks the REAL user's defaults through the HOME override —
        // clear the bits that show up in renders (focus queue, stale actives).
        AppServices.focusQueue.clear()
        print("store:", store.tasks.map(\.title))
        print("active:", store.activeTask?.title ?? "nil")

        let timer = PomodoroTimer()

        // 3) Real UI views.
        AppRouter.shared.section = .timer
        write(MainWindowView(timer: timer)
                .frame(width: 1040, height: 720)
                .environment(\.colorScheme, .dark),
              to: "\(outDir)/main-timer.png")

        AppRouter.shared.section = .tasks
        write(MainWindowView(timer: timer)
                .frame(width: 1040, height: 720)
                .environment(\.colorScheme, .dark),
              to: "\(outDir)/main-tasks.png")

        write(FloatingTimerView(timer: timer)
                .frame(width: 232, height: 88)
                .environment(\.colorScheme, .dark),
              to: "\(outDir)/floating.png")

        write(TodayPanelView(timer: timer)
                .frame(width: 280)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.colorScheme, .dark),
              to: "\(outDir)/today.png")

        // 4) Frame sequences for the feature videos (assembled with ffmpeg).
        // Timer: a running focus session counting down.
        AppRouter.shared.section = .timer
        timer.startFocusSession()
        for f in 0..<32 {
            write(MainWindowView(timer: timer)
                    .frame(width: 1040, height: 720)
                    .environment(\.colorScheme, .dark),
                  to: String(format: "%@/anim-timer/f%03d.png", outDir, f), scale: 1)
            timer.removeTime(38)
        }
        timer.stop()

        // Tasks: the Today panel living — tasks get checked off, a new one
        // arrives through quick add. (MainWindowView's list is List-backed,
        // which ImageRenderer leaves empty — the Today panel is plain stacks.)
        for f in 0..<36 {
            if f == 10, store.tasks.count > 1 { store.toggleDone(store.tasks[1].id) }
            if f == 20 {
                store.add(title: "Reply to Alisher — pricing deck", category: "Work",
                          tags: ["email"], dueDate: Date(), priority: .medium)
            }
            if f == 28, let last = store.tasks.last(where: { !$0.isDone }) {
                store.toggleDone(last.id)
            }
            write(TodayPanelView(timer: timer)
                    .frame(width: 280)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.colorScheme, .dark),
                  to: String(format: "%@/anim-tasks/f%03d.png", outDir, f))
        }
        print("site assets rendered to \(outDir)")
    }
    exit(0)
}

// Headless dev previews: renders the menu-bar popover, the custom calendar and
// the task editor to PNGs so UI changes can be eyeballed without launching the
// app (same idea as --render-site-assets, but for development).
if let i = CommandLine.arguments.firstIndex(of: "--render-dev-preview"),
   i + 1 < CommandLine.arguments.count {
    let outDir = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated {
        try? FileManager.default.createDirectory(atPath: outDir,
                                                 withIntermediateDirectories: true)
        @MainActor func write(_ view: some View, to path: String, scale: CGFloat = 2) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path))
            }
        }

        let store = TaskStore.shared
        store.add(title: "Ship landing page v1", category: "Work", tags: ["launch"],
                  dueDate: Date(), estimatedPomodoros: 3, project: "Sharingan", priority: .high)
        store.add(title: "Review pull request #42", category: "Work",
                  dueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                  priority: .medium)
        var big = store.tasks[0]
        big.pomodoroKind = .big
        big.subtasks = [Subtask(title: "Write the hero copy", pomodoroKind: .small),
                        Subtask(title: "Verify Lighthouse 100")]
        store.update(big)

        let timer = PomodoroTimer()
        write(MenuBarView(timer: timer)
                .frame(width: 360, height: 700)
                .background(Color.black.opacity(0.85))
                .environment(\.colorScheme, .dark),
              to: "\(outDir)/menubar.png")
        write(BlinkCalendar(date: .constant(Date()))
                .padding(16)
                .background(Color.black.opacity(0.85))
                .environment(\.colorScheme, .dark),
              to: "\(outDir)/calendar.png")
        write(TaskEditorView(task: store.tasks[0], settings: timer.settings)
                .frame(width: 460, height: 640)
                .environment(\.colorScheme, .dark),
              to: "\(outDir)/editor.png")
        print("dev previews rendered to \(outDir)")
    }
    exit(0)
}

// Dev-only: `Sharingan --notch-simulate` drives the notch HUD on a machine that
// has no hardware notch, by pretending the menu-bar screen carries a 14" MacBook
// Pro cutout (200×37). The HUD otherwise renders ONLY on a display with a real
// notch — there is no synthetic pill — so without this flag the feature is
// invisible on notchless dev hardware. Gated on the launch argument alone: no UI
// toggle, no persisted setting, nothing a normal launch can flip.
if CommandLine.arguments.contains("--notch-simulate") {
    MainActor.assumeIsolated { NotchWindowManager.simulateNotch = true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
