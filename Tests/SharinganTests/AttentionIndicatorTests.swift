import Testing
import Foundation
import CloudKit
@testable import SharinganCore

@Suite("Attention indicator mapping")
struct AttentionIndicatorTests {
    @Test func hiddenWhenNotEngaged() {
        #expect(AttentionIndicator.from(state: .attentive, isEngaged: false) == .hidden)
        #expect(AttentionIndicator.from(state: .away(since: Date()), isEngaged: false) == .hidden)
    }

    @Test func mapsStates() {
        let d = Date()
        #expect(AttentionIndicator.from(state: .attentive, isEngaged: true) == .onScreen)
        #expect(AttentionIndicator.from(state: .drifting(since: d), isEngaged: true) == .drifting)
        #expect(AttentionIndicator.from(state: .away(since: d), isEngaged: true) == .distracted)
        #expect(AttentionIndicator.from(state: .noFace(since: d), isEngaged: true) == .distracted)
    }

    @Test func labels() {
        #expect(AttentionIndicator.onScreen.label == "On screen")
        #expect(AttentionIndicator.drifting.label == "…")
        #expect(AttentionIndicator.distracted.label == "Distracted")
        #expect(AttentionIndicator.hidden.label == "")
    }
}

@Suite("Away stats aggregation")
struct AwayStatsTests {
    private func rec(_ ev: Int?, _ sec: Double?) -> SessionRecord {
        var r = SessionRecord(start: Date(timeIntervalSince1970: 0),
                              end: Date(timeIntervalSince1970: 1500),
                              phase: .focus, completed: true, plannedSeconds: 1500)
        r.attentionAwayEvents = ev
        r.attentionAwaySeconds = sec
        return r
    }

    @Test func nilWhenNoneTracked() {
        #expect(AnalyticsEngine.awayTotals(sessions: [rec(nil, nil), rec(nil, nil)]) == nil)
        #expect(AnalyticsEngine.awayTotals(sessions: []) == nil)
    }

    @Test func sumsTrackedOnly() {
        let t = AnalyticsEngine.awayTotals(sessions: [rec(2, 90), rec(nil, nil), rec(0, 0), rec(1, 30)])
        #expect(t?.events == 3)
        #expect(t?.seconds == 120)
    }

    @Test func codableRoundTripAndLegacyDecode() throws {
        let r = rec(3, 42)
        let back = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(r))
        #expect(back.attentionAwayEvents == 3)
        #expect(back.attentionAwaySeconds == 42)
        let legacy = try JSONDecoder().decode(SessionRecord.self,
            from: Data(#"{"start":0,"end":60}"#.utf8))
        #expect(legacy.attentionAwayEvents == nil)
        #expect(legacy.attentionAwaySeconds == nil)
    }

    @Test func syncRoundTrip() throws {
        let zone = CKRecordZone.ID(zoneName: "SharinganData", ownerName: CKCurrentUserDefaultName)
        let r = rec(2, 75)
        let ck = RecordMapper.record(for: r, in: zone, systemFields: nil)
        let back = try #require(RecordMapper.sessionRecord(from: ck))
        #expect(back.attentionAwayEvents == 2)
        #expect(back.attentionAwaySeconds == 75)
        let plain = rec(nil, nil)
        let back2 = try #require(RecordMapper.sessionRecord(
            from: RecordMapper.record(for: plain, in: zone, systemFields: nil)))
        #expect(back2.attentionAwayEvents == nil)
    }
}
