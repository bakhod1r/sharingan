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
    static let cutout = CGSize(width: 200, height: 37)

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
        let tallest = NotchGeometry.expandedSize(cutout: Self.cutout).height

        // Short states: the notch's own corner, exactly.
        #expect(NotchGeometry.cornerRadius(forHeight: base, baseHeight: base,
                                           maxHeight: tallest)
                == NotchGeometry.cornerRadius)
        // Shorter than the baseline (a metric we never produce, but the mask
        // must not be asked for a negative interpolation) clamps to the base.
        #expect(NotchGeometry.cornerRadius(forHeight: base - 10, baseHeight: base,
                                           maxHeight: tallest)
                == NotchGeometry.cornerRadius)
        // The tallest state we draw reaches the top of the ramp.
        #expect(NotchGeometry.cornerRadius(forHeight: tallest, baseHeight: base,
                                           maxHeight: tallest)
                == NotchGeometry.maxCornerRadius)

        // Monotone, and never outside [base, max] however tall the island gets.
        var previous = NotchGeometry.cornerRadius
        for h in stride(from: base, through: base + 600, by: 7) {
            let r = NotchGeometry.cornerRadius(forHeight: h, baseHeight: base,
                                               maxHeight: tallest)
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
        let expanded = NotchGeometry.expandedSize(cutout: Self.cutout)
        for size in NotchHUDSize.allCases {
            let l = NotchGeometry.layout(Self.notched, size: size)
            #expect(l.panelSize.width >= expanded.width)
            #expect(l.panelSize.height >= expanded.height)
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

    /// The metrics a `NotchHUDModel` carries *before anyone tells it about a
    /// screen* — `NotchScreenMetrics.none`. The default has to be the safe
    /// answer, because the hit-test mask is cut from these numbers: a plausible
    /// 14"-MacBook-Pro fixture as the default would have any path that drew the
    /// island before `refresh()` ran claim a 200×37 cutout that may not exist.
    @Test("the unwritten default metrics claim no notch, and nothing hittable")
    func defaultMetricsAreNoNotch() {
        let m = NotchScreenMetrics.none
        #expect(!m.hasHardwareNotch)
        #expect(m.cutout == nil)
        #expect(NotchGeometry.panelSize(m) == .zero)
        for size in NotchHUDSize.allCases {
            #expect(NotchGeometry.layout(m, size: size).island.isEmpty)
            #expect(!NotchGeometry.hitTest(CGPoint(x: 0, y: 0), metrics: m, size: size))
            #expect(!NotchGeometry.hitTest(CGPoint(x: 100, y: 10), metrics: m, size: size))
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
    /// SwiftUI replica of the panel measures 321pt at five rows (286 before the
    /// rows grew the subtask badge and the pomodoro ring); the island must not be
    /// shorter than that.
    @Test("the expanded island fits the panel's full content")
    func expandedIslandFitsItsContent() {
        #expect(NotchGeometry.expandedSize(cutout: Self.cutout).height >= 321)
        let expanded = NotchGeometry.layout(Self.notched, size: .expanded)
        #expect(expanded.island.height
                == NotchGeometry.expandedSize(cutout: Self.cutout).height)
        #expect(expanded.panelSize.height >= expanded.island.height)
    }
}

/// The expanded island is sized from the config, not from a constant: a panel
/// with sections switched off must not hang the same slab of black over the
/// screen as a full one.
///
/// Every number these tests pin comes from measuring a structural SwiftUI
/// replica of `NotchExpandedPanel` at the island's real 340pt width and reading
/// `fittingSize` — see the notch settings report for the table. They are the
/// contract: too small clips the content at the `.clipShape` (the bug this
/// feature already shipped once), too large paints dead black over the desktop.
@Suite("Notch expanded sizing")
struct NotchExpandedSizingTests {
    static let cutout = CGSize(width: 200, height: 37)
    static let metrics = NotchScreenMetrics(screenWidth: 1512, menuBarHeight: 37,
                                            notchWidth: 200, notchHeight: 37)

    /// The measured body heights (top padding excluded), from the replica.
    @Test("the body height matches the measured replica for the shipped config")
    func bodyMatchesMeasurement() {
        // Replica: five rows, every section on → 278pt of body, 321pt of island
        // over a 37pt cutout. The geometry adds `bodySlack` on top, and nothing
        // else. (243/286 before the rows grew the subtask badge and the ring.)
        let full = NotchContentConfig.default
        #expect(NotchGeometry.expandedBodyHeight(full)
                == 278 + NotchGeometry.bodySlack)
        #expect(NotchGeometry.expandedSize(full, cutout: Self.cutout).height
                == 321 + NotchGeometry.bodySlack)

        // Replica: three rows, every section on → 218pt of body.
        var three = full
        three.taskRows = 3
        #expect(NotchGeometry.expandedBodyHeight(three) == 218 + NotchGeometry.bodySlack)

        // Replica: tasks only, five rows → 166pt of body.
        let tasksOnly = NotchContentConfig(showTimerControls: false, showTasks: true,
                                           showQuickActions: false,
                                           showStatusStrip: false, taskRows: 5)
        #expect(NotchGeometry.expandedBodyHeight(tasksOnly) == 166 + NotchGeometry.bodySlack)

        // Replica: timer row only → 69pt of body.
        let timerOnly = NotchContentConfig(showTimerControls: true, showTasks: false,
                                           showQuickActions: false, showStatusStrip: false)
        #expect(NotchGeometry.expandedBodyHeight(timerOnly) == 69 + NotchGeometry.bodySlack)

        // Replica: timer + quick actions, no tasks, no strip → 101pt of body.
        let noTasks = NotchContentConfig(showTimerControls: true, showTasks: false,
                                         showQuickActions: true, showStatusStrip: false)
        #expect(NotchGeometry.expandedBodyHeight(noTasks) == 101 + NotchGeometry.bodySlack)
    }

    @Test("switching a section off makes the island materially shorter")
    func sectionsShrinkTheIsland() {
        let full = NotchContentConfig.default
        let fullH = NotchGeometry.expandedSize(full, cutout: Self.cutout).height

        for keyPath: WritableKeyPath<NotchContentConfig, Bool> in [
            \.showTimerControls, \.showTasks, \.showQuickActions, \.showStatusStrip
        ] {
            var c = full
            c[keyPath: keyPath] = false
            let h = NotchGeometry.expandedSize(c, cutout: Self.cutout).height
            // Every section costs at least its own height plus the stack gap it
            // takes: nothing here is free, so nothing may shrink by nothing.
            #expect(h < fullH)
        }

        var bare = full
        bare.showTimerControls = false
        bare.showTasks = false
        bare.showQuickActions = false
        bare.showStatusStrip = false
        let bareH = NotchGeometry.expandedSize(bare, cutout: Self.cutout).height
        // Every section off is not "a bit shorter", it is a different island:
        // less than half the full one, i.e. no 300pt slab over an empty panel.
        #expect(bareH < fullH / 2)
    }

    @Test("more task rows make a taller island, monotonically")
    func rowsGrowTheIsland() {
        var heights: [CGFloat] = []
        for rows in NotchContentConfig.taskRowRange {
            var c = NotchContentConfig.default
            c.taskRows = rows
            heights.append(NotchGeometry.expandedSize(c, cutout: Self.cutout).height)
        }
        for (a, b) in zip(heights, heights.dropFirst()) {
            #expect(b > a)
            // One row is the measured 30pt (a 28pt row plus the list's 2pt gap).
            #expect(b - a == NotchGeometry.taskRowHeight + NotchGeometry.taskRowSpacing)
        }
        // Five rows against three: 60pt (218 → 278 of body), measured.
        #expect(heights.last! - heights.first! == 60)
        // …and rows cost nothing at all when the task list is off.
        var off = NotchContentConfig.default
        off.showTasks = false
        var off3 = off
        off3.taskRows = 3
        #expect(NotchGeometry.expandedSize(off, cutout: Self.cutout)
                == NotchGeometry.expandedSize(off3, cutout: Self.cutout))
    }

    /// The floor is not arbitrary: the motion layer springs a morph on
    /// `growthRank`, which claims `.expanded` is bigger than `.activity`. An
    /// island sized from an all-off config would be 57pt tall and make that a
    /// lie, so the expanded island never goes under the announcement's height.
    @Test("the island never shrinks below the cutout plus a minimum")
    func heightHasAFloor() {
        let bare = NotchContentConfig(showTimerControls: false, showTasks: false,
                                      showQuickActions: false, showStatusStrip: false)
        let h = NotchGeometry.expandedSize(bare, cutout: Self.cutout).height
        #expect(h >= NotchGeometry.activitySize.height)
        #expect(h > Self.cutout.height + NotchGeometry.idleExtraHeight)

        // …and it is still an ordered morph for every config: the expanded
        // island outranks every shorter state, whatever the user switched off.
        var m = Self.metrics
        for cfg in [bare, .default] {
            for cutoutHeight in [CGFloat(32), 37, 44] {
                m.notchHeight = cutoutHeight
                let expanded = NotchGeometry.layout(m, size: .expanded, config: cfg).island
                let idle = NotchGeometry.layout(m, size: .idle, config: cfg).island
                let activity = NotchGeometry.layout(m, size: .activity, config: cfg).island
                #expect(expanded.width * expanded.height > activity.width * activity.height)
                #expect(expanded.width * expanded.height > idle.width * idle.height)
            }
        }
    }

    /// The panel is the union of every state, so it has to grow with whatever
    /// the config made the expanded island — and the island has to stay inside
    /// it, or the `.clipShape` crops the panel's own content.
    @Test("the panel still covers the island for every config")
    func panelCoversEveryConfig() {
        for ears in NotchEarsMode.allCases {
            for rows in NotchContentConfig.taskRowRange {
                for tasks in [true, false] {
                    let c = NotchContentConfig(ears: ears, showTimerControls: true,
                                               showTasks: tasks, showQuickActions: true,
                                               showStatusStrip: true, taskRows: rows)
                    for size in NotchHUDSize.allCases {
                        let l = NotchGeometry.layout(Self.metrics, size: size, config: c)
                        #expect(l.island.maxX <= l.panelSize.width + 0.01)
                        #expect(l.island.maxY <= l.panelSize.height + 0.01)
                        #expect(l.island.minX >= -0.01)
                    }
                }
            }
        }
    }

    /// The island is the panel's frame, and the panel's content is laid out to
    /// it — so if `.expanded` is drawn at a height the settings did not ask for,
    /// the content is either clipped or floating in black. It must be exactly
    /// the configured size.
    @Test("the expanded layout is cut from the configured size")
    func layoutUsesTheConfiguredSize() {
        var c = NotchContentConfig.default
        c.showTasks = false
        c.showStatusStrip = false
        let expected = NotchGeometry.expandedSize(c, cutout: Self.cutout)
        let l = NotchGeometry.layout(Self.metrics, size: .expanded, config: c)
        #expect(l.island.size == expected)
        // …and the mask follows it: a point just under the shortened island is
        // menu bar / desktop again, not HUD.
        let below = CGPoint(x: l.panelSize.width / 2, y: expected.height + 6)
        #expect(!NotchGeometry.hitTest(below, metrics: Self.metrics, size: .expanded, config: c))
        // With everything on, the same point is inside the taller island.
        #expect(NotchGeometry.hitTest(below, metrics: Self.metrics, size: .expanded,
                                      config: .default))
    }
}

/// The ears mode is not a label switch: it changes the island's silhouette, and
/// therefore how much of the menu bar the HUD can swallow. The drawn shape and
/// the hit-test mask are cut from one layout, so these tests pin both at once.
@Suite("Notch ears")
struct NotchEarsGeometryTests {
    static let m = NotchScreenMetrics(screenWidth: 1512, menuBarHeight: 37,
                                      notchWidth: 200, notchHeight: 37)

    private static func config(_ ears: NotchEarsMode) -> NotchContentConfig {
        var c = NotchContentConfig.default
        c.ears = ears
        return c
    }

    @Test("the live island is exactly as wide as the ears it grows")
    func islandWidthFollowsEars() throws {
        let ear = NotchGeometry.earWidth
        let cutoutW = Self.m.notchWidth

        let both = NotchGeometry.layout(Self.m, size: .live, config: Self.config(.both))
        #expect(both.island.width == cutoutW + 2 * ear)
        #expect(both.leftEar != nil)
        #expect(both.rightEar != nil)

        let right = NotchGeometry.layout(Self.m, size: .live, config: Self.config(.trailingOnly))
        #expect(right.island.width == cutoutW + ear)
        #expect(right.leftEar == nil)
        #expect(right.rightEar != nil)

        let none = NotchGeometry.layout(Self.m, size: .live, config: Self.config(.none))
        #expect(none.island.width == cutoutW)
        #expect(none.leftEar == nil)
        #expect(none.rightEar == nil)
        // The progress line survives every mode — it is the one thing "Progress
        // bar only" still shows.
        for mode in NotchEarsMode.allCases {
            let l = NotchGeometry.layout(Self.m, size: .live, config: Self.config(mode))
            let track = try #require(l.progressTrack)
            #expect(track.width == l.island.width)
            #expect(track.maxY <= l.island.maxY + 0.01)
        }
    }

    /// Whatever the mode, the black has to stay glued to the hardware cutout —
    /// a one-eared island *centered* on the panel would slide the cutout off
    /// centre and paint the island half a notch away from the camera housing.
    @Test("the island always covers the cutout, whichever ears are dropped")
    func islandStaysOnTheCutout() {
        for mode in NotchEarsMode.allCases {
            let l = NotchGeometry.layout(Self.m, size: .live, config: Self.config(mode))
            let cutoutMinX = l.panelSize.width / 2 - Self.m.notchWidth / 2
            let cutoutMaxX = l.panelSize.width / 2 + Self.m.notchWidth / 2
            #expect(l.island.minX <= cutoutMinX + 0.01)
            #expect(l.island.maxX >= cutoutMaxX - 0.01)
            #expect(l.island.minY == 0)
        }
    }

    /// The whole point of the setting: dropping an ear must stop the HUD
    /// covering that menu-bar real estate, not merely hide the label on top of
    /// it. The mask is cut from the same layout the shape is drawn from, so a
    /// point in the suppressed ear falls through to the menu bar.
    @Test("a suppressed ear is no longer hittable")
    func suppressedEarsFallThrough() {
        let panelW = NotchGeometry.panelSize(Self.m, config: Self.config(.both)).width
        let cutoutMinX = panelW / 2 - Self.m.notchWidth / 2
        let cutoutMaxX = panelW / 2 + Self.m.notchWidth / 2
        // Dead centre of each ear, in the menu bar row.
        let leftEar = CGPoint(x: cutoutMinX - NotchGeometry.earWidth / 2, y: 10)
        let rightEar = CGPoint(x: cutoutMaxX + NotchGeometry.earWidth / 2, y: 10)
        let overCutout = CGPoint(x: panelW / 2, y: 10)

        func hit(_ p: CGPoint, _ mode: NotchEarsMode) -> Bool {
            NotchGeometry.hitTest(p, metrics: Self.m, size: .live, config: Self.config(mode))
        }

        // Both: the documented cost — both ears are live HUD.
        #expect(hit(leftEar, .both))
        #expect(hit(rightEar, .both))

        // Right only: the left ear's pixels are the menu bar's again.
        #expect(!hit(leftEar, .trailingOnly))
        #expect(hit(rightEar, .trailingOnly))

        // Progress bar only: both ears fall through; only the cutout is HUD,
        // and the cutout is not menu-bar real estate anyone can click anyway.
        #expect(!hit(leftEar, .none))
        #expect(!hit(rightEar, .none))
        #expect(hit(overCutout, .none))
    }

    /// The ears mode narrows the mask; it must narrow the *panel* no further
    /// than the island, and the expanded state must not be affected by it at all
    /// (the panel body has no ears).
    @Test("the ears do not resize the expanded panel")
    func earsDoNotTouchTheExpandedPanel() {
        let sizes = NotchEarsMode.allCases.map {
            NotchGeometry.layout(Self.m, size: .expanded, config: Self.config($0)).island.size
        }
        #expect(Set(sizes.map(\.width)).count == 1)
        #expect(Set(sizes.map(\.height)).count == 1)
    }
}

/// The island is sized from the rows the panel **actually draws** — today's open
/// tasks, bounded by the user's cap — and not from the cap alone. Sizing from the
/// cap is what left a strip of dead black over the screen for rows that did not
/// exist (four tasks in an island built for five), and a full five rows' worth of
/// nothing on a day with no tasks at all.
///
/// Every number here comes from the same structural SwiftUI replica of
/// `NotchExpandedPanel` the rest of the table came from, hosted at the island's
/// real 340pt width and asked for its `fittingSize`. The 0…5 sweep, all sections
/// on (body height, cutout gap excluded):
///
///     rows | task section | body  | island over a 37pt cutout
///        0 |        30    | 160   | 203      ← the empty-state caption
///        1 |        28    | 158   | 201
///        2 |        58    | 188   | 231
///        3 |        88    | 218   | 261
///        4 |       118    | 248   | 291
///        5 |       148    | 278   | 321
///
/// The rows carry the subtask badge and the pomodoro ring the main window's rows
/// carry, which is what took a row from 21pt to 28: the ring is 22pt, inside 3pt
/// of padding either side. The panel *pins* the row to that, so a task with no
/// badges is not a shorter row (it would measure 21) and the island fits the list
/// whatever today's tasks happen to carry.
@Suite("Notch task-row sizing")
struct NotchTaskRowSizingTests {
    static let cutout = CGSize(width: 200, height: 37)
    static let metrics = NotchScreenMetrics(screenWidth: 1512, menuBarHeight: 37,
                                            notchWidth: 200, notchHeight: 37)

    /// Cap 5 (the default), told there are `count` tasks today.
    private static func config(count: Int?, cap: Int = 5) -> NotchContentConfig {
        NotchContentConfig(taskRows: cap, taskCount: count)
    }

    private static func height(count: Int?, cap: Int = 5) -> CGFloat {
        NotchGeometry.expandedSize(config(count: count, cap: cap), cutout: cutout).height
    }

    /// The row carries what the main window's row carries — subtask badge,
    /// pomodoro ring, play/pause — and the ring is the tallest thing in it. The
    /// panel *pins* the row to `taskRowContentHeight` and hands that same number
    /// to the ring as its diameter, so the drawn row and the reserved row are one
    /// number, whatever the task happens to carry: a task with no subtasks and no
    /// estimate measures 21pt on its own (measured), and is held to 28 here.
    @Test("one task row is the measured 28pt, and its parts add up to it")
    func theRowIsTheConstant() {
        #expect(NotchGeometry.taskRowContentHeight == 22)   // the ring's diameter
        #expect(NotchGeometry.taskRowPadding == 3)
        #expect(NotchGeometry.taskRowHeight == 28)
        #expect(NotchGeometry.taskRowHeight
                == NotchGeometry.taskRowContentHeight + 2 * NotchGeometry.taskRowPadding)
        // One row's section is one row — no spacing to add on its own.
        #expect(NotchGeometry.taskSectionHeight(rows: 1) == NotchGeometry.taskRowHeight)
        // The empty-state caption is still not a row, and still the one place the
        // island is taller with *fewer* tasks (30 against 28).
        #expect(NotchGeometry.emptyTaskListHeight > NotchGeometry.taskRowHeight)
        #expect(NotchGeometry.emptyTaskListHeight < NotchGeometry.taskSectionHeight(rows: 2))
    }

    @Test("the task section matches the measured replica for 0…5 rows")
    func taskSectionMatchesTheReplica() {
        let measured: [Int: CGFloat] = [0: 30, 1: 28, 2: 58, 3: 88, 4: 118, 5: 148]
        for (rows, h) in measured {
            #expect(NotchGeometry.taskSectionHeight(rows: rows) == h)
        }
        // …and the body it lands in, likewise (10 bottom + Σ sections + 8 × n).
        let body: [Int: CGFloat] = [0: 160, 1: 158, 2: 188, 3: 218, 4: 248, 5: 278]
        for (rows, h) in body {
            #expect(NotchGeometry.expandedBodyHeight(Self.config(count: rows))
                    == h + NotchGeometry.bodySlack)
        }
    }

    /// The defect: the height followed the cap. Four tasks in an island built for
    /// five left a row's worth (30pt) of black above the quick-actions row.
    @Test("the height follows the real row count, not the cap")
    func heightFollowsTheCountNotTheCap() {
        // Four tasks, cap five: an island for four, not for five.
        #expect(Self.height(count: 4) == 37 + 6 + 248 + NotchGeometry.bodySlack)
        #expect(Self.height(count: 4) < Self.height(count: 5))
        #expect(Self.height(count: 5) - Self.height(count: 4)
                == NotchGeometry.taskRowHeight + NotchGeometry.taskRowSpacing)

        // Two tasks under a cap of five is the same island as two under a cap of
        // three: what is drawn decides the height, and only what is drawn.
        #expect(Self.height(count: 2, cap: 5) == Self.height(count: 2, cap: 3))

        // Rows 1…5 are monotone, and a row costs the measured 30pt throughout.
        for n in 1..<5 {
            #expect(Self.height(count: n + 1) - Self.height(count: n)
                    == NotchGeometry.taskRowHeight + NotchGeometry.taskRowSpacing)
        }
    }

    /// …and it is still the user's cap that bounds it. Twenty tasks today does
    /// not mean a twenty-row island: the panel draws `cap` of them.
    @Test("the cap still bounds the island")
    func theCapStillBounds() {
        #expect(Self.height(count: 20, cap: 3) == Self.height(count: 3, cap: 3))
        #expect(Self.height(count: 9, cap: 5) == Self.height(count: 5, cap: 5))
        // A cap outside the measured 3…5 range is clamped before it is used, as
        // before — a decoded 40 cannot size the island off the screen.
        #expect(Self.height(count: 40, cap: 40) == Self.height(count: 5, cap: 5))
    }

    /// Nothing planned today used to reserve five rows of black. It now reserves
    /// the caption's height — which is a *real* height, not zero and not a row:
    /// 30pt measured, taller than one row (28) and shorter than two (58). The
    /// island is therefore 2pt taller at zero tasks than at one, the single place
    /// the height is not monotone in the count.
    @Test("the empty state is materially shorter than a full list, and is not one row")
    func emptyStateIsShortButNotARow() {
        let empty = Self.height(count: 0)
        let full = Self.height(count: 5)

        // 207 vs 325: 118pt of dead black gone.
        #expect(empty == 37 + 6 + 160 + NotchGeometry.bodySlack)
        #expect(full - empty == 118)
        // "Materially" shorter — not a rounding: more than a quarter of the tall
        // island, and shorter than every list that has anything in it but one.
        #expect(empty < full * 0.75)
        #expect(empty < Self.height(count: 2))

        // The caption is not a task row, and is not free either.
        #expect(NotchGeometry.emptyTaskListHeight > NotchGeometry.taskRowHeight)
        #expect(Self.height(count: 0) - Self.height(count: 1)
                == NotchGeometry.emptyTaskListHeight - NotchGeometry.taskRowHeight)

        // With the task list switched off entirely there is no caption to make
        // room for, so *that* island is shorter still.
        var off = Self.config(count: 0)
        off.showTasks = false
        #expect(NotchGeometry.expandedSize(off, cutout: Self.cutout).height < empty)
    }

    /// An island that was never told the count sizes for the cap — exactly what
    /// the HUD did before. It is the only safe direction to be wrong in: the
    /// island clips its content to its own silhouette, so over-reserving leaves
    /// black, while under-reserving would crop a row the panel drew.
    @Test("an unknown count reserves the cap")
    func unknownCountReservesTheCap() {
        #expect(Self.height(count: nil) == Self.height(count: 5))
        #expect(Self.height(count: nil, cap: 3) == Self.height(count: 3, cap: 3))
        #expect(NotchContentConfig.default.renderedTaskRows
                == NotchContentConfig.default.clampedTaskRows)
        // And the count is not a setting: dropping it gets the cap-sized config
        // back, whatever was stamped on.
        #expect(Self.config(count: 1).sizedForRowCap == NotchContentConfig.default)
        #expect(NotchContentConfig.default.withTaskCount(2).renderedTaskRows == 2)
    }

    /// The load-bearing invariant. Whatever the count does to the island, the
    /// hit-test mask is cut from that same island — anything the mask claims but
    /// the panel does not draw is a click at the top of the screen the user
    /// loses, and anything drawn outside it is black that cannot be clicked.
    @Test("the mask follows the shortened island, and the panel still covers it")
    func maskAndPanelFollowTheCount() {
        for count in [0, 1, 2, 3, 4, 5] {
            let c = Self.config(count: count)
            let l = NotchGeometry.layout(Self.metrics, size: .expanded, config: c)
            let expected = NotchGeometry.expandedSize(c, cutout: Self.cutout)

            // Drawn == masked == computed.
            #expect(l.island.size == expected)
            #expect(NotchGeometry.hitTest(CGPoint(x: l.panelSize.width / 2,
                                                  y: expected.height - 4),
                                          metrics: Self.metrics, size: .expanded, config: c))
            // A point just below is the desktop again, not HUD.
            #expect(!NotchGeometry.hitTest(CGPoint(x: l.panelSize.width / 2,
                                                   y: expected.height + 6),
                                           metrics: Self.metrics, size: .expanded, config: c))
            // And the island never leaves the panel, in any state.
            for size in NotchHUDSize.allCases {
                let l = NotchGeometry.layout(Self.metrics, size: size, config: c)
                #expect(l.island.maxY <= l.panelSize.height + 0.01)
                #expect(l.island.maxX <= l.panelSize.width + 0.01)
                #expect(l.island.minX >= -0.01)
            }
        }

        // The *window*, though, is deliberately pinned to the cap: it must not
        // resize under an island that is still springing to its new height, and
        // it costs nothing to leave at the maximum (the mask, not the window, is
        // what gives the menu bar back).
        let atCap = NotchGeometry.panelSize(Self.metrics, config: Self.config(count: nil))
        for count in [0, 1, 2, 3, 4, 5] {
            #expect(NotchGeometry.panelSize(Self.metrics,
                                            config: Self.config(count: count)) == atCap)
        }
    }

    /// The floor that keeps `growthRank` honest survives the smallest island the
    /// count can produce: `.expanded` is still the biggest shape, or the motion
    /// layer springs it *shut* as it opens.
    @Test("an empty list still outranks every shorter state")
    func emptyListStillOutranksTheOtherStates() {
        var bare = Self.config(count: 0)
        bare.showTimerControls = false
        bare.showQuickActions = false
        bare.showStatusStrip = false

        var m = Self.metrics
        for cfg in [Self.config(count: 0), Self.config(count: 1), bare] {
            for cutoutHeight in [CGFloat(32), 37, 44] {
                m.notchHeight = cutoutHeight
                func area(_ s: NotchHUDSize) -> CGFloat {
                    let r = NotchGeometry.layout(m, size: s, config: cfg).island
                    return r.width * r.height
                }
                #expect(area(.expanded) > area(.activity))
                #expect(area(.expanded) > area(.live))
                #expect(area(.expanded) > area(.idle))
            }
        }
    }
}
