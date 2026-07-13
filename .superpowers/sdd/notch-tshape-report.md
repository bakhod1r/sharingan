# Stage 1 — the Notch HUD island becomes a T (stops covering the menu bar)

## What was wrong

`activity` and `expanded` were rectangles anchored to the top of the screen,
340pt / 300pt wide. Because both the drawn shape **and** `NotchGeometry.hitTest`
derive from one silhouette, that rectangle covered — and swallowed clicks on —
the menu-bar titles either side of the notch (`File Edit View` … `Window Help`).

## The shape

The wide states are now a **T**:

- **stem** = the hardware cutout's width, through the menu-bar row (space the
  camera housing already blocks);
- **body** = the island's full width, starting at `y = menuBarHeight`, hanging
  into the desktop, centered under the cutout;
- **concave fillets** where the body flares out of the stem, so the join reads as
  the notch stretching, not two rectangles glued together.

`idle` and `live` are untouched: a stem as wide as the island degenerates the T
back to the rounded-bottom rectangle they always drew, so the ears still sit in
the menu-bar row.

## One path, one mask (the load-bearing invariant)

- New `NotchSilhouette` (SharinganCore) carries the numbers: `stemWidth`,
  `bodyTop`, bottom `cornerRadius`, `bodyTopRadius`, `filletRadius`.
- `NotchGeometry.islandPath(in:silhouette:)` cuts **one** non-convex path from
  them. `IslandShape` draws it; `hitTest` masks against it (`islandPath(in:
  l.island, silhouette: l.silhouette).contains(point)`). The menu-bar strip
  either side of the stem is outside the path → outside the mask → clickable
  menu bar again.
- Path construction: stem top edge → down the stem → **outward** quad fillet into
  the menu-bar row → body top edge → body top corner → right/bottom/left rounded
  corners → back up → left fillet → close. Traced consistently, no
  self-intersection; `CGPath.contains` (nonzero winding) fills the interior.
- **Only the corner radius animates** on `IslandShape` (`animatableData`). The
  stem width and body top are deliberately *not* animatable, so they snap to the
  new state's value the instant the hit-test mask does, while the frame springs
  underneath — the drawn shape stays inside the mask through the whole morph, in
  both directions. `NotchGeometry.flat(...)` gives the short/closing states a
  `bodyTop` too, so a closing overhang (frame still 340-wide, mask already
  live-narrow) is drawn as a T hanging *below* the menu bar (over the desktop,
  click-through) instead of a slab across the titles.

## Path/geometry construction (exact)

`stemWidth = cutout.width`, `bodyTop = m.stemHeight = max(menuBarHeight,
notchHeight)` (floored at the housing so it never eats the top of the timer).
`expandedSize(config, menuBarHeight:)` = `menuBarHeight + expandedBodyHeight`.
The cutout's height is no longer in the island height — the body starts below the
menu bar, so the housing is the stem's problem, not the content's.

## Measured height constants (standalone replica, /private/tmp/notch-measure)

The replica reproduces the shipped table exactly at top-padding 0
(160/158/188/218/248/278 for 0…5 rows), so it is faithful. The T gave the body
its own **10pt top padding** (an inset from a rounded edge) where it used to have
a 6pt gap under the camera housing. Re-measured body heights (top padding 10):

| rows | 0 | 1 | 2 | 3 | 4 | 5 |
|------|---|---|---|---|---|---|
| body | 170 | 168 | 198 | 228 | 258 | **288** |

Changed constants: `contentTopGap: 6` → **`contentTopPadding: 10`**;
`activitySize = 300×68` (const) → **`activitySize(menuBarHeight:) = 300 ×
(menuBarHeight + 44)`**, `activityBodyHeight = 44` (16pt icon+line inside 14pt
air top and bottom, measured). Full five-row island over a 37pt menu bar =
`37 + 288 + 4 slack = 329` (was 321+4=325 under a 37pt cutout).

## Geometry tests added (`@Suite "Notch T-shape"`, plus 2 in the sizing suite)

For a 200pt cutout on a 1512pt screen, menu bar 37, expanded:
- a point in the menu-bar row **100pt left of the cutout's edge is NOT hittable**
  (and 100pt right of it, over the status items, likewise) — in `expanded` and
  `activity` alike;
- a point in the **stem** (over the housing) IS hittable;
- a point in the **body** (below the menu bar) IS hittable;
- a point in the **notch-row gap** between the stem's edge and the body's edge is
  NOT hittable, though it is inside the island's bounding box;
- a **full sweep** of the menu-bar row asserts nothing but the cutout (± the 10pt
  fillet flare) is hittable;
- the fillet flares outward and is bounded to a `filletRadius` square against the
  housing; the body follows `menuBarHeight` for 24/37/55; the T holds for every
  row count 0…5 and tasks on/off; the flat states keep their rectangle and the
  live island's whole row stays solid.

## Dependents fixed

- `NotchExpandedPanel`: top padding was `cutout.height + 6`; now the content
  fills `layout.body` (below the menu bar), inset by `contentTopPadding`.
- `NotchActivityView`: dropped its `contentTop = cutout+4` push; centers in
  `layout.body`.
- `NotchHUDView` / `IslandShape`: draw, stroke and clip from `l.silhouette`.
- `NotchMotion`: doc updated — the mask is now a non-convex path; the spring that
  would break it is the one that doesn't exist (silhouette stem/body-top are not
  animatable). `NotchLayout` gained `body` and `silhouette`; `cornerRadius` is now
  a computed passthrough.
- `docs/TECHNICAL.md` notch section updated.

## What I SAW

Headless previews re-rendered (`swift run Sharingan --render-dev-preview
/private/tmp/notch-native-preview`) — these drive the **real** production views
(`NotchHUDView` → `IslandShape` → `NotchGeometry.islandPath`, `NotchExpandedPanel`)
with 14"-MacBook-Pro fixture metrics, over a grey menu-bar stand-in:

- `notch-expanded.png` — stem is cutout-width through the menu-bar row; grey
  stand-in visible either side of it (no black slab); body hangs below with the
  timer/tasks/actions filling it; concave fillets flare outward at the join (no
  square inner corner). Correct.
- `notch-activity.png` — "Break time" centered in the body, T stem above.
- `notch-expanded-empty.png` — shorter T, "Nothing planned for today" in the body.
- `notch-live.png` / `notch-idle` — unchanged flat rectangle with ears + progress
  bar.

## Doubts / limits (honest)

1. **I could NOT take a live `screencapture` on real notched hardware.** This
   execution environment is a **notchless 1440×900 headless machine**
   (`safeAreaInsets.top == 0`, aux areas nil), so the runtime HUD tears itself
   down here (`hudScreen()` → nil), and `screencapture` is blocked outright
   ("could not create image from display" — no Screen Recording permission). The
   plan assumed a notched dev machine with a working display; this sandbox is
   neither. The headless previews are the faithful substitute — the same view
   code, driven by fixture metrics, written to PNG by the app's own renderer
   rather than by screencapture — and they show the T correctly. A human on the
   real MacBook should still eyeball it once.
2. The fillet quad is a single quadratic; at very tall menu bars it stays a clean
   flare, but I did not tune its curvature against a real Dynamic Island — a
   designer may want a two-arc S-fillet in stage 2. Shape is correct and the mask
   matches it; this is taste, not correctness.
3. `activityBodyHeight = 44` is measured for the current one-line announcement; a
   two-line announcement would need re-measuring (same as before).
