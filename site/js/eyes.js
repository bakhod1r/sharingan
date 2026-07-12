// Sharingan eyes — a faithful WebGL port of the app's MoveEyeView
// (Sources/Sharingan/Views/MoveEyesView.swift + WallpaperWindowManager.swift):
// the same almond eye — Bézier lids, gray edge highlights, white sclera,
// translating iris — with the wallpaper's gaze/blink/wink/doze behaviors.
// The iris itself is sampled from the app's own renders (one PNG per style),
// so every one of the 18 styles is pixel-identical to the app.
// Exposes initEyes(canvas, opts) -> api | null.

import * as THREE from "./vendor/three.module.min.js";

// SharinganStyle.allCases, in the app's order — iris textures are the app's
// own renders, one PNG per style under assets/app/iris/.
export const STYLES = [
  "tomoe1", "tomoe2", "classic", "mangekyou", "mangekyouKamui",
  "mangekyouEternal", "itachi", "sixStar", "blade", "orbit", "crescent",
  "fourBlade", "madara", "shuriken", "swirl", "triangleTomoe",
  "ringCrescents", "rinnegan",
];
export const STYLE_LABELS = {
  tomoe1: "Classic (1 tomoe)", tomoe2: "Classic (2 tomoe)",
  classic: "Classic (3 tomoe)", mangekyou: "Mangekyō",
  mangekyouKamui: "Mangekyō — Kamui", mangekyouEternal: "Mangekyō — Eternal",
  itachi: "Itachi", sixStar: "Six-point star", blade: "Three-blade",
  orbit: "Orbit rings", crescent: "Triple crescent", fourBlade: "Four-blade",
  madara: "Madara — fan blades", shuriken: "Shuriken", swirl: "Single swirl",
  triangleTomoe: "Triangle tomoe", ringCrescents: "Ring + crescents",
  rinnegan: "Rinnegan",
};
const IRIS_URL = (name) => `assets/app/iris/${name}.png`;

const REACH = 500; // px — same clamp radius as the wallpaper's gaze()
const IDLE_SPIN_DELAY = 1.2; // s of stillness before the iris starts spinning
const WINK_IDLE_DELAY = 6; // s of stillness before playful winks
const DOZE_DELAY = 45; // s of stillness before the eyes drift shut

const EYE_VERT = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

// All geometry below mirrors MoveEyesView.swift exactly: control points,
// stroke widths, offsets and proportions are the app's numbers, evaluated
// in the same unit space (x across the 2.1:1 almond, y top→down).
const EYE_FRAG = /* glsl */ `
  precision highp float;
  varying vec2 vUv;
  uniform float uOpen;      // eyelid, 1 open … 0 closed
  uniform float uSquint;    // scroll-driven narrowing on top of uOpen
  uniform float uSpin;      // iris rotation, radians
  uniform float uEmergence; // 0…1 — the pattern whirling awake
  uniform vec2  uGaze;      // normalized look direction, screen space
  uniform float uMirror;    // 1 = right eye
  uniform sampler2D uIrisTex; // the app's iris render for the current style

  #define PI 3.14159265359
  #define W 2.1

  // MoveEyeShape control data (unit rect, y down)
  const vec2 TIP0 = vec2(0.00, 0.06);
  const vec2 TIP1 = vec2(1.00, 0.94);
  const vec2 UP_C1 = vec2(0.32, -0.10);
  const vec2 UP_C2 = vec2(0.76, 0.20);
  const vec2 LO_C1 = vec2(0.07, 0.86);
  const vec2 LO_C2 = vec2(0.52, 1.08);

  float bez(float p0, float c1, float c2, float p3, float t) {
    float m = 1.0 - t;
    return m*m*m*p0 + 3.0*m*m*t*c1 + 3.0*m*t*t*c2 + t*t*t*p3;
  }

  // Solve the cubic's parameter for a given x (x(t) is monotonic).
  float solveT(float x, float c1x, float c2x) {
    float t = x;
    for (int i = 0; i < 3; i++) {
      float m = 1.0 - t;
      float f = 3.0*m*m*t*c1x + 3.0*m*t*t*c2x + t*t*t - x;
      float d = 3.0*m*m*c1x + 6.0*m*t*(c2x - c1x) + 3.0*t*t*(1.0 - c2x);
      t -= f / max(d, 1e-3);
    }
    return clamp(t, 0.0, 1.0);
  }

  // y of the current upper lid at x (controls lerp toward the lower lid as
  // the eye closes — the blink morph MoveEyeShape animates), plus t for trims.
  vec2 upperLid(float x, float open) {
    float k = 1.0 - clamp(open, 0.0, 1.0);
    vec2 c1 = mix(UP_C1, LO_C1, k);
    vec2 c2 = mix(UP_C2, LO_C2, k);
    float t = solveT(x, c1.x, c2.x);
    return vec2(bez(TIP0.y, c1.y, c2.y, TIP1.y, t), t);
  }

  vec2 lowerLid(float x) {
    float t = solveT(x, LO_C1.x, LO_C2.x);
    return vec2(bez(TIP0.y, LO_C1.y, LO_C2.y, TIP1.y, t), t);
  }

  float band(float y, float center, float halfW, float aa) {
    return 1.0 - smoothstep(halfW - aa, halfW + aa, abs(y - center));
  }

  void main() {
    // unit rect coords, y down (SwiftUI space). The plane carries a margin
    // around the unit rect so lid strokes can overflow like the app's
    // unclipped SwiftUI layers — map UV out to [-0.06,1.06] × [-0.15,1.15].
    float xr = (vUv.x - 0.5) * 1.12 + 0.5;
    float x = uMirror > 0.5 ? 1.0 - xr : xr;
    float y = 0.5 - (vUv.y - 0.5) * 1.3;
    float inX = step(0.0, x) * step(x, 1.0);
    float gx = uMirror > 0.5 ? -uGaze.x : uGaze.x;
    float gy = uGaze.y;
    float aa = 0.006;

    float open = uOpen * (1.0 - 0.42 * clamp(uSquint, 0.0, 1.0));

    vec2 up = upperLid(x, open);
    vec2 lo = lowerLid(x);
    float almond = (1.0 - smoothstep(-aa, aa, up.x - y))
                 * (1.0 - smoothstep(-aa, aa, y - lo.x));

    vec4 col = vec4(0.0);

    // gray edge highlights (behind the black lid line)
    float gUp = band(y, up.x - 0.048, 0.07, aa) * step(up.y, 0.62) * inX;
    col = mix(col, vec4(0.55, 0.57, 0.59, 1.0), gUp);
    float gLo = band(y, lo.x + 0.018, 0.0175, aa)
              * step(0.22, lo.y) * step(lo.y, 0.78) * inX;
    col = mix(col, vec4(0.26, 0.28, 0.30, 1.0), gLo);

    // black lid base: filled almond + thicker upper lid stroke
    float blackCov = max(almond, band(y, up.x - 0.028, 0.05, aa) * inX);
    col = mix(col, vec4(0.0, 0.0, 0.0, 1.0), blackCov);

    // ---- sclera frame: 0.90w × 0.96h, nudged outward and up ------------
    float xs = (x - 0.55) / 0.90 + 0.5;
    float ys = (y - 0.453) / 0.96 + 0.5;
    vec2 sUp = upperLid(xs, open);
    vec2 sLo = lowerLid(xs);
    float sclera = (1.0 - smoothstep(-aa, aa, sUp.x - ys))
                 * (1.0 - smoothstep(-aa, aa, ys - sLo.x));
    sclera *= step(0.0, xs) * step(xs, 1.0);

    if (sclera > 0.001) {
      vec3 sc = mix(vec3(1.0), vec3(0.93, 0.91, 0.91), ys);

      // iris placement (MoveEyeView.irisOffset): rides the OPEN aperture
      float uS = clamp(0.5 + gx * 0.20, 0.12, 0.88);
      vec2 aUp = upperLid(uS, 1.0);
      float aLo = lowerLid(uS).x;
      float midY = (aUp.x + aLo) * 0.5;
      float halfH = max(0.0, (aLo - aUp.x) * 0.5);
      float irisUnitR = 0.26;
      float slack = max(0.0, halfH - irisUnitR * 0.28);
      float baseY = (upperLid(0.5, 1.0).x + lowerLid(0.5).x) * 0.5;
      float iy = clamp(baseY + gy * slack, midY - slack, midY + slack);

      // physical coords in eye-height units (x stretched by W)
      vec2 p = vec2(x * W, y);
      vec2 ic = vec2((0.55 + (uS - 0.5) * 0.90) * W, 0.453 + (iy - 0.5) * 0.96);
      float irisR = 0.26 * 0.96;
      float d = length(p - ic);
      float rn = d / irisR;

      // soft pink blush behind the iris
      float blush = 0.50 * (1.0 - smoothstep(0.88, 1.76, rn));
      sc = mix(sc, vec3(0.95, 0.68, 0.70), blush);

      if (rn < 1.0 + aa) {
        // the app's iris texture, spun by uSpin and whirling awake with
        // uEmergence (scale + counter-twist + fade, like MoveIrisView)
        float e = clamp(uEmergence, 0.0, 1.0);
        float theta = uSpin - (1.0 - e) * 4.538; // -260° twist while closed
        vec2 pd = (p - ic) / irisR;
        if (uMirror > 0.5) { pd.x = -pd.x; theta = -theta; }
        float ca = cos(theta), sa = sin(theta);
        vec2 q = mat2(ca, sa, -sa, ca) * pd;
        q /= (0.75 + 0.25 * e);
        vec4 tex = texture2D(uIrisTex, clamp(q * 0.5 + 0.5, 0.0, 1.0));
        float inQ = step(max(abs(q.x), abs(q.y)), 1.0);

        // bare red iris base shows through while the pattern whirls awake
        vec3 iris = mix(vec3(0.65, 0.05, 0.05), vec3(0.34, 0.0, 0.01),
                        smoothstep(0.1, 1.0, rn));
        iris = mix(vec3(0.0), iris, smoothstep(0.115, 0.145, rn)); // pupil
        iris = mix(iris, tex.rgb, tex.a * inQ * min(1.0, e * 2.4));

        float irisCov = 1.0 - smoothstep(1.0 - aa * 2.0, 1.0 + aa * 2.0, rn);
        sc = mix(sc, iris, irisCov);
      }

      col = mix(col, vec4(sc, 1.0), sclera);
    }

    if (col.a < 0.01) discard;
    gl_FragColor = col;
  }
`;

function makeGlowTexture() {
  const c = document.createElement("canvas");
  c.width = c.height = 256;
  const g = c.getContext("2d");
  const grad = g.createRadialGradient(128, 128, 10, 128, 128, 128);
  grad.addColorStop(0, "rgba(255, 23, 68, 0.5)");
  grad.addColorStop(0.4, "rgba(198, 40, 40, 0.2)");
  grad.addColorStop(1, "rgba(198, 40, 40, 0)");
  g.fillStyle = grad;
  g.fillRect(0, 0, 256, 256);
  return new THREE.CanvasTexture(c);
}

function buildEye(glowTexture, mirrored, irisTexture) {
  const group = new THREE.Group();

  const glow = new THREE.Sprite(
    new THREE.SpriteMaterial({
      map: glowTexture,
      blending: THREE.AdditiveBlending,
      depthTest: false,
      depthWrite: false,
      opacity: 0.55,
    })
  );
  glow.scale.set(4.6, 3.2, 1);
  glow.renderOrder = -1;
  group.add(glow);

  const eyeMat = new THREE.ShaderMaterial({
    vertexShader: EYE_VERT,
    fragmentShader: EYE_FRAG,
    transparent: true,
    depthWrite: false,
    uniforms: {
      uOpen: { value: 1 },
      uSquint: { value: 0 },
      uSpin: { value: 0 },
      uEmergence: { value: 0 },
      uGaze: { value: new THREE.Vector2(0, 0) },
      uMirror: { value: mirrored ? 1 : 0 },
      uIrisTex: { value: irisTexture },
    },
  });
  // 2.1:1 almond (eye height = 2 world units) plus overflow margin for the
  // lid strokes — the shader maps UV back to the padded unit rect
  const plane = new THREE.Mesh(new THREE.PlaneGeometry(4.704, 2.6), eyeMat);
  group.add(plane);

  // the state machine drives lids and iris through the same material
  return { group, eyeMat, irisMat: eyeMat, lidMat: eyeMat, glow, gaze: new THREE.Vector2() };
}

const easeOut = (t) => 1 - Math.pow(1 - t, 3);
const easeIn = (t) => t * t * t;
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const rand = (lo, hi) => lo + Math.random() * (hi - lo);

export function initEyes(canvas, opts = {}) {
  const eyeCount = opts.eyes ?? 2;
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true });
  } catch {
    return null;
  }
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));

  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(35, 1, 0.1, 50);
  camera.position.z = 10;
  // gazeTarget() projects through matrixWorldInverse on the very first frame,
  // BEFORE the first render has updated camera matrices — with a stale
  // identity view matrix the eyes sit at w=0 and project() yields NaN,
  // which the gaze lerp then locks in forever.
  camera.updateMatrixWorld();

  // ---- iris textures (the app's own renders, loaded lazily per style) ----
  const loader = new THREE.TextureLoader();
  const texCache = new Map();
  function irisTexture(name) {
    if (!texCache.has(name)) {
      const tex = loader.load(IRIS_URL(name));
      tex.flipY = false;
      tex.colorSpace = THREE.SRGBColorSpace;
      tex.anisotropy = 4;
      texCache.set(name, tex);
    }
    return texCache.get(name);
  }
  let style = opts.style ?? "classic";
  let styleIndex = Math.max(0, STYLES.indexOf(style));

  const rig = new THREE.Group(); // scroll parallax target
  scene.add(rig);

  const glowTexture = makeGlowTexture();
  const eyes = [];
  for (let i = 0; i < eyeCount; i++) {
    const eye = buildEye(glowTexture, eyeCount === 2 && i === 1, irisTexture(style));
    rig.add(eye.group);
    eyes.push(eye);
  }

  // ---- tweens (lids + emergence) ----------------------------------------
  const tweens = [];
  function tween(set, from, to, dur, ease, delay = 0) {
    tweens.push({ set, from, to, dur, ease, start: performance.now() + delay * 1000 });
  }
  function runTweens(now) {
    for (let i = tweens.length - 1; i >= 0; i--) {
      const t = tweens[i];
      const k = (now - t.start) / (t.dur * 1000);
      if (k < 0) continue;
      if (k >= 1) {
        t.set(t.to);
        tweens.splice(i, 1);
      } else {
        t.set(t.from + (t.to - t.from) * t.ease(k));
      }
    }
  }
  const setLid = (i) => (v) => (eyes[i].lidMat.uniforms.uOpen.value = v);
  const lidValue = (i) => eyes[i].lidMat.uniforms.uOpen.value;
  const setEmergence = (v) =>
    eyes.forEach((e) => (e.irisMat.uniforms.uEmergence.value = v));

  // ---- layout ------------------------------------------------------------
  function layout() {
    const w = canvas.clientWidth || 1;
    const h = canvas.clientHeight || 1;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    const worldPerPx = (2 * camera.position.z * Math.tan((camera.fov * Math.PI) / 360)) / h;
    const visH = 2 * camera.position.z * Math.tan((camera.fov * Math.PI) / 360);
    if (eyeCount === 2) {
      // wallpaper composition: eyes at 32% / 68% width, upper third
      const portrait = h > w;
      const eyeH = portrait
        ? Math.min(w * 0.2, h * 0.18)
        : Math.min(w * 0.115, h * 0.21);
      const scale = (eyeH * worldPerPx) / 2; // plane height is 2 units
      const y = visH * (portrait ? 0.3 : 0.24);
      eyes[0].group.position.set(-0.18 * w * worldPerPx, y, 0);
      eyes[1].group.position.set(0.18 * w * worldPerPx, y, 0);
      eyes.forEach((e) => e.group.scale.setScalar(scale));
    } else {
      const eyeH = Math.min(h * 0.52, (w * 0.82) / 2.1);
      eyes[0].group.position.set(0, 0, 0);
      eyes[0].group.scale.setScalar((eyeH * worldPerPx) / 2);
    }
  }
  const ro = new ResizeObserver(layout);
  ro.observe(canvas);
  layout();

  // ---- gaze ----------------------------------------------------------------
  const pointer = { x: innerWidth / 2, y: innerHeight / 2, moved: performance.now() };
  const onMove = (ev) => {
    pointer.x = ev.clientX;
    pointer.y = ev.clientY;
    pointer.moved = performance.now();
  };
  addEventListener("pointermove", onMove, { passive: true });

  // When set (exercise demo), the eyes look here instead of at the cursor.
  let gazeOverride = null;

  const proj = new THREE.Vector3();
  function gazeTarget(eye, t) {
    if (gazeOverride) return gazeOverride;
    const stillFor = (performance.now() - pointer.moved) / 1000;
    if (stillFor > 30 || !matchMedia("(pointer: fine)").matches) {
      // no cursor to follow — slow autonomous wander
      return { dx: Math.sin(t * 0.23) * 0.6, dy: Math.cos(t * 0.17) * 0.4 };
    }
    proj.setFromMatrixPosition(eye.group.matrixWorld).project(camera);
    const rect = canvas.getBoundingClientRect();
    const cx = rect.left + ((proj.x + 1) / 2) * rect.width;
    const cy = rect.top + ((1 - proj.y) / 2) * rect.height;
    let dx = (pointer.x - cx) / REACH;
    let dy = (pointer.y - cy) / REACH;
    const len = Math.hypot(dx, dy);
    if (len > 1) {
      dx /= len;
      dy /= len;
    }
    return { dx, dy };
  }

  // ---- eyelid state machine (port of WallpaperEyesView.updateEyelids) ----
  let dozing = false;
  let winkRightNext = true;
  let nextBlink = performance.now() + rand(2000, 5000);
  let disposed = false;

  function closeBoth(dur, ease) {
    eyes.forEach((_, i) => tween(setLid(i), lidValue(i), 0, dur, ease));
  }
  function openBoth(dur, ease, delay = 0) {
    eyes.forEach((_, i) => tween(setLid(i), lidValue(i), 1, dur, ease, delay));
  }
  function wink(hold) {
    const i = eyeCount === 1 ? 0 : winkRightNext ? 1 : 0;
    winkRightNext = !winkRightNext;
    tween(setLid(i), lidValue(i), 0, 0.09, easeIn);
    tween(setLid(i), 0, 1, 0.16, easeOut, hold);
  }
  function blinkOnce() {
    nextBlink = performance.now() + rand(3500, 8000);
    if (Math.random() < 0.3) {
      wink(0.4);
    } else {
      closeBoth(0.09, easeIn);
      openBoth(0.16, easeOut, 0.2);
    }
  }
  function updateEyelids() {
    const now = performance.now();
    const stillFor = (now - pointer.moved) / 1000;
    if (stillFor > DOZE_DELAY && !dozing) {
      dozing = true;
      closeBoth(0.9, easeInOut);
      tween(setEmergence, eyes[0].irisMat.uniforms.uEmergence.value, 0, 0.7, easeIn);
    } else if (stillFor <= DOZE_DELAY && dozing) {
      dozing = false;
      nextBlink = now + rand(2000, 5000);
      // wake with the next pattern in the evolution chain
      setStyle(STYLES[(styleIndex + 1) % STYLES.length]);
      openBoth(0.25, easeOut);
      return; // setStyle already replays emergence
    }
    if (dozing || now < nextBlink) return;
    if (stillFor > WINK_IDLE_DELAY) {
      wink(0.45);
      nextBlink = now + rand(2500, 4000);
    } else {
      blinkOnce();
    }
  }
  const lidTimer = reduceMotion ? 0 : setInterval(updateEyelids, 200);

  // ---- click burst: one accelerate→decelerate double-whirl per click ------
  // (port of WallpaperEyesView.clickBurst — the wallpaper listens globally)
  let burstSpin = 0;
  let glowPulse = 0;
  const onClick = () => {
    if (reduceMotion) return;
    const from = burstSpin;
    tween((v) => (burstSpin = v), from, from + Math.PI * 4, 1.0, easeInOut);
    tween((v) => (glowPulse = v), 1, 0, 0.8, easeOut);
  };
  addEventListener("pointerdown", onClick, { passive: true });

  // ---- public API ----------------------------------------------------------
  function setStyle(name) {
    if (!STYLES.includes(name)) return;
    style = name;
    styleIndex = STYLES.indexOf(name);
    const tex = irisTexture(name);
    eyes.forEach((e) => (e.irisMat.uniforms.uIrisTex.value = tex));
    if (reduceMotion) {
      setEmergence(1);
    } else {
      tween(setEmergence, 0, 1, 0.9, easeOut);
    }
  }
  // Back-compat with the old 5-pattern picker indices.
  const LEGACY = ["tomoe1", "tomoe2", "classic", "mangekyou", "rinnegan"];
  function setPattern(i) {
    setStyle(LEGACY[((i % LEGACY.length) + LEGACY.length) % LEGACY.length]);
  }

  // ---- render loop -----------------------------------------------------------
  let spinSpeed = 0;
  let spin = 0;
  let squint = 0;
  let lastScroll = scrollY;
  let raf = 0;
  let last = performance.now();

  function frame(now) {
    raf = requestAnimationFrame(frame);
    const dt = Math.min((now - last) / 1000, 0.1);
    last = now;
    const t = now / 1000;

    runTweens(now);

    // iris spin: eases in after a beat of stillness, out on movement;
    // click bursts stack on top regardless of idle state
    if (!reduceMotion) {
      const still = (now - pointer.moved) / 1000 > IDLE_SPIN_DELAY;
      spinSpeed += ((still && !dozing ? 1.15 : 0) - spinSpeed) * Math.min(1, dt * 2.5);
      spin += spinSpeed * dt;
      eyes.forEach((e) => (e.irisMat.uniforms.uSpin.value = spin + burstSpin));
    }

    for (const eye of eyes) {
      const g = gazeTarget(eye, t);
      eye.gaze.x += (g.dx - eye.gaze.x) * Math.min(1, dt * 6);
      eye.gaze.y += (g.dy - eye.gaze.y) * Math.min(1, dt * 6);
      eye.eyeMat.uniforms.uGaze.value.copy(eye.gaze);
      eye.glow.scale.set(4.6 + glowPulse, 3.2 + glowPulse * 0.7, 1);
    }

    if (eyeCount === 2) {
      const s = scrollY / Math.max(innerHeight, 1);
      rig.position.y = s * 1.4;
      rig.rotation.z = s * 0.04;

      // scroll velocity → the eyes narrow while the page rushes past
      const v = Math.abs(scrollY - lastScroll) / Math.max(dt, 0.001);
      lastScroll = scrollY;
      const squintTarget = reduceMotion ? 0 : Math.min(0.85, v / 3200);
      squint += (squintTarget - squint) * Math.min(1, dt * (squintTarget > squint ? 10 : 3));
      eyes.forEach((e) => (e.lidMat.uniforms.uSquint.value = squint));
    }

    renderer.render(scene, camera);
  }

  function start() {
    if (!raf && !disposed) {
      last = performance.now();
      raf = requestAnimationFrame(frame);
    }
  }
  function stop() {
    cancelAnimationFrame(raf);
    raf = 0;
  }
  const onVisibility = () => (document.hidden ? stop() : start());
  document.addEventListener("visibilitychange", onVisibility);

  // don't burn frames while the canvas is scrolled out of view
  const vis = new IntersectionObserver(([e]) =>
    e.isIntersecting && !document.hidden ? start() : stop()
  );
  vis.observe(canvas);

  if (location.hash === "#debug") {
    window.__eyes = window.__eyes || [];
    window.__eyes.push({ renderer, scene, camera, eyes, canvas });
  }

  // awakening: the pattern whirls out of the pupil on first show
  if (reduceMotion) {
    setEmergence(1);
  } else {
    tween(setEmergence, 0, 1, 0.9, easeOut, 0.4);
  }
  start();

  return {
    setStyle,
    setPattern,
    get style() {
      return style;
    },
    /// Exercise demo: aim the eyes at {dx,dy} (−1…1), or null → cursor.
    setGazeTarget(target) {
      gazeOverride = target;
    },
    /// Exercise demo: one deliberate blink.
    blink() {
      if (!reduceMotion) blinkOnce();
    },
    dispose() {
      disposed = true;
      stop();
      clearInterval(lidTimer);
      removeEventListener("pointermove", onMove);
      removeEventListener("pointerdown", onClick);
      document.removeEventListener("visibilitychange", onVisibility);
      vis.disconnect();
      ro.disconnect();
      renderer.dispose();
    },
  };
}
