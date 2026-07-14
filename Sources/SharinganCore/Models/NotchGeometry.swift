import Foundation
import CoreGraphics

/// Everything the HUD needs to know about the screen it lives on. Built from
/// `NSScreen` in the app layer so the geometry itself stays pure and testable.
public struct NotchScreenMetrics: Equatable, Sendable {
    public var screenWidth: CGFloat
    public var menuBarHeight: CGFloat
    /// Width of the hardware cutout, 0 when the display has none.
    public var notchWidth: CGFloat
    /// Height of the hardware cutout (== safe-area top), 0 when there is none.
    public var notchHeight: CGFloat

    public init(screenWidth: CGFloat, menuBarHeight: CGFloat,
                notchWidth: CGFloat, notchHeight: CGFloat) {
        self.screenWidth = screenWidth
        self.menuBarHeight = menuBarHeight
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }

    /// A display with no cutout — and, on this model, no screen either. The safe
    /// default for anything that has not been told the real metrics yet: it
    /// yields no cutout, no layout and a hit-test mask that claims nothing (see
    /// `NotchHUDModel.metrics`).
    public static let none = NotchScreenMetrics(screenWidth: 0, menuBarHeight: 0,
                                                notchWidth: 0, notchHeight: 0)

    public var hasHardwareNotch: Bool { notchWidth > 0 && notchHeight > 0 }

    /// How deep the island's **stem** runs — the menu-bar row it passes through,
    /// and where the body below it begins.
    ///
    /// It is the menu bar's height, floored at the camera housing's: the body
    /// carries every readable thing the island has, so it must start below
    /// *both* or the housing eats the top of the timer. `NotchWindowManager`
    /// already computes the menu bar as a `max` that includes the notch height,
    /// so on real hardware this floor never bites; it is here because the
    /// geometry is pure and will be handed whatever a caller has.
    public var stemHeight: CGFloat { max(menuBarHeight, notchHeight) }

    /// The hardware cutout the island is modelled on, `nil` when the display has
    /// none. There is deliberately no synthetic fallback: an app-drawn pill
    /// hanging over the menu bar of a notchless Mac reads as a bug, so on such a
    /// display the HUD simply does not exist — no cutout, no layout, no panel.
    public var cutout: CGSize? {
        hasHardwareNotch ? CGSize(width: notchWidth, height: notchHeight) : nil
    }
}

/// The five shapes the island can take. `activity` is a transient announcement
/// (session done, break started) that collapses on its own.
public enum NotchHUDSize: String, CaseIterable, Sendable {
    case hidden, idle, live, activity, expanded

    /// How much room the shape takes, ordered — the one thing the motion layer
    /// needs from a morph: is the island *growing* or *shrinking*? Opening and
    /// closing are deliberately different springs (see `NotchMotion`), and one
    /// spring for both directions is what makes a morph feel cheap.
    ///
    /// Ordered by island *area*, not width, because area is what the eye reads
    /// as "bigger": `.live` is the widest state (the cutout plus two ears) but
    /// only a 41pt-tall strip, so arriving at the shorter-but-far-taller
    /// `.activity` still reads as the island opening, and is sprung as one.
    public var growthRank: Int {
        switch self {
        case .hidden:   return 0
        case .idle:     return 1
        case .live:     return 2
        case .activity: return 3
        case .expanded: return 4
        }
    }
}

/// What the island is allowed to show — `PomodoroSettings`' notch keys,
/// projected into the only form the geometry cares about.
///
/// This is not a cosmetic filter. The expanded island's height is *computed*
/// from it, and the live island's width from `ears`, so the black the HUD hangs
/// over the screen (and the hit-test mask cut from it) shrinks to what the user
/// actually asked for. Defaults reproduce the behavior the HUD shipped with, so
/// an upgraded settings blob cannot resize the island by surprise.
public struct NotchContentConfig: Equatable, Sendable {
    public var ears: NotchEarsMode
    public var showTimerControls: Bool
    public var showTasks: Bool
    public var showQuickActions: Bool
    public var showStatusStrip: Bool
    /// Requested row count — the *cap*, and the only part of this the user sets.
    /// Trust it for nothing: read `clampedTaskRows`.
    public var taskRows: Int
    /// How many task rows there actually are to draw right now — today's open
    /// tasks, as `NotchTaskRows` orders them. `NotchWindowManager` writes it
    /// from `TaskStore` (nothing else does; the geometry cannot see a store),
    /// and `renderedTaskRows` is where the cap meets it.
    ///
    /// `nil` means *nobody has said yet*, and is deliberately the default: an
    /// unknown count sizes the island for the cap, which is what the HUD did
    /// before the count was fed in. Unknown therefore over-reserves and never
    /// clips — the only direction of error that is safe, since the island clips
    /// its content to its own silhouette.
    public var taskCount: Int?

    /// The range the panel's height constants were *measured* over. Fewer than
    /// three rows is not worth a task list; more than five does not fit under
    /// the timer row without the island growing past the menu bar's neighbours.
    public static let taskRowRange = 3...5

    public init(ears: NotchEarsMode = .both,
                showTimerControls: Bool = true,
                showTasks: Bool = true,
                showQuickActions: Bool = true,
                showStatusStrip: Bool = true,
                taskRows: Int = NotchTaskRows.defaultLimit,
                taskCount: Int? = nil) {
        self.ears = ears
        self.showTimerControls = showTimerControls
        self.showTasks = showTasks
        self.showQuickActions = showQuickActions
        self.showStatusStrip = showStatusStrip
        self.taskRows = taskRows
        self.taskCount = taskCount
    }

    /// The cap. A decoded blob (or a future build's key) can carry anything; an
    /// unclamped 40 here would size the island off the bottom of the screen.
    public var clampedTaskRows: Int {
        min(max(taskRows, Self.taskRowRange.lowerBound), Self.taskRowRange.upperBound)
    }

    /// **The one number the island's height, its hit-test mask and the panel's
    /// task list are all cut from**: how many rows the expanded panel will
    /// actually draw. The user's cap bounds today's real count — reserving five
    /// rows' worth of black for four tasks is dead space over the user's screen,
    /// and reserving it for *none* is a slab of nothing.
    ///
    /// Zero is not "no section": the panel draws its "No open tasks"
    /// caption there, which has a height of its own (see
    /// `NotchGeometry.emptyTaskListHeight`) and is not one row's worth.
    public var renderedTaskRows: Int {
        guard let taskCount else { return clampedTaskRows }
        return min(clampedTaskRows, max(0, taskCount))
    }

    /// The same config with the count forgotten — i.e. sized for the *cap*, the
    /// tallest task list this config could ever be asked to draw. `panelSize`
    /// uses it so the window stays put while the task list churns: the panel is
    /// invisible and click-through everywhere the mask says no, so leaving it at
    /// the maximum costs nothing, while resizing the *window* under an island
    /// that is still springing to its new height would clip the animation.
    public var sizedForRowCap: NotchContentConfig {
        var c = self
        c.taskCount = nil
        return c
    }

    /// The same config, told how many rows there are.
    public func withTaskCount(_ count: Int) -> NotchContentConfig {
        var c = self
        c.taskCount = count
        return c
    }

    /// Everything on, five rows, both ears — what the HUD did before it was
    /// configurable.
    public static let `default` = NotchContentConfig()
}

/// The island's silhouette, as a set of numbers a path can be cut from — the
/// **T**: a stem the width of the hardware cutout occupying the menu-bar row,
/// and a body that begins below the menu bar and hangs into the desktop.
///
/// Every state's shape is one of these, including the flat ones: an island whose
/// `stemWidth` is its own full width has no waist to speak of and degenerates to
/// the rounded-bottom rectangle the short states have always drawn. That is the
/// point — one path definition, one hit-test mask, no special cases.
///
/// It is deliberately expressed **relative to the rect it is drawn in** rather
/// than in panel coordinates: the SwiftUI shape is handed an animating rect and
/// has to cut the same silhouette from it that `hitTest` cuts from the island's
/// resting rect.
public struct NotchSilhouette: Equatable, Sendable {
    /// Width of the part that lives in the menu-bar row, centered in the rect.
    /// The hardware cutout's width for the wide states; the rect's own width for
    /// the flat ones (which is what makes them plain rectangles).
    public var stemWidth: CGFloat
    /// Where the wide body starts, measured down from the rect's top edge — the
    /// menu-bar height. Everything above it is stem; everything below is body.
    public var bodyTop: CGFloat
    /// The body's bottom corners (the notch's own, grown — see
    /// `NotchGeometry.cornerRadius(forHeight:baseHeight:maxHeight:)`).
    public var cornerRadius: CGFloat
    /// The body's outer top corners, where it meets the bottom of the menu bar.
    public var bodyTopRadius: CGFloat
    /// The **concave** fillet where the body meets the stem: the black flares
    /// outward into the menu-bar row instead of turning a square inner corner,
    /// which is what makes the island read as the cutout stretching rather than
    /// as a window that appeared under it.
    public var filletRadius: CGFloat

    public init(stemWidth: CGFloat, bodyTop: CGFloat, cornerRadius: CGFloat,
                bodyTopRadius: CGFloat, filletRadius: CGFloat) {
        self.stemWidth = stemWidth
        self.bodyTop = bodyTop
        self.cornerRadius = cornerRadius
        self.bodyTopRadius = bodyTopRadius
        self.filletRadius = filletRadius
    }
}

/// Rects for one state, in panel coordinates: origin top-left, y grows down.
public struct NotchLayout: Equatable, Sendable {
    public var panelSize: CGSize
    /// The silhouette's **bounding box** — as wide as the body and as tall as
    /// the whole T, menu-bar row included. The content views are framed to it
    /// and the drawn shape is cut from it, so it is the one rect everything
    /// geometric is anchored to.
    public var island: CGRect
    public var leftEar: CGRect?
    public var rightEar: CGRect?
    public var progressTrack: CGRect?
    public var silhouette: NotchSilhouette

    /// The bottom radius, for the callers that only ever wanted that.
    public var cornerRadius: CGFloat { silhouette.cornerRadius }

    /// **Where content goes**: the part of the island below the menu bar. The
    /// expanded panel and the announcement fill this and nothing above it — the
    /// stem is a strip of hardware-width black over the camera housing, not a
    /// place anything can be read.
    ///
    /// Meaningless for the flat states (`idle`, `live`), whose whole island *is*
    /// the menu-bar row; they lay their ears out against `island` instead.
    public var body: CGRect {
        CGRect(x: island.minX, y: island.minY + silhouette.bodyTop,
               width: island.width,
               height: max(0, island.height - silhouette.bodyTop))
    }
}

public enum NotchGeometry {
    /// The expanded island's width. Everything below is measured *at* this
    /// width — a wider island would rewrap nothing (every row is `lineLimit(1)`)
    /// but a narrower one would, so the width is part of the contract.
    public static let expandedWidth: CGFloat = 340
    public static let earWidth: CGFloat = 78
    /// The idle island is the cutout plus this lip, so it reads as hardware.
    public static let idleExtraHeight: CGFloat = 4
    /// The announcement's width, and the height of its **body** — the part below
    /// the menu bar. (Measured: a 14pt icon beside a 12pt line is 16pt of
    /// content; 14pt of air above and below it is 44.) The island itself is this
    /// plus the menu-bar row the stem occupies, so `activitySize(menuBarHeight:)`
    /// and not a constant.
    public static let activityWidth: CGFloat = 300
    public static let activityBodyHeight: CGFloat = 44
    public static func activitySize(menuBarHeight: CGFloat) -> CGSize {
        CGSize(width: activityWidth, height: menuBarHeight + activityBodyHeight)
    }
    public static let progressHeight: CGFloat = 3
    /// The hardware cutout's own bottom corner — the radius of the short states
    /// (`idle`, `live`), which are the cutout plus a 4pt lip.
    public static let cornerRadius: CGFloat = 14
    /// … and the radius of the tall one. The expanded panel wearing the notch's
    /// 14pt corner looks pinched; 22pt reads as the same shape, grown.
    public static let maxCornerRadius: CGFloat = 22

    // MARK: - The T
    //
    // The wide states used to be rectangles anchored to the top of the screen,
    // which put a slab of black — and, since the mask follows the drawn shape, a
    // dead hit region — across the menu-bar titles either side of the notch. The
    // island is now a T: the stem is exactly the hardware cutout's width and
    // occupies the menu-bar row (space the camera housing already took, so it
    // costs the user nothing), and the body starts at `menuBarHeight` and hangs
    // into the desktop below it.

    /// The body's outer top corners, where it meets the bottom of the menu bar.
    public static let bodyTopRadius: CGFloat = 12
    /// The concave fillet where the body meets the stem. It flares the black
    /// outward into the menu-bar row for these few points either side of the
    /// cutout — the join reads as the notch stretching instead of as two
    /// rectangles glued together, and it costs a `filletRadius`-square of
    /// menu bar hard against the camera housing, where nothing is clickable
    /// anyway.
    public static let filletRadius: CGFloat = 10

    // MARK: - Expanded panel sizing (measured, not guessed)
    //
    // The expanded island's height is computed from what the panel is configured
    // to show. Every constant below was read off a structural SwiftUI replica of
    // `NotchExpandedPanel` — same stack, same spacings, same fonts — laid out at
    // `expandedWidth` and asked for its `fittingSize`. The table is in the notch
    // settings report; the formula reproduces all 40 measured combinations to
    // the point.
    //
    // Getting one of these wrong is not cosmetic. Too small and the content is
    // cropped at the island's `.clipShape` (the bug this feature already shipped
    // once, at a 260pt guess); too large and the HUD hangs dead black over the
    // user's screen.

    /// The body's top padding: the gap between the body's own top edge — the
    /// bottom of the menu bar — and the first pixel of content.
    ///
    /// It used to be a 6pt gap *under the camera housing*, because the content
    /// sat inside a rectangle that started at the top of the screen and had to
    /// clear the cutout. The T's body starts below the menu bar, so this is now
    /// an ordinary inset from a rounded edge, and it is measured with the rest:
    /// the replica's body is 288pt at five rows against 278 with no top padding.
    public static let contentTopPadding: CGFloat = 10
    /// The panel's bottom padding.
    public static let contentBottomPadding: CGFloat = 10
    /// The `VStack`'s spacing — one gap per section, plus one for the trailing
    /// `Spacer`, which is a child of the stack like any other.
    public static let sectionSpacing: CGFloat = 8
    /// The timer row and the divider under it: 51pt measured.
    public static let timerRowHeight: CGFloat = 51
    /// A task row's *content*: the pomodoro ring, which is the tallest thing in
    /// it — the checkbox (12pt), the 12pt title and the 13pt play button all sit
    /// inside it. `NotchExpandedPanel` pins the row to this and hands it to the
    /// ring as its diameter, so the two cannot drift.
    ///
    /// The pin is not decoration. The row's badges are conditional — a task with
    /// no subtasks and no estimate measures 21pt against a badged row's 28 — and
    /// the island's height is computed from the row *count*, which knows nothing
    /// about what any row carries. Unpinned, a list of bare tasks would sit 35pt
    /// short of the black reserved for it.
    public static let taskRowContentHeight: CGFloat = 22
    /// The row's vertical padding, either side of the content.
    public static let taskRowPadding: CGFloat = 3
    /// One task row: 28pt measured (22 + 3 + 3) — the enriched row, which carries
    /// the subtask badge and the pomodoro ring the main window's rows carry.
    /// (It was 21pt when the row was a checkbox, a title and a play button.)
    public static let taskRowHeight: CGFloat = taskRowContentHeight + 2 * taskRowPadding
    /// … and 2pt of list spacing between rows, so a row *costs* 30pt — the 60pt
    /// over two rows the 5-row/3-row measurement shows (218 → 278).
    public static let taskRowSpacing: CGFloat = 2
    /// With no open tasks the panel draws neither rows nor nothing: it
    /// draws a centered "No open tasks" caption, and that caption
    /// needs a height of its own — 30pt measured (an 11pt rounded line inside
    /// 8pt of vertical padding).
    ///
    /// It is deliberately *not* `taskRowHeight`. It is taller than one row (28)
    /// and shorter than two (58), so the island at zero tasks is 2pt taller than
    /// at one — the one place the height is not monotone in the row count, and a
    /// real measurement rather than a rounding.
    public static let emptyTaskListHeight: CGFloat = 30
    /// The quick-actions row: 24pt buttons, measured.
    public static let quickActionsHeight: CGFloat = 24
    /// The blocker/streak strip: 13pt of 9pt labels, measured.
    public static let statusStripHeight: CGFloat = 13
    /// Headroom over the measured fit. `fittingSize` is the *ideal* height and
    /// the panel's `Spacer` absorbs this, so it does not read as dead space at
    /// the bottom — it is the margin that keeps a hairline of rounding from
    /// clipping the last row.
    public static let bodySlack: CGFloat = 4

    /// The task section's height for the number of rows the panel will actually
    /// draw. Measured: 0 → 30 (the empty-state caption), 1 → 28, 2 → 58, 3 → 88,
    /// 4 → 118, 5 → 148.
    public static func taskSectionHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return emptyTaskListHeight }
        let n = CGFloat(rows)
        return taskRowHeight * n + taskRowSpacing * (n - 1)
    }

    /// Height of the island's **body** — the whole of it, since the body is now
    /// all there is below the menu bar: its own top padding, its sections, its
    /// bottom padding and the slack. The menu-bar row the stem occupies is added
    /// by `expandedSize`, which knows the real menu bar.
    ///
    /// The task list is sized from `config.renderedTaskRows` — what the panel
    /// *draws* — and not from `clampedTaskRows`, which is only the user's cap.
    /// Sizing from the cap is how the island came to hang a strip of dead black
    /// over the screen for rows that do not exist.
    public static func expandedBodyHeight(_ config: NotchContentConfig = .default) -> CGFloat {
        var sections: [CGFloat] = []
        if config.showTimerControls { sections.append(timerRowHeight) }
        if config.showTasks {
            sections.append(taskSectionHeight(rows: config.renderedTaskRows))
        }
        if config.showQuickActions { sections.append(quickActionsHeight) }
        if config.showStatusStrip { sections.append(statusStripHeight) }

        // n sections and the always-present `Spacer` are n+1 children, so n+1-1
        // = n gaps between them.
        return contentTopPadding
            + contentBottomPadding
            + sections.reduce(0, +)
            + sectionSpacing * CGFloat(sections.count)
            + bodySlack
    }

    /// The expanded island, sized to what it was configured to show: the
    /// menu-bar row the stem passes through, plus the body that hangs below it.
    ///
    /// The **cutout's** height is not in it any more, and that is the change: the
    /// content used to be pushed clear of the camera housing inside a rectangle
    /// that started at the top of the screen, so the island was as tall as the
    /// housing plus its content. The body now starts where the menu bar ends
    /// (`menuBarHeight ≥ notchHeight` by construction — see
    /// `NotchWindowManager.metrics`), so the housing is the stem's problem and
    /// not the content's.
    ///
    /// Floored at the announcement's height for a reason that is not
    /// cosmetic: `NotchHUDSize.growthRank` promises `.expanded` is the biggest
    /// shape, and the motion layer picks the opening spring or the closing one
    /// off that promise alone. An all-sections-off config would otherwise
    /// produce a body of 24pt — a smaller island than `.activity` — and hovering
    /// it would spring *shut* as it opened.
    public static func expandedSize(_ config: NotchContentConfig = .default,
                                    menuBarHeight: CGFloat) -> CGSize {
        let height = menuBarHeight + expandedBodyHeight(config)
        return CGSize(width: expandedWidth,
                      height: max(height, activitySize(menuBarHeight: menuBarHeight).height))
    }

    /// How wide the live island grows: the cutout, plus one ear per ear the user
    /// still wants. This is the *silhouette*, so it is also exactly how much
    /// menu bar the HUD can swallow — which is the whole point of the setting.
    public static func liveWidth(cutout: CGSize, ears: NotchEarsMode) -> CGFloat {
        cutout.width + earWidth * CGFloat(ears.earCount)
    }

    /// The bottom radius interpolates with the island's height: a taller island
    /// is a rounder one. `maxHeight` is the tallest island *this config* draws —
    /// the expanded one — so the ramp always tops out exactly there.
    ///
    /// This lives in Core, next to `islandPath`, for the same reason the path
    /// does: the *drawn* radius and the radius `hitTest` masks with must be the
    /// same number by construction. If they drift, a corner that is masked
    /// rounder than it is painted leaves a wedge that is clickable but shows the
    /// menu bar — and in `.live` that wedge sits on live menu-bar real estate.
    public static func cornerRadius(forHeight height: CGFloat,
                                    baseHeight: CGFloat,
                                    maxHeight: CGFloat) -> CGFloat {
        guard height > baseHeight else { return cornerRadius }
        let span = max(1, maxHeight - baseHeight)
        let t = min(1, (height - baseHeight) / span)
        return cornerRadius + (maxCornerRadius - cornerRadius) * t
    }

    /// Hover must persist this long before the island opens (a pointer merely
    /// crossing the top of the screen must not trigger it) …
    public static let hoverOpenDelay: TimeInterval = 0.25
    /// … and this long after leaving before it closes, so a diagonal exit
    /// across a corner doesn't slam it shut.
    public static let hoverCloseDelay: TimeInterval = 0.15
    public static let activityDuration: TimeInterval = 2.0

    /// The union of every state the *current config* can draw — the geometry's
    /// **canvas**: every layout rect is placed inside it and every x-coordinate
    /// is measured against its centered width. `.zero` without a hardware
    /// notch — there is no panel to size.
    ///
    /// The *window* is no longer this size at all times. It keeps this union
    /// **width** in every state, but its height hugs the current state
    /// (`panelHeight(_:size:config:)` — see there for why). This union height
    /// remains what the dev preview photographs, so the grey plate shows
    /// exactly where each state's island is not.
    ///
    /// "Can draw" includes a task list that is **full**, which is why this alone
    /// reads `config.sizedForRowCap` while the island reads the real count. Two
    /// reasons, both load-bearing:
    ///
    /// 1. A window whose height tracked the task count would have to be resized
    ///    the instant a task is ticked off — *while the island is still springing
    ///    down to its new height*. `NSWindow` clips its content view, so the
    ///    animating island would be sliced off at the new, shorter window edge.
    ///    Held at the cap, the window never moves and the island animates inside
    ///    it.
    /// 2. It costs nothing. The panel is invisible and click-through everywhere
    ///    `hitTest` says no, and `hitTest` masks against the *island*, which
    ///    follows the real count. The mask, not the window's frame, is what gives
    ///    the menu bar back.
    public static func panelSize(_ m: NotchScreenMetrics,
                                 config: NotchContentConfig = .default) -> CGSize {
        guard let cutout = m.cutout else { return .zero }
        let expanded = expandedSize(config.sizedForRowCap, menuBarHeight: m.stemHeight)
        // The panel is centered on the cutout, but a one-eared island is *not*
        // symmetric about it — so an ear must be reserved on both sides even
        // when only one is grown, or the trailing ear (island 278pt wide, panel
        // 340pt) hangs 8pt past the panel's edge and is clipped away with its
        // hit region. Reserving it costs nothing: the panel is invisible and
        // click-through everywhere `hitTest` says no. The *mask* is what gives
        // the menu bar back, not the panel's width.
        let earReserve = config.ears.earCount > 0 ? 2 * earWidth : 0
        let width = max(expanded.width,
                        cutout.width + earReserve,
                        activityWidth)
        let height = max(expanded.height, cutout.height + idleExtraHeight)
        return CGSize(width: width, height: height)
    }

    /// The panel *window*'s height while the island is in `size` — the island's
    /// own depth, `layout.island.maxY`, and **not** `panelSize.height`.
    ///
    /// The window used to be the union of every state at all times, and gave
    /// everything the island wasn't drawing back to the desktop through two
    /// fragile things: the content view's `hitTest` returning nil, and the
    /// window server's alpha-based click-through. The server *caches* a
    /// transparent window's clickable shape and refreshes it lazily — after one
    /// expand-and-collapse the stale cache could keep the entire expanded
    /// region click-opaque, a dead zone over the browser tabs below the menu
    /// bar while the island was nothing but the live ears. The robust fix is
    /// for the window to only ever be as big as the current silhouette: when
    /// the island is closed there is **no window** over that region, and no
    /// cache to go stale.
    ///
    /// Height only. The window keeps `panelSize`'s union **width** in every
    /// state: the live ears legitimately span it, and its side margins sit in
    /// the menu-bar row, where the silhouette mask already hands the pixels
    /// back — horizontal never had the dead zone, because no state hangs window
    /// below the menu bar without also being exactly this tall.
    ///
    /// Reads `config.sizedForRowCap`, like `panelSize` and for the same reason:
    /// tick a task off the *open* island and the island springs shorter, but
    /// the window must not move under the spring (`NSWindow` clips its content
    /// view mid-animation). The cap is the tallest list this config can draw,
    /// so the expanded height is one number for the whole churn.
    ///
    /// `0` for `.hidden` and for a display with no notch: no island, no
    /// window — the manager orders the panel out rather than framing nothing.
    public static func panelHeight(_ m: NotchScreenMetrics, size: NotchHUDSize,
                                   config: NotchContentConfig = .default) -> CGFloat {
        layout(m, size: size, config: config.sizedForRowCap).island.maxY
    }

    /// Nothing drawn, nothing hittable — the layout of a display with no notch,
    /// and of the `.hidden` state.
    private static func empty(panel: CGSize) -> NotchLayout {
        NotchLayout(panelSize: panel, island: .zero, leftEar: nil,
                    rightEar: nil, progressTrack: nil,
                    silhouette: flat(width: 0, cornerRadius: cornerRadius,
                                     menuBarHeight: 0))
    }

    /// The silhouette of a state that lives **entirely in the menu-bar row** —
    /// `idle` and `live`, the cutout plus a 4pt lip. A stem as wide as the island
    /// itself has no body beside it, so the T degenerates to the rounded-bottom
    /// rectangle these states have always drawn.
    ///
    /// `bodyTop` is carried anyway, and it matters *while the island is moving*.
    /// The silhouette is not animated (see `IslandShape`) — it flips to the new
    /// state's the instant the hit-test mask does — but the island's **frame**
    /// springs. Closing from `.expanded`, the frame is still 340pt wide for a few
    /// frames after the mask has shrunk to the live island; with `bodyTop` set,
    /// those wide frames are drawn as a T whose stem is exactly the live island's
    /// width, so the overhang hangs *below* the menu bar (over the desktop, where
    /// it is click-through and harmless) instead of painting a slab across the
    /// menu-bar titles on the way out.
    private static func flat(width: CGFloat, cornerRadius: CGFloat,
                             menuBarHeight: CGFloat) -> NotchSilhouette {
        NotchSilhouette(stemWidth: width, bodyTop: menuBarHeight,
                        cornerRadius: cornerRadius, bodyTopRadius: bodyTopRadius,
                        filletRadius: 0)
    }

    public static func layout(_ m: NotchScreenMetrics, size: NotchHUDSize,
                              config: NotchContentConfig = .default) -> NotchLayout {
        // No hardware notch, no HUD: every state collapses to nothing, whatever
        // size was asked for.
        guard let cutout = m.cutout else { return empty(panel: .zero) }
        let panel = panelSize(m, config: config)
        let expanded = expandedSize(config, menuBarHeight: m.stemHeight)
        let menuBar = m.stemHeight

        func centered(width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: (panel.width - width) / 2, y: 0, width: width, height: height)
        }

        /// The short states — the cutout plus its lip — are the baseline the
        /// radius grows from, and the expanded island is the top of the ramp.
        let baseHeight = cutout.height + idleExtraHeight
        func radius(_ island: CGRect) -> CGFloat {
            cornerRadius(forHeight: island.height, baseHeight: baseHeight,
                         maxHeight: expanded.height)
        }

        /// The T: a stem the width of the hardware cutout through the menu-bar
        /// row, and the body — the island's full width — below it.
        func tee(_ island: CGRect) -> NotchSilhouette {
            NotchSilhouette(stemWidth: cutout.width, bodyTop: menuBar,
                            cornerRadius: radius(island),
                            bodyTopRadius: bodyTopRadius,
                            filletRadius: filletRadius)
        }

        /// The cutout's own left edge. The island is anchored to the hardware,
        /// never centered on the panel — with one ear, centering would slide the
        /// black half an ear off the camera housing.
        let cutoutMinX = (panel.width - cutout.width) / 2

        switch size {
        case .hidden:
            return empty(panel: panel)

        case .idle:
            let island = centered(width: cutout.width, height: baseHeight)
            return NotchLayout(panelSize: panel, island: island, leftEar: nil,
                               rightEar: nil, progressTrack: nil,
                               silhouette: flat(width: island.width,
                                                cornerRadius: radius(island),
                                                menuBarHeight: menuBar))

        case .live:
            // The island grows only the ears the user still wants — so this is
            // also how much menu bar the mask below can swallow. `.none` leaves
            // the island exactly the cutout, with the progress line along its
            // bottom edge and not one pixel of the menu bar taken.
            //
            // The ears stay in the menu-bar row on purpose: they are the point of
            // a notch HUD, they are what `notchEars` exists to switch off, and a
            // 41pt strip of time-and-task is not the slab the T removes.
            let ears = config.ears
            let width = liveWidth(cutout: cutout, ears: ears)
            let minX = ears.showsLeadingEar ? cutoutMinX - earWidth : cutoutMinX
            let island = CGRect(x: minX, y: 0, width: width, height: baseHeight)
            let left = ears.showsLeadingEar
                ? CGRect(x: cutoutMinX - earWidth, y: 0,
                         width: earWidth, height: cutout.height)
                : nil
            let right = ears.showsTrailingEar
                ? CGRect(x: cutoutMinX + cutout.width, y: 0,
                         width: earWidth, height: cutout.height)
                : nil
            let track = CGRect(x: island.minX,
                               y: island.maxY - progressHeight,
                               width: island.width, height: progressHeight)
            return NotchLayout(panelSize: panel, island: island, leftEar: left,
                               rightEar: right, progressTrack: track,
                               silhouette: flat(width: island.width,
                                                cornerRadius: radius(island),
                                                menuBarHeight: menuBar))

        case .activity:
            let size = activitySize(menuBarHeight: menuBar)
            let island = centered(width: max(size.width, cutout.width),
                                  height: size.height)
            return NotchLayout(panelSize: panel, island: island, leftEar: nil,
                               rightEar: nil, progressTrack: nil,
                               silhouette: tee(island))

        case .expanded:
            let island = centered(width: expanded.width, height: expanded.height)
            return NotchLayout(panelSize: panel, island: island, leftEar: nil,
                               rightEar: nil, progressTrack: nil,
                               silhouette: tee(island))
        }
    }

    /// **The one definition of the island's shape.** The app's `IslandShape`
    /// draws this path and `hitTest` masks against it, so the drawn pixels and
    /// the clickable region cannot drift apart. (They did, once: masking against
    /// the bare rect left a wedge at each bottom corner that was hittable but not
    /// drawn, and in `.live` that wedge sits on live menu-bar real estate.)
    ///
    /// It cuts the **T** of `NotchSilhouette` from `rect`:
    ///
    ///                    ┌──────┐               ← stem: the cutout's width,
    ///                    │      │                 through the menu-bar row
    ///     ╭──────────────╯      ╰──────────────╮ ← concave fillets, flaring out
    ///     │                                    │   into the menu bar
    ///     │              body                  │
    ///     ╰────────────────────────────────────╯
    ///
    /// and degenerates — with no branch of its own — to the rounded-bottom
    /// rectangle the short states draw, the moment the stem is as wide as the
    /// rect it is cut from.
    ///
    /// Non-convex for the first time, which is the whole point: the menu-bar row
    /// either side of the stem is **outside** this path, so it is outside the
    /// mask, so a click there reaches the menu bar.
    public static func islandPath(in rect: CGRect,
                                  silhouette s: NotchSilhouette) -> CGPath {
        let p = CGMutablePath()
        guard rect.width > 0, rect.height > 0 else { return p }

        // The waist. Nothing to cut when the stem is the whole width (the flat
        // states), or when there is no menu-bar row above the body to cut it
        // through: fall back to the plain rounded-bottom rect.
        let stemW = min(s.stemWidth, rect.width)
        let halfGap = (rect.width - stemW) / 2
        let bodyTop = s.bodyTop
        guard halfGap > 0.01, bodyTop > 0.01, bodyTop < rect.height - 0.01 else {
            let r = min(s.cornerRadius, rect.height / 2, rect.width / 2)
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                           control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                           control: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        }

        let bodyHeight = rect.height - bodyTop
        // Every radius is clamped to the room there actually is, because the rect
        // is *animating*: the island springs from 200pt wide to 340 while these
        // numbers stay put, so for a few frames the body is barely wider than the
        // stem and the corners have to give way rather than fold the path back
        // through itself.
        let fillet = min(s.filletRadius, bodyTop, halfGap)
        let topR = max(0, min(s.bodyTopRadius, bodyHeight / 2, halfGap - fillet))
        let r = min(s.cornerRadius, bodyHeight / 2, rect.width / 2)

        let stemMinX = rect.midX - stemW / 2
        let stemMaxX = rect.midX + stemW / 2
        let top = rect.minY
        let bt = rect.minY + bodyTop

        p.move(to: CGPoint(x: stemMinX, y: top))
        p.addLine(to: CGPoint(x: stemMaxX, y: top))
        // Down the stem's trailing edge, then out into the menu-bar row: the
        // control point sits at the *fillet's* corner, not at the join's, so the
        // curve bows away from the join and the black flares outward. (Bowing the
        // other way would chamfer the corner off — the cheap look.)
        p.addLine(to: CGPoint(x: stemMaxX, y: bt - fillet))
        p.addQuadCurve(to: CGPoint(x: stemMaxX + fillet, y: bt),
                       control: CGPoint(x: stemMaxX + fillet, y: bt - fillet))
        p.addLine(to: CGPoint(x: rect.maxX - topR, y: bt))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: bt + topR),
                       control: CGPoint(x: rect.maxX, y: bt))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: bt + topR))
        p.addQuadCurve(to: CGPoint(x: rect.minX + topR, y: bt),
                       control: CGPoint(x: rect.minX, y: bt))
        p.addLine(to: CGPoint(x: stemMinX - fillet, y: bt))
        p.addQuadCurve(to: CGPoint(x: stemMinX, y: bt - fillet),
                       control: CGPoint(x: stemMinX - fillet, y: bt - fillet))
        p.closeSubpath()
        return p
    }

    /// The flat silhouette — a rounded-bottom rectangle — for callers that have
    /// only a radius to hand.
    public static func islandPath(in rect: CGRect,
                                  cornerRadius: CGFloat = cornerRadius) -> CGPath {
        islandPath(in: rect,
                   silhouette: flat(width: rect.width, cornerRadius: cornerRadius,
                                    menuBarHeight: 0))
    }

    /// True when `point` (panel coordinates) is inside the *currently rendered*
    /// shape. The panel is far bigger than the island, so this is what keeps
    /// menu-bar clicks working: everything outside falls through. Always false
    /// without a hardware notch — nothing is rendered there.
    ///
    /// The ears need no test of their own: they are sub-rects of the island in
    /// `.live` and are drawn inside its silhouette, so masking against the
    /// silhouette covers them — and, unlike their rects, it does not claim the
    /// rounded-off corners.
    ///
    /// Since the silhouette became a **T**, this is also what hands the menu bar
    /// back in the wide states: the mask is the island's *path*, not its bounding
    /// box, and the menu-bar row either side of the stem is outside it. A click
    /// on `File` while the island is expanded falls through to `File`.
    ///
    /// `config` must be the one the view is drawing with, or the mask and the
    /// shape drift: an island narrowed to one ear but masked for two would keep
    /// swallowing menu-bar clicks in a strip that is no longer even black.
    public static func hitTest(_ point: CGPoint, metrics: NotchScreenMetrics,
                               size: NotchHUDSize,
                               config: NotchContentConfig = .default) -> Bool {
        guard metrics.hasHardwareNotch else { return false }
        let l = layout(metrics, size: size, config: config)
        guard !l.island.isEmpty else { return false }
        return islandPath(in: l.island, silhouette: l.silhouette).contains(point)
    }
}
