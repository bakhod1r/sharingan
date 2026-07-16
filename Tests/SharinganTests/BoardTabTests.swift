import Foundation
import Testing
@testable import SharinganCore

@Suite("Board tab")
struct BoardTabTests {

    /// The tab is persisted to `UserDefaults` (`board.tab`), and
    /// `BoardSectionView` restores it via `BoardTab(rawValue:)`. If a case is
    /// renamed, every user silently snaps back to the default — so these exact
    /// strings are a stability contract, not an implementation detail.
    @Test("raw values are the stable persisted strings")
    func rawValuesAreStable() {
        #expect(BoardTab.weekly.rawValue == "weekly")
        #expect(BoardTab.jira.rawValue == "jira")
    }

    @Test("both tabs are present, Weekly before Jira")
    func allCasesInOrder() {
        #expect(BoardTab.allCases == [.weekly, .jira])
    }

    /// A missing / unknown stored value must fall back to Weekly — the exact
    /// path `BoardSectionView` takes when `board.tab` is absent or stale.
    @Test("unknown stored raw value has no case (view defaults to weekly)")
    func unknownRawValueIsNil() {
        #expect(BoardTab(rawValue: "kanban") == nil)
        #expect((BoardTab(rawValue: "kanban") ?? .weekly) == .weekly)
    }

    @Test("a persist round-trip through UserDefaults preserves the tab")
    func roundTripsThroughDefaults() throws {
        let suite = "BoardTabTests.roundTrip"
        let d = try #require(UserDefaults(suiteName: suite))
        d.removePersistentDomain(forName: suite)
        defer { d.removePersistentDomain(forName: suite) }

        d.set(BoardTab.jira.rawValue, forKey: "board.tab")
        let restored = BoardTab(rawValue: d.string(forKey: "board.tab") ?? "")
        #expect(restored == .jira)
    }

    @Test("titles are the segmented-control labels")
    func titlesMatchUI() {
        #expect(BoardTab.weekly.title == "Weekly")
        #expect(BoardTab.jira.title == "Jira")
    }
}
