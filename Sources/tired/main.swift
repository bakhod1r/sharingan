import Foundation
import BlinkCore

/// `tired` — Blink CLI.
///
/// Foydalanish:
///   tired start 25         # 25-daq focus boshlash
///   tired start 5pm        # 5pm gacha timer
///   tired pause
///   tired resume
///   tired skip
///   tired reset
///   tired add 5m
///   tired remove 10m
///   tired set 2h 30m
///   tired status           # joriy holatni chiqaradi
///   tired task add ertaga 15:00 p1 #ish hisobot yozish
///   tired task list        # ochiq tasklar (raqamlangan)
///   tired task done 2
@main
struct TiredCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else {
            printUsage()
            exit(0)
        }

        let cmd = args[0].lowercased()
        switch cmd {
        case "status":
            printStatus()
        case "start":
            let payload = args.count >= 2 ? args[1...].joined(separator: " ") : ""
            CLIBridge.postCommand(CLIBridge.darwinCommandStart, payload: payload)
            print("→ start \(payload.isEmpty ? "(default)" : payload)")
        case "pause":
            CLIBridge.postCommand(CLIBridge.darwinCommandPause)
            print("→ pause")
        case "resume":
            CLIBridge.postCommand(CLIBridge.darwinCommandResume)
            print("→ resume")
        case "skip":
            CLIBridge.postCommand(CLIBridge.darwinCommandSkip)
            print("→ skip")
        case "stop", "reset":
            CLIBridge.postCommand(CLIBridge.darwinCommandStop)
            print("→ reset")
        case "add":
            let p = args.count >= 2 ? args[1...].joined(separator: " ") : "5m"
            CLIBridge.postCommand(CLIBridge.darwinCommandAdd, payload: p)
            print("→ add \(p)")
        case "rm", "remove":
            let p = args.count >= 2 ? args[1...].joined(separator: " ") : "5m"
            CLIBridge.postCommand(CLIBridge.darwinCommandRemove, payload: p)
            print("→ remove \(p)")
        case "set":
            let p = args.count >= 2 ? args[1...].joined(separator: " ") : ""
            CLIBridge.postCommand(CLIBridge.darwinCommandSetDuration, payload: p)
            print("→ set \(p)")
        case "task":
            handleTask(Array(args.dropFirst()))
        case "help", "--help", "-h":
            printUsage()
        case "version", "--version":
            print("tired 1.0")
        default:
            print("Unknown command: \(cmd)\n")
            printUsage()
            exit(2)
        }
    }

    static func handleTask(_ args: [String]) {
        guard let sub = args.first?.lowercased() else {
            printUsage()
            exit(2)
        }
        switch sub {
        case "add":
            let text = args.dropFirst().joined(separator: " ")
            guard !text.isEmpty else {
                print("Usage: tired task add <text>")
                exit(2)
            }
            CLIBridge.postCommand(CLIBridge.darwinCommandTaskAdd, payload: text)
            print("Added: \(text)")
        case "list":
            printTaskList()
        case "done", "start", "queue":
            guard args.count >= 2, let n = Int(args[1]) else {
                print("Usage: tired task \(sub) <n>   (n from 'tired task list')")
                exit(2)
            }
            guard let entries = CLIBridge.readTaskSnapshot() else {
                print("Sharingan is not running (no task snapshot).")
                return
            }
            guard let id = CLIBridge.resolveTaskIndex(n, in: entries) else {
                print("No task #\(n) — the list has \(entries.count) open task(s).")
                exit(2)
            }
            let title = entries[n - 1].title
            switch sub {
            case "done":
                CLIBridge.postCommand(CLIBridge.darwinCommandTaskDone, payload: id.uuidString)
                print("→ done: \(title)")
            case "start":
                CLIBridge.postCommand(CLIBridge.darwinCommandTaskStart, payload: id.uuidString)
                print("→ start: \(title)")
            default:
                CLIBridge.postCommand(CLIBridge.darwinCommandTaskQueue, payload: id.uuidString)
                print("→ queued: \(title)")
            }
        default:
            print("Unknown task command: \(sub)\n")
            printUsage()
            exit(2)
        }
    }

    static func printTaskList() {
        // The app rewrites the task snapshot on every task change; no snapshot
        // means it never ran (or the shared dir was wiped).
        guard let entries = CLIBridge.readTaskSnapshot() else {
            print("Sharingan is not running (no task snapshot).")
            return
        }
        guard !entries.isEmpty else {
            print("No open tasks.")
            return
        }
        let df = DateFormatter()
        df.dateFormat = "MMM d HH:mm"
        let width = String(entries.count).count
        for (i, e) in entries.enumerated() {
            var line = String(format: "%\(width)d. ", i + 1)
            if !e.priorityLabel.isEmpty { line += "[\(e.priorityLabel)] " }
            line += e.title
            if let due = e.due { line += "  (due \(df.string(from: due)))" }
            for tag in e.tags { line += " #\(tag)" }
            if let project = e.project { line += " @\(project)" }
            print(line)
        }
    }

    static func printUsage() {
        print("""
        tired — Blink CLI

        Usage:
          tired start [duration]    Start focus timer (default 25); accepts natural
                                     language: '5 min', '2h 30m', '5pm', '15'
          tired pause               Pause running timer
          tired resume              Resume paused timer
          tired skip                Skip to next phase
          tired reset               Stop & reset to focus start
          tired add [duration]      Add time (default 5m); e.g. 'tired add 10 min'
          tired remove [duration]   Remove time (default 5m); alias: rm
          tired set [duration]      Set custom duration; e.g. 'tired set 2h'
          tired status              Show current timer state
          tired task add <text>     Add a task; natural language: 'ertaga 15:00 p1 #ish hisobot'
          tired task list           List open tasks (numbered)
          tired task done <n>       Mark task n done
          tired task start <n>      Make task n the active task
          tired task queue <n>      Add task n to the focus queue
          tired version             Print version
          tired help                This message

        Examples:
          tired start 25            # 25-minute focus
          tired start 5pm          # until 5:00 PM
          tired add 5m             # +5 minutes
          tired status             # → Focus 12:34 ● 3 today, streak 7
          tired task add juma 9:00 p2 @blink release notes
          tired task done 2        # complete task #2 from 'task list'
        """)
    }

    static func printStatus() {
        guard let s = CLIBridge.readSnapshot() else {
            print("Sharingan is not running (no snapshot).")
            return
        }
        // The app writes the snapshot on state changes only; a running
        // countdown is reconstructed from its timestamp.
        var remaining = s.remainingSeconds
        if s.isRunning, let at = s.updatedAt {
            let age = Date().timeIntervalSince(at)
            // Countdown ran out long ago and nothing rewrote the snapshot —
            // the app crashed or quit; don't report a phantom session forever.
            if age > s.remainingSeconds + 120 {
                print("Sharingan is not running (stale snapshot).")
                return
            }
            remaining = max(0, s.remainingSeconds - age)
        }
        let symbol = s.isRunning ? "●" : "⏸"
        let m = Int(remaining) / 60
        let sec = Int(remaining) % 60
        let time = String(format: "%02d:%02d", m, sec)
        let pct = s.totalSeconds > 0
            ? Int((1 - remaining / s.totalSeconds) * 100)
            : 0
        print("Sharingan — \(s.phase.label) \(time) \(symbol)  \(pct)%")
        print("\(s.cyclesCompletedToday) completed today · streak \(s.streak) days")
    }
}