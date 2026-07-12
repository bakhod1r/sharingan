// "Try it live" widget — the app's natural-language quick add, ported to the page.

const $ = (id) => document.getElementById(id);

// ---- Natural-language quick add ----------------------------------------------
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
