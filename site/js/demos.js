// "Try it live" widgets — tiny in-page recreations of the app's three
// pillars: a working pomodoro, the natural-language quick add, and the
// 8-direction gaze drill (driven by the WebGL eye).

const $ = (id) => document.getElementById(id);
const pad = (n) => String(n).padStart(2, "0");

// ---- 1. Mini pomodoro (60× speed: one "minute" ticks by per second) --------
export function initTimerDemo() {
  const time = $("dt-time");
  const phase = $("dt-phase");
  const ring = document.querySelector(".dt-progress");
  const toggle = $("dt-toggle");
  if (!time) return;

  const FOCUS = 25 * 60;
  const BREAK = 5 * 60;
  let total = FOCUS;
  let left = FOCUS;
  let focus = true;
  let timerId = 0;

  const C = 2 * Math.PI * 54;
  ring.style.strokeDasharray = C;

  function paint() {
    time.textContent = `${pad(Math.floor(left / 60))}:${pad(left % 60)}`;
    phase.textContent = focus ? "Focus" : "Break";
    ring.style.strokeDashoffset = C * (1 - left / total);
    document.querySelector(".demo-timer").classList.toggle("is-break", !focus);
  }

  function switchPhase(toFocus) {
    focus = toFocus;
    total = focus ? FOCUS : BREAK;
    left = total;
    paint();
  }

  function tick() {
    left = Math.max(0, left - 60); // one "minute" per real second
    if (left === 0) {
      switchPhase(!focus);
    } else {
      paint();
    }
  }

  function setRunning(run) {
    clearInterval(timerId);
    timerId = run ? setInterval(tick, 1000) : 0;
    toggle.textContent = run ? "Pause" : "Start";
  }

  toggle.addEventListener("click", () => setRunning(!timerId));
  $("dt-skip").addEventListener("click", () => {
    switchPhase(!focus);
  });
  $("dt-reset").addEventListener("click", () => {
    setRunning(false);
    switchPhase(true);
  });
  paint();
}

// ---- 2. Natural-language quick add ------------------------------------------
// A small port of the app's parser: p1–p4, #tag, @project, ~estimate,
// times ("15:00", "5pm") and day words in English and Uzbek.
export function parseQuickAdd(text) {
  let title = [];
  const out = { tags: [], project: null, priority: null, due: null, time: null, estimate: null };
  for (const raw of text.trim().split(/\s+/)) {
    const w = raw.toLowerCase();
    let m;
    if ((m = w.match(/^p([1-4])$/))) out.priority = "P" + m[1];
    else if (raw.startsWith("#") && raw.length > 1) out.tags.push(raw.slice(1));
    else if (raw.startsWith("@") && raw.length > 1) out.project = raw.slice(1);
    else if ((m = w.match(/^~(\d+)$/))) out.estimate = +m[1];
    else if (/^\d{1,2}:\d{2}$/.test(w)) out.time = w;
    else if ((m = w.match(/^(\d{1,2})(am|pm)$/))) out.time = m[1] + " " + m[2];
    else if (w === "today" || w === "bugun") out.due = "today";
    else if (w === "tomorrow" || w === "ertaga") out.due = "tomorrow";
    else title.push(raw);
  }
  out.title = title.join(" ");
  return out;
}

const PRIORITY_COLOR = { P1: "#ff1744", P2: "#ff9100", P3: "#448aff", P4: "#9aa3af" };

export function initQuickAddDemo() {
  const input = $("qa-input");
  const chips = $("qa-chips");
  const list = $("qa-list");
  if (!input) return;

  function chip(label, cls = "") {
    const s = document.createElement("span");
    s.className = "qa-chip " + cls;
    s.textContent = label;
    return s;
  }

  function renderChips() {
    const p = parseQuickAdd(input.value);
    chips.replaceChildren();
    if (p.title) chips.append(chip(p.title, "qa-title"));
    if (p.due) chips.append(chip("📅 " + p.due));
    if (p.time) chips.append(chip("🕒 " + p.time));
    if (p.priority) {
      const c = chip(p.priority);
      c.style.color = PRIORITY_COLOR[p.priority];
      chips.append(c);
    }
    for (const t of p.tags) chips.append(chip("#" + t));
    if (p.project) chips.append(chip("@" + p.project));
    if (p.estimate) chips.append(chip("🍅 ×" + p.estimate));
  }

  function addTask(p) {
    if (!p.title) return;
    const li = document.createElement("li");
    const dot = document.createElement("span");
    dot.className = "qa-dot";
    dot.style.background = PRIORITY_COLOR[p.priority ?? "P4"];
    const label = document.createElement("span");
    label.className = "qa-task-title";
    label.textContent = p.title;
    li.append(dot, label);
    const meta = [p.due, p.time, ...(p.tags ?? []).map((t) => "#" + t)]
      .filter(Boolean)
      .join(" · ");
    if (meta) {
      const m = document.createElement("span");
      m.className = "qa-meta";
      m.textContent = meta;
      li.append(m);
    }
    li.addEventListener("click", () => li.classList.toggle("done"));
    list.prepend(li);
  }

  input.addEventListener("input", renderChips);
  input.addEventListener("keydown", (e) => {
    if (e.key !== "Enter") return;
    addTask(parseQuickAdd(input.value));
    input.value = "";
    renderChips();
  });

  addTask(parseQuickAdd("tomorrow 15:00 p1 #work ship the report"));
  addTask(parseQuickAdd("p3 #home water the plants"));
}

// ---- 3. Gaze drills (needs the WebGL eye's api) ------------------------------
// Pick a drill and the eye performs it — the same paths MoveEyePair traces
// on the app's break screen (8 directions, circle, figure-8, blink).
export function initExerciseDemo(eye) {
  const msg = $("ex-msg");
  const dot = $("ex-dot");
  const stage = document.querySelector(".ex-stage");
  const picker = document.querySelector(".ex-picker");
  if (!picker || !eye) return;

  let run = 0; // increments to cancel the previous drill

  function aim(dx, dy) {
    eye.setGazeTarget({ dx, dy });
    dot.style.left = 50 + dx * 42 + "%";
    dot.style.top = 50 + dy * 42 + "%";
  }

  function finish(id) {
    if (id !== run) return;
    dot.hidden = true;
    eye.setGazeTarget(null);
    msg.textContent = "Done — now with your own eyes. The app verifies it by camera.";
  }

  async function eight(id) {
    const DIRS = [
      ["right", 1, 0], ["up-right", 0.8, -0.8], ["up", 0, -1],
      ["up-left", -0.8, -0.8], ["left", -1, 0], ["down-left", -0.8, 0.8],
      ["down", 0, 1], ["down-right", 0.8, 0.8],
    ];
    for (const [name, dx, dy] of DIRS) {
      if (id !== run) return;
      msg.textContent = `Look ${name}`;
      aim(dx, dy);
      await new Promise((r) => setTimeout(r, 1500));
    }
    finish(id);
  }

  // continuous paths — same parametrization as the app's offset(at:)
  function path(id, seconds, fn, label) {
    msg.textContent = label;
    const t0 = performance.now();
    (function step(now) {
      if (id !== run || !stage.isConnected) return;
      const t = (now - t0) / 1000;
      if (t >= seconds) return finish(id);
      const ramp = Math.min(1, t / 0.6, (seconds - t) / 0.6);
      const [dx, dy] = fn(t * 1.7);
      aim(dx * ramp, dy * ramp);
      requestAnimationFrame(step);
    })(t0);
  }

  async function blinkBurst(id) {
    dot.hidden = true;
    for (let i = 1; i <= 3; i++) {
      if (id !== run) return;
      msg.textContent = `Blink ${i} of 3…`;
      eye.blink();
      await new Promise((r) => setTimeout(r, 900));
    }
    finish(id);
  }

  picker.addEventListener("click", (e) => {
    const btn = e.target.closest("button[data-drill]");
    if (!btn) return;
    picker.querySelector(".active")?.classList.remove("active");
    btn.classList.add("active");
    const id = ++run;
    dot.hidden = false;
    switch (btn.dataset.drill) {
      case "eight":
        eight(id);
        break;
      case "circle":
        path(id, 6, (a) => [Math.cos(a), Math.sin(a)], "Trace the circle — smooth and slow");
        break;
      case "figure8":
        path(id, 8, (a) => [Math.sin(a), Math.sin(2 * a) / 2], "Sweep the figure-8");
        break;
      case "blink":
        blinkBurst(id);
        break;
    }
  });
}

// ---- 4. Style carousel: every eye spinning, click to try it live -------------
export function buildCarousel(styles, labels, onPick) {
  const track = $("style-track");
  if (!track) return;
  const makeSet = (copy) => {
    for (let i = 0; i < styles.length; i++) {
      const name = styles[i];
      const b = document.createElement("button");
      b.type = "button";
      b.className = "carousel-item" + (name === "classic" ? " active" : "");
      b.dataset.style = name;
      if (copy) b.tabIndex = -1; // the duplicate set is purely visual
      b.setAttribute("aria-label", "Preview " + labels[name]);
      const img = document.createElement("img");
      img.src = `assets/app/iris/${name}.png`;
      img.alt = "";
      img.loading = "lazy";
      img.width = 92;
      img.height = 92;
      img.className = "iris-spin";
      img.style.animationDuration = 7 + (i % 5) * 2.5 + "s";
      const label = document.createElement("span");
      label.textContent = labels[name];
      b.append(img, label);
      b.addEventListener("click", () => {
        onPick(name);
        track.querySelectorAll(".carousel-item").forEach((el) =>
          el.classList.toggle("active", el.dataset.style === name)
        );
      });
      track.append(b);
    }
  };
  makeSet(false);
  makeSet(true); // duplicate for the seamless marquee loop
}
