import { CONFIG } from "./config.js";
import { initTimerDemo, initQuickAddDemo, initExerciseDemo, buildCarousel } from "./demos.js";

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

// ---- links & version --------------------------------------------------------
document.querySelectorAll(".js-download").forEach((a) => (a.href = CONFIG.downloadUrl));
document.querySelectorAll(".js-github").forEach((a) => (a.href = CONFIG.githubUrl));
document.querySelectorAll(".cta-meta").forEach((el) => {
  el.textContent = el.textContent.replace(/v\d+\.\d+\.\d+/, "v" + CONFIG.version);
});
document.getElementById("year").textContent = new Date().getFullYear();

// ---- theme toggle (dark is the default; choice persists) --------------------
const themeMeta = document.querySelector('meta[name="theme-color"]');
document.querySelector(".theme-toggle")?.addEventListener("click", () => {
  const light = document.documentElement.dataset.theme !== "light";
  document.documentElement.dataset.theme = light ? "light" : "";
  themeMeta?.setAttribute("content", light ? "#f6f4f0" : "#0a0b0d");
  try {
    localStorage.setItem("theme", light ? "light" : "");
  } catch {}
});

// ---- "try it live" widgets (no WebGL needed) ---------------------------------
initTimerDemo();
initQuickAddDemo();

// ---- eyes (WebGL) — loaded AFTER first paint so three.js never blocks FCP;
// the CSS .bg-fallback backdrop stays underneath either way -------------------
requestAnimationFrame(() =>
  setTimeout(async () => {
    let mod;
    try {
      mod = await import("./eyes.js");
    } catch {
      return; // no module/WebGL support — static fallback backdrop remains
    }
    const { initEyes, STYLES, STYLE_LABELS } = mod;

    const bgCanvas = document.getElementById("bg-eyes");
    const bg = initEyes(bgCanvas, { eyes: 2, style: "classic" });
    if (!bg) bgCanvas.remove();

    // dim the eyes once the hero scrolls away so content reads
    if (bg) {
      new IntersectionObserver(
        ([e]) => bgCanvas.classList.toggle("dimmed", !e.isIntersecting),
        { threshold: 0.15 }
      ).observe(document.querySelector(".hero"));
    }

    // the demo and drill eyes are extra WebGL contexts — create each only
    // when its section approaches the viewport
    function lazyEye(canvasId, onReady) {
      const canvas = document.getElementById(canvasId);
      new IntersectionObserver(
        ([e], obs) => {
          if (!e.isIntersecting) return;
          obs.disconnect();
          const eye = initEyes(canvas, { eyes: 1, style: "classic" });
          if (!eye) canvas.style.display = "none";
          else onReady(eye);
        },
        { rootMargin: "400px" }
      ).observe(canvas);
    }

    // wallpaper section: the live demo eye + the 18-style carousel picker
    let demo = null;
    lazyEye("demo-eye", (eye) => (demo = eye));
    buildCarousel(STYLES, STYLE_LABELS, (name) => demo?.setStyle(name));

    // eye-health pillar: the drill demo gets its own eye
    lazyEye("exercise-eye", (eye) => initExerciseDemo(eye));
  }, 0)
);

// ---- scroll reveal -----------------------------------------------------------
const io = new IntersectionObserver(
  (entries) =>
    entries.forEach((e) => {
      if (e.isIntersecting) {
        e.target.classList.add("is-visible");
        io.unobserve(e.target);
      }
    }),
  { threshold: 0.12 }
);
document.querySelectorAll("[data-reveal]").forEach((el) => io.observe(el));

// ---- scrollspy: app-like nav that tracks the section in view ------------------
const navLinks = [...document.querySelectorAll('.nav nav > a[href^="#"]')];
const spy = new IntersectionObserver(
  (entries) =>
    entries.forEach((e) => {
      if (!e.isIntersecting) return;
      navLinks.forEach((a) =>
        a.classList.toggle("active", a.getAttribute("href") === "#" + e.target.id)
      );
    }),
  { rootMargin: "-40% 0px -55% 0px" }
);
document.querySelectorAll("main section[id]").forEach((s) => spy.observe(s));

// ---- terminal typing loop ------------------------------------------------------
const LINES = [
  { text: "$ tired start 25", cls: "" },
  { text: "▶ Focus — 25:00", cls: "t-out" },
  { text: "$ tired task add tomorrow p1 #work report", cls: "" },
  { text: "✓ Task added — P1 · #work", cls: "t-out" },
  { text: "$ tired status", cls: "" },
  { text: "● Focus 18:42 remaining · streak 12 days", cls: "t-red" },
  { text: "$ tired skip", cls: "" },
  { text: "☕ Break — eyes off the screen", cls: "t-out" },
];

const body = document.getElementById("terminal-body");
if (reduceMotion) {
  body.replaceChildren(
    ...LINES.flatMap((l) => {
      const s = document.createElement("span");
      s.className = l.cls;
      s.textContent = l.text;
      return [s, "\n"];
    })
  );
} else {
  const caret = document.createElement("span");
  caret.className = "caret";
  let line = 0;
  let typed = "";

  function retype() {
    body.textContent = "";
    for (let i = 0; i < line; i++) {
      const s = document.createElement("span");
      s.className = LINES[i].cls;
      s.textContent = LINES[i].text;
      body.append(s, "\n");
    }
    const cur = document.createElement("span");
    cur.className = LINES[line]?.cls ?? "";
    cur.textContent = typed;
    body.append(cur, caret);
  }

  function tick() {
    const l = LINES[line];
    if (!l) {
      // full loop: hold, then start over
      setTimeout(() => {
        line = 0;
        typed = "";
        retype();
        setTimeout(tick, 400);
      }, 4000);
      return;
    }
    const isOutput = l.cls !== "";
    if (isOutput) {
      // output lines land at once, like a real terminal
      typed = l.text;
      retype();
      line++;
      typed = "";
      setTimeout(tick, 650);
    } else if (typed.length < l.text.length) {
      typed = l.text.slice(0, typed.length + 1);
      retype();
      setTimeout(tick, 24 + Math.random() * 26);
    } else {
      line++;
      typed = "";
      setTimeout(tick, 500);
    }
  }

  // start typing when the terminal scrolls into view
  new IntersectionObserver(
    ([e], obs) => {
      if (e.isIntersecting) {
        obs.disconnect();
        retype();
        setTimeout(tick, 500);
      }
    },
    { threshold: 0.3 }
  ).observe(body);
}
