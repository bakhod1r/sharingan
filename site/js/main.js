import { CONFIG } from "./config.js";
import { initEyes } from "./eyes.js";

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

// ---- links & version --------------------------------------------------------
document.querySelectorAll(".js-download").forEach((a) => (a.href = CONFIG.downloadUrl));
document.querySelectorAll(".js-github").forEach((a) => (a.href = CONFIG.githubUrl));
document.querySelectorAll(".cta-meta").forEach((el) => {
  el.textContent = el.textContent.replace(/v\d+\.\d+\.\d+/, "v" + CONFIG.version);
});
document.getElementById("year").textContent = new Date().getFullYear();

// ---- background eyes (WebGL) — CSS .bg-fallback stays underneath ------------
const bgCanvas = document.getElementById("bg-eyes");
const bg = initEyes(bgCanvas, { eyes: 2, patternIndex: 2 });
if (!bg) bgCanvas.remove();

// dim the eyes once the hero scrolls away so content reads
const hero = document.querySelector(".hero");
if (bg) {
  new IntersectionObserver(
    ([e]) => bgCanvas.classList.toggle("dimmed", !e.isIntersecting),
    { threshold: 0.15 }
  ).observe(hero);
}

// ---- showcase demo eye + pattern picker --------------------------------------
const demoCanvas = document.getElementById("demo-eye");
const demo = initEyes(demoCanvas, { eyes: 1, patternIndex: 2 });
if (!demo) demoCanvas.style.display = "none";
document.querySelectorAll(".pattern-picker button").forEach((btn) =>
  btn.addEventListener("click", () => {
    demo?.setPattern(+btn.dataset.pattern);
    document.querySelector(".pattern-picker .active")?.classList.remove("active");
    btn.classList.add("active");
  })
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
  body.innerHTML = LINES.map(
    (l) => `<span class="${l.cls}">${l.text}</span>`
  ).join("\n");
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
