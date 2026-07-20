import Testing
import Foundation

/// Regression coverage for the 1.10.1 board-scroll fix.
///
/// The Kanban and Weekly boards each wrapped their columns in a *horizontal*
/// scroll view only, and every column grew from a fixed `minHeight` with no
/// upper bound — so once a column held more cards than fit on screen the
/// overflow was clipped and could not be reached by any gesture.
///
/// The fix is pure SwiftUI layout: there is no state or function to exercise,
/// and a `ScrollView`'s scrolling cannot be driven from a unit test. What
/// *can* regress silently is someone removing the per-column scroll view or
/// restoring the unbounded height while refactoring, which is exactly the
/// shape of the original bug. These tests pin the source instead of the
/// behavior — a weaker guarantee, deliberately chosen over no guard at all.
@Suite("Board column scrolling")
struct BoardColumnScrollTests {

    /// Repo root, derived from this file's location.
    private static let viewsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SharinganTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("Sources/Sharingan/Views")

    private func source(_ name: String) throws -> String {
        let url = Self.viewsDir.appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func kanbanColumnScrollsItsCards() throws {
        let src = try source("SharinganBoardView.swift")
        #expect(src.contains("ScrollView(.vertical"),
                "Kanban columns must scroll their cards vertically")
        #expect(src.contains("maxHeight: .infinity, alignment: .top"),
                "Kanban columns must fill the board height, not grow past it")
    }

    @Test func weeklyColumnScrollsItsCards() throws {
        let src = try source("WeeklyBoardView.swift")
        #expect(src.contains("ScrollView(.vertical"),
                "Weekly columns must scroll their cards vertically")
        #expect(src.contains("maxHeight: .infinity, alignment: .top"),
                "Weekly columns must fill the board height, not grow past it")
    }

    /// The bug was an *unbounded* `minHeight`, not the `minHeight` itself —
    /// columns still keep a floor so an empty board doesn't collapse. This
    /// pins that the floor is always paired with a ceiling.
    @Test func columnMinHeightIsAlwaysPairedWithAMaxHeight() throws {
        for file in ["SharinganBoardView.swift", "WeeklyBoardView.swift"] {
            let src = try source(file)
            #expect(!src.contains("minHeight: 440, alignment:"),
                    "\(file): minHeight without maxHeight reintroduces the clipping bug")
        }
    }

    /// Timeline was never affected — it scrolls its whole canvas instead of
    /// per column. Pinned so a future "consistency" refactor doesn't quietly
    /// drop it.
    @Test func timelineKeepsItsCanvasScroll() throws {
        let src = try source("TimelineBoardView.swift")
        #expect(src.contains("ScrollView(.vertical"),
                "Timeline must keep its vertical canvas scroll")
    }
}
