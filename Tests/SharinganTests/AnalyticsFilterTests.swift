import Testing
import Foundation
@testable import SharinganCore

@Suite("Analytics filter")
struct AnalyticsFilterTests {
    private let cal = Calendar.current

    // MARK: Preset range

    @Test func presetSpanDaysMatchesRange() {
        #expect(AnalyticsFilter(range: .today).spanDays == 1)
        #expect(AnalyticsFilter(range: .week).spanDays == 7)
        #expect(AnalyticsFilter(range: .year).spanDays == 365)
    }

    @Test func presetIntervalCountsBackFromNow() {
        let now = Date()
        let f = AnalyticsFilter(range: .week)
        let iv = f.interval(now: now)
        let startDay = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: now)!)
        #expect(iv.start == startDay)
        #expect(iv.end == now)
    }

    @Test func notCustomWithoutBothEnds() {
        var f = AnalyticsFilter(range: .month)
        f.customStart = Date()
        #expect(!f.isCustomRange)          // only one end set
        #expect(f.spanDays == 30)          // falls back to preset
    }

    // MARK: Custom calendar range

    @Test func customRangeSpanIsInclusive() {
        let start = cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let end = cal.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let f = AnalyticsFilter(range: .today, customStart: start, customEnd: end)
        #expect(f.isCustomRange)
        #expect(f.spanDays == 10)          // 1st…10th inclusive
    }

    @Test func customIntervalCoversEndDay() {
        let start = cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let end = cal.date(from: DateComponents(year: 2026, month: 3, day: 3))!
        let iv = AnalyticsFilter(customStart: start, customEnd: end).interval()
        // A session at 23:00 on the end day must fall inside the window.
        let lateEndDay = cal.date(bySettingHour: 23, minute: 0, second: 0, of: end)!
        #expect(iv.contains(lateEndDay))
        #expect(iv.contains(cal.startOfDay(for: start)))
    }

    @Test func customRangeToleratesReversedDates() {
        let a = cal.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let b = cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        // from > to: still resolves to the same 10-day inclusive span.
        let f = AnalyticsFilter(customStart: a, customEnd: b)
        #expect(f.spanDays == 10)
        #expect(f.interval().start == cal.startOfDay(for: b))
    }

    @Test func heatmapSpanFlooredAndCapped() {
        #expect(AnalyticsFilter(range: .today).heatmapSpanDays == 28)   // floored
        #expect(AnalyticsFilter(range: .year).heatmapSpanDays == 364)   // capped
    }

    // MARK: Device facet

    @Test func deviceFilterFlags() {
        var f = AnalyticsFilter()
        #expect(!f.hasDeviceFilter)
        #expect(!f.narrowsSessions)
        f.devices = ["MacBook Pro"]
        #expect(f.hasDeviceFilter)
        #expect(f.narrowsSessions)         // a device filter narrows the set
    }
}

@Suite("Device identity")
struct DeviceIdentityTests {
    @Test func prefersLocalizedName() {
        #expect(DeviceIdentity.resolveName(localized: "Bakhodir's MacBook Pro",
                                           hostName: "whatever.local")
                == "Bakhodir's MacBook Pro")
    }
    @Test func fallsBackToHostNameTrimmed() {
        #expect(DeviceIdentity.resolveName(localized: nil,
                                           hostName: "Bakhodirs-MacBook-Pro.local")
                == "Bakhodirs-MacBook-Pro")
    }
    @Test func emptyLocalizedIsIgnored() {
        #expect(DeviceIdentity.resolveName(localized: "  ", hostName: "host.lan") == "host")
    }
    @Test func neverEmpty() {
        #expect(DeviceIdentity.resolveName(localized: nil, hostName: "") == "Mac")
    }
}
