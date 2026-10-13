(() => {
  'use strict';
  // Every drawing below is a 1:1 port of the game's own painters (lib/run/**, lib/components/**),
  // with their constants; file references in the comments. Nothing here is a new design.
  const REDUCED = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const IMG = {};
  ['spikes:/a/ground_spikes.44c9981c48.png', 'coin:/a/coin.b02efd97f6.png', 'circle:/a/background_score.aff0698d91.png', 'sound:/a/soundbutton.be744432b2.png', 'mute:/a/mutebutton.5455abd43c.png']
    .forEach((s) => { const [k, d] = s.split(':'); const i = new Image(); i.src = d; IMG[k] = i; });
  const PINK = '#EC008C', PLUM = '#7A0044', GOLD = '#FFB529', SOFT = '#FCD9EE', ACCENT = '#FF4FB7', TAU = Math.PI * 2;
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const rnd = (a, b) => a + Math.random() * (b - a);
  const LOOK_SCALE = 0.985;                              // Config.lookScale

  // ---------- palettes.dart colour stages; streak_config.dart names + colours ----------
  const STAGES = [
    ['#F1F1F1', '#828282'], ['#E5F2F9', '#667B84'], ['#F9EDE6', '#806A62'], ['#ECF6E5', '#767E67'],
    ['#ECEAF8', '#6E6880'], ['#747474', '#FFFFFF'], ['#087990', '#0CD9FF'], ['#197500', '#7EE400'],
    ['#001D89', '#0067FF'], ['#921037', '#FF1F64'], ['#FFB529', '#FFFFFF'],
  ];
  const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  const mix = (a, b, t) => { const A = hex(a), B = hex(b); return '#' + A.map((v, i) => Math.round(v + (B[i] - v) * t).toString(16).padStart(2, '0')).join(''); };
  const rgba = (h, a) => { const [r, g, b] = hex(h); return `rgba(${r},${g},${b},${a})`; };
  const STREAK = ['PERFECT', 'GREAT', 'ON FIRE', 'AMAZING', 'SOARING', 'SKY HIGH', 'HIGH FLYER', 'FEATHERLIGHT', 'EAGLE EYE', 'FREE BIRD', 'TAILWIND', 'SKYLARK', 'TOP BIRD', 'WINGMASTER', 'RINGMASTER',
    'SPIKE-PROOF', 'BLAZING', 'FIREBIRD', 'PEREGRINE', 'STORMRIDER', 'THUNDERBIRD', 'HURRICANE', 'SKYDRAGON', 'GRIFFIN', 'MIGHTY ROC'];
  const STREAK_C = ['#EC008C', '#FF4FB7', '#FFB529', '#FF7A1A', '#E8141C', '#C2185B', '#9B30D9', '#1E9BE0', '#00897B', '#7A0044'];
  const streakName = (n) => n <= 1 ? 'PERFECT' : STREAK[Math.min(n, STREAK.length) - 1] + ' ×' + n;

  // ---------- canvas plumbing ----------
  function setup(id) {
    const c = document.getElementById(id), w = c.width, h = c.height, d = Math.min(2, devicePixelRatio || 1);
    c.width = w * d; c.height = h * d;
    const x = c.getContext('2d'); x.setTransform(d, 0, 0, d, 0, 0);
    return { c, x, w, h, d, visible: true };
  }
  const tintCache = new Map();
  function tinted(img, color, w, h) {
    const key = img.src + color + w + 'x' + h;
    let s = tintCache.get(key);
    if (!s && img.complete) {
      s = document.createElement('canvas'); s.width = Math.ceil(w * 2); s.height = Math.ceil(h * 2);
      const t = s.getContext('2d'); t.drawImage(img, 0, 0, s.width, s.height);
      t.globalCompositeOperation = 'source-in'; t.fillStyle = color; t.fillRect(0, 0, s.width, s.height);
      tintCache.set(key, s);
    }
    return s;
  }
  // spike_strip.dart: ground_spikes.png tinted with the stage foreground, Config.spikeHeight 44
  const SPIKE_H = 44;
  function spikeStrip(x, w, y, color, down, h = SPIKE_H) {
    const sw = 768 * h / 144, s = tinted(IMG.spikes, color, sw, h);
    if (!s) return;
    x.save();
    if (down) { x.translate(0, y + h); x.scale(1, -1); } else x.translate(0, y);
    for (let i = 0; i < w; i += sw) x.drawImage(s, i, 0, sw, h);
    x.restore();
  }
  function txt(x, s, px, py, size, color, font = 'ui', align = 'center', spacing = 0) {
    x.font = (font === 'fredoka' ? '600 ' : '') + size + 'px ' + ({ fredoka: '"Fredoka"', score: '"LVDC Common2"', ui: '"Opificio Neue"' }[font]);
    x.fillStyle = color; x.textAlign = align; x.textBaseline = 'middle'; x.letterSpacing = spacing + 'px';
    x.fillText(s, px, py); x.letterSpacing = '0px';
  }
  // the bird never rotates in a run (Bird: fixedRotation); only the death tumble and the comet tilt it
  function birdAt(x, look, px, py, scale, t, flap, rot = 0, alpha = 1) {
    x.save(); x.globalAlpha = alpha; x.translate(px, py); if (rot) x.rotate(rot); x.scale(scale, scale);
    SKIN.drawLook(x, look, t, flap); x.restore();
  }
  // ring_painter.dart master #3: 24 pt wide (rx 12), ry = opening / 2 + 7, stroke 7, butt caps; back = right half
  const RING_PINK = ['#EC008C', '#B0006B'], RING_GOLD = ['#FFB529', '#D48A00'], RING_BRIGHT = ['#FFD54A', '#E0A800'];
  function ringHalf(x, cx, cy, opening, front, cols = RING_PINK, lw = 7, dash = null, alpha = 1) {
    const ry = opening / 2 + 7;
    x.save(); x.globalAlpha = alpha; x.lineWidth = lw; x.lineCap = 'butt'; x.strokeStyle = front ? cols[0] : cols[1];
    if (dash) x.setLineDash(dash);
    x.beginPath(); x.ellipse(cx, cy, 12, ry, 0, front ? Math.PI / 2 : -Math.PI / 2, front ? Math.PI * 1.5 : Math.PI / 2); x.stroke();
    x.restore();
  }
  // life_icons.dart: heart24 and shield24 paths in their 24-unit boxes
  const HEART24 = new Path2D('M12 21s-9-5.6-9-12a5 5 0 0 1 9-3 5 5 0 0 1 9 3c0 6.4-9 12-9 12z');
  const SHINE = new Path2D('M8 8.5a3 3 0 0 1 3-1.3');
  const SHIELD24 = new Path2D('M12 1.5L21.5 5L21.5 11.5C21.5 17 17.5 21 12 22.5C6.5 21 2.5 17 2.5 11.5L2.5 5Z');
  const STAR10 = new Path2D('M12 7.5L13.5 10.7L17 11.1L14.4 13.5L15.1 17L12 15.2L8.9 17L9.6 13.5L7 11.1L10.5 10.7Z');
  function paintHeart(x, cx, cy, size, { fill = '#FF3B5C', outline = 0, shine = false, alpha = 1, rot = 0 } = {}) {
    x.save(); x.globalAlpha = alpha; x.translate(cx, cy); if (rot) x.rotate(rot); x.scale(size / 24, size / 24); x.translate(-12, -12);
    x.fillStyle = fill; x.fill(HEART24);
    if (outline) { x.lineWidth = outline; x.lineJoin = 'round'; x.strokeStyle = '#FFFFFF'; x.stroke(HEART24); }
    if (shine) { x.lineWidth = 1.4; x.lineCap = 'round'; x.strokeStyle = 'rgba(255,255,255,.8)'; x.stroke(SHINE); }
    x.restore();
  }
  function paintShield(x, cx, cy, width) {
    x.save(); x.translate(cx, cy); x.scale(width / 24, width / 24); x.translate(-12, -13.2);
    x.fillStyle = PINK; x.fill(SHIELD24); x.lineJoin = 'round'; x.lineWidth = 2.2; x.strokeStyle = GOLD; x.stroke(SHIELD24);
    x.save(); x.translate(12, 12.5); x.scale(.8, .8); x.translate(-12, -12.5); x.lineWidth = .9; x.strokeStyle = '#FFFFFF'; x.stroke(SHIELD24); x.restore();
    x.fillStyle = GOLD; x.fill(STAR10); x.lineWidth = .6; x.strokeStyle = '#FFFFFF'; x.stroke(STAR10);
    x.restore();
  }
  // heart_pickup.dart: 32 pt, white outline 1.8, pulse 1 ↔ 1.14 per 1 s
  const heartPickup = (x, cx, cy, t) => paintHeart(x, cx, cy, 32 * (1 + .14 * (.5 - .5 * Math.cos(TAU * (t % 1)))), { outline: 1.8 });
  // shield_pickup.dart: the shield icon 38 pt, bob ±3 pt at ω 6
  const shieldPickup = (x, cx, cy, t) => paintShield(x, cx, cy + 3 * Math.sin(t * 6), 38);
  // comet_star.dart §5.6: 46 pt gold 4-point star, white 2 pt outline, inner white star, pink / gold tail to the right
  const star4 = (r, w) => { const p = new Path2D(); p.moveTo(0, -r); p.lineTo(w, -w); p.lineTo(r, 0); p.lineTo(w, w); p.lineTo(0, r); p.lineTo(-w, w); p.lineTo(-r, 0); p.lineTo(-w, -w); p.closePath(); return p; };
  const STAR_OUT = star4(21, 6), STAR_IN = star4(11, 3);
  function cometStar(x, cx, cy, t) {
    cy += 4 * Math.sin(t * 4);
    x.fillStyle = rgba(PINK, .85); x.beginPath(); x.moveTo(cx + 7, cy - 9); x.lineTo(cx + 73, cy); x.lineTo(cx + 7, cy + 9); x.fill();
    x.fillStyle = rgba(GOLD, .9); x.beginPath(); x.moveTo(cx + 7, cy - 5); x.lineTo(cx + 49, cy); x.lineTo(cx + 7, cy + 5); x.fill();
    x.save(); x.translate(cx, cy); x.rotate(14 * Math.PI / 180 * Math.sin(t * 3)); const s = 1 + .08 * Math.sin(t * 6); x.scale(s, s);
    x.fillStyle = GOLD; x.fill(STAR_OUT); x.lineWidth = 2; x.lineJoin = 'round'; x.strokeStyle = '#FFFFFF'; x.stroke(STAR_OUT);
    x.fillStyle = 'rgba(255,255,255,.9)'; x.fill(STAR_IN); x.restore();
  }
  // capsule.dart §5.29 (Hourglass #2F80FF): pulsing ring r 25, 34 pt rounded square r 8, darker band, white hourglass
  function capsule(x, cx, cy, t) {
    cy += 3 * Math.sin(t * 3);
    const pulse = Math.sin(t * 5), s = 1 + .06 * pulse, col = '#2F80FF';
    x.save(); x.translate(cx, cy); x.scale(s, s);
    x.lineWidth = 3; x.strokeStyle = rgba(col, clamp(.35 + .25 * pulse, 0, 1)); x.beginPath(); x.arc(0, 0, 25, 0, TAU); x.stroke();
    x.fillStyle = col; x.beginPath(); x.roundRect(-17, -17, 34, 34, 8); x.fill();
    x.fillStyle = 'rgba(0,0,0,.14)'; x.beginPath(); x.roundRect(-17, 5, 34, 12, 6); x.fill();
    x.fillStyle = '#FFFFFF'; x.fillRect(-9, -12, 18, 3); x.fillRect(-9, 9, 18, 3);
    x.beginPath(); [[-7, -9], [7, -9], [1, 0], [7, 9], [-7, 9], [-1, 0]].forEach(([a, b], i) => i ? x.lineTo(a, b) : x.moveTo(a, b)); x.fill();
    x.fillStyle = col; x.beginPath(); x.moveTo(-4, 7); x.lineTo(4, 7); x.lineTo(0, 2); x.fill();
    x.restore();
  }
  // shield.dart: the shield circle around the bird (r 38, soft pink .28, gold 3.5, white dashed r 31 spinning 90°/s)
  function shieldCircle(x, cx, cy, t) {
    const k = 1 + .05 * Math.sin(t * 5);
    x.save(); x.translate(cx, cy); x.scale(k, k);
    x.fillStyle = rgba(SOFT, .28); x.beginPath(); x.arc(0, 0, 38, 0, TAU); x.fill();
    x.lineWidth = 3.5; x.strokeStyle = GOLD; x.stroke();
    x.rotate(t * Math.PI / 2); x.setLineDash([7, 9]); x.lineWidth = 2.5; x.strokeStyle = 'rgba(255,255,255,.8)';
    x.beginPath(); x.arc(0, 0, 31, 0, TAU); x.stroke(); x.restore();
  }
  // score_hud.dart: background_score.png (183 pt) tinted with the stage foreground, LVDC digits in the stage background
  function scoreCircle(x, cx, cy, score, fg, bg) {
    const s = tinted(IMG.circle, fg, 183, 183); if (s) x.drawImage(s, cx - 91.5, cy - 91.5, 183, 183);
    const digits = String(score).length, size = digits <= 2 ? 125 : digits === 3 ? 96 : 76;
    txt(x, String(score), cx, cy + 6, size, bg, 'score');
  }
  // banners.dart master #7: full-width band at y 190, white Opificio, letter-spacing .1 em, padding 6;
  // scale-in over 12 %, hold to 75 %, then scale out + fade. Streak duration .9 + .16 × min(tier, 6).
  function bannerDraw(x, b, width = 320, top = 190) {
    const k = clamp(b.t / b.dur, 0, 1);
    let sy = 1, a = 1;
    if (k < .12) sy = k / .12; else if (k > .75) { sy = a = 1 - (k - .75) / .25; }
    if (sy <= 0) return;
    const size = Math.min(34, Math.floor(300 / (b.s.length * .72))), h = size * 1.25 + 12;
    x.save(); x.globalAlpha = a; x.translate(0, top + h / 2); x.scale(1, sy); x.translate(0, -h / 2);
    x.fillStyle = b.col; x.fillRect(0, 0, width, h);
    txt(x, b.s, width / 2 + size * .05, h / 2 + 1, size, '#FFFFFF', 'ui', 'center', size * .1);
    x.restore();
  }
  // particle_pool.dart: one flat pool; shapes rect, circle, flame (teardrop with colour ramp), triangle, heart
  function flamePath(x, r) {
    x.beginPath(); x.moveTo(-r, 0); x.quadraticCurveTo(-r, -r * 1.9, r * .2, -r * 2.2); x.quadraticCurveTo(r, -r * .9, r, 0);
    x.arc(0, 0, r, 0, Math.PI, false); x.closePath();
  }
  const FIRE_RAMP = ['#FFFFFF', '#FFF3B0', '#FF9100', '#D50000'];
  function rampColor(r, k) { const u = k * (r.length - 1), i = Math.min(r.length - 2, Math.floor(u)); return mix(r[i], r[i + 1], u - i); }
  function Pool() { return { list: [] }; }
  function spawn(pool, p) { pool.list.push(Object.assign({ t: 0, vx: 0, vy: 0, g: 0, drag: 0, rot: 0, spin: 0, a0: 1, a1: 0, s0: 1, s1: 1, h: 0 }, p)); }
  function poolStep(pool, dt) {
    for (const p of pool.list) { p.t += dt; if (p.drag) p.vx *= 1 - p.drag * dt; p.vy += p.g * dt; p.x += p.vx * dt; p.y += p.vy * dt; p.rot += p.spin * dt; }
    pool.list = pool.list.filter((p) => p.t < p.life);
  }
  function poolDraw(x, pool) {
    for (const p of pool.list) {
      const k = clamp(p.t / p.life, 0, 1), a = p.a0 + (p.a1 - p.a0) * k; if (a <= 0) continue;
      const s = p.s0 + (p.s1 - p.s0) * k, w = p.w * s, h = (p.h || p.w) * s;
      x.save(); x.globalAlpha = clamp(a, 0, 1); x.translate(p.x, p.y); if (p.rot) x.rotate(p.rot);
      x.fillStyle = p.ramp ? rampColor(p.ramp, k) : p.color;
      if (p.shape === 'flame') { flamePath(x, w / 2 * (1 - k * .65)); x.fill(); }
      else if (p.shape === 'circle') { x.beginPath(); x.arc(0, 0, w / 2, 0, TAU); x.fill(); }
      else if (p.shape === 'tri') { x.beginPath(); x.moveTo(0, -h / 2); x.lineTo(w / 2, h / 2); x.lineTo(-w / 2, h / 2); x.fill(); }
      else if (p.shape === 'heart') { x.restore(); paintHeart(x, p.x, p.y, w, { fill: p.color, alpha: a, rot: p.rot }); continue; }
      else x.fillRect(-w / 2, -h / 2, w, h);
      x.restore();
    }
  }
  // fever.dart FireMaster (PRD-2.2 §21): streak ×3/×5/×7 = level 1/2/3; 55/95/150 flames per s; size .7/.85/1;
  // 40 % behind (x −22, ±14), 35 % on top (y −15), the rest below (lift .5); vx −130…−60, vy −80…−20; warm halo
  function Fire() { return { pool: Pool(), acc: 0 }; }
  function fireLevel(streak) { return streak >= 7 ? 3 : streak >= 5 ? 2 : streak >= 3 ? 1 : 0; }
  function fireStep(f, dt, bx, by, level, k = 1) {
    if (level) {
      f.acc += [55, 95, 150][level - 1] * dt; const sc = [.7, .85, 1][level - 1];
      while (f.acc >= 1) {
        f.acc -= 1; const e = Math.random(); let x, y, lift = 1;
        if (e < .4) { x = -22 - 2 + Math.random() * 6; y = (Math.random() * 2 - 1) * 14; }
        else if (e < .75) { x = -20 + Math.random() * 36; y = -15 - 3 + Math.random() * 5; }
        else { x = -20 + Math.random() * 30; y = 15 - 2 + Math.random() * 5; lift = .5; }
        const size = rnd(9, 16) * sc, life = rnd(.3, .55) * (.8 + .2 * sc), vx = rnd(-130, -60), vy = rnd(-80, -20) * lift;
        spawn(f.pool, { shape: 'flame', x: bx + x * k, y: by + y * k, vx, vy, rot: Math.atan2(vy, vx) + Math.PI / 2, w: size * .6 * k, ramp: FIRE_RAMP, life, a1: .2 });
      }
    } else f.acc = 0;
    poolStep(f.pool, dt);
  }
  function fireDraw(x, f, bx, by, level, k = 1) {
    if (level) {
      const r = [34, 42, 52][level - 1] * k, a = [.22, .30, .38][level - 1];
      const g = x.createRadialGradient(bx - 4 * k, by - 2 * k, 0, bx - 4 * k, by - 2 * k, r);
      g.addColorStop(6 * k / r, rgba('#FF9100', a)); g.addColorStop(1, rgba('#FF9100', 0));
      x.fillStyle = g; x.beginPath(); x.arc(bx - 4 * k, by - 2 * k, r, 0, TAU); x.fill();
    }
    poolDraw(x, f.pool);
  }
  // tier_trail.dart: the equipped trail (default Classic flame) while on fire / in a ride, 2× scale, 18 pt behind
  const TRAIL_K = 2 * LOOK_SCALE;
  function trailStepDraw(x, st, dt, on, bx, by, speed, k = 1) {
    if (on) SKIN.trailEmit(st, 'flame', bx - 18 * k, by, dt, TRAIL_K * k, -speed);
    SKIN.trailStep(st, dt);
    SKIN.trailDraw(x, st, 'flame', TRAIL_K * k, { x: bx, y: by });
  }
  // perfect_burst.dart master #9: 8 + 3 × min(tier, 3) squares 5–8 pt, pink / gold / soft pink, 25–55 pt out, 350–600 ms
  function perfectBurst(pool, px, py, tier) {
    const n = 8 + 3 * Math.min(Math.max(tier, 1), 3), C = [PINK, GOLD, SOFT];
    for (let i = 0; i < n; i++) { const a = Math.random() * TAU, d = rnd(25, 55), life = rnd(.35, .6), s = rnd(5, 8); spawn(pool, { x: px, y: py, vx: Math.cos(a) * d / life, vy: Math.sin(a) * d / life, w: s, color: C[i % 3], life }); }
  }
  // dust_puff.dart: 12–22 discs r 4–9 in the surface colour, ±140 sideways, 10–90 up, drag, +60 down, .8 → 0 in .6–1 s
  function dustPuff(pool, px, py, color, up = true) {
    const n = 12 + (Math.random() * 11 | 0);
    for (let i = 0; i < n; i++) spawn(pool, { shape: 'circle', x: px, y: py, vx: rnd(-140, 140), vy: (up ? -1 : 1) * rnd(10, 90), drag: 2, g: 60, w: rnd(8, 18), color, life: rnd(.6, 1), a0: .8 });
  }
  // save_burst.dart: the shield shatters into 12 triangles, the extra-life badge into 12 small hearts
  function saveBurst(pool, px, py, hearts) {
    for (let i = 0; i < 12; i++) {
      const a = i / 12 * TAU + rnd(-.2, .2), v = rnd(120, 220);
      spawn(pool, hearts ? { shape: 'heart', x: px, y: py, vx: Math.cos(a) * v, vy: Math.sin(a) * v, g: 300, w: rnd(8, 12), color: '#FF3B5C', life: .7, spin: rnd(-6, 6) }
                         : { shape: 'tri', x: px, y: py, vx: Math.cos(a) * v, vy: Math.sin(a) * v, g: 300, w: rnd(7, 11), color: i % 2 ? GOLD : PINK, life: .7, spin: rnd(-8, 8) });
    }
  }
  // coin_popup.dart master #8: gold "+N" 28 pt Opificio + 24 pt coin; 1.1 s: in 20 % fade/scale .7 → 1.1, y +6 → −4; then out to y −40
  function coinPopups(x, list, dt) {
    for (let i = list.length - 1; i >= 0; i--) {
      const p = list[i]; p.t += dt; if (p.t > 1.1) { list.splice(i, 1); continue; }
      const k = p.t / 1.1; let a, s, y;
      if (k < .2) { const u = k / .2; a = u; s = .7 + .4 * u; y = 6 - 10 * u; } else { const u = (k - .2) / .8; a = 1 - u; s = 1.1 - .1 * u; y = -4 - 36 * u; }
      x.save(); x.globalAlpha = a; x.translate(p.x + 20, p.y - 58 + y); x.scale(s, s);
      txt(x, '+' + p.n, -6, 0, 28, GOLD, 'ui', 'right'); if (IMG.coin.complete) x.drawImage(IMG.coin, -3, -12, 24, 24);
      x.restore();
    }
  }
  // miss_flash.dart §5.13: white flash, red shock ring (1 → 2.6×), then the ring drains to a grey dashed ghost
  function missFlash(x, m, cx, cy, opening) {
    const t = m.t;
    if (t < .55) { const u = t / .55; x.save(); x.globalAlpha = 1 - u; x.lineWidth = 6 - 5 * u; x.strokeStyle = '#E8141C'; x.beginPath(); x.ellipse(cx, cy, 12 * (1 + 1.6 * u), (opening / 2 + 7) * (1 + 1.6 * u), 0, 0, TAU); x.stroke(); x.restore(); }
    if (t < .12) { ringHalf(x, cx, cy, opening, false, ['#FFFFFF', '#FFFFFF'], 8); ringHalf(x, cx, cy, opening, true, ['#FFFFFF', '#FFFFFF'], 8); return true; }
    const u = clamp((t - .12) / .4, 0, 1), e = u * u * (3 - 2 * u);
    ringHalf(x, cx, cy, opening, false, ['#969696', '#787878'], 7, u > .3 ? [6, 6] : null, 1 - .65 * e);
    ringHalf(x, cx, cy, opening, true, ['#969696', '#787878'], 7, u > .3 ? [6, 6] : null, 1 - .65 * e);
    return true;
  }
  // comet_ride.dart §5.6: tail triangles + gold shell (r 28, pink rim 3.5, inner #FFD98A r 22), bird at 90 %, countdown ring r 34
  function cometBack(x, cx, cy, tilt) {
    x.save(); x.translate(cx, cy); x.rotate(tilt);
    x.fillStyle = rgba(GOLD, .45); x.beginPath(); x.moveTo(-4, -22); x.lineTo(-104, 0); x.lineTo(-4, 22); x.fill();
    x.fillStyle = rgba(PINK, .55); x.beginPath(); x.moveTo(-4, -15); x.lineTo(-74, 0); x.lineTo(-4, 15); x.fill();
    x.fillStyle = GOLD; x.beginPath(); x.arc(0, 0, 28, 0, TAU); x.fill(); x.lineWidth = 3.5; x.strokeStyle = PINK; x.stroke();
    x.fillStyle = '#FFD98A'; x.beginPath(); x.arc(0, 0, 22, 0, TAU); x.fill(); x.restore();
  }
  function cometFront(x, cx, cy, left, secs) {
    x.save(); x.translate(cx, cy);
    x.lineWidth = 6; x.lineCap = 'round'; x.strokeStyle = GOLD; x.beginPath(); x.arc(0, 0, 34, -Math.PI / 2, -Math.PI / 2 + TAU * left); x.stroke();
    x.lineCap = 'butt'; x.strokeStyle = 'rgba(255,255,255,.2)'; x.beginPath(); x.arc(0, 0, 34, 0, TAU); x.stroke(); x.restore();
    txt(x, secs + 's', cx, cy + 50, 18, GOLD);
  }

  window.FS = { REDUCED, IMG, ACCENT, FIRE_RAMP, Fire, GOLD, HEART24, LOOK_SCALE, PINK, PLUM, Pool, RING_BRIGHT, RING_GOLD, RING_PINK, SHIELD24, SHINE, SOFT, SPIKE_H, STAGES, STAR10, STAR_IN, STAR_OUT, STREAK, STREAK_C, TAU, TRAIL_K, bannerDraw, birdAt, capsule, clamp, coinPopups, cometBack, cometFront, cometStar, dustPuff, fireDraw, fireLevel, fireStep, flamePath, heartPickup, hex, missFlash, mix, paintHeart, paintShield, perfectBurst, poolDraw, poolStep, rampColor, rgba, ringHalf, rnd, saveBurst, scoreCircle, setup, shieldCircle, shieldPickup, spawn, spikeStrip, star4, streakName, tintCache, tinted, trailStepDraw, txt };
})();
