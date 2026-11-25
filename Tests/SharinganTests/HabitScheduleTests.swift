import XCTest
@testable import SharinganCore

final class HabitScheduleTests: XCTestCase {
    func testScheduleCodecRoundTrip() throws {
        let cases: [HabitSchedule] = [.daily, .weekdays([2, 4, 6]), .timesPerWeek(3)]
        for s in cases {
            XCTAssertEqual(HabitSchedule(string: s.stringValue), s)
            let data = try JSONEncoder().encode(s)
            XCTAssertEqual(try JSONDecoder().decode(HabitSchedule.self, from: data), s)
        }
        XCTAssertEqual(HabitSchedule.weekdays([6, 2, 4]).stringValue, "weekdays:2,4,6")
        XCTAssertEqual(HabitSchedule.timesPerWeek(3).stringValue, "perWeek:3")
    }

    func testUnknownScheduleStringsFallBackToDaily() {
        for bad in ["", "garbage", "weekdays:", "weekdays:9,0", "perWeek:0", "perWeek:8", "perWeek:x"] {
            XCTAssertEqual(HabitSchedule(string: bad), .daily, bad)
        }
    }

    func testModeCodecRoundTripAndFallback() {
        XCTAssertEqual(HabitCompletionMode(string: HabitCompletionMode.pomodoro(target: 4).stringValue), .pomodoro(target: 4))
        XCTAssertEqual(HabitCompletionMode(string: "manual"), .manual)
        XCTAssertEqual(HabitCompletionMode(string: "pomodoro:0"), .manual)
        XCTAssertEqual(HabitCompletionMode(string: "???"), .manual)
    }

    func testTaskHabitJSONRoundTripAndTaskItemDecode() throws {
        let h = TaskHabit(schedule: .weekdays([2, 3]), mode: .pomodoro(target: 2),
                          startDay: Date(timeIntervalSince1970: 86_400))
        var t = TaskItem(title: "Run"); t.habit = h
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(TaskItem.self, from: data).habit, h)
        // Old payloads without the key still decode.
        XCTAssertNil(try JSONDecoder().decode(TaskItem.self, from: try JSONEncoder().encode(TaskItem(title: "x"))).habit)
    }

    func testEyeStageThresholds() {
        let expect: [(Int, HabitEyeStage)] = [
            (0, .dormant), (1, .tomoe1), (2, .tomoe1), (3, .tomoe2), (6, .tomoe2), (7, .tomoe3),
            (13, .tomoe3), (14, .mangekyou), (29, .mangekyou), (30, .eternalMangekyou),
            (89, .eternalMangekyou), (90, .rinnegan), (500, .rinnegan)]
        for (n, s) in expect { XCTAssertEqual(HabitEyeStage.stage(forStreak: n), s, "\(n)") }
        XCTAssertNil(HabitEyeStage.dormant.style)
        XCTAssertEqual(HabitEyeStage.tomoe3.style, .classic)
        XCTAssertEqual(HabitEyeStage.rinnegan.style, .rinnegan)
        XCTAssertEqual(HabitEyeStage.mangekyou.awakened, "Mangekyō")
        XCTAssertEqual(HabitEyeStage.eternalMangekyou.awakened, "Eternal Mangekyō")
    }

    func testNextStage() {
        XCTAssertEqual(HabitEyeStage.nextStage(after: 0)?.stage, .tomoe1)
        XCTAssertEqual(HabitEyeStage.nextStage(after: 0)?.unitsToGo, 1)
        XCTAssertEqual(HabitEyeStage.nextStage(after: 10)?.stage, .mangekyou)
        XCTAssertEqual(HabitEyeStage.nextStage(after: 10)?.unitsToGo, 4)
        XCTAssertNil(HabitEyeStage.nextStage(after: 90))
    }
}
