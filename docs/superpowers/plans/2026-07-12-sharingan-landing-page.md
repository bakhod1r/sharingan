# Sharingan Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Premium single-page marketing + download site for the Sharingan macOS app in `site/`, with a three.js background of two Sharingan eyes that follow the mouse and behave like the app's live wallpaper.

**Architecture:** Pure static site — one `index.html`, hand-written CSS, vanilla ES-module JS, three.js vendored locally. `eyes.js` is a self-contained WebGL renderer exposing `initEyes(canvas, opts)`; `main.js` handles DOM behavior; `config.js` holds the only editable constants.

**Tech Stack:** HTML5, CSS (no framework), three.js (vendored ES module), GitHub Pages.

## Global Constraints

- No build step, no npm, no CDN at runtime — three.js is committed at `site/js/vendor/three.module.min.js`.
- English copy only. Single `h1`. Lighthouse SEO score must be 100.
- Canonical URL: `https://bakhod1r.github.io/Blink/`. Download URL: `https://github.com/bakhod1r/Blink/releases/latest/download/Sharingan.dmg` (both only in `js/config.js` + static head tags).
- Palette: bg `#0a0b0d`, red gradient `#c62828 → #ff1744`, text `#ece9e4`. Requirements line: "macOS 14+ · Apple Silicon".
- Respect `prefers-reduced-motion`; page must be fully usable without WebGL.
- Commit + push after every task (multi-Mac workflow).

---

### Task 1: Scaffold + vendored three.js + config

**Files:**
- Create: `site/js/vendor/three.module.min.js` (vendored)
- Create: `site/js/config.js`
- Create: `site/.nojekyll` (empty — GitHub Pages must not run Jekyll)

**Interfaces:**
- Produces: `CONFIG` object `{version, downloadUrl, githubUrl, siteUrl}` imported by `main.js`; `three.module.min.js` imported by `eyes.js` as `./vendor/three.module.min.js`.

- [ ] **Step 1: Vendor three.js**

```bash
cd /Users/mrb/Desktop/Blink
mkdir -p site/js/vendor site/css site/assets
curl -sL -o site/js/vendor/three.module.min.js https://unpkg.com/three@0.160.0/build/three.module.min.js
head -c 200 site/js/vendor/three.module.min.js   # sanity: starts with license banner / const
```

Expected: file ~650KB, valid JS.

- [ ] **Step 2: Write config.js**

```js
// site/js/config.js
export const CONFIG = {
  version: "1.0.0",
  downloadUrl:
    "https://github.com/bakhod1r/Blink/releases/latest/download/Sharingan.dmg",
  githubUrl: "https://github.com/bakhod1r/Blink",
  siteUrl: "https://bakhod1r.github.io/Blink/",
};
```

- [ ] **Step 3: Create `.nojekyll`, commit**

```bash
touch site/.nojekyll
git add site && git commit -m "feat(site): scaffold — vendored three.js, config" && git push
```

### Task 2: index.html — full content + SEO head

**Files:**
- Create: `site/index.html`
- Create: `site/robots.txt`, `site/sitemap.xml`

**Interfaces:**
- Produces: DOM hooks used by JS — `#bg-eyes` (fixed canvas), `#demo-eye` (showcase canvas), `.pattern-picker button[data-pattern]`, `#terminal-body` (typing target), `[data-reveal]` (scroll reveal), `a.js-download` (href set from CONFIG), `#year`.

- [ ] **Step 1: Write index.html**

Head (exact):

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Sharingan — Pomodoro & Eye-Health App for macOS</title>
  <meta name="description" content="Sharingan is a free macOS menu-bar Pomodoro and eye-health app: enforced screen breaks, camera-verified eye exercises, tasks with natural-language input, streaks, and a live Sharingan wallpaper.">
  <link rel="canonical" href="https://bakhod1r.github.io/Blink/">
  <meta name="theme-color" content="#0a0b0d">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Sharingan — Pomodoro & Eye-Health App for macOS">
  <meta property="og:description" content="Enforced breaks, camera-verified eye exercises, tasks, streaks — and a desktop that watches back.">
  <meta property="og:url" content="https://bakhod1r.github.io/Blink/">
  <meta property="og:image" content="https://bakhod1r.github.io/Blink/assets/og-image.png">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Sharingan — Pomodoro & Eye-Health App for macOS">
  <meta name="twitter:description" content="Enforced breaks, camera-verified eye exercises, tasks, streaks — and a desktop that watches back.">
  <meta name="twitter:image" content="https://bakhod1r.github.io/Blink/assets/og-image.png">
  <link rel="icon" href="assets/favicon.ico" sizes="32x32">
  <link rel="icon" href="assets/icon.svg" type="image/svg+xml">
  <link rel="apple-touch-icon" href="assets/apple-touch-icon.png">
  <link rel="stylesheet" href="css/style.css">
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    "name": "Sharingan",
    "operatingSystem": "macOS 14.0 or later",
    "applicationCategory": "UtilitiesApplication",
    "description": "Pomodoro and eye-health app for macOS with enforced breaks, camera-verified eye exercises, task management, streaks, and a live wallpaper.",
    "offers": { "@type": "Offer", "price": "0", "priceCurrency": "USD" },
    "downloadUrl": "https://github.com/bakhod1r/Blink/releases/latest/download/Sharingan.dmg",
    "author": { "@type": "Person", "name": "mrb" },
    "url": "https://bakhod1r.github.io/Blink/"
  }
  </script>
</head>
```

Body structure (semantic; all sections carry `data-reveal` on inner blocks):

```html
<body>
  <canvas id="bg-eyes" aria-hidden="true"></canvas>
  <div class="bg-fallback" aria-hidden="true"></div>

  <header class="nav">
    <a class="brand" href="#">Sharingan</a>
    <nav aria-label="Primary">
      <a href="#features">Features</a>
      <a href="#wallpaper">Wallpaper</a>
      <a href="#cli">CLI</a>
      <a class="btn btn-ghost js-github" href="#">GitHub</a>
    </nav>
  </header>

  <main>
    <section class="hero">
      <p class="eyebrow">For macOS — free &amp; open</p>
      <h1>Your eyes deserve <span class="red">a guardian</span>.</h1>
      <p class="sub">Sharingan is a menu-bar Pomodoro &amp; eye-health companion —
        enforced screen breaks, camera-verified eye exercises, tasks, streaks,
        and a desktop that watches back.</p>
      <div class="cta-row">
        <a class="btn btn-red js-download" href="#">Download for Mac</a>
        <span class="cta-meta">v1.0.0 · macOS 14+ · Apple Silicon · free</span>
      </div>
    </section>

    <section id="features" aria-labelledby="features-h">
      <h2 id="features-h">Everything a tired pair of eyes needs</h2>
      <ul class="grid">…12 feature cards (copy table below)…</ul>
    </section>

    <section id="wallpaper" aria-labelledby="wallpaper-h">
      <h2 id="wallpaper-h">A desktop that watches back</h2>
      <p>Sharingan ships a live wallpaper: two eyes on your desktop that follow
         your cursor, blink, wink when you're idle, doze off when you're away —
         and wake with the next pattern in the evolution chain.
         <strong>This page's background is that same engine, rebuilt in WebGL.</strong></p>
      <div class="demo-card">
        <canvas id="demo-eye" aria-label="Interactive Sharingan eye demo"></canvas>
        <div class="pattern-picker" role="group" aria-label="Eye pattern">
          <button data-pattern="0">1 tomoe</button>
          <button data-pattern="1">2 tomoe</button>
          <button data-pattern="2" class="active">3 tomoe</button>
          <button data-pattern="3">Mangekyō</button>
          <button data-pattern="4">Rinnegan</button>
        </div>
      </div>
    </section>

    <section id="cli" aria-labelledby="cli-h">
      <h2 id="cli-h">Terminal-grade control</h2>
      <p>The <code>tired</code> CLI and a <code>sharingan://</code> URL scheme
         drive the timer from Terminal, Shortcuts or Raycast.</p>
      <div class="terminal" role="img" aria-label="Terminal showing tired CLI commands">
        <div class="terminal-bar"><span></span><span></span><span></span></div>
        <pre id="terminal-body"></pre>
      </div>
    </section>

    <section id="download" aria-labelledby="download-h">
      <h2 id="download-h">Rest your eyes. Keep your streak.</h2>
      <p>Free download. No account, no tracking — camera frames never leave your Mac.</p>
      <a class="btn btn-red btn-lg js-download" href="#">Download Sharingan.dmg</a>
      <p class="cta-meta">macOS 14+ · Apple Silicon</p>
    </section>
  </main>

  <footer>
    <p>© <span id="year">2026</span> mrb · <a class="js-github" href="#">Source on GitHub</a></p>
  </footer>
  <script type="module" src="js/main.js"></script>
</body>
</html>
```

Feature card copy (each `<li class="card" data-reveal>` = `<h3>` + `<p>`):

| h3 | p |
|---|---|
| Pomodoro, your rules | Countdown or count-up, custom focus and break lengths, long breaks every N rounds, auto-start and repeat. |
| Breaks you can't skip past | A full-screen liquid-glass overlay on every monitor. ⌘Q, ⌘W and app switching stay blocked until your eyes rest. |
| Camera-verified exercises | 20-20-20, 8-direction gaze and blink drills — validated live on-device with Vision face landmarks. |
| Private by design | Blink and gaze detection run entirely on your Mac, with a pulsing indicator whenever the camera is on. |
| Floating timer | An always-on-top glass chip that joins every Space. Drag it anywhere; it steps aside during breaks. |
| Tasks & focus queue | Priorities P1–P4, tags, projects, subtasks, recurrence. Queue tasks — each pomodoro advances to the next. |
| Natural-language input | “tomorrow 15:00 p1 #work report”, “5pm”, “+15m” — English and Uzbek shorthand, parsed live. |
| Streaks & milestones | Daily streaks with badges at 1, 7, 14, 30, 90 and 365 days, plus 7/30-day focus charts. |
| Break comfort | Rain, forest, white-noise or lo-fi ambience, smooth screen dimming, posture and water reminders. |
| App blocking | Hide or force-quit Chrome, Slack, Telegram and friends the moment a break starts. |
| iCloud sync | Settings and streaks follow you to every Mac through your private CloudKit database. |
| Six themes + CLI | Liquid Glass, Frosted, Midnight, Cream, Neon, Mono — and the `tired` CLI for everything. |

- [ ] **Step 2: robots.txt + sitemap.xml**

```
# site/robots.txt
User-agent: *
Allow: /
Sitemap: https://bakhod1r.github.io/Blink/sitemap.xml
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://bakhod1r.github.io/Blink/</loc></url>
</urlset>
```

- [ ] **Step 3: Verify + commit**

```bash
python3 -m http.server 4173 -d site &   # then curl -s localhost:4173 | grep -c '<h1'  → 1
git add site && git commit -m "feat(site): index.html with full content + SEO head" && git push
```

### Task 3: style.css — premium design system + all sections

**Files:**
- Create: `site/css/style.css`

**Interfaces:**
- Consumes: class names from Task 2.
- Produces: `.is-visible` class contract for `[data-reveal]` (main.js adds it); `--eyes-dim` custom property on `:root` (eyes.js reads nothing from CSS; main.js sets canvas opacity via class `.dimmed`).

- [ ] **Step 1: Write the design system + layout**

Tokens and core (exact):

```css
:root {
  --bg: #0a0b0d;
  --ink: #ece9e4;
  --muted: #9a948c;
  --red: #ff1744;
  --red-deep: #c62828;
  --hairline: rgba(236, 233, 228, 0.08);
  --glass: rgba(18, 19, 23, 0.55);
  --font-display: "Iowan Old Style", "Palatino", Georgia, serif;
  --font-body: -apple-system, "SF Pro Text", "Helvetica Neue", Inter, sans-serif;
}
* { box-sizing: border-box; margin: 0; }
html { scroll-behavior: smooth; }
body { background: var(--bg); color: var(--ink); font: 16px/1.65 var(--font-body); }
#bg-eyes { position: fixed; inset: 0; width: 100%; height: 100%;
           pointer-events: none; transition: opacity .6s ease; }
#bg-eyes.dimmed { opacity: .22; }
.bg-fallback { position: fixed; inset: 0; z-index: -1; background:
  radial-gradient(60% 45% at 50% 70%, rgba(198,40,40,.10), transparent 70%), var(--bg); }
h1 { font: 700 clamp(2.6rem, 7vw, 5rem)/1.05 var(--font-display); letter-spacing: -.02em; }
h2 { font: 600 clamp(1.7rem, 4vw, 2.6rem)/1.15 var(--font-display); }
.red { background: linear-gradient(120deg, var(--red-deep), var(--red));
       -webkit-background-clip: text; background-clip: text; color: transparent; }
```

Then, complete styles for: sticky glass `header.nav`; `.hero` (min-height 92vh, centered column, eyebrow in letterspaced small caps red); `.btn` / `.btn-red` (red gradient, subtle outer glow `box-shadow: 0 0 32px rgba(255,23,68,.25)`, hover lift) / `.btn-ghost` / `.btn-lg`; `.grid` (auto-fit minmax(280px,1fr) gap 1.25rem); `.card` (glass: `background: var(--glass); backdrop-filter: blur(14px); border: 1px solid var(--hairline); border-radius: 18px; padding: 1.5rem;` hover → border-color rgba(255,23,68,.35) + glow); `.demo-card` (glass card, canvas 100%×360px, picker buttons pill glass, `.active` red); `.terminal` (dark card, 3 dots bar, `pre` in ui-monospace, min-height 260px); `#download` centered; `footer` hairline top, muted. Sections: `max-width: 1080px; margin: 0 auto; padding: 7rem 1.5rem;` `main { position: relative; z-index: 1; }`.

Reveal contract:

```css
[data-reveal] { opacity: 0; transform: translateY(24px);
  transition: opacity .7s ease, transform .7s cubic-bezier(.2,.7,.2,1); }
[data-reveal].is-visible { opacity: 1; transform: none; }
@media (prefers-reduced-motion: reduce) {
  [data-reveal] { opacity: 1; transform: none; transition: none; }
  html { scroll-behavior: auto; }
}
```

- [ ] **Step 2: Verify + commit**

Serve, check hero/grid/terminal render well at 1440px, 768px, 390px widths (browser tool or screenshots).

```bash
git add site/css && git commit -m "feat(site): premium design system + section styles" && git push
```

### Task 4: eyes.js — three.js eye renderer with gaze follow

**Files:**
- Create: `site/js/eyes.js`

**Interfaces:**
- Consumes: `./vendor/three.module.min.js`.
- Produces: `initEyes(canvas, opts) -> { setPattern(i), dispose() }` where `opts = { eyes: 1|2, interactive: bool, patternIndex: int }`. Pattern indices: 0=1-tomoe, 1=2-tomoe, 2=3-tomoe, 3=mangekyou, 4=rinnegan.

- [ ] **Step 1: Scene + eye construction**

Renderer: `WebGLRenderer({canvas, alpha:true, antialias:true})`, DPR capped at 2, `PerspectiveCamera(35)` at z=10. Try/catch around context creation → on failure return `null` (caller shows `.bg-fallback` only).

Each eye = `THREE.Group`:
- Sclera: `SphereGeometry(1, 48, 48)`, `MeshStandardMaterial({ color: 0x1a1b1f, roughness: .35 })` — dark anime sclera so the red iris dominates.
- Iris: `CircleGeometry(0.58, 64)` positioned `z=0.828` (on sphere surface: √(1−0.58²)≈0.815, +epsilon), with `ShaderMaterial` (Step 2).
- Highlight: small white `CircleGeometry(0.09)` sprite-ish mesh at upper-left of iris, `MeshBasicMaterial` opacity .85.
- Lid: `SphereGeometry(1.03, 48, 48)` with `ShaderMaterial` that discards fragments below the lid line: uniform `uOpen` (0 closed…1 open); fragment keeps (renders skin `#0e0f12`) where `vLocalY > mix(-1.05, 1.05, uOpen)` — i.e. lid descends from above as `uOpen` falls; else `discard`.
- Red rim glow: `Sprite` with radial-gradient `CanvasTexture` (red → transparent), scale 3.2, behind eye, `AdditiveBlending`, opacity .28.

Layout: two eyes at world x ≈ ±2.3 (matching wallpaper 32%/68%), y ≈ +0.3; scale from viewport so eye height ≈ `min(w*0.13, h*0.24)` px. Lights: ambient .55 + directional from camera-left.

Gaze (port of `WallpaperEyesView.gaze`): pointer position → offset from each eye's screen-projected center, divided by `reach = 500` px, clamped to length 1 → target yaw/pitch (max ±0.45 rad). Per-frame `group.rotation.x/y` lerp toward target at .08. Touch/no pointer: slow Lissajous wander (`sin(t*.23)`, `cos(t*.17)` × .2).

- [ ] **Step 2: Iris fragment shader (patterns)**

ShaderMaterial uniforms: `uSpin` (radians), `uPattern` (int 0–4), `uEmergence` (0–1, pattern scale-out from pupil). UV → polar `(r, a)` with `a += uSpin`. Layers:
1. Base: radial gradient `mix(#4a0508, #c62828, smoothstep(1.0, 0.15, r))` with darkened outer ring at `r > .92` (black rim).
2. Pupil: black disc `r < .16`, soft edge.
3. Pattern (scaled by `uEmergence`, drawn at orbit `r≈.5`):
   - 0/1/2 → 1/2/3 tomoe: for i in count, tomoe = head circle (radius .10 at orbit angle `i*2π/count`) + tail: arc band trailing 70°, width tapering `mix(.09, .0, t)`. SDF union, filled black.
   - 3 mangekyou: 3 curved blades — `abs(fract(a*3/2π + curve(r)) - .5) < width(r)` styled triangle sweep, black, plus thin ring at orbit.
   - 4 rinnegan: whole iris overridden to purple-grey base (`#8a7fb5` → `#3e3860`) with 4 concentric dark rings `abs(sin(r*4π))` bands; no tomoe.
4. Fine ring at `r=.5` connecting tomoe (classic look), skipped for rinnegan.

- [ ] **Step 3: Animation loop + API**

Single RAF; `document.hidden` → pause via `visibilitychange`. `uSpin += dt * spinSpeed` where `spinSpeed` eases 0 ↔ 1.1 rad/s (idle → spin after 1.2s mouse stillness, like wallpaper `idleDelay`). `setPattern(i)` sets `uPattern` and replays emergence (`uEmergence` 0→1 over .9s easeOut). `initEyes` reads `opts.eyes` (bg=2, demo=1), handles `ResizeObserver`.

- [ ] **Step 4: Verify + commit**

Temporary test page or wire into main.js directly; check in browser: two eyes render, follow cursor smoothly, tomoe spin on idle.

```bash
git add site/js/eyes.js && git commit -m "feat(site): three.js sharingan eyes with gaze follow" && git push
```

### Task 5: eyes.js — wallpaper behaviors (blink/wink/doze/evolve) + scroll integration

**Files:**
- Modify: `site/js/eyes.js`

**Interfaces:**
- Produces: same `initEyes` API; behaviors run internally. Scroll dimming stays in main.js via canvas class (Task 6).

- [ ] **Step 1: Eyelid state machine (port of `updateEyelids`)**

State per scene: `lastMoved` (pointer timestamp), per-eye `lidTarget`, `dozing`, `nextBlink`, `winkRightNext`, `chainOffset`. Tick every 200ms (setInterval, cleared on dispose):

- still > 45s (web doze delay) and not dozing → `dozing=true`, both lids → 0 over .9s, emergence → 0 over .7s.
- movement while dozing → wake: `chainOffset++` → `setPattern((base + chainOffset) % 5)`, lids → 1 in .25s, emergence 0→1 over .8s.
- not dozing, `now >= nextBlink`:
  - still > 6s → wink (alternate side, hold .45s), `nextBlink = now + rand(2.5,4)`
  - else 30% wink / 70% both-lid blink (close .09s, hold .11s, open .16s), `nextBlink = now + rand(3.5,8)`.

Lid animation: per-frame `uOpen` lerp toward target with per-transition duration (store `{from,to,start,dur,ease}` tween per lid).

`prefers-reduced-motion: reduce` → skip interval entirely: eyes static, `uEmergence=1`, gaze still follows (no spin/blink).

- [ ] **Step 2: Scroll parallax**

In RAF: `const s = scrollY / innerHeight;` eyes group `position.y += s * 1.2` (drift up), slight `rotation.z = s * .05`. (Dim/fade handled by main.js class.)

- [ ] **Step 3: Verify + commit**

Browser: wait 6s idle → winks alternate; simulate doze (temporarily set doze=8s) → eyes close, move mouse → wake with NEXT pattern. Restore 45s. Reduced-motion via DevTools emulation → static.

```bash
git add site/js/eyes.js && git commit -m "feat(site): blink/wink/doze/pattern-evolution behaviors" && git push
```

### Task 6: main.js — page behavior + wiring

**Files:**
- Create: `site/js/main.js`

**Interfaces:**
- Consumes: `CONFIG` from `./config.js`; `initEyes` from `./eyes.js`; DOM hooks from Task 2.

- [ ] **Step 1: Write main.js**

```js
import { CONFIG } from "./config.js";
import { initEyes } from "./eyes.js";

// Links & version
document.querySelectorAll(".js-download").forEach(a => (a.href = CONFIG.downloadUrl));
document.querySelectorAll(".js-github").forEach(a => (a.href = CONFIG.githubUrl));
document.querySelectorAll(".cta-meta").forEach(el =>
  (el.textContent = el.textContent.replace("v1.0.0", "v" + CONFIG.version)));
document.getElementById("year").textContent = new Date().getFullYear();

// Background eyes (fallback: canvas removed, .bg-fallback remains)
const bgCanvas = document.getElementById("bg-eyes");
const bg = initEyes(bgCanvas, { eyes: 2, patternIndex: 2 });
if (!bg) bgCanvas.remove();

// Dim eyes past the hero
const hero = document.querySelector(".hero");
new IntersectionObserver(([e]) =>
  bgCanvas.classList.toggle("dimmed", !e.isIntersecting),
  { threshold: 0.15 }).observe(hero);

// Showcase demo eye + pattern picker
const demo = initEyes(document.getElementById("demo-eye"), { eyes: 1, patternIndex: 2 });
document.querySelectorAll(".pattern-picker button").forEach(btn =>
  btn.addEventListener("click", () => {
    demo?.setPattern(+btn.dataset.pattern);
    document.querySelector(".pattern-picker .active")?.classList.remove("active");
    btn.classList.add("active");
  }));

// Scroll reveal
const io = new IntersectionObserver(entries => entries.forEach(e => {
  if (e.isIntersecting) { e.target.classList.add("is-visible"); io.unobserve(e.target); }
}), { threshold: 0.12 });
document.querySelectorAll("[data-reveal]").forEach(el => io.observe(el));

// Terminal typing loop
const LINES = [
  "$ tired start 25", "▶ Focus — 25:00",
  "$ tired task add tomorrow p1 #work report", "✓ Task added — P1 · #work",
  "$ tired status", "● Focus 18:42 remaining · streak 12 days",
  "$ tired skip", "☕ Break — eyes off the screen",
];
```

…plus the typing loop: type LINES sequentially into `#terminal-body` char-by-char (24ms/char, 700ms line pause, loop with 4s hold; skip entirely under reduced motion — print all lines at once).

- [ ] **Step 2: Verify + commit**

Browser: download/GitHub hrefs correct, demo pattern buttons switch pattern, reveal works, terminal types.

```bash
git add site/js/main.js && git commit -m "feat(site): page wiring — demo picker, reveal, terminal" && git push
```

### Task 7: Assets — favicons + og-image

**Files:**
- Create: `site/assets/favicon.ico`, `site/assets/icon.svg`, `site/assets/apple-touch-icon.png`, `site/assets/og-image.png`

- [ ] **Step 1: Generate from app icon**

Source: `Sources/Sharingan/Resources/AppIcon.png`.

```bash
cd /Users/mrb/Desktop/Blink
sips -z 180 180 Sources/Sharingan/Resources/AppIcon.png --out site/assets/apple-touch-icon.png
sips -z 32 32 Sources/Sharingan/Resources/AppIcon.png --out site/assets/favicon-32.png
# ico: single-size png-in-ico is fine for the web
python3 - <<'EOF'
from struct import pack
png = open('site/assets/favicon-32.png','rb').read()
ico = pack('<3H', 0, 1, 1) + pack('<4B2H2I', 32, 32, 0, 0, 1, 32, len(png), 22) + png
open('site/assets/favicon.ico','wb').write(ico)
EOF
rm site/assets/favicon-32.png
```

`icon.svg`: hand-write a minimal Sharingan mark (red circle, black pupil, 3 comma tomoe) — reuse geometry from `Views/IconRenderer.swift` proportions.

og-image (1200×630): render via a small HTML file + headless Chrome screenshot, or compose with `sips`/Python PIL if available: dark bg, centered app icon at 256px, "Sharingan" display text, red glow. Any reproducible local method is fine; commit the PNG.

- [ ] **Step 2: Commit**

```bash
git add site/assets && git commit -m "feat(site): favicons + og-image" && git push
```

### Task 8: Verification — browser pass + Lighthouse SEO 100

- [ ] **Step 1: Full browser pass** (use browser-testing skill / Playwright): desktop 1440, mobile 390 — hero, gaze follow, blink/wink, pattern picker, terminal, download hrefs, no console errors.
- [ ] **Step 2: Lighthouse**

```bash
npx --yes lighthouse http://localhost:4173 --only-categories=seo,performance,accessibility,best-practices --chrome-flags="--headless=new" --output=json --output-path=/tmp/lh.json
python3 -c "import json;d=json.load(open('/tmp/lh.json'));print({k:round(v['score']*100) for k,v in d['categories'].items()})"
```

Expected: `seo: 100`. Fix anything short (meta, contrast, tap targets) and re-run.

- [ ] **Step 3: Validate JSON-LD** (paste into schema validator or check with python json.loads on the extracted block), final commit + push.

```bash
git add -A site && git commit -m "feat(site): sharingan landing page — verified, SEO 100" && git push
```

---

## Deploy note (follow-up, not in this plan)

Enable GitHub Pages via Actions (branch-deploy only supports `/` or `/docs`, not `/site`): add `.github/workflows/pages.yml` using `actions/upload-pages-artifact` with `path: site` + `actions/deploy-pages`, and set repo Settings → Pages → Source → GitHub Actions. Publish a GitHub Release with `Sharingan.dmg` so the download URL resolves.
