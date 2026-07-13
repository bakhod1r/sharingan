import Testing
import Foundation
import CoreGraphics
@testable import SharinganCore

@Suite("Notch geometry")
struct NotchGeometryTests {

    /// 14" MacBook Pro, points.
    static let notched = NotchScreenMetrics(screenWidth: 1512, menuBarHeight: 37,
                                            notchWidth: 200, notchHeight: 37)
    /// External / notchless display: synthetic notch.
    static let plain = NotchScreenMetrics(screenWidth: 1920, menuBarHeight: 24,
                                          notchWidth: 0, notchHeight: 0)

    @Test("hardware notch is detected from a non-zero cutout")
    func detectsHardwareNotch() {
        #expect(Self.notched.hasHardwareNotch)
        #expect(!Self.plain.hasHardwareNotch)
    }

    @Test("the panel is always big enough for the largest state")
    func panelCoversExpanded() {
        for size in NotchHUDSize.allCases {
            let l = NotchGeometry.layout(Self.notched, size: size)
            #expect(l.panelSize.width >= NotchGeometry.expandedSize.width)
            #expect(l.panelSize.height >= NotchGeometry.expandedSize.height)
            // and every drawn rect stays inside the panel
            #expect(l.island.maxX <= l.panelSize.width + 0.01)
            #expect(l.island.maxY <= l.panelSize.height + 0.01)
            #expect(l.island.minX >= -0.01)
            #expect(l.island.minY >= -0.01)
        }
    }

    @Test("the island is centered on the notch and grows downward only")
    func islandCentered() {
        let idle = NotchGeometry.layout(Self.notched, size: .idle)
        let expanded = NotchGeometry.layout(Self.notched, size: .expanded)
        #expect(abs(idle.island.midX - idle.panelSize.width / 2) < 0.01)
        #expect(abs(expanded.island.midX - expanded.panelSize.width / 2) < 0.01)
        // top edge is pinned to the screen top in every state
        #expect(idle.island.minY == 0)
        #expect(expanded.island.minY == 0)
        // expanded is strictly taller and wider
        #expect(expanded.island.height > idle.island.height)
        #expect(expanded.island.width > idle.island.width)
    }

    @Test("idle is the notch plus a small lip")
    func idleHugsNotch() {
        let idle = NotchGeometry.layout(Self.notched, size: .idle)
        #expect(idle.island.width == Self.notched.notchWidth)
        #expect(idle.island.height == Self.notched.notchHeight + NotchGeometry.idleExtraHeight)
        #expect(idle.leftEar == nil)
        #expect(idle.rightEar == nil)
    }

    @Test("live grows ears on both sides of the cutout without covering it")
    func liveEarsFlankTheNotch() throws {
        let live = NotchGeometry.layout(Self.notched, size: .live)
        let left = try #require(live.leftEar)
        let right = try #require(live.rightEar)
        let cutoutMinX = live.panelSize.width / 2 - Self.notched.notchWidth / 2
        let cutoutMaxX = live.panelSize.width / 2 + Self.notched.notchWidth / 2
        #expect(left.maxX <= cutoutMinX + 0.01)
        #expect(right.minX >= cutoutMaxX - 0.01)
        #expect(left.width == NotchGeometry.earWidth)
        #expect(right.width == NotchGeometry.earWidth)
        // ears live in the menu bar row
        #expect(left.maxY <= Self.notched.notchHeight + 0.01)
    }

    @Test("the progress track spans the island's bottom edge while live")
    func progressTrackSpansIsland() throws {
        let live = NotchGeometry.layout(Self.notched, size: .live)
        let track = try #require(live.progressTrack)
        #expect(track.width == live.island.width)
        #expect(track.maxY <= live.island.maxY + 0.01)
        #expect(track.height > 0)
        #expect(NotchGeometry.layout(Self.notched, size: .idle).progressTrack == nil)
    }

    @Test("a notchless screen gets a synthetic cutout of the fallback width")
    func syntheticNotch() {
        let idle = NotchGeometry.layout(Self.plain, size: .idle)
        #expect(idle.island.width == NotchGeometry.syntheticNotchWidth)
        #expect(idle.island.height == Self.plain.menuBarHeight + NotchGeometry.idleExtraHeight)
    }

    @Test("hidden draws nothing")
    func hiddenIsEmpty() {
        let l = NotchGeometry.layout(Self.notched, size: .hidden)
        #expect(l.island.isEmpty)
        #expect(l.leftEar == nil)
        #expect(l.rightEar == nil)
        #expect(l.progressTrack == nil)
    }

    @Test("hit testing is limited to the rendered shape")
    func hitTestMasksToShape() {
        let m = Self.notched
        let idle = NotchGeometry.layout(m, size: .idle)
        let panelWidth = idle.panelSize.width
        let center = CGPoint(x: panelWidth / 2, y: 4)
        let sideMargin = CGPoint(x: 2, y: 4)          // beside the idle island
        let below = CGPoint(x: panelWidth / 2, y: 200) // under the idle island

        // Idle: only the small lip over the cutout is hittable.
        #expect(NotchGeometry.hitTest(center, metrics: m, size: .idle))
        #expect(!NotchGeometry.hitTest(sideMargin, metrics: m, size: .idle))
        #expect(!NotchGeometry.hitTest(below, metrics: m, size: .idle))

        // Live: the ears reach the panel's edges, so the menu-bar row across
        // the island IS hittable — that is the documented cost of the ears.
        // Everything below the island still falls through.
        let earPoint = CGPoint(x: panelWidth / 2 - m.notchWidth / 2 - 10, y: 10)
        #expect(NotchGeometry.hitTest(earPoint, metrics: m, size: .live))
        #expect(!NotchGeometry.hitTest(below, metrics: m, size: .live))

        // Expanded: the panel body is hittable, its side margins are not.
        #expect(NotchGeometry.hitTest(below, metrics: m, size: .expanded))
        #expect(!NotchGeometry.hitTest(CGPoint(x: 2, y: 200), metrics: m, size: .expanded))

        // Hidden is never hittable.
        #expect(!NotchGeometry.hitTest(center, metrics: m, size: .hidden))
    }
}
