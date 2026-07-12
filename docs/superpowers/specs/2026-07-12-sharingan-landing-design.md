# Sharingan Landing Page — Design Spec

Date: 2026-07-12
Status: Approved (user: "bos")

## Goal

A premium, single-page marketing site for the Sharingan macOS app with a
download CTA, living in `site/`, deployed via GitHub Pages. The page
background is a three.js recreation of the app's live-wallpaper: two large
Sharingan eyes that follow the mouse, blink, wink, doze, and evolve patterns.

## Decisions (user-approved)

- **Hosting:** GitHub Pages serving `site/`; the Download button points to the
  `Sharingan.dmg` asset on GitHub Releases. Until the repo has a public
  release, the URL lives in ONE constant (`js/config.js`) as a placeholder.
- **Language:** English only.
- **Stack:** Pure static — one `index.html`, hand-written CSS/JS, three.js
  vendored locally (no CDN, no build step, no framework).

## Architecture

```
site/
  index.html          # all content, semantic HTML
  css/style.css       # design system + sections
  js/config.js        # DOWNLOAD_URL, VERSION — the only editable constants
  js/vendor/three.module.min.js   # vendored three.js (ES module)
  js/eyes.js          # three.js scene: eyes, gaze, blink/doze/evolve
  js/main.js          # scroll reveal, nav, terminal typing, misc UI
  assets/             # og-image, favicons, app icon
  robots.txt
  sitemap.xml
```

Each JS unit has one purpose: `eyes.js` exposes `initEyes(canvas)` and knows
nothing about page content; `main.js` handles DOM behavior; `config.js` is
data only.

## Three.js background ("Living Wallpaper")

Fixed full-viewport canvas behind all content (`pointer-events: none`).
Composition mirrors `WallpaperEyesView`: left eye at ~32% width, right at
~68%, dark backdrop (#0a0b0d-ish) with a soft black lower-center shadow and a
deep red vignette.

Each eye:
- Sclera sphere + iris rendered with a custom fragment shader (red radial
  gradient, black pupil, ring, 3 tomoe drawn in shader space so they can
  spin), glossy specular highlight, subtle red rim glow (sprite/bloom-fake).
- **Gaze:** eyes rotate toward the cursor with lerp smoothing and a clamped
  reach (port of `gaze(from:)` with reach=500px logic).
- **Eyelids:** shader/geometry lids driven by the same state machine as the
  wallpaper — random blinks (3.5–8s), alternating winks after ~6s idle,
  full doze after long idle, snap-open + **pattern evolution** step on wake
  (tomoe1 → tomoe2 → classic → mangekyou → …), tomoe spin while idle.
- **Scroll:** parallax drift + fade/dim once past the hero so content reads.
- `prefers-reduced-motion`: static eyes, no spin/blink loops.
- Touch devices: no cursor — slow autonomous wander gaze.
- Performance: single RAF loop, DPR capped at 2, scene paused when tab hidden.

## Page sections

1. **Hero** — display headline ("Your eyes deserve a guardian."), subline
   ("Sharingan — Pomodoro & eye-health for your Mac"), Download .dmg button
   (version + macOS 14+ note), quiet secondary GitHub link. Eyes brightest here.
2. **Features grid** — glass cards from real README features: Pomodoro core,
   Break blocking, Eye exercises + camera blink/gaze detection, Floating
   timer, Tasks & focus queue with NL quick add, Streaks & milestones,
   Ambience + screen dim, iCloud sync, App blocking, Themes, Live Wallpaper,
   `tired` CLI. Hover: subtle red glow.
3. **Wallpaper showcase** — section explaining the live wallpaper; interactive
   mini-demo card reusing the same eye renderer at card size with a pattern
   picker (subset of the 18 styles).
4. **CLI section** — terminal mock card, typing animation cycling `tired`
   commands.
5. **Download CTA** — final section: requirements (macOS 14+, Apple Silicon),
   big .dmg button.
6. **Footer** — © 2026 mrb, GitHub link.

## Visual language

- Palette: obsidian black base, Sharingan red gradient (#c62828 → #ff1744),
  off-white text, liquid-glass cards (backdrop-blur, 1px hairline borders).
- Type: display serif for headlines + grotesk for body, self-hosted subset
  (or system-stack fallback if font files would hurt perf budget).
- Scroll-reveal via IntersectionObserver. No animation libraries.

## SEO (target: Lighthouse SEO 100)

- Semantic landmarks, single `h1`, descriptive headings hierarchy.
- `<title>`, meta description, canonical, theme-color.
- Open Graph + Twitter card with generated og-image (1200×630).
- JSON-LD `SoftwareApplication` (name, OS, price 0 or offers, screenshot).
- `robots.txt`, `sitemap.xml`, favicon set from the app icon, alt text
  everywhere, `loading="lazy"` below the fold, preload of critical assets.
- Verification step: run Lighthouse; SEO must be 100, perf/a11y/best-practices
  as high as feasible with a WebGL canvas present.

## Error handling

- No WebGL → canvas hidden, static CSS radial-gradient fallback backdrop;
  content fully usable.
- Download URL unset → button still renders with placeholder href and a
  `data-todo` marker; console warning.

## Testing / verification

- Serve locally (`python3 -m http.server`), browser-check: gaze follows
  mouse, blink/wink/doze cycle, pattern evolution on wake, scroll fade,
  reduced-motion mode, mobile layout.
- Lighthouse run for SEO 100 evidence.
- HTML validity (no console errors, valid JSON-LD via schema check).

## Out of scope

- Multi-page docs, blog, analytics, i18n, auto-release pipeline, notarization
  docs. Deploy workflow (Pages setup) is a follow-up unless the repo already
  has a GitHub remote.
