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
