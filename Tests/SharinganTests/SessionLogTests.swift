import Testing
import Foundation
@testable import SharinganCore

@Suite("Focus session log")
@MainActor
struct SessionLogTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("session-log-\(UUID().uuidString).json")
    }

    private func record(start: Date, minutes: Double, phase: PomodoroPhase = .focus,
                        completed: Bool = true) -> SessionRecord {
        SessionRecord(start: start, end: start.addingTimeInterval(minutes * 60),
                      phase: phase, completed: completed,
                      plannedSeconds: minutes * 60)
    }

    @Test func appendPersistsAndReloads() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let log = FocusSessionLog(fileURL: url)
        let start = Date()
        log.append(record(start: start, minutes: 25))
        log.flushForTesting()

        let reloaded = FocusSessionLog(fileURL: url)
        #expect(reloaded.records.count == 1)
        #expect(reloaded.records[0].phase == .focus)
        #expect(abs(reloaded.records[0].seconds - 1500) < 1)
    }

    @Test func corruptFileStartsEmptyAndIsSetAside() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json{{{".utf8).write(to: url)
        let log = FocusSessionLog(fileURL: url)
        #expect(log.records.isEmpty)
        // The broken blob is preserved aside, never silently destroyed.
        let aside = url.deletingPathExtension().appendingPathExtension("corrupt.json")
        defer { try? FileManager.default.removeItem(at: aside) }
        #expect(FileManager.default.fileExists(atPath: aside.path))
    }

    @Test func sessionsOnDayBucketsByStartDay() {
        let log = FocusSessionLog(fileURL: tempURL())
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        // Spans midnight: started yesterday 23:50, ran 20 minutes → yesterday's.
        log.append(record(start: yesterday.addingTimeInterval(23 * 3600 + 50 * 60),
                          minutes: 20))
        log.append(record(start: today.addingTimeInterval(9 * 3600), minutes: 25))

        #expect(log.sessions(on: yesterday).count == 1)
        #expect(log.sessions(on: today).count == 1)
        #expect(log.daysWithData() == [yesterday, today])
    }

    @Test func decodingToleratesMissingNewFields() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let json = """
        [{"id":"\(UUID().uuidString)","start":700000000,"end":700001500,
          "phase":"focus","plannedSeconds":1500}]
        """
        try Data(json.utf8).write(to: url)
        let log = FocusSessionLog(fileURL: url)
        #expect(log.records.count == 1)
        #expect(log.records[0].completed)             // defaults true
        #expect(log.records[0].appUsage.isEmpty)      // defaults empty
    }

    @Test func appendTrimsRecordsOlderThan400Days() {
        let log = FocusSessionLog(fileURL: tempURL())
        let old = Calendar.current.date(byAdding: .day, value: -401, to: Date())!
        log.append(record(start: old, minutes: 25))
        log.append(record(start: Date(), minutes: 25))
        #expect(log.records.count == 1)
    }
}
