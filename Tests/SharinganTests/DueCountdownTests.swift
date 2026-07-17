import XCTest
@testable import SharinganCore

/// `DueDate.countdown` is what task rows and board cards render for a deadline,
/// so its wording and its date-only rule are pinned here.
final class DueCountdownTests: XCTestCase {
    private let cal = Calendar.current
    private lazy var now = cal.date(from: DateComponents(year: 2026, month: 7, day: 17,
                                                         hour: 12, minute: 0))!

    private func due(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 7, day: day,
                                      hour: hour, minute: minute))!
    }

    func testCoarsestTwoUnitsOnly() {
        // 3 days and 4 hours out — minutes are not appended once days are shown.
        XCTAssertEqual(DueDate.countdown(to: due(20, 16, 30), now: now), "3d 4h left")
        XCTAssertEqual(DueDate.countdown(to: due(17, 14, 15), now: now), "2h 15m left")
        XCTAssertEqual(DueDate.countdown(to: due(17, 12, 8), now: now), "8m left")
    }

    func testWholeUnitsDropTheSecondUnit() {
        XCTAssertEqual(DueDate.countdown(to: due(19, 12), now: now), "2d left")
        XCTAssertEqual(DueDate.countdown(to: due(17, 15), now: now), "3h left")
    }

    func testPastDeadlineCountsUp() {
        XCTAssertEqual(DueDate.countdown(to: due(15, 12), now: now), "2d late")
        XCTAssertEqual(DueDate.countdown(to: due(17, 9, 30), now: now), "2h 30m late")
    }

    func testTheDeadlineMinuteItself() {
        XCTAssertEqual(DueDate.countdown(to: due(17, 12), now: now), "due now")
        XCTAssertEqual(DueDate.countdown(to: now.addingTimeInterval(-30), now: now), "just late")
    }

    /// A date-only due expires at the END of its day — the same rule
    /// `TaskItem.isOverdue()` follows. Today's date-only deadline must read as
    /// time remaining, never as late.
    func testDateOnlyDueExpiresAtEndOfItsDay() {
        XCTAssertEqual(DueDate.countdown(to: due(17, 0), now: now), "12h left")
        XCTAssertEqual(DueDate.countdown(to: due(16, 0), now: now), "12h late")
    }

    /// A due carrying a real time of day is taken at face value, not stretched
    /// to the end of its day.
    func testTimedDueIsNotStretched() {
        XCTAssertEqual(DueDate.countdown(to: due(17, 18), now: now), "6h left")
    }

    func testCountdownAgreesWithIsOverdue() {
        for candidate in [due(15, 12), due(16, 0), due(17, 0), due(17, 18), due(20, 16)] {
            let task = TaskItem(title: "t", dueDate: candidate)
            XCTAssertEqual(DueDate.countdown(to: candidate, now: now).hasSuffix("late"),
                           task.isOverdue(now: now),
                           "countdown and isOverdue disagree for \(candidate)")
        }
    }
}
