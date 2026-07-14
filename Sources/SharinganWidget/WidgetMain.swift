import WidgetKit
import SwiftUI

// The appex entry point. This target is deliberately OUTSIDE Package.swift:
// make-app.sh compiles these sources (plus the two WidgetSnapshot* files
// from SharinganCore) straight into the .appex binary with swiftc, the same
// hand-assembly philosophy as the rest of the bundle. Compiled with
// -parse-as-library, so @main hands control to WidgetKit's host loop.
@main
struct SharinganWidgetBundle: WidgetBundle {
    var body: some Widget {
        PomodoroWidget()
    }
}

struct PomodoroWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SharinganPomodoro",
                            provider: PomodoroProvider()) { entry in
            PomodoroWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Pomodoro")
        .description("Timer, active task and today's progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PomodoroEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct PomodoroProvider: TimelineProvider {
    func placeholder(in context: Context) -> PomodoroEntry {
        PomodoroEntry(date: Date(), snapshot: .sample())
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (PomodoroEntry) -> Void) {
        // The gallery preview should look alive even before the app has ever
        // written a snapshot; a real refresh shows the real state.
        let now = Date()
        let snap = WidgetSnapshotStore.read()?.normalized(now: now)
            ?? (context.isPreview ? .sample(now: now) : .empty(now: now))
        completion(PomodoroEntry(date: now, snapshot: snap))
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<PomodoroEntry>) -> Void) {
        let now = Date()
        let snap = (WidgetSnapshotStore.read() ?? .empty(now: now)).normalized(now: now)

        guard snap.isRunning, let end = snap.endDate, end > now else {
            // Paused/idle: the app pushes a reload on every change; the
            // midnight backstop only rolls a stale "today" count to 0.
            let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
            completion(Timeline(entries: [PomodoroEntry(date: now, snapshot: snap)],
                                policy: .after(midnight)))
            return
        }

        // Running: seconds tick via Text(timerInterval:) inside a single
        // entry; one entry per minute just re-fills the progress ring.
        // At the end the running app rewrites the snapshot anyway — the
        // final entry + .atEnd only cover an app that died mid-session.
        var entries: [PomodoroEntry] = []
        var t = now
        while t < end && entries.count < 121 {
            entries.append(PomodoroEntry(date: t, snapshot: snap))
            t += 60
        }
        entries.append(PomodoroEntry(date: end, snapshot: snap.idled()))
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
