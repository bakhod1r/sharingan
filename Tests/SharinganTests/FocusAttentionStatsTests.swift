import Testing
import Foundation
@testable import SharinganCore

@MainActor
private final class StatsSource: AttentionSampleSource {
    func start(onSample: @escaping @MainActor (AttentionSample) -> Void) {}
    func stop() {}
}

@MainActor
private final class StatsPresenter: AttentionAlertPresenter {
    func showAttentionAlert(state: AttentionState, taskTitle: String?) {}
    func hideAttentionAlert() {}
}

@MainActor
@Suite("Focus attention away stats", .serialized)
struct FocusAttentionStatsTests {
    private let t0 = Date(timeIntervalSince1970: 3_000_000)

    private func rig() -> FocusAttentionService {
        let s = FocusAttentionService(source: StatsSource())
        s.presenter = StatsPresenter()
        s.engage(policy: AttentionPolicy())
        return s
    }

    private func feed(_ s: FocusAttentionService, from: Double, to: Double, away: Bool) {
        var t = from
        while t <= to + 1e-9 {
            s.now = { [t0] in t0.addingTimeInterval(t) }
            s.ingest(AttentionSample(faceDetected: true, yaw: away ? 60 : 0,
                                     at: t0.addingTimeInterval(t)))
            t += 0.1
        }
    }

    @Test func freshServiceHasNoStats() {
        let s = rig()
        let r = s.takeSessionStats()
        #expect(r.events == 0)
        #expect(r.seconds == 0)
        #expect(!s.wasEngagedThisSession)
    }

    @Test func oneLapseCountsEventAndSeconds() {
        let s = rig()
        feed(s, from: 0, to: 3, away: true)
        feed(s, from: 3.1, to: 4.5, away: false)
        let r = s.takeSessionStats()
        #expect(r.events == 1)
        #expect(r.seconds > 0.5 && r.seconds < 3.5)
    }

    @Test func twoLapsCountTwo() {
        let s = rig()
        feed(s, from: 0, to: 3, away: true)
        feed(s, from: 3.1, to: 5, away: false)
        feed(s, from: 5.1, to: 8, away: true)
        feed(s, from: 8.1, to: 10, away: false)
        #expect(s.takeSessionStats().events == 2)
    }

    @Test func releaseClosesOpenAlertAndStatsSurvive() {
        let s = rig()
        feed(s, from: 0, to: 3, away: true)
        s.now = { [t0] in t0.addingTimeInterval(13) }
        s.release()
        let r = s.takeSessionStats()
        #expect(r.events == 1)
        #expect(r.seconds > 10)
    }

    @Test func takeResets() {
        let s = rig()
        feed(s, from: 0, to: 3, away: true)
        _ = s.takeSessionStats()
        let r = s.takeSessionStats()
        #expect(r.events == 0)
        #expect(r.seconds == 0)
        #expect(!s.wasEngagedThisSession)
    }

    @Test func engageAfterReleaseKeepsUntaken() {
        // A manual pause releases the guard mid-session; resuming re-engages.
        let s = rig()
        feed(s, from: 0, to: 3, away: true)
        s.release()
        s.engage(policy: AttentionPolicy())
        #expect(s.takeSessionStats().events == 1)
    }

    @Test func wasEngagedFlag() {
        let s = rig()
        #expect(s.wasEngagedThisSession)
    }
}
