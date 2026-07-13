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
        // The style is applied to the settings *value*, and the timer is built
        // from it. Never `timer.settings.breakBackgroundStyle = style`:
        // `PomodoroTimer.settings` persists to `UserDefaults` in `didSet`, so
        // photographing a preview would rewrite the user's real break
        // background. `didSet` does not run for an assignment inside `init`,
        // which is the whole reason `PomodoroTimer(settings:)` exists.
        var settings = PomodoroTimer.savedSettings()
        if i + 2 < CommandLine.arguments.count,
           let style = BreakBackgroundStyle(rawValue: CommandLine.arguments[i + 2]) {
            settings.breakBackgroundStyle = style
        }
        let timer = PomodoroTimer(settings: settings)
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
// `Sharingan --render-site-assets <outdir>` writes per-style iris PNGs
// (transparent, for the animated carousel) and real UI views seeded with sample
// tasks. The seeding is safe: the flag itself is what makes `TaskStore.shared`
// resolve to a throwaway SQLite under the temp dir (`HeadlessRender`), so the
// user's real database is never opened. The `HOME=` override this used to rely
// on never worked — `FileManager.urls(for:in:)` does not read `$HOME`.
// The flag is parsed by `HeadlessRender` and not here, because the same call is
// what redirected `TaskStore.shared` to a throwaway database before this line
// ran. Two copies of the rule could disagree, and the disagreement that matters
// is a process that redirected its store and then went on to run as the app.
if let outDir = HeadlessRender.outputDirectory(for: "--render-site-assets") {
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

        // 2) Seed sample tasks (isolated store — see the note above).
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
        // (The focus queue is *read* here, never written: `NotchTaskRows.rows`
        // only keeps queued ids that resolve to a task in the store, and this
        // render's store is the throwaway — so the user's queued ids name nothing
        // and simply do not appear. Nothing has to be cleared, and clearing it
        // would empty the user's real, planned queue: `FocusQueue` persists.)
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
// Same rule, same place — see the site-assets block above.
if let outDir = HeadlessRender.outputDirectory(for: "--render-dev-preview") {
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

        /// `ImageRenderer` cannot photograph a `ScrollView` — it rasterizes the
        /// container and none of its content (see the Today-panel note above).
        /// Every Settings page is a `ScrollView`, so host it in a real (offscreen,
        /// never fronted) window and cache its display instead. A hosted view also
        /// runs `onAppear`, which is where the Settings page asks whether this Mac
        /// has a notch.
        @MainActor func writeHosted(_ view: some View, to path: String, size: NSSize) {
            let host = NSHostingView(rootView: view.frame(width: size.width,
                                                          height: size.height))
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            // A turn of the run loop, so `onAppear` has fired before the shot.
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: path))
        }

        // Sample tasks for the shots. `TaskStore.shared` persists — but not
        // here: the process was launched with a render flag, so `HeadlessRender`
        // has already pointed the shared store at a throwaway SQLite under the
        // temp dir, and the user's real database in Application Support is not
        // opened at all. (It was, once, and every render of these previews left
        // a copy of both tasks in the user's list.)
        let store = TaskStore.shared
        store.add(title: "Ship landing page v1", category: "Work", tags: ["launch"],
                  dueDate: Date(), estimatedPomodoros: 3, project: "Sharingan", priority: .high)
        store.add(title: "Review pull request #42", category: "Work",
                  dueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                  priority: .medium)
        var big = store.tasks[0]
        big.pomodoroKind = .big
        big.pomodorosDone = 2
        big.subtasks = [Subtask(title: "Write the hero copy", isDone: true,
                                pomodoroKind: .small),
                        Subtask(title: "Verify Lighthouse 100")]
        store.update(big)
        // Two more due *today*, so the notch's task list (which draws today's
        // open tasks) photographs all three shapes a row can take: an estimate to
        // fill (the ring), pomodoros with no estimate (a 🍅 count), and neither
        // (no badge at all). The rows are pinned to one height, and the shot is
        // where that is checked.
        store.add(title: "Draft the release notes", category: "Work", dueDate: Date())
        store.add(title: "Answer support mail", category: "Personal", dueDate: Date())
        var counted = store.tasks.first { $0.title == "Draft the release notes" }!
        counted.pomodorosDone = 4
        store.update(counted)

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
        // The Timer page, Advanced accordion down: the notch section, and on a
        // Mac with no camera housing its disabled state — the one part of the
        // HUD that is visible without a notch, so the one part that can be
        // reviewed on any machine.
        //
        // Hosted, not `ImageRenderer`-ed: the renderer does not rasterize a
        // `ScrollView`'s content (it comes out an empty rectangle), and every
        // Settings page is one. A real hosting view in a real window also runs
        // `onAppear`, which is where the page asks whether this Mac has a notch.
        writeHosted(SettingsView(timer: timer, settings: .constant(timer.settings),
                                 initialCategory: .timer, initialAdvancedExpanded: true)
                        .background(Color(white: 0.12))
                        .environment(\.colorScheme, .dark),
                    to: "\(outDir)/settings-timer.png",
                    size: NSSize(width: 640, height: 2000))
        // The notch island, in each shape it takes. This machine has no camera
        // housing, so the HUD never instantiates at runtime here — but the view
        // is driven entirely by `NotchHUDModel`, so handing it 14"-MacBook-Pro
        // metrics photographs exactly what a notched Mac would draw. The grey
        // plate underneath stands in for the menu bar the island sits over.
        let notchModel = NotchHUDModel()
        notchModel.metrics = NotchScreenMetrics(screenWidth: 1512, menuBarHeight: 37,
                                                notchWidth: 200, notchHeight: 37)
        notchModel.progress = 0.62
        notchModel.remaining = 14 * 60 + 13
        notchModel.phase = .focus
        store.activeTaskID = store.tasks[0].id
        // What `NotchWindowManager` does at runtime, which the preview has no
        // manager to do for it: tell the island how many task rows there really
        // are. Without it the model carries no count, the geometry falls back to
        // the row *cap*, and the preview would photograph the very strip of dead
        // black this change removes.
        notchModel.config.taskCount = NotchWindowManager
            .taskRows(limit: notchModel.config.clampedTaskRows).count

        @MainActor func writeIsland(_ name: String) {
            // The panel is the window's size (pinned to the row cap); the island
            // inside it is sized to the rows that exist. The grey shows through
            // wherever the island is not — which is the whole thing being checked.
            let panel = NotchGeometry.panelSize(notchModel.metrics, config: notchModel.config)
            write(NotchHUDView(model: notchModel, timer: timer)
                    .environmentObject(timer)
                    .frame(width: panel.width, height: panel.height)
                    .background(Color(white: 0.32))
                    .environment(\.colorScheme, .dark),
                  to: "\(outDir)/\(name).png")
        }

        for (name, mutate) in [
            ("notch-idle", { (s: inout NotchHUDState) in }),
            ("notch-live", { s in s.engaged = true }),
            ("notch-activity", { s in s.engaged = true; s.activity = .breakStarted }),
            ("notch-expanded", { s in s.engaged = true; s.hovering = true }),
        ] as [(String, (inout NotchHUDState) -> Void)] {
            var state = NotchHUDState()
            mutate(&state)
            notchModel.state = state
            writeIsland(name)
        }

        // The two ends of the island's height, which is the only way to *see*
        // that it follows the task list: a full list against an empty one. The
        // store is the render's throwaway (see above), so seeding and completing
        // tasks here costs the user nothing.
        var open = NotchHUDState()
        open.engaged = true
        open.hovering = true
        notchModel.state = open

        for i in 1...4 {
            store.add(title: "Today's task \(i)", category: "Work", dueDate: Date(),
                      priority: .medium)
        }
        notchModel.config.taskCount = NotchWindowManager
            .taskRows(limit: notchModel.config.clampedTaskRows).count   // 5, the cap
        writeIsland("notch-expanded-full")

        for task in store.tasks where !task.isDone { store.toggleDone(task.id) }
        notchModel.config.taskCount = NotchWindowManager
            .taskRows(limit: notchModel.config.clampedTaskRows).count   // 0
        writeIsland("notch-expanded-empty")

        print("dev previews rendered to \(outDir)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
