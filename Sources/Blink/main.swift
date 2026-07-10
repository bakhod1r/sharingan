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

// Headless preview of all vector Sharingan iris styles (debug utility):
// `Blink --render-iris-grid <path>`.
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
// `Blink --render-eyes-preview <path>`.
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
// `Blink --render-anim-previews <outdir>` writes PNG frames per scenario
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
// `Blink --render-break-preview <path> [styleRawValue]`.
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
// `Blink --render-gaze-grid <path>`.
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
