import Testing
import Foundation
import CoreGraphics
@testable import SharinganCore

@Suite("Notch geometry")
struct NotchGeometryTests {

    /// 14" MacBook Pro, points.
    static let notched = NotchScreenMetrics(screenWidth: 1512, menuBarHeight: 37,
                                            notchWidth: 200, notchHeight: 37)
    /// External / notchless display: no cutout, and therefore no HUD at all.
    static let plain = NotchScreenMetrics(screenWidth: 1920, menuBarHeight: 24,
                                          notchWidth: 0, notchHeight: 0)

    @Test("hardware notch is detected from a non-zero cutout")
    func detectsHardwareNotch() {
        #expect(Self.notched.hasHardwareNotch)
        #expect(!Self.plain.hasHardwareNotch)
    }

    /// The motion layer picks the opening spring or the closing one off this
    /// ordering and nothing else, so the order is the contract: every shape is
    /// ranked, and no two share a rank (a tie would make a real morph read as
    /// "neither growing nor shrinking" and take the closing spring by default).
    @Test("the shapes are strictly ordered by how much room they take")
    func growthRankIsAStrictOrder() {
        let ranks = NotchHUDSize.allCases.map(\.growthRank)
        #expect(Set(ranks).count == NotchHUDSize.allCases.count)

        #expect(NotchHUDSize.hidden.growthRank < NotchHUDSize.idle.growthRank)
        #expect(NotchHUDSize.idle.growthRank < NotchHUDSize.live.growthRank)
        #expect(NotchHUDSize.live.growthRank < NotchHUDSize.activity.growthRank)
        #expect(NotchHUDSize.activity.growthRank < NotchHUDSize.expanded.growthRank)

        // The ordering claims to follow island *area*. Check it actually does on
        // real hardware metrics — `.live` is the widest state but a thin strip,
        // and ranking it above `.activity` would be a lie the springs act on.
        let m = Self.notched
        func area(_ s: NotchHUDSize) -> CGFloat {
            let r = NotchGeometry.layout(m, size: s).island
            return r.width * r.height
        }
        let ordered = NotchHUDSize.allCases.sorted { $0.growthRank < $1.growthRank }
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            #expect(area(a) < area(b))
        }
    }

    /// The radius is a pure function of height so that the drawn shape and the
    /// hit-test mask can be cut from the same number. Two properties matter: it
    /// never moves for the short states (`idle`/`live` are the cutout plus a
    /// lip, and must keep the hardware's own 14pt corner), and it is monotone
    /// and bounded, so no island can ever ask for a corner rounder than half of
    /// itself.
    @Test("the bottom radius grows with the island's height, and stays bounded")
    func cornerRadiusFollowsHeight() {
        let base = Self.notched.notchHeight + NotchGeometry.idleExtraHeight

        // Short states: the notch's own corner, exactly.
        #expect(NotchGeometry.cornerRadius(forHeight: base, baseHeight: base)
                == NotchGeometry.cornerRadius)
        // Shorter than the baseline (a metric we never produce, but the mask
        // must not be asked for a negative interpolation) clamps to the base.
        #expect(NotchGeometry.cornerRadius(forHeight: base - 10, baseHeight: base)
                == NotchGeometry.cornerRadius)
        // The tallest state we draw reaches the top of the ramp.
        #expect(NotchGeometry.cornerRadius(forHeight: NotchGeometry.expandedSize.height,
                                           baseHeight: base)
                == NotchGeometry.maxCornerRadius)

        // Monotone, and never outside [base, max] however tall the island gets.
        var previous = NotchGeometry.cornerRadius
        for h in stride(from: base, through: base + 600, by: 7) {
            let r = NotchGeometry.cornerRadius(forHeight: h, baseHeight: base)
            #expect(r >= previous)
            #expect(r >= NotchGeometry.cornerRadius)
            #expect(r <= NotchGeometry.maxCornerRadius)
            previous = r
        }

        // And the layouts are cut from it: the two short states share the
        // hardware corner, the panel gets the grown one.
        let m = Self.notched
        #expect(NotchGeometry.layout(m, size: .idle).cornerRadius
                == NotchGeometry.cornerRadius)
        #expect(NotchGeometry.layout(m, size: .live).cornerRadius
                == NotchGeometry.cornerRadius)
        #expect(NotchGeometry.layout(m, size: .expanded).cornerRadius
                == NotchGeometry.maxCornerRadius)
        #expect(NotchGeometry.layout(m, size: .activity).cornerRadius
                > NotchGeometry.cornerRadius)
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

    /// The synthetic-notch fallback is gone: a display with no hardware cutout
    /// gets no island, no ears, no track and no panel, in *every* state — and
    /// nothing on it is ever hittable, so the menu bar stays entirely the
    /// menu bar's.
    @Test("a notchless screen has no cutout and no HUD in any state")
    func notchlessScreenHasNoHUD() {
        #expect(Self.plain.cutout == nil)
        #expect(NotchGeometry.panelSize(Self.plain) == .zero)

        for size in NotchHUDSize.allCases {
            let l = NotchGeometry.layout(Self.plain, size: size)
            #expect(l.panelSize == .zero)
            #expect(l.island == .zero)
            #expect(l.island.isEmpty)
            #expect(l.leftEar == nil)
            #expect(l.rightEar == nil)
            #expect(l.progressTrack == nil)
        }
    }

    @Test("a notchless screen is never hittable")
    func notchlessScreenIsNeverHittable() {
        let probes = [CGPoint(x: 0, y: 0), CGPoint(x: 960, y: 0),
                      CGPoint(x: 960, y: 12), CGPoint(x: 960, y: 130),
                      CGPoint(x: 170, y: 4)]
        for size in NotchHUDSize.allCases {
            for p in probes {
                #expect(!NotchGeometry.hitTest(p, metrics: Self.plain, size: size))
            }
        }
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

    /// The island is drawn with rounded *bottom* corners, so the mask has to be
    /// cut from the same silhouette: a point inside the island's rect but
    /// outside its rounded corner is menu bar, not island, and a click there
    /// belongs to whatever is underneath.
    @Test("the rounded bottom corners are not hittable, in live and expanded alike")
    func roundedCornersFallThrough() {
        let m = Self.notched
        let live = NotchGeometry.layout(m, size: .live).island
        let expanded = NotchGeometry.layout(m, size: .expanded).island

        for island in [live, expanded] {
            let inset: CGFloat = 2
            let corners = [CGPoint(x: island.minX + inset, y: island.maxY - inset),
                           CGPoint(x: island.maxX - inset, y: island.maxY - inset)]
            for c in corners {
                #expect(island.contains(c))                 // inside the bare rect …
                #expect(!NotchGeometry.islandPath(in: island,
                                                  cornerRadius: NotchGeometry.cornerRadius)
                    .contains(c))                           // … outside the drawn shape
            }
        }
        #expect(!NotchGeometry.hitTest(CGPoint(x: live.minX + 2, y: live.maxY - 2),
                                       metrics: m, size: .live))
        #expect(!NotchGeometry.hitTest(CGPoint(x: expanded.maxX - 2, y: expanded.maxY - 2),
                                       metrics: m, size: .expanded))
        // The straight part of the bottom edge, between the corners, still is.
        #expect(NotchGeometry.hitTest(CGPoint(x: live.midX, y: live.maxY - 2),
                                      metrics: m, size: .live))
        #expect(NotchGeometry.hitTest(CGPoint(x: expanded.midX, y: expanded.maxY - 2),
                                      metrics: m, size: .expanded))
    }

    /// The expanded island has to be tall enough for what the panel puts in it —
    /// the timer row, `NotchTaskRows.defaultLimit` task rows, the quick actions
    /// and the status strip — or the `.clipShape` crops the bottom off. A
    /// SwiftUI replica of the panel measures 286pt at five rows (see the notch
    /// report); the island must not be shorter than that.
    @Test("the expanded island fits the panel's full content")
    func expandedIslandFitsItsContent() {
        #expect(NotchGeometry.expandedSize.height >= 286)
        let expanded = NotchGeometry.layout(Self.notched, size: .expanded)
        #expect(expanded.island.height == NotchGeometry.expandedSize.height)
        #expect(expanded.panelSize.height >= expanded.island.height)
    }
}
