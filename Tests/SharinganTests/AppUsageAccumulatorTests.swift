import Testing
import Foundation
@testable import SharinganCore

@Suite("App usage accumulator")
struct AppUsageAccumulatorTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func creditsTimeBetweenActivations() {
        var acc = AppUsageAccumulator()
        acc.activate(bundleID: "com.a", at: t0)
        acc.activate(bundleID: "com.b", at: t0.addingTimeInterval(60))
        acc.flush(at: t0.addingTimeInterval(90))
        let r = acc.result()
        #expect(r["com.a"] == 60)
        #expect(r["com.b"] == 30)
    }

    @Test func idleStopsCounting() {
        var acc = AppUsageAccumulator()
        acc.activate(bundleID: "com.a", at: t0)
        acc.idle(at: t0.addingTimeInterval(30))          // credits 30 s, parks
        acc.flush(at: t0.addingTimeInterval(120))         // nothing current → no credit
        #expect(acc.result()["com.a"] == 30)
    }

    @Test func nilBundleCountsNothing() {
        var acc = AppUsageAccumulator()
        acc.activate(bundleID: nil, at: t0)
        acc.flush(at: t0.addingTimeInterval(100))
        #expect(acc.result().isEmpty)
    }

    @Test func resumesAfterIdle() {
        var acc = AppUsageAccumulator()
        acc.activate(bundleID: "com.a", at: t0)
        acc.idle(at: t0.addingTimeInterval(10))
        acc.activate(bundleID: "com.a", at: t0.addingTimeInterval(50))
        acc.flush(at: t0.addingTimeInterval(70))
        #expect(acc.result()["com.a"] == 30)              // 10 before idle + 20 after
    }
}
