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
          tired version             Print version
          tired help                This message

        Examples:
          tired start 25            # 25-minute focus
          tired start 5pm          # until 5:00 PM
          tired add 5m             # +5 minutes
          tired status             # → Focus 12:34 ● 3 today, streak 7
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