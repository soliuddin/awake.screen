/* Stay Awake: keeps the screen on using the browser's Screen Wake Lock.
   No network requests, no storage, no eval, no innerHTML. Everything runs locally in this tab. */
(() => {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const app = $('app'), stage = $('stage'), cv = $('fx'), btn = $('power');
  const note = $('note'), timerEl = $('timer'), floatBtn = $('float');
  const ctx = cv.getContext('2d');
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const TAU = Math.PI * 2;
  const rand = (a, b) => a + Math.random() * (b - a);

  let on = false, busyToggle = false;
  let lock = null, vid = null, vcv = null, vtick = null, clock = null, t0 = 0, pip = null;
  let time = 0, hue = 28, size = 1, running = false, token = 0;
  let sparks = [], ripples = [], rippleClock = 0, sparkAcc = 0;

  /* ---------------- keep-awake ---------------- */

  async function useWakeLock() {
    const nav = pip ? pip.navigator : navigator;
    if (!('wakeLock' in nav)) return false;
    try {
      const l = await nav.wakeLock.request('screen');
      lock = l;
      l.addEventListener('release', () => { if (lock === l) lock = null; });
      return true;
    } catch (e) { return false; }
  }

  // Fallback for browsers without Wake Lock: a tiny hidden video keeps the display awake.
  async function useVideo() {
    try {
      if (!vid) {
        vcv = document.createElement('canvas');
        vcv.width = vcv.height = 16;
        if (!vcv.captureStream) return false;
        vid = document.createElement('video');
        vid.className = 'keep';
        vid.setAttribute('playsinline', '');
        vid.muted = true;
        vid.loop = true;
        vid.srcObject = vcv.captureStream(2);
        document.body.appendChild(vid);
      }
      const g = vcv.getContext('2d');
      let f = 0;
      clearInterval(vtick);
      vtick = setInterval(() => { f++; g.fillStyle = f % 2 ? '#000' : '#010101'; g.fillRect(0, 0, 16, 16); }, 500);
      await vid.play();
      return true;
    } catch (e) { return false; }
  }

  async function acquire() {
    if (await useWakeLock()) return 'Screen Wake Lock';
    if (await useVideo()) return 'video fallback';
    return '';
  }

  function release() {
    if (lock) { try { lock.release(); } catch (e) { /* already released */ } lock = null; }
    clearInterval(vtick);
    if (vid) { try { vid.pause(); vid.remove(); } catch (e) { /* ignore */ } vid = null; vcv = null; }
  }

  async function reacquire() { release(); await acquire(); }

  /* ---------------- UI state ---------------- */

  const pad = (n) => (n < 10 ? '0' : '') + n;
  function renderTime() {
    const s = Math.floor((Date.now() - t0) / 1000);
    timerEl.textContent = pad(Math.floor(s / 3600)) + ':' + pad(Math.floor(s / 60) % 60) + ':' + pad(s % 60);
  }

  function setUi(isOn, msg, isErr) {
    app.dataset.on = String(isOn);
    btn.setAttribute('aria-pressed', String(isOn));
    btn.setAttribute('aria-label', isOn ? 'Screen is staying awake. Tap to turn off.' : 'Keep screen awake');
    note.textContent = msg;
    note.classList.toggle('err', Boolean(isErr));
    timerEl.hidden = !isOn;
  }

  btn.addEventListener('click', async () => {
    if (busyToggle) return;
    if (on) {
      on = false;
      release();
      clearInterval(clock);
      setUi(false, 'Turned off.');
      burst(false);
      return;
    }
    busyToggle = true;
    const method = await acquire();
    busyToggle = false;
    if (!method) {
      setUi(false, 'Your browser blocked keep-awake. Open this page directly in Chrome, Edge, Safari or Firefox.', true);
      return;
    }
    on = true;
    t0 = Date.now();
    renderTime();
    clearInterval(clock);
    clock = setInterval(renderTime, 1000);
    setUi(true, 'Screen is staying awake using ' + method + '.');
    burst(true);
  });

  // Browsers drop the lock when the tab is hidden; take it back when you return.
  document.addEventListener('visibilitychange', () => {
    if (on && document.visibilityState === 'visible' && !lock && !(vid && !vid.paused)) acquire();
  });

  /* ---------------- light show ---------------- */

  // colour for the light show: cycles while on, stays red while off
  const col = (dh, l, a) => 'hsla(' + ((((on ? hue : 355) + dh) % 360 + 360) % 360).toFixed(1) + ',100%,' + l + '%,' + a.toFixed(3) + ')';

  function spawn(speed) {
    if (sparks.length > 240) return;
    sparks.push({
      a: rand(0, TAU), d: 1.04, v: rand(0.3, 0.7) * speed,
      life: 0, max: rand(0.9, 1.9), s: rand(0.005, 0.012), dh: rand(-50, 50)
    });
  }

  function burst(isOn) {
    if (reduce) { kick(); return; }
    const n = isOn ? 70 : 26;
    for (let i = 0; i < n; i++) spawn(isOn ? 1.6 : 0.9);
    ripples.push({ age: 0, fast: true });
    if (isOn) ripples.push({ age: -0.14, fast: true });
    kick();
  }

  function update(dt) {
    time += dt;
    hue = (28 + time * 36) % 360;
    const hs = hue.toFixed(1);
    document.documentElement.style.setProperty('--h', hs);
    if (pip) pip.document.documentElement.style.setProperty('--h', hs);

    if (on) {
      sparkAcc += dt * 38;
      while (sparkAcc >= 1) { sparkAcc -= 1; spawn(1); }
      rippleClock += dt;
      if (rippleClock > 0.95) { rippleClock = 0; ripples.push({ age: 0, fast: false }); }
    }
    for (const s of sparks) {
      s.life += dt;
      s.d += s.v * dt;
      s.v *= Math.max(0, 1 - 0.8 * dt);
      s.a += 0.35 * dt;
    }
    sparks = sparks.filter((s) => s.life < s.max);
    for (const r of ripples) r.age += dt;
    ripples = ripples.filter((r) => r.age < (r.fast ? 0.9 : 2.4));
  }

  // a bright head with a tapering tail that circles the button
  function comet(c, r, head, dir, dh, w) {
    const N = 36, step = 0.045;
    for (let k = 0; k < N; k++) {
      const a0 = head - dir * k * step;
      const a1 = a0 - dir * step * 1.3;
      const t = 1 - k / N;
      ctx.lineWidth = size * 0.011 * w * (0.35 + 0.65 * t);
      ctx.strokeStyle = col(dh + k * 2, 62, t * t * 0.95);
      ctx.beginPath();
      ctx.arc(c, c, r, Math.min(a0, a1), Math.max(a0, a1));
      ctx.stroke();
    }
    const hx = c + Math.cos(head) * r, hy = c + Math.sin(head) * r, hr = size * 0.03 * w;
    const g = ctx.createRadialGradient(hx, hy, 0, hx, hy, hr);
    g.addColorStop(0, col(dh, 90, 1));
    g.addColorStop(1, col(dh, 60, 0));
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(hx, hy, hr, 0, TAU);
    ctx.fill();
  }

  function draw() {
    const c = size / 2, R = size * 0.22;
    ctx.setTransform(cv.width / size, 0, 0, cv.width / size, 0, 0);
    ctx.clearRect(0, 0, size, size);
    ctx.globalCompositeOperation = 'lighter';
    ctx.lineCap = 'round';

    if (on) {
      // breathing aura
      const pulse = 0.5 + 0.5 * Math.sin(time * 2.1);
      const g = ctx.createRadialGradient(c, c, R * 0.8, c, c, R * 2.25);
      g.addColorStop(0, col(0, 55, 0.34 + 0.12 * pulse));
      g.addColorStop(0.5, col(40, 50, 0.1));
      g.addColorStop(1, col(80, 50, 0));
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(c, c, R * 2.25, 0, TAU);
      ctx.fill();

      // radar sweep over a ring of 72 ticks
      const sweep = time * 2.4;
      ctx.lineWidth = size * 0.0065;
      for (let i = 0; i < 72; i++) {
        const a = (i / 72) * TAU;
        const d = (((sweep - a) % TAU) + TAU) % TAU;
        ctx.strokeStyle = col(i * 2.5, 62, 0.14 + 0.86 * Math.pow(1 - d / TAU, 3));
        ctx.beginPath();
        ctx.moveTo(c + Math.cos(a) * R * 1.4, c + Math.sin(a) * R * 1.4);
        ctx.lineTo(c + Math.cos(a) * R * 1.52, c + Math.sin(a) * R * 1.52);
        ctx.stroke();
      }

      // three comets, two turning one way and one the other
      comet(c, R * 1.24, time * 1.7, 1, 0, 1.5);
      comet(c, R * 1.68, -time * 1.15 + 2, -1, 120, 1.2);
      comet(c, R * 1.9, time * 0.8 + 4, 1, 220, 1.0);

      // eight rainbow beads on the outer orbit
      for (let i = 0; i < 8; i++) {
        const a = time * 0.9 + (i / 8) * TAU;
        const bx = c + Math.cos(a) * R * 2.08, by = c + Math.sin(a) * R * 2.08;
        const br = size * 0.026;
        const bg = ctx.createRadialGradient(bx, by, 0, bx, by, br);
        bg.addColorStop(0, col(i * 45, 85, 1));
        bg.addColorStop(0.35, col(i * 45, 60, 0.7));
        bg.addColorStop(1, col(i * 45, 55, 0));
        ctx.fillStyle = bg;
        ctx.beginPath();
        ctx.arc(bx, by, br, 0, TAU);
        ctx.fill();
      }
    } else {
      // idle: dim red aura, ring of ticks and two thin orbits
      const g = ctx.createRadialGradient(c, c, R * 0.8, c, c, R * 2.1);
      g.addColorStop(0, col(0, 55, 0.2));
      g.addColorStop(1, col(0, 50, 0));
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(c, c, R * 2.1, 0, TAU);
      ctx.fill();
      ctx.lineWidth = size * 0.0065;
      ctx.strokeStyle = col(0, 60, 0.32);
      for (let i = 0; i < 72; i++) {
        const a = (i / 72) * TAU;
        ctx.beginPath();
        ctx.moveTo(c + Math.cos(a) * R * 1.4, c + Math.sin(a) * R * 1.4);
        ctx.lineTo(c + Math.cos(a) * R * 1.52, c + Math.sin(a) * R * 1.52);
        ctx.stroke();
      }
      ctx.lineWidth = size * 0.004;
      ctx.strokeStyle = col(0, 55, 0.3);
      ctx.beginPath();
      ctx.arc(c, c, R * 1.24, 0, TAU);
      ctx.stroke();
      ctx.strokeStyle = col(0, 55, 0.2);
      ctx.beginPath();
      ctx.arc(c, c, R * 1.68, 0, TAU);
      ctx.stroke();
    }

    // ripples leave the button and thin out as they travel
    for (const r of ripples) {
      if (r.age < 0) continue;
      const p = r.age / (r.fast ? 0.9 : 2.4);
      const rad = R * (1.03 + p * (r.fast ? 1.2 : 1.15));
      ctx.lineWidth = size * (r.fast ? 0.009 : 0.006) * (1 - p * 0.5);
      ctx.strokeStyle = col(p * 80, r.fast ? 78 : 62, Math.pow(1 - p, 1.5) * 0.85);
      ctx.beginPath();
      ctx.arc(c, c, rad, 0, TAU);
      ctx.stroke();
    }

    // sparks
    for (const s of sparks) {
      const t = s.life / s.max;
      const x = c + Math.cos(s.a) * s.d * R, y = c + Math.sin(s.a) * s.d * R;
      ctx.fillStyle = col(s.dh, 70, Math.pow(1 - t, 1.4));
      ctx.beginPath();
      ctx.arc(x, y, size * s.s * (1 - t * 0.4), 0, TAU);
      ctx.fill();
    }
    ctx.globalCompositeOperation = 'source-over';
  }

  function fit() {
    const r = stage.getBoundingClientRect();
    const d = Math.min(2, (pip ? pip.devicePixelRatio : window.devicePixelRatio) || 1);
    size = Math.max(1, r.width);
    const px = Math.max(1, Math.round(size * d));
    if (cv.width !== px) { cv.width = px; cv.height = px; }
  }

  const alive = () => on || sparks.length > 0 || ripples.length > 0;

  function kick() {
    if (reduce) { fit(); update(0); draw(); return; }   // still frame, no motion
    if (running) return;
    running = true;
    const my = ++token;
    let last = 0;
    const loop = (ts) => {
      if (my !== token) return;
      if (!last) last = ts;
      const dt = Math.min(0.05, (ts - last) / 1000);
      last = ts;
      fit();
      update(dt);
      draw();
      if (alive()) (pip || window).requestAnimationFrame(loop);
      else { running = false; draw(); }   // settle on the still red idle look
    };
    (pip || window).requestAnimationFrame(loop);
  }

  function restart() { running = false; token++; kick(); }
  window.addEventListener('resize', () => { if (reduce) kick(); });

  /* ---------------- floating window (desktop Chrome / Edge) ---------------- */

  floatBtn.hidden = !('documentPictureInPicture' in window);
  floatBtn.addEventListener('click', async () => {
    if (pip) { pip.close(); return; }
    try {
      const w = await window.documentPictureInPicture.requestWindow({ width: 220, height: 220 });
      pip = w;
      for (const l of document.querySelectorAll('link[rel="stylesheet"]')) {
        const n = w.document.createElement('link');
        n.rel = 'stylesheet';
        n.href = l.href;
        w.document.head.append(n);
      }
      app.classList.add('mini');
      w.document.body.append(app);
      floatBtn.textContent = 'Bring back';
      w.addEventListener('pagehide', () => {
        pip = null;
        app.classList.remove('mini');
        document.body.insertBefore(app, floatBtn);
        floatBtn.textContent = 'Float window';
        if (on) reacquire();
        restart();
      });
      if (on) reacquire();
      restart();
    } catch (e) {
      note.textContent = 'A floating window is not allowed here. Open this page directly in desktop Chrome or Edge.';
      note.classList.add('err');
    }
  });

  kick();
})();
