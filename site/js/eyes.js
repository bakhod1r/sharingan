// Sharingan eyes — WebGL port of the app's live wallpaper
// (Sources/Sharingan/Services/WallpaperWindowManager.swift).
// Exposes initEyes(canvas, opts) -> { setPattern(i), dispose() } | null.
// Patterns: 0=1-tomoe, 1=2-tomoe, 2=3-tomoe, 3=Mangekyō, 4=Rinnegan.

import * as THREE from "./vendor/three.module.min.js";

const PATTERN_COUNT = 5;
const REACH = 500; // px — same clamp radius as the wallpaper's gaze()
const IDLE_SPIN_DELAY = 1.2; // s of stillness before tomoe start spinning
const WINK_IDLE_DELAY = 6; // s of stillness before playful winks
const DOZE_DELAY = 45; // s of stillness before the eyes drift shut

// The iris is painted directly onto the eyeball sphere (polar projection
// around the +z pole) — a separate flat disc would sit inside the sphere
// and be occluded by its front cap.
const EYE_VERT = /* glsl */ `
  varying vec3 vNorm;
  void main() {
    vNorm = position; // unit sphere: position == normal (object space)
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

const EYE_FRAG = /* glsl */ `
  precision highp float;
  varying vec3 vNorm;
  uniform float uSpin;
  uniform float uEmergence;
  uniform int uPattern;

  #define PI 3.14159265359
  #define IRIS_SIN 0.57

  // Coverage of one tomoe (comma) whose head sits on the orbit ring at
  // angle "th": a round head plus an arc tail that tapers to nothing.
  float tomoe(vec2 p, float r, float a, float th, float orbit) {
    vec2 head = orbit * vec2(cos(th), sin(th));
    float cov = 1.0 - smoothstep(-0.012, 0.012, length(p - head) - 0.105);
    float da = mod(a - th, 2.0 * PI); // trailing angle behind the head
    float span = 1.35;
    if (da > 0.0 && da < span) {
      float t = da / span;
      float w = 0.095 * pow(1.0 - t, 1.6);
      float ring = abs(r - (orbit + 0.045 * sin(t * PI))) - w;
      cov = max(cov, 1.0 - smoothstep(-0.012, 0.012, ring));
    }
    return cov;
  }

  void main() {
    vec3 n = normalize(vNorm);
    // anime sclera: near-black shell with a soft vertical gradient
    vec3 sclera = mix(vec3(0.045, 0.048, 0.058), vec3(0.10, 0.105, 0.12),
                      (n.y + 1.0) * 0.5);
    if (n.z <= 0.0) { gl_FragColor = vec4(sclera, 1.0); return; }

    vec2 p = n.xy / IRIS_SIN; // iris space, rim at |p| = 1
    float r = length(p);
    if (r >= 1.12) { gl_FragColor = vec4(sclera, 1.0); return; }

    float a = atan(p.y, p.x);
    float e = max(uEmergence, 0.0001);

    // -- base iris ------------------------------------------------------
    vec3 col;
    if (uPattern == 4) { // Rinnegan: ripple-grey lavender
      col = mix(vec3(0.62, 0.58, 0.78), vec3(0.23, 0.20, 0.35),
                smoothstep(0.05, 1.0, r));
    } else {
      col = mix(vec3(0.82, 0.10, 0.16), vec3(0.38, 0.015, 0.045),
                smoothstep(0.12, 1.0, r));
      // faint radial fibres for depth
      col *= 1.0 + 0.022 * sin(a * 60.0) * smoothstep(0.2, 0.7, r);
    }

    // -- pattern ink ----------------------------------------------------
    float ink = 0.0;
    vec2 pe = p / e; // emergence: pattern whirls out of the pupil
    float re = r / e;
    float ae = a - (1.0 - e) * 2.2; // slight counter-twist while emerging

    if (uPattern <= 2) {
      float cnt = float(uPattern + 1);
      // thin ring through the tomoe orbit
      ink = max(ink, 1.0 - smoothstep(0.002, 0.010, abs(re - 0.5) - 0.008));
      for (int i = 0; i < 3; i++) {
        if (i >= int(cnt)) break;
        float th = uSpin + float(i) * 2.0 * PI / cnt;
        ink = max(ink, tomoe(pe, re, ae, th, 0.5));
      }
    } else if (uPattern == 3) {
      // Mangekyō: three curved blades sweeping pupil -> rim
      float sector = 2.0 * PI / 3.0;
      float ang = mod(ae + uSpin + 2.2 * (re - 0.2), sector) - sector * 0.5;
      float w = mix(0.34, 0.05, smoothstep(0.16, 0.85, re));
      float blade = (1.0 - smoothstep(-0.03, 0.03, abs(ang) - w))
                  * (1.0 - smoothstep(0.85, 0.95, re))
                  * smoothstep(0.14, 0.2, re);
      ink = max(ink, blade);
      ink = max(ink, 1.0 - smoothstep(0.002, 0.010, abs(re - 0.62) - 0.006));
    } else {
      // Rinnegan: concentric rings, no spin
      for (int i = 1; i <= 4; i++) {
        float rr = float(i) * 0.21;
        ink = max(ink, 1.0 - smoothstep(0.003, 0.011, abs(re - rr) - 0.006));
      }
    }
    ink *= smoothstep(0.0, 0.15, uEmergence);
    col = mix(col, vec3(0.02, 0.005, 0.01), ink * 0.96);

    // -- pupil ----------------------------------------------------------
    float pupil = (uPattern == 4) ? 0.13 : 0.17;
    col = mix(vec3(0.0), col, smoothstep(pupil - 0.015, pupil + 0.015, r));

    // -- limbus rim + fake gloss ----------------------------------------
    col = mix(col, vec3(0.05, 0.005, 0.012), smoothstep(0.88, 0.99, r));
    col = mix(col, sclera, smoothstep(1.0, 1.12, r)); // blend into sclera
    col *= 1.0 - 0.16 * smoothstep(0.0, 1.5, length(p - vec2(-0.5, 0.55)));
    col += vec3(0.10, 0.02, 0.03)
         * (1.0 - smoothstep(0.0, 0.5, length(p - vec2(-0.32, 0.38))));

    gl_FragColor = vec4(col, 1.0);
  }
`;

const LID_VERT = /* glsl */ `
  varying vec3 vPos;
  void main() {
    vPos = position;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

const LID_FRAG = /* glsl */ `
  precision highp float;
  varying vec3 vPos;
  uniform float uOpen;
  uniform float uSquint; // scroll-driven narrowing on top of the lid state
  void main() {
    float openEff = uOpen * (1.0 - uSquint * 0.42);
    float edge = mix(-1.12, 1.12, openEff); // lid line descends as uOpen falls
    if (vPos.y < edge) discard;
    vec3 col = mix(vec3(0.035, 0.039, 0.047), vec3(0.075, 0.082, 0.096),
                   (vPos.y + 1.0) * 0.5);
    // warm red seam right at the lid edge
    col = mix(vec3(0.28, 0.03, 0.05), col,
              smoothstep(0.0, 0.09, vPos.y - edge));
    gl_FragColor = vec4(col, 1.0);
  }
`;

function makeGlowTexture() {
  const c = document.createElement("canvas");
  c.width = c.height = 256;
  const g = c.getContext("2d");
  const grad = g.createRadialGradient(128, 128, 10, 128, 128, 128);
  grad.addColorStop(0, "rgba(255, 23, 68, 0.55)");
  grad.addColorStop(0.4, "rgba(198, 40, 40, 0.22)");
  grad.addColorStop(1, "rgba(198, 40, 40, 0)");
  g.fillStyle = grad;
  g.fillRect(0, 0, 256, 256);
  return new THREE.CanvasTexture(c);
}

function buildEye(glowTexture) {
  const group = new THREE.Group();

  const glow = new THREE.Sprite(
    new THREE.SpriteMaterial({
      map: glowTexture,
      blending: THREE.AdditiveBlending,
      depthTest: false,
      depthWrite: false,
      opacity: 0.7,
    })
  );
  glow.scale.setScalar(3.3);
  glow.renderOrder = -1;
  group.add(glow);

  // The ball that actually rotates toward the cursor. Sclera + iris live in
  // one shader on the sphere itself, so the iris hugs the surface.
  const ball = new THREE.Group();

  const irisMat = new THREE.ShaderMaterial({
    vertexShader: EYE_VERT,
    fragmentShader: EYE_FRAG,
    uniforms: {
      uSpin: { value: 0 },
      uEmergence: { value: 0 },
      uPattern: { value: 2 },
    },
  });
  const eyeball = new THREE.Mesh(new THREE.SphereGeometry(1, 64, 64), irisMat);
  ball.add(eyeball);

  // glossy anime highlights — float just off the surface so they read
  const hl = new THREE.Mesh(
    new THREE.CircleGeometry(0.085, 32),
    new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.85 })
  );
  hl.position.set(-0.17, 0.2, 1.012);
  ball.add(hl);
  const hl2 = new THREE.Mesh(
    new THREE.CircleGeometry(0.038, 24),
    new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.6 })
  );
  hl2.position.set(0.14, -0.12, 1.012);
  ball.add(hl2);

  group.add(ball);

  // The lid does NOT rotate with the gaze — it sits over the socket.
  const lidMat = new THREE.ShaderMaterial({
    vertexShader: LID_VERT,
    fragmentShader: LID_FRAG,
    uniforms: { uOpen: { value: 1 }, uSquint: { value: 0 } },
  });
  const lid = new THREE.Mesh(new THREE.SphereGeometry(1.035, 48, 48), lidMat);
  group.add(lid);

  return { group, ball, irisMat, lidMat, glow };
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
  // which the rotation lerp then locks in forever.
  camera.updateMatrixWorld();

  const rig = new THREE.Group(); // scroll parallax target
  scene.add(rig);

  const glowTexture = makeGlowTexture();
  const eyes = [];
  for (let i = 0; i < eyeCount; i++) {
    const eye = buildEye(glowTexture);
    rig.add(eye.group);
    eyes.push(eye);
  }

  let pattern = opts.patternIndex ?? 2;
  eyes.forEach((e) => (e.irisMat.uniforms.uPattern.value = pattern));

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
    if (eyeCount === 2) {
      // wallpaper composition: eyes at 32% / 68% width, hovering in the
      // upper third so the hero headline sits beneath their gaze
      const visH = 2 * camera.position.z * Math.tan((camera.fov * Math.PI) / 360);
      const portrait = h > w;
      const scale = portrait
        ? Math.min(w * 0.13, h * 0.16) * worldPerPx
        : Math.min(w * 0.16, h * 0.2) * worldPerPx;
      const y = visH * (portrait ? 0.28 : 0.2);
      eyes[0].group.position.set(-0.18 * w * worldPerPx, y, 0);
      eyes[1].group.position.set(0.18 * w * worldPerPx, y, 0);
      eyes.forEach((e) => e.group.scale.setScalar(scale));
    } else {
      const scale = Math.min(w, h) * 0.31 * worldPerPx;
      eyes[0].group.position.set(0, 0, 0);
      eyes[0].group.scale.setScalar(scale);
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

  const proj = new THREE.Vector3();
  function gazeTarget(eye, t) {
    const stillFor = (performance.now() - pointer.moved) / 1000;
    if (stillFor > 30 || !matchMedia("(pointer: fine)").matches) {
      // no cursor to follow — slow autonomous wander
      return { yaw: Math.sin(t * 0.23) * 0.2, pitch: Math.cos(t * 0.17) * 0.14 };
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
    return { yaw: dx * 0.5, pitch: dy * 0.38 };
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
  function advancePattern() {
    setPattern((pattern + 1) % PATTERN_COUNT);
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
      advancePattern(); // wake with the next pattern in the chain
      openBoth(0.25, easeOut);
      return; // setPattern already replays emergence
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
  function setPattern(i) {
    pattern = ((i % PATTERN_COUNT) + PATTERN_COUNT) % PATTERN_COUNT;
    eyes.forEach((e) => (e.irisMat.uniforms.uPattern.value = pattern));
    if (reduceMotion) {
      setEmergence(1);
    } else {
      tween(setEmergence, 0, 1, 0.9, easeOut);
    }
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

    // tomoe spin: eases in after a beat of stillness, out on movement;
    // click bursts stack on top regardless of idle state
    if (!reduceMotion && pattern !== 4) {
      const still = (now - pointer.moved) / 1000 > IDLE_SPIN_DELAY;
      spinSpeed += ((still && !dozing ? 1.15 : 0) - spinSpeed) * Math.min(1, dt * 2.5);
      spin += spinSpeed * dt;
      eyes.forEach((e) => (e.irisMat.uniforms.uSpin.value = spin + burstSpin));
    }

    for (const eye of eyes) {
      const g = gazeTarget(eye, t);
      eye.ball.rotation.y += (g.yaw - eye.ball.rotation.y) * Math.min(1, dt * 6);
      eye.ball.rotation.x += (g.pitch - eye.ball.rotation.x) * Math.min(1, dt * 6);
      eye.glow.scale.setScalar(3.3 + glowPulse * 0.7);
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
    setPattern,
    dispose() {
      disposed = true;
      stop();
      clearInterval(lidTimer);
      removeEventListener("pointermove", onMove);
      removeEventListener("pointerdown", onClick);
      document.removeEventListener("visibilitychange", onVisibility);
      ro.disconnect();
      renderer.dispose();
    },
  };
}
