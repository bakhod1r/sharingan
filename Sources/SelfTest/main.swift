import Foundation
import SharinganCore

@MainActor
struct SelfTest {
    static var failures: Int = 0
    static var passed: Int = 0

    static func check(_ condition: Bool, _ msg: String,
                      file: String = #file, line: Int = #line) {
        if condition {
            passed += 1
            print("  ✓ \(msg)")
        } else {
            failures += 1
            print("  ✗ \(msg)  [\(file):\(line)]")
        }
    }

    static func main() {
        print("Sharingan self-tests")
        testModels()
        testPomodoroKinds()
        do { try testPomodoroKindCoding() } catch {
            failures += 1
            print("  ✗ Kind coding threw: \(error)")
        }
        testKindResolution()
        testTimerKindSwitch()
        testTimerInitialState()
        testTimerSkipTransition()
        testTimerStopReset()
        testStatsFlow()
        testAddRemoveTime()
        testSetCustomDuration()
        testParserDurations()
        testParserClockTarget()
        testParserAddRemove()
        testCountUpMode()
        do { try testCoderRoundTrip() } catch {
            failures += 1
            print("  ✗ Codable threw: \(error)")
        }
testRepeatConfig()
        testStreakStore()
        testStatsWithStreak()
testAlarmSoundEnum()
        testGazeDirection()
        testBreakExerciseModel()
        testStreakRewardCenter()
        testReminders()
        testAmbienceEnum()
testBrightnessSettings()
        testAppBlocker()
        testBlockedAppPresets()
        testTaskPlanning()
        testWeeklyReport()
        testChartAggregation()
        testSQLitePersistence()
        testJSONMigration()

        print("\nPassed: \(passed)  Failed: \(failures)")
        if failures > 0 {
            print("SELF-TEST FAILED")
            exit(1)
        }
        print("SELF-TEST PASSED")
    }

    // MARK: Models

    static func testTaskPlanning() {
        print("• Task planning (reorder / estimate / plan / subtasks / recurrence)")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-selftest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = TaskStore(fileURL: dir.appendingPathComponent("tasks.json"))
        let cal = Calendar.current

        store.add(title: "A")
        store.add(title: "B")
        store.add(title: "C")
        check(store.tasks.count == 3, "3 tasks added")
        let a = store.tasks[0], b = store.tasks[1], c = store.tasks[2]
        check(a.sortOrder < b.sortOrder && b.sortOrder < c.sortOrder, "sortOrder increments on add")

        // Reorder: move C up → A, C, B
        store.move(c.id, up: true)
        let ordered = store.tasks.filter { !$0.isDone }.sorted(by: TaskStore.inListOrder).map(\.id)
        check(ordered == [a.id, c.id, b.id], "move up reorders within category")

        // Estimate
        store.setEstimate(a.id, 5)
        check(store.tasks.first { $0.id == a.id }?.estimatedPomodoros == 5, "estimate set")
        store.setEstimate(a.id, nil)
        check(store.tasks.first { $0.id == a.id }?.estimatedPomodoros == nil, "estimate cleared")

        // Plan for today
        store.togglePlannedToday(b.id)
        check(store.tasks.first { $0.id == b.id }?.isPlannedToday() == true, "planned for today")
        store.togglePlannedToday(b.id)
        check(store.tasks.first { $0.id == b.id }?.isPlannedToday() == false, "unplanned")

        // Subtasks
        store.addSubtask(a.id, title: "s1")
        store.addSubtask(a.id, title: "s2")
        check(store.tasks.first { $0.id == a.id }?.subtasks.count == 2, "2 subtasks added")
        if let sid = store.tasks.first(where: { $0.id == a.id })?.subtasks.first?.id {
            store.toggleSubtask(a.id, sid)
            check(store.tasks.first { $0.id == a.id }?.subtaskProgress.done == 1, "subtask toggled done")
            store.deleteSubtask(a.id, sid)
            check(store.tasks.first { $0.id == a.id }?.subtasks.count == 1, "subtask deleted")
        }

        // Notes + project
        store.setNotes(a.id, "hello")
        check(store.tasks.first { $0.id == a.id }?.notes == "hello", "notes set")
        store.setProject(a.id, "Proj")
        check(store.projects == ["Proj"], "project listed")

        // Recurrence regeneration on completion
        store.setRecurrence(a.id, .daily)
        var upd = store.tasks.first { $0.id == a.id }!
        let due = cal.startOfDay(for: Date())
        upd.dueDate = due
        store.update(upd)
        let before = store.tasks.count
        store.toggleDone(a.id)
        check(store.tasks.count == before + 1, "recurring completion spawns next occurrence")
        let openA = store.tasks.filter { !$0.isDone && $0.title == "A" }
        check(openA.count == 1, "exactly one open 'A' remains")
        if let next = openA.first, let nd = next.dueDate {
            check(cal.isDate(nd, inSameDayAs: cal.date(byAdding: .day, value: 1, to: due)!),
                  "next occurrence due date advanced by one day")
            check(next.pomodorosDone == 0, "spawned occurrence resets counters")
        }

        // Recurrence.nextDate weekdays skips the weekend (2026-01-02 is a Friday)
        var comps = DateComponents(); comps.year = 2026; comps.month = 1; comps.day = 2
        if let friday = cal.date(from: comps) {
            check(!cal.isDateInWeekend(Recurrence.weekdays.nextDate(after: friday)),
                  "weekdays recurrence skips the weekend")
        }

        // Overdue recurring task: completing one whose due date is 5 days in the
        // past must land the next occurrence in the FUTURE, not spawn another
        // already-past copy.
        let storeOD = TaskStore(fileURL: dir.appendingPathComponent("tod.json"))
        storeOD.add(title: "late", recurrence: .daily)
        var late = storeOD.tasks[0]
        late.dueDate = cal.date(byAdding: .day, value: -5, to: Date())
        storeOD.update(late)
        storeOD.toggleDone(late.id)
        let nextLate = storeOD.tasks.first { !$0.isDone && $0.title == "late" }
        if let nd = nextLate?.dueDate {
            check(nd > Date(), "overdue recurring task's next occurrence is in the future")
        } else {
            check(false, "overdue recurring task should spawn an occurrence with a due date")
        }

        // A recurring task with NO due date spawns a copy that is also due-less,
        // so no surprise deadline reminder is scheduled.
        let storeND = TaskStore(fileURL: dir.appendingPathComponent("tnd.json"))
        storeND.add(title: "nodue", recurrence: .daily)
        let nd0 = storeND.tasks[0]
        check(nd0.dueDate == nil, "recurring task added without a due date")
        storeND.toggleDone(nd0.id)
        let ndNext = storeND.tasks.first { !$0.isDone && $0.title == "nodue" }
        check(ndNext != nil, "due-less recurring task still spawns next occurrence")
        check(ndNext?.dueDate == nil, "due-less recurring occurrence stays due-less")

        // A non-recurring completion does NOT spawn a copy.
        let store2 = TaskStore(fileURL: dir.appendingPathComponent("t2.json"))
        store2.add(title: "solo")
        let solo = store2.tasks[0]
        store2.toggleDone(solo.id)
        check(store2.tasks.count == 1, "non-recurring completion spawns nothing")

        // Project clear.
        store.setProject(b.id, "Proj")
        store.setProject(b.id, nil)
        check(store.tasks.first { $0.id == b.id }?.project == nil, "project cleared to nil")

        // Weekday totals bucket history by weekday (0=Mon…6=Sun).
        var wdStats = PomodoroStats()
        var wdComps = DateComponents(); wdComps.year = 2026; wdComps.month = 1; wdComps.day = 5 // Mon
        let monday = cal.date(from: wdComps)!
        wdStats.history = [DailyCount(day: monday, count: 3),
                           DailyCount(day: cal.date(byAdding: .day, value: 2, to: monday)!, count: 1)] // Wed
        let wt = wdStats.weekdayTotals()
        check(wt[0] == 3, "Monday bucket = 3")
        check(wt[2] == 1, "Wednesday bucket = 1")
        check(wdStats.bestWeekday == 0, "best weekday is Monday")

        // Priority: set/persist + P-label mapping + defensive decode default.
        let storeP = TaskStore(fileURL: dir.appendingPathComponent("tprio.json"))
        storeP.add(title: "urgent")
        let pt = storeP.tasks[0]
        check(pt.priority == .none, "new task defaults to no priority")
        storeP.setPriority(pt.id, .high)
        check(storeP.tasks[0].priority == .high, "priority set to high")
        check(TaskPriority.high.label == "P1", "high maps to P1")
        check(TaskPriority.none.label == "P4", "none maps to P4")
        check(TaskPriority.high.colorHex != nil && TaskPriority.none.colorHex == nil,
              "flag color only for real priorities")
        // Legacy TaskItem JSON without `priority` decodes to .none.
        let legacyTask = #"{"id":"\#(UUID().uuidString)","title":"old","isDone":false}"#.data(using: .utf8)!
        if let t = try? JSONDecoder().decode(TaskItem.self, from: legacyTask) {
            check(t.priority == .none, "legacy task decodes priority=.none")
        } else { check(false, "legacy task should decode") }

        // Categories: rename (custom only) reassigns tasks; delete falls back;
        // presets can't be renamed/deleted.
        let storeCat = TaskStore(fileURL: dir.appendingPathComponent("tcat.json"))
        _ = storeCat.addCategory(name: "Side", colorHex: "#FF0000", icon: "star.fill")
        storeCat.add(title: "sidejob", category: "Side")
        check(storeCat.isCustomCategory("Side"), "Side is custom")
        check(!storeCat.isCustomCategory("Work"), "Work is a preset")
        check(storeCat.renameCategory("Side", to: "Hustle"), "custom rename succeeds")
        check(storeCat.tasks.first { $0.title == "sidejob" }?.category == "Hustle",
              "rename reassigns the task's category")
        check(!storeCat.renameCategory("Work", to: "Job"), "preset rename refused")
        check(!storeCat.renameCategory("Hustle", to: "Work"), "rename to existing name refused")
        storeCat.deleteCategory("Hustle")
        check(storeCat.tasks.first { $0.title == "sidejob" }?.category == TaskCategory.presets[0].name,
              "delete reassigns tasks to first preset")
        check(!storeCat.allCategories.contains { $0.name == "Hustle" }, "deleted category gone")

        // allTags: distinct, most-used first.
        let storeTag = TaskStore(fileURL: dir.appendingPathComponent("ttag.json"))
        storeTag.add(title: "a", tags: ["x", "y"])
        storeTag.add(title: "b", tags: ["x"])
        check(storeTag.allTags.first == "x", "most-used tag ranks first")
        check(Set(storeTag.allTags) == ["x", "y"], "allTags is the distinct set")

        // Weekly board: setPlannedDate buckets tasks by day; nil unschedules.
        let storeWB = TaskStore(fileURL: dir.appendingPathComponent("twb.json"))
        storeWB.add(title: "mon"); storeWB.add(title: "tue"); storeWB.add(title: "free")
        let wbMon = storeWB.tasks[0], wbTue = storeWB.tasks[1], wbFree = storeWB.tasks[2]
        let monDay = cal.startOfDay(for: Date())
        let tueDay = cal.date(byAdding: .day, value: 1, to: monDay)!
        storeWB.setPlannedDate(wbMon.id, monDay)
        storeWB.setPlannedDate(wbTue.id, tueDay)
        check(storeWB.tasksPlanned(on: monDay).map(\.id) == [wbMon.id], "one task planned on day 1")
        check(storeWB.tasksPlanned(on: tueDay).map(\.id) == [wbTue.id], "one task planned on day 2")
        check(storeWB.unscheduledTasks.map(\.id) == [wbFree.id], "unplanned task in backlog")
        // Planned date normalizes to start-of-day (drop at any time lands on the day).
        storeWB.setPlannedDate(wbFree.id, tueDay.addingTimeInterval(13 * 3600))
        check(storeWB.tasksPlanned(on: tueDay).count == 2, "drop at 1pm still buckets on that day")
        check(storeWB.tasks.first { $0.id == wbFree.id }?.plannedDate == tueDay,
              "planned date normalized to start-of-day")
        // Unschedule with nil returns it to the backlog.
        storeWB.setPlannedDate(wbMon.id, nil)
        check(storeWB.unscheduledTasks.contains { $0.id == wbMon.id }, "nil unschedules back to backlog")
        // Completed tasks never appear on the board.
        storeWB.toggleDone(wbTue.id)
        check(storeWB.tasksPlanned(on: tueDay).allSatisfy { !$0.isDone }, "done tasks excluded from board")

        // Drag reorder: move B before C-equivalent. Rebuild a clean 3-task store.
        let store3 = TaskStore(fileURL: dir.appendingPathComponent("t3.json"))
        store3.add(title: "X"); store3.add(title: "Y"); store3.add(title: "Z")
        let x = store3.tasks[0], y = store3.tasks[1], z = store3.tasks[2]
        store3.moveTask(z.id, before: x.id)   // Z to front → Z, X, Y
        let ord3 = store3.tasks.sorted(by: TaskStore.inListOrder).map(\.id)
        check(ord3 == [z.id, x.id, y.id], "drag moveTask reorders before target")

        try? FileManager.default.removeItem(at: dir)
    }

    static func testSQLitePersistence() {
        print("• SQLite persistence (full round-trip across instances)")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-sqlite-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("blink.sqlite")
        let cal = Calendar.current
        let due = cal.date(byAdding: .day, value: 2, to: Date())!

        // Write with every non-default field set, then re-open a fresh instance.
        do {
            let s = TaskStore(fileURL: dbURL)
            s.add(title: "Ship v2", category: "Work",
                  tags: ["urgent", "release"], dueDate: due,
                  estimatedPomodoros: 4, recurrence: .weekly,
                  project: "Sharingan", notes: "line1\nline2", priority: .high)
            let id = s.tasks[0].id
            s.addSubtask(id, title: "step 1")
            s.addSubtask(id, title: "step 2")
            s.setPlannedDate(id, Date())
            _ = s.addCategory(name: "Side", colorHex: "#123456", icon: "star.fill")
        }

        let s2 = TaskStore(fileURL: dbURL)
        check(s2.tasks.count == 1, "task survives a fresh DB open")
        guard let t = s2.tasks.first else { check(false, "no task reloaded"); return }
        check(t.title == "Ship v2", "title round-trips")
        check(t.category == "Work", "category round-trips")
        check(t.tags == ["urgent", "release"], "tags (JSON) round-trip")
        check(t.priority == .high, "priority round-trips")
        check(t.recurrence == .weekly, "recurrence round-trips")
        check(t.project == "Sharingan", "project round-trips")
        check(t.notes == "line1\nline2", "multiline notes round-trip")
        check(t.estimatedPomodoros == 4, "estimate round-trips")
        check(t.subtasks.count == 2, "subtasks (JSON) round-trip")
        check(t.dueDate.map { abs($0.timeIntervalSince(due)) < 0.001 } ?? false, "dueDate round-trips")
        check(t.plannedDate != nil, "plannedDate round-trips")
        check(s2.customCategories.contains { $0.name == "Side" && $0.colorHex == "#123456" },
              "custom category round-trips")

        // A nil-heavy task keeps its NULLs.
        let s3url = dir.appendingPathComponent("plain.sqlite")
        do { let s = TaskStore(fileURL: s3url); s.add(title: "Bare") }
        let s3 = TaskStore(fileURL: s3url)
        check(s3.tasks.first?.dueDate == nil, "nil dueDate stays nil")
        check(s3.tasks.first?.estimatedPomodoros == nil, "nil estimate stays nil")
        check(s3.tasks.first?.project == nil, "nil project stays nil")
    }

    static func testJSONMigration() {
        print("• Legacy JSON → SQLite migration")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-migrate-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Seed the old-format files next to where the DB will live.
        let legacyTasks = [TaskItem(title: "Old task", category: "Personal", priority: .low)]
        let legacyCats = [TaskCategory(name: "Legacy", colorHex: "#abcdef", icon: "book.fill")]
        try? JSONEncoder().encode(legacyTasks)
            .write(to: dir.appendingPathComponent("tasks.json"))
        try? JSONEncoder().encode(legacyCats)
            .write(to: dir.appendingPathComponent("categories.json"))

        // First open with an empty DB should import them.
        let s = TaskStore(fileURL: dir.appendingPathComponent("blink.sqlite"))
        check(s.tasks.first?.title == "Old task", "legacy task imported")
        check(s.customCategories.contains { $0.name == "Legacy" }, "legacy category imported")
        let fm = FileManager.default
        check(!fm.fileExists(atPath: dir.appendingPathComponent("tasks.json").path),
              "tasks.json renamed after migration")
        check(fm.fileExists(atPath: dir.appendingPathComponent("tasks.json.migrated").path),
              "tasks.json kept as .migrated backup")

        // Re-opening must NOT double-import (JSON already renamed) — still one task.
        let s2 = TaskStore(fileURL: dir.appendingPathComponent("blink.sqlite"))
        check(s2.tasks.count == 1, "no double-import on second launch")
    }

    static func testWeeklyReport() {
        print("• Weekly report (growth / decline)")
        let cal = Calendar.current
        let now = Date()
        var stats = PomodoroStats()
        for _ in 0..<3 { stats.registerFocusCompletion(on: now) }              // this week: 3
        let d8 = cal.date(byAdding: .day, value: -8, to: now)!
        for _ in 0..<2 { stats.registerFocusCompletion(on: d8) }               // last week: 2
        check(stats.thisWeekTotal(now: now) == 3, "this-week total = 3")
        check(stats.lastWeekTotal(now: now) == 2, "last-week total = 2")
        if let ch = stats.weekOverWeekChange(now: now) {
            check(abs(ch - 0.5) < 0.0001, "week-over-week change = +50%")
        } else {
            check(false, "week-over-week change should be non-nil")
        }
        var fresh = PomodoroStats()
        fresh.registerFocusCompletion(on: now)
        check(fresh.weekOverWeekChange(now: now) == nil, "no prior week → nil change")
    }

    static func testChartAggregation() {
        print("• Chart aggregation (weekly / monthly buckets)")
        let cal = Calendar.current
        let now = Date()
        var stats = PomodoroStats()
        // 3 today, 2 eight days ago (previous calendar week for most week-days).
        for _ in 0..<3 { stats.registerFocusCompletion(on: now) }
        let d8 = cal.date(byAdding: .day, value: -8, to: now)!
        for _ in 0..<2 { stats.registerFocusCompletion(on: d8) }
        // 4 forty days ago (previous month for most days).
        let d40 = cal.date(byAdding: .day, value: -40, to: now)!
        for _ in 0..<4 { stats.registerFocusCompletion(on: d40) }

        let weeks = stats.recentWeeks(4)
        check(weeks.count == 4, "recentWeeks returns exactly n buckets")
        check(weeks.last?.count == 3, "current week bucket = 3")
        let weekSum = weeks.reduce(0) { $0 + $1.count }
        // d40 may fall outside a 4-week window; the 3 + 2 always land inside it.
        check(weekSum >= 5, "recentWeeks sums the in-window days")

        let months = stats.recentMonths(3)
        check(months.count == 3, "recentMonths returns exactly n buckets")
        check(months.reduce(0) { $0 + $1.count } == 9, "recentMonths sums all 3 months = 9")
        // Buckets are chronological, oldest first.
        check(months.first!.day < months.last!.day, "month buckets are chronological")

        // History now retains well beyond 90 days (400-day window).
        let old = cal.date(byAdding: .day, value: -200, to: now)!
        var deep = PomodoroStats()
        deep.registerFocusCompletion(on: old)
        deep.registerFocusCompletion(on: now)
        check(deep.recentMonths(12).reduce(0) { $0 + $1.count } == 2,
              "200-day-old history survives (retention > 90d)")
    }

    static func testModels() {
        print("• Pomodoro models")
        let s = PomodoroSettings()
        check(s.focusSeconds == 25 * 60, "focusSeconds default 25m")
        check(s.shortBreakSeconds == 5 * 60, "shortBreakSeconds default 5m")
        check(s.longBreakSeconds == 15 * 60, "longBreakSeconds default 15m")
        check(s.duration(for: .focus) == 25 * 60, "duration(.focus)")
        check(s.duration(for: .paused) == 0, "duration(.paused) == 0")
        // A 0-minute misconfiguration must floor to >= 1s so a phase can't
        // complete on its first tick and spin under auto mode.
        var zero = PomodoroSettings()
        zero.focusMinutes = 0
        zero.shortBreakMinutes = 0
        zero.longBreakMinutes = 0
        check(zero.duration(for: .focus) >= 1, "zero focus floored to >= 1s")
        check(zero.duration(for: .shortBreak) >= 1, "zero shortBreak floored to >= 1s")
        check(zero.duration(for: .longBreak) >= 1, "zero longBreak floored to >= 1s")
        check(zero.duration(for: .paused) == 0, "paused stays 0 even when floored")
        check(PomodoroPhase.allCases.count == 4, "phase count == 4")
        check(TimerMode.allCases.count == 2, "mode count == 2")
        check(SharinganTheme.allCases.count == 6, "theme count == 6")
        check(PomodoroPhase.focus.gradient.count == 2, "focus gradient stack")
    }

    static func testPomodoroKinds() {
        print("• Pomodoro kinds (Small / Normal / Big)")
        check(PomodoroKind.allCases.count == 3, "3 kinds")
        check(PomodoroKind.small.defaultConfig == .init(focusMinutes: 10, breakMinutes: 3),
              "small default 10/3")
        check(PomodoroKind.normal.defaultConfig == .init(focusMinutes: 25, breakMinutes: 5),
              "normal default 25/5")
        check(PomodoroKind.big.defaultConfig == .init(focusMinutes: 90, breakMinutes: 15),
              "big default 90/15")

        var s = PomodoroSettings()
        check(s.activeKind == .normal, "normal is the default kind")
        check(s.focusMinutes == 25 && s.shortBreakMinutes == 5,
              "flat accessors read the active kind")

        // Switching the active kind swaps what the timer-facing accessors read.
        s.activeKind = .small
        check(s.focusMinutes == 10 && s.shortBreakMinutes == 3,
              "small kind → 10/3 via accessors")
        check(s.duration(for: .focus) == 10 * 60, "duration follows active kind")
        s.activeKind = .big
        check(s.focusMinutes == 90 && s.duration(for: .shortBreak) == 15 * 60,
              "big kind → 90/15 via accessors")

        // Every kind is user-configurable, independently of the others.
        s.setConfig(.init(focusMinutes: 50, breakMinutes: 8), for: .big)
        check(s.config(for: .big).focusMinutes == 50, "big focus configurable")
        check(s.duration(for: .focus) == 50 * 60, "custom big drives the timer")
        check(s.config(for: .small) == PomodoroKind.small.defaultConfig,
              "editing big leaves small untouched")

        // Writing through the flat accessor edits only the ACTIVE kind.
        s.activeKind = .small
        s.focusMinutes = 12
        check(s.config(for: .small).focusMinutes == 12, "accessor writes small")
        check(s.config(for: .normal).focusMinutes == 25, "normal unchanged")
    }

    static func testPomodoroKindCoding() throws {
        print("• Pomodoro kind persistence & migration")
        // Round-trip: per-kind overrides and the selected kind survive.
        var s = PomodoroSettings()
        s.setConfig(.init(focusMinutes: 15, breakMinutes: 4), for: .small)
        s.activeKind = .small
        let decoded = try JSONDecoder().decode(
            PomodoroSettings.self, from: JSONEncoder().encode(s))
        check(decoded == s, "kind settings encode/decode equal")
        check(decoded.activeKind == .small, "activeKind survives")
        check(decoded.config(for: .small).focusMinutes == 15, "small override survives")

        // A pre-kinds blob (flat minutes) migrates into the normal kind so the
        // user's custom durations survive the update.
        let legacy = #"{"focusMinutes": 40, "shortBreakMinutes": 7}"#
        let migrated = try JSONDecoder().decode(
            PomodoroSettings.self, from: Data(legacy.utf8))
        check(migrated.config(for: .normal) == .init(focusMinutes: 40, breakMinutes: 7),
              "legacy 40/7 lands on normal")
        check(migrated.activeKind == .normal, "legacy blob defaults to normal")
        check(migrated.config(for: .small) == PomodoroKind.small.defaultConfig
              && migrated.config(for: .big) == PomodoroKind.big.defaultConfig,
              "small/big stay factory after migration")

        // Legacy keys must NOT clobber an explicit normal config.
        let mixed = #"{"focusMinutes": 40, "kindConfigs": {"normal": {"focusMinutes": 33, "breakMinutes": 6}}}"#
        let kept = try JSONDecoder().decode(PomodoroSettings.self, from: Data(mixed.utf8))
        check(kept.config(for: .normal).focusMinutes == 33,
              "explicit kindConfigs beats legacy keys")

        // Tasks & subtasks: kind round-trips, and old rows decode to nil.
        var task = TaskItem(title: "Deep work")
        task.pomodoroKind = .big
        task.subtasks = [Subtask(title: "outline", pomodoroKind: .small)]
        let t2 = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task))
        check(t2.pomodoroKind == .big, "task kind survives round-trip")
        check(t2.subtasks[0].pomodoroKind == .small, "subtask kind survives round-trip")
        let oldTask = try JSONDecoder().decode(
            TaskItem.self, from: Data(#"{"title": "old"}"#.utf8))
        check(oldTask.pomodoroKind == nil, "pre-kind task decodes to nil kind")
        let oldSub = try JSONDecoder().decode(
            Subtask.self, from: Data(#"{"title": "old step"}"#.utf8))
        check(oldSub.pomodoroKind == nil, "pre-kind subtask decodes to nil kind")
    }

    static func testKindResolution() {
        print("• Kind resolution (subtask ▸ task ▸ none)")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blink-selftest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = TaskStore(fileURL: dir.appendingPathComponent("tasks.json"))

        store.add(title: "Thesis chapter")
        store.add(title: "Inbox zero")
        var thesis = store.tasks[0]
        thesis.pomodoroKind = .big
        thesis.subtasks = [Subtask(title: "outline", pomodoroKind: .small),
                           Subtask(title: "draft")]
        store.update(thesis)

        check(store.resolvedActiveKind == nil, "no active task → no preference")
        store.setActive(thesis.id)
        check(store.resolvedActiveKind == .big, "task kind wins without a target step")
        store.setActiveSubtask(taskID: thesis.id, subtaskID: thesis.subtasks[0].id)
        check(store.resolvedActiveKind == .small, "targeted subtask kind overrides task")
        store.setActiveSubtask(taskID: thesis.id, subtaskID: thesis.subtasks[1].id)
        check(store.resolvedActiveKind == .big, "kindless subtask falls back to task kind")
        store.setActive(store.tasks[1].id)
        check(store.resolvedActiveKind == nil, "kindless task → no preference")

        try? FileManager.default.removeItem(at: dir)
    }

    static func testTimerKindSwitch() {
        print("• Timer kind switching")
        let timer = PomodoroTimer()
        let original = timer.settings   // restore afterwards: settings persist
        timer.stop()

        timer.applyKind(.small)
        check(timer.settings.activeKind == .small, "applyKind selects small")
        check(timer.remainingSeconds == timer.settings.duration(for: .focus),
              "idle applyKind refreshes the countdown")
        check(!timer.isRunning, "applyKind never starts the timer")
        timer.applyKind(.small)
        check(timer.remainingSeconds == timer.settings.duration(for: .focus),
              "re-applying the same kind is a no-op")

        timer.startFocusSession(kind: .big)
        check(timer.isRunning && timer.phase == .focus, "session starts in focus")
        check(timer.settings.activeKind == .big, "session adopts the task's kind")
        check(timer.totalSeconds == timer.settings.duration(for: .focus),
              "session length is the big focus length")

        // Starting a task with a DIFFERENT kind mid-run restarts fresh.
        timer.startFocusSession(kind: .small)
        check(timer.settings.activeKind == .small, "mid-run switch adopts small")
        check(timer.remainingSeconds == timer.settings.duration(for: .focus),
              "mid-run switch restarts the countdown")

        // Same kind (or none) resumes/keeps the session — no restart.
        timer.pause()
        let before = timer.remainingSeconds
        timer.startFocusSession(kind: .small)
        check(timer.remainingSeconds == before, "same-kind resume keeps progress")
        timer.startFocusSession()
        check(timer.remainingSeconds == before, "nil kind keeps the current kind")

        timer.stop()
        timer.settings = original
    }

    static func testTimerInitialState() {
        print("• PomodoroTimer initial state")
        let timer = PomodoroTimer()
        check(timer.phase == .focus, "starts in focus")
        check(timer.isRunning == false, "not running initially")
        check(abs(timer.remainingSeconds - timer.settings.focusSeconds) < 0.001,
              "remaining == focus duration")
        check(timer.totalSeconds == timer.settings.focusSeconds, "total == focus")
        check(timer.progress == 0, "progress starts at 0")
        check(timer.cyclesCompletedInRound == 0, "cycles start at 0")
        check(timer.elapsedSeconds == 0, "elapsed starts at 0")
    }

    static func testTimerSkipTransition() {
        print("• timer.skip() focus -> shortBreak")
        let timer = PomodoroTimer()
        timer.skip()
        check(timer.phase == .shortBreak, "phase becomes shortBreak")
        check(timer.isRunning == false, "not auto-run on skip()")
        check(timer.remainingSeconds == timer.settings.shortBreakSeconds,
              "remaining set to short break duration")

        timer.skip()
        check(timer.phase == .focus, "skip shortBreak -> focus")
        check(timer.remainingSeconds == timer.settings.focusSeconds,
              "remaining reset to focus duration")
    }

    static func testTimerStopReset() {
        print("• timer.stop()")
        let timer = PomodoroTimer()
        timer.skip()
        timer.stop()
        check(timer.phase == .focus, "stop resets phase to focus")
        check(timer.cyclesCompletedInRound == 0, "stop clears cycles")
        check(timer.remainingSeconds == timer.settings.focusSeconds,
              "stop resets remaining")
        check(timer.elapsedSeconds == 0, "stop clears elapsed")
        check(timer.isRunning == false, "stop halts running")
        check(timer.repeatIndex == 0, "stop clears repeatIndex")
    }

    static func testStatsFlow() {
        print("• PomodoroStats flow")
        var stats = PomodoroStats()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        stats.registerFocusCompletion(on: today)
        stats.registerFocusCompletion(on: today)
        stats.registerFocusCompletion(on: today)
        check(stats.completedFocus == 3, "completedFocus accumulates")
        check(stats.completedToday == 3, "completedToday accumulates")
        // Same-day reset is a no-op — a live count is never wiped.
        stats.resetTodayIfNeeded(now: today)
        check(stats.completedToday == 3, "same-day resetToday keeps count")
        // A completion on a new day rolls the today-counter over.
        var rolled = PomodoroStats()
        rolled.registerFocusCompletion(on: yesterday)
        rolled.registerFocusCompletion(on: yesterday)
        rolled.registerFocusCompletion(on: today)
        check(rolled.completedToday == 1, "completedToday rolls over at midnight")
        check(rolled.completedFocus == 3, "global retained across days")
    }

    // MARK: New timer API

    static func testAddRemoveTime() {
        print("• add/remove time")
        let timer = PomodoroTimer()
        let start = timer.remainingSeconds
        timer.addTime(120)
        check(timer.remainingSeconds == start + 120, "addTime +120s")
        timer.removeTime(60)
        check(timer.remainingSeconds == start + 60, "removeTime -60s")
        timer.removeTime(3600)
        check(timer.remainingSeconds == 0, "removeTime floored at 0")
    }

    static func testSetCustomDuration() {
        print("• setCustomDuration / applyParsed")
        let timer = PomodoroTimer()
        timer.setCustomDuration(600)
        check(timer.remainingSeconds == 600, "setCustomDuration sets 600")
        check(timer.elapsedSeconds == 0, "elapsed reset after setCustom")
        check(timer.isRunning == false, "not running after setCustom")

        timer.applyParsed(.init(kind: .setDuration(1200)))
        check(timer.remainingSeconds == 1200, "applyParsed setDuration 1200")

        timer.applyParsed(.init(kind: .addTime(60)))
        check(timer.remainingSeconds == 1260, "applyParsed addTime")
        timer.applyParsed(.init(kind: .removeTime(120)))
        check(timer.remainingSeconds == 1140, "applyParsed removeTime")

        timer.applyParsed(.init(kind: .setDuration(0)))
        check(timer.cyclesCompletedInRound == 0, "setDuration(0) resets")
        check(timer.phase == .focus, "setDuration(0) phase focus")
    }

    // MARK: Parser

    static func testParserDurations() {
        print("• parser: durations")
        expectSetDuration("5 min", 300)
        expectSetDuration("5min", 300)
        expectSetDuration("20 minutes", 1200)
        expectSetDuration("2h 30m", 2 * 3600 + 30 * 60)
        expectSetDuration("2h30m", 2 * 3600 + 30 * 60)
        expectSetDuration("90 seconds", 90)
        expectSetDuration("25", 25 * 60)
        expectSetDuration("1h", 3600)
    }

    static func expectSetDuration(_ input: String, _ expected: TimeInterval,
                                  file: String = #file, line: Int = #line) {
        guard let p = NaturalLanguageParser.parse(input),
              case .setDuration(let d) = p.kind else {
            check(false, "parsed '\(input)'", file: file, line: line)
            return
        }
        check(abs(d - expected) < 0.001, "'\(input)' → \(d)s (expected \(expected)s)",
              file: file, line: line)
    }

    static func testParserClockTarget() {
        print("• parser: clock target")
        let now = Date()
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 17
        comps.minute = 0
        comps.second = 0
        let expected5pm = cal.date(from: comps)!
        let shifted = expected5pm.addingTimeInterval(-3600)

        if let p = NaturalLanguageParser.parse("5pm", now: shifted),
           case .setTargetTime(let target) = p.kind {
            let delta = target.timeIntervalSince(shifted)
            check(abs(delta - 3600) < 5,
                  "'5pm' now+1h delta=\(delta)")
        } else {
            check(false, "'5pm' should parse to setTargetTime")
        }
    }

    static func testParserAddRemove() {
        print("• parser: add/remove")
        expectDelta("Add 5 min", 300)
        expectDelta("+5m", 300)
        expectDelta("Remove 1 hour", -3600)
        expectDelta("-1h", -3600)
    }

    static func expectDelta(_ input: String, _ expected: TimeInterval,
                            file: String = #file, line: Int = #line) {
        guard let p = NaturalLanguageParser.parse(input) else {
            check(false, "parsed '\(input)'", file: file, line: line)
            return
        }
        let actual: TimeInterval
        switch p.kind {
        case .addTime(let d):    actual = d
        case .removeTime(let d): actual = -d
        default:
            check(false, "'\(input)' expected add/remove", file: file, line: line)
            return
        }
        check(abs(actual - expected) < 0.001,
              "'\(input)' → \(actual)s (expected \(expected)s)",
              file: file, line: line)
    }

    // MARK: Count-up mode

    static func testCountUpMode() {
        print("• count-up mode")
        var settings = PomodoroSettings()
        settings.timerMode = .countUp
        let timer = PomodoroTimer()
        timer.settings = settings
        timer.setCustomDuration(60)
        check(timer.isCountUpMode == true, "countUp mode set")
        check(timer.isCountUpMode == true, "isCountUpMode true")
        check(timer.remainingSeconds == 60, "countUp remaining = 60")
        check(timer.elapsedSeconds == 0, "countUp elapsed starts 0")
        check(timer.progress == 0, "countUp starts at progress 0")
    }

    // MARK: Repeat

    static func testRepeatConfig() {
        print("• repeatConfig")
        let rep = RepeatConfig(enabled: true, count: 5, delaySeconds: 120)
        check(rep.enabled == true, "repeat enabled")
        check(rep.count == 5, "repeat count == 5")
        check(rep.delaySeconds == 120, "delay 120s")
        check(rep.delaysTotal == 4 * 120, "delaysTotal = (count-1)*delay")
        check(RepeatConfig().delaysTotal == 0, "default delaysTotal == 0")
        check(RepeatConfig(enabled: true, count: -3).count == 1,
              "negative count floored to 1")
        check(RepeatConfig(enabled: true, delaySeconds: -5).delaySeconds == 0,
              "negative delay floored to 0")
    }

    // MARK: Coder

    static func testCoderRoundTrip() throws {
        print("• Codable round-trip")
        var s = PomodoroSettings()
        s.focusMinutes = 45
        s.shortBreakMinutes = 10
        s.longBreakMinutes = 30
        s.longBreakEvery = 6
        s.ttsRate = 0.62
        s.ttsPitch = 1.2
        s.timerMode = .countUp
        s.theme = .neon
        s.repeatConfig = RepeatConfig(enabled: true, count: 3, delaySeconds: 90)
        s.flashAtFiveSecLeft = true
        s.dockWidgetEnabled = false
        s.globalShortcutsEnabled = false
        s.breakMessage = "Test message."

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(PomodoroSettings.self, from: data)

        check(decoded == s, "settings encode/decode equal")
        check(decoded.focusMinutes == 45, "decoded focusMinutes")
        check(decoded.timerMode == .countUp, "decoded timerMode")
        check(decoded.theme == .neon, "decoded theme")
        check(decoded.repeatConfig == s.repeatConfig, "decoded repeatConfig")
        check(decoded.dockWidgetEnabled == false, "decoded dockWidgetEnabled flag")
        check(abs(decoded.ttsRate - 0.62) < 0.0001, "decoded ttsRate")

        var stats = PomodoroStats()
        for _ in 0..<7 { stats.registerFocusCompletion() }
        let sdata = try JSONEncoder().encode(stats)
        let sdecoded = try JSONDecoder().decode(PomodoroStats.self, from: sdata)
        check(sdecoded == stats, "stats encode/decode equal")
        check(sdecoded.completedFocus == 7, "decoded stats count")
    }

    // MARK: Streak

    static func testStreakStore() {
        print("• StreakStore")
        var streak = StreakStore()
        check(streak.currentStreak == 0, "fresh streak 0")
        check(streak.longestStreak == 0, "fresh longest 0")
        check(streak.completedToday() == false, "nothing completed today")

        let cal = Calendar.current
        let today = Date()
        streak.registerFocus(on: today, calendar: cal)
        check(streak.currentStreak == 1, "first completion → streak 1")
        check(streak.longestStreak == 1, "longest updated to 1")
        check(streak.completedToday(on: today, calendar: cal) == true,
              "completedToday true after first")

        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        var s2 = StreakStore()
        s2.registerFocus(on: yesterday, calendar: cal)
        s2.registerFocus(on: today, calendar: cal)
        check(s2.currentStreak == 2, "consecutive days → streak 2")
        check(s2.longestStreak == 2, "longest = 2")

        // Gap of 3 days resets streak to 1
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: today)!
        var s3 = StreakStore()
        s3.registerFocus(on: threeDaysAgo, calendar: cal)
        check(s3.currentStreak == 1, "streak 1 after first day")
        s3.registerFocus(on: today, calendar: cal)
        check(s3.currentStreak == 1, "gap resets streak to 1 (not continued)")
        check(s3.longestStreak == 1, "longest stays 1 after gap reset")

        // Same-day re-registration does not increase streak
        var s4 = StreakStore()
        s4.registerFocus(on: today, calendar: cal)
        s4.registerFocus(on: today, calendar: cal)
        check(s4.currentStreak == 1, "same-day re-register keeps streak 1")
    }

    static func testStatsWithStreak() {
        print("• PomodoroStats with streak")
        var stats = PomodoroStats()
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        stats.registerFocusCompletion(on: yesterday)
        stats.registerFocusCompletion(on: Date())
        check(stats.streak.currentStreak == 2, "stats streak 2 via registerFocusCompletion")
        check(stats.streakDays == 2, "streakDays mirrors currentStreak")
        check(stats.completedFocus == 2, "completedFocus increments")
    }

    static func testAlarmSoundEnum() {
        print("• AlarmSoundService.Sound")
        check(AlarmSoundService.Sound.allCases.count == 4, "4 sound cases")
        check(AlarmSoundService.Sound(rawValue: "glass") == .glass, "rawValue glass")
        check(AlarmSoundService.Sound(rawValue: "softBell") == .softBell, "rawValue softBell")
        check(AlarmSoundService.Sound(rawValue: "silent") == .silent, "rawValue silent")
        check(AlarmSoundService.Sound(rawValue: "invalid") == nil, "invalid rawValue → nil")
        check(AlarmSoundService.Sound.silent.label == "Silent", "silent label")
    }

    static func testGazeDirection() {
        print("• GazeDirection")
        check(GazeDirection.center.magnitude == 0, "center magnitude 0")
        check(GazeDirection.right.magnitude == 1, "right magnitude 1")
        check(GazeDirection.upLeft.magnitude - 0.9899 < 0.01, "upLeft ~0.99")
        check(GazeDirection.center.matches(.center), "center matches itself")
        check(GazeDirection.right.matches(.right), "right matches itself")
        check(GazeDirection.right.matches(GazeDirection(dx: 0.85, dy: 0.1)),
              "right matches near-right")
        check(!GazeDirection.right.matches(.left), "right does not match left")
        check(!GazeDirection.up.matches(.down), "up does not match down")
        check(GazeDirection(dx: 0, dy: 0).matches(.center, tolerance: 0.1),
              "near-center matches center")
        check(GazeDirection(dx: 1.2, dy: 1.5).dx == 1, "dx clamped to 1")
        check(GazeDirection(dx: -1.2, dy: 0).dx == -1, "dx clamped to -1")
        check(GazeDirection.center.label == "center", "center label")
        check(GazeDirection.right.label == "right", "right label")
        check(GazeDirection.up.label == "up", "up label")
    }

    static func testBreakExerciseModel() {
        print("• BreakExercise model")
        check(BreakExerciseStep(direction: "up", holdSeconds: 3).instruction.contains("up"),
              "auto instruction contains 'up'")
        check(BreakExerciseStep(direction: "down", holdSeconds: 0.1).holdSeconds == 0.5,
              "holdSeconds floor 0.5")
        check(BreakExerciseStep(direction: "left", holdSeconds: 4,
                                instruction: "Custom").instruction == "Custom",
              "custom instruktsiya saqlanadi")
        check(BreakExerciseStep(direction: "up", holdSeconds: 1).targetGaze == .up,
              "up → .up gaze")
        check(BreakExerciseStep(direction: "right", holdSeconds: 1).targetGaze == .right,
              "right → .right gaze")
        check(BreakExerciseStep(direction: "center", holdSeconds: 1).targetGaze == .center,
              "center → .center gaze")
        check(BreakExerciseStep(direction: "unknown", holdSeconds: 1).targetGaze == .center,
              "unknown → .center fallback")
        check(BreakExercise.twentyRule.steps.count == 2, "20-20-20 has 2 steps")
        check(BreakExercise.gaze.steps.count == 16, "gaze has 16 steps")
        check(BreakExercise.blink.steps.count == 2, "blink has 2 steps")
        check(BreakExercise.library().count == 3, "library has 3 exercises")
        check(BreakExercise.library() == [.twentyRule, .gaze, .blink],
              "library ordering")
    }

    static func testStreakRewardCenter() {
        print("• StreakRewardCenter")
        let center = StreakRewardCenter.shared
        center.resetForTesting()

        center.evaluate(streak: 0)
        check(center.pendingReward == nil, "no reward at streak 0")
        check(center.unlockedBadges.isEmpty, "no unlocked at streak 0")

        center.evaluate(streak: 1)
        check(center.pendingReward != nil, "reward at streak 1")
        check(center.pendingReward?.badge.id == "first", "first badge id")
        check(center.unlockedBadges.count == 1, "1 unlocked after streak 1")

        center.dismiss()
        check(center.pendingReward == nil, "dismissed clears pending")

        // Re-evaluating same streak should not re-fire.
        center.evaluate(streak: 1)
        check(center.pendingReward == nil, "no re-fire on same streak")

        // Jump to 7 → week badge unlocked.
        center.evaluate(streak: 7)
        check(center.pendingReward != nil, "reward at streak 7")
        check(center.pendingReward?.badge.id == "week", "week badge id")
        check(center.unlockedBadges.count == 2, "2 unlocked after streak 7")

        center.dismiss()

        // Jump to 30 → month badge unlocked, skipping 14 is fine but only
        // the highest newly-unlocked milestone shows.
        center.evaluate(streak: 30)
        check(center.pendingReward != nil, "reward at streak 30")
        check(center.pendingReward?.badge.id == "month", "month badge id")

        // Verify all milestones earned for streak 30.
        let earned30 = StreakBadge.earned(forStreak: 30)
        check(earned30.map { $0.id } == ["first", "week", "fortnight", "month"],
              "30-day earns 4 badges")

        // Next milestone after 30 is quarter (90).
        check(StreakBadge.next(forStreak: 30)?.id == "quarter",
              "next after 30 is quarter")

        // Next milestone after 0 is first (1).
        check(StreakBadge.next(forStreak: 0)?.id == "first",
              "next after 0 is first")

        // No next after 365.
        check(StreakBadge.next(forStreak: 400) == nil,
              "no next after 365+")

        center.resetForTesting()
        check(center.unlockedBadges.isEmpty, "reset clears unlocked")

        // prime(): seeding an already-earned streak at launch must NOT announce,
        // and must suppress re-announcing that milestone on the next evaluate —
        // this is the "no re-announce across restart" fix.
        center.resetForTesting()
        center.prime(streak: 7)
        check(center.pendingReward == nil, "prime does not announce")
        check(center.unlockedBadges.count == 2, "prime seeds earned badges (first, week)")
        center.evaluate(streak: 7)
        check(center.pendingReward == nil, "primed streak does not re-announce on evaluate")
        // A genuinely new milestone still fires after priming.
        center.evaluate(streak: 30)
        check(center.pendingReward?.badge.id == "month", "new milestone still fires after prime")
        center.resetForTesting()
    }

    static func testReminders() {
        print("• Reminders")
        let posture = ReminderItem(kind: .posture, intervalMinutes: 15)
        check(posture.kind == .posture, "posture kind")
        check(posture.intervalMinutes == 15, "interval 15")
        check(posture.intervalSeconds == 900, "intervalSeconds 900")
        check(posture.enabled == true, "enabled by default")
        check(posture.resolvedMessage.contains("straight"), "posture default msg")
        let water = ReminderItem(kind: .water, intervalMinutes: 10,
                                  message: "Drink water please")
        check(water.resolvedMessage == "Drink water please",
              "custom message overrides default")
        let custom = ReminderItem(kind: .custom, intervalMinutes: 0)
        check(custom.intervalMinutes == 1, "0 floored to 1")

        var s = ReminderSettings()
        check(s.enabled == true, "settings enabled default")
        check(s.duringFocusOnly == true, "focus-only default")
        check(s.reminders.count == 2, "2 default reminders")
        check(s.reminders[0].kind == .posture, "first is posture")
        check(s.reminders[1].kind == .water, "second is water")
        s.reminders.append(.init(kind: .custom, intervalMinutes: 30,
                                   message: "Stretch"))
        check(s.reminders.count == 3, "added custom reminder")
    }

    static func testAmbienceEnum() {
        print("• Ambience enum")
        check(BreakAmbienceService.Ambience.allCases.count == 5, "5 ambience cases")
        check(BreakAmbienceService.Ambience(rawValue: "rain") == .rain, "rain rawValue")
        check(BreakAmbienceService.Ambience(rawValue: "whiteNoise") == .whiteNoise, "whiteNoise")
        check(BreakAmbienceService.Ambience.silent.label == "Silent", "silent label")
        check(BreakAmbienceService.Ambience.rain.label == "Rain", "rain label")
        check(BreakAmbienceService.Ambience.lofi.label.contains("Lo-fi"), "lofi label")
    }

    static func testBrightnessSettings() {
        print("• Brightness settings")
        let s = PomodoroSettings()
        check(s.brightnessDimEnabled == false, "brightness disabled by default")
        check(s.brightnessDimPercent == 35, "default 35% dim")
        check(s.brightnessSmooth == true, "smooth default true")

        let svc = BrightnessService.shared
        check(svc.isDimming == false, "not dimming initially")
        check(svc.enabled == false, "service disabled initially")
        svc.enabled = true
        svc.levelPercent = 50
        check(svc.levelPercent == 50, "levelPercent set")

        // applyFactor clamning testlash (via dim)
        let target = BrightnessService.shared
        target.smooth = false
        target.enabled = true
        target.levelPercent = 30
        target.dimToBreak() // shouldn't crash; will set system gamma
        check(target.isDimming == true, "isDimming true after dim")
        target.restore()
        check(target.isDimming == false, "isDimming false after restore")

        // Disabled flag forbids dimying
        target.enabled = false
        target.dimToBreak()
        check(target.isDimming == false, "disabled does not dim")
        target.enabled = true
    }

    static func testAppBlocker() {
        print("• AppBlocker settings")
        let s = AppBlockerSettings()
        check(s.enabled == false, "blocker disabled by default")
        check(s.onlyDuringBreak == true, "break-only default")
        check(s.killOnFrontmost == false, "hide by default")
        check(s.blockedApps.count == 6, "6 preset apps")
        check(s.matches(bundleID: "com.apple.Safari") == false,
              "disabled does not match")
        var on = s
        on.enabled = true
        check(on.matches(bundleID: "com.apple.Safari") == true, "Safari matches when enabled")
        check(on.matches(bundleID: "com.example.unknown") == false, "unknown no match")
        check(on.matches(bundleID: "") == false, "empty bundleID no match")

        // Per-app isEnabled: disabling one entry stops it matching without removing it.
        if let idx = on.blockedApps.firstIndex(where: { $0.bundleID == "com.apple.Safari" }) {
            on.blockedApps[idx].isEnabled = false
        }
        check(on.matches(bundleID: "com.apple.Safari") == false, "disabled app entry does not match")
        check(on.blockedApps.count == 6, "disabled app stays in the list")
        check(on.matches(bundleID: "com.google.Chrome") == true, "other enabled app still matches")

        // Defensive decode: a legacy BlockedApp JSON without `isEnabled` defaults on.
        let legacy = #"{"bundleID":"com.foo.Bar","name":"Bar"}"#.data(using: .utf8)!
        if let app = try? JSONDecoder().decode(BlockedApp.self, from: legacy) {
            check(app.isEnabled == true, "legacy BlockedApp decodes isEnabled=true")
        } else {
            check(false, "legacy BlockedApp should decode")
        }
    }

    static func testBlockedAppPresets() {
        print("• BlockedApp presets")
        check(BlockedApp.presets.count == 6, "6 presets")
        check(BlockedApp.presets.contains { $0.bundleID == "ru.keepcoder.Telegram" },
              "Telegram in presets")
        check(BlockedApp.presets.contains { $0.name == "Chrome" }, "Chrome in presets")
        let chrome = BlockedApp(bundleID: "com.google.Chrome", name: "Chrome")
        check(chrome.id == "com.google.Chrome", "id = bundleID")
        check(chrome == .init(bundleID: "com.google.Chrome", name: "Chrome"),
              "equality")
        var s = AppBlockerSettings()
        s.blockedApps.removeAll { $0.bundleID == "com.apple.Safari" }
        s.enabled = true
        check(s.matches(bundleID: "com.apple.Safari") == false, "removed Safari")
        check(s.matches(bundleID: "ru.keepcoder.Telegram") == true, "Telegram still set")
    }
}
Task { @MainActor in
    SelfTest.main()
}

// Keep the process alive until the main-actor task completes.
import Foundation
RunLoop.main.run(until: Date().addingTimeInterval(60))
