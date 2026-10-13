(() => {
  'use strict';
  // Every drawing below is a 1:1 port of the game's own painters (lib/run/**, lib/components/**),
  // with their constants; file references in the comments. Nothing here is a new design.
  const REDUCED = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const IMG = {};
  ['spikes:{{a:@images/ground_spikes.png}}', 'coin:{{a:@images/menu/coin.png}}', 'circle:{{a:@images/background_score.png}}', 'sound:{{a:@images/soundbutton.png}}', 'mute:{{a:@images/mutebutton.png}}']
    .forEach((s) => { const [k, d] = s.split(':'); const i = new Image(); i.src = d; IMG[k] = i; });
  const PINK = '#EC008C', PLUM = '#7A0044', GOLD = '#FFB529', SOFT = '#FCD9EE', ACCENT = '#FF4FB7', TAU = Math.PI * 2;
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const rnd = (a, b) => a + Math.random() * (b - a);
  const LOOK_SCALE = 0.985;                              // Config.lookScale

  // ---------- sound (off by default; the game's own files, fetched only once the visitor switches sound on) ----------
  const SND = { flap: '{{a:@audio/flap.mp3}}', point: '{{a:@audio/point.mp3}}', perfect: '{{a:@audio/perfect_1.mp3}}', die: '{{a:@audio/gameover.mp3}}', click: '{{a:@audio/click.mp3}}',
                shield: '{{a:@audio/pu_shield_get.mp3}}', heart: '{{a:@audio/pu_heart_1.mp3}}', comet: '{{a:@audio/pu_comet_get.mp3}}', cometEnd: '{{a:@audio/pu_comet_end.mp3}}', slow: '{{a:@audio/hourglass_start.mp3}}',
                rim: '{{a:@audio/rim_tonk.mp3}}', miss: '{{a:@audio/miss_shock.mp3}}', save: '{{a:@audio/pu_shield_hit.mp3}}' };
  const audio = {};
  let soundOn = false;
  function sfx(n, vol = 0.5) {
    if (!soundOn) return;
    try { audio[n] = audio[n] || new Audio(SND[n]); const a = audio[n].cloneNode(); a.volume = vol; a.play().catch(() => {}); } catch (e) {}
  }
  const sndBtn = document.getElementById('sound'), sndImg = document.getElementById('snd-img');
  sndBtn.addEventListener('click', () => {
    soundOn = !soundOn;
    if (soundOn) for (const n in SND) if (!audio[n]) { try { audio[n] = new Audio(SND[n]); audio[n].preload = 'auto'; } catch (e) {} }
    sndBtn.setAttribute('aria-pressed', soundOn);
    sndBtn.setAttribute('aria-label', soundOn ? 'Sound on' : 'Sound off');
    sndImg.style.setProperty('--icon', 'url(' + (soundOn ? IMG.sound.src : IMG.mute.src) + ')');
    sfx('click');
  });
  sndImg.style.setProperty('--icon', 'url(' + IMG.mute.src + ')');

  // ---------- hero and versus rays: centred behind the phone at every width ----------
  const rayCentres = [[document.querySelector('.hero'), document.getElementById('play-frame')], [document.getElementById('versus'), document.getElementById('vs')]];
  function centreRays() {
    for (const [zone, phone] of rayCentres) {
      const z = zone.getBoundingClientRect(), f = phone.getBoundingClientRect();
      zone.style.setProperty('--rx', (f.left + f.width / 2 - z.left) + 'px');
      zone.style.setProperty('--ry', (f.top + f.height / 2 - z.top) + 'px');
    }
  }
  addEventListener('resize', centreRays); addEventListener('load', centreRays); document.fonts.ready.then(centreRays); centreRays();

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

  // =====================================================================================
  // 1. hero: a real run (RunConfig: gravity 1250, flap −370, max fall 650, cruise 150, bird x 70, r 14.75)
  // =====================================================================================
  const G = 1250, FLAP = -370, MAXFALL = 650, CRUISE = 150, BIRD_X = 70, R = 14.75, VW = 320, VH = 568, MID = 284, SPACING = 310;
  // the director's gap items, compressed so a short demo shows them all (real runs space them out more)
  const PLAN = { 2: 'heart', 4: 'shield', 6: 'capsule', 9: 'comet' };
  const demo = setup('demo');
  const LOOKS = [{ bird: 'classic' }, { bird: 'classic', hat: 'cap', acc: 'shades' }, { bird: 'buzz', hat: 'crown' }, { bird: 'sky', acc: 'shades' }, { bird: 'duck', hat: 'tophat' }];
  const D = { auto: true, idle: 0, t: 0, best: 0 };
  let demoLook = LOOKS[0];
  function demoReset(newLook) {
    Object.assign(D, {
      y: MID, vy: 0, hoops: [], items: [], score: 0, streak: 0, stage: 0, stageT: 1, prev: 0, n: 0,
      dead: false, deadT: 0, spin: 0, flapT: 0, banner: null, coins: [], fx: Pool(), fire: Fire(), trail: SKIN.Trail(),
      shield: false, life: false, inv: 0, slow: 0, ride: null, land: 0, speeds: [], miss: null,
    });
    D.giveUp = rnd(40, 90);                                                         // the autopilot crashes now and then, so the demo restarts
    for (let i = 0; i < 3; i++) addHoop(220 + i * SPACING);
    if (newLook) demoLook = LOOKS[(Math.random() * LOOKS.length) | 0];
  }
  function addHoop(x, cy) {
    const prev = D.hoops[D.hoops.length - 1], i = D.n++;
    const open = Math.max(92, 118 * (1 - .0032 * i)), ry = open / 2 + 7;          // opening0 118, shrink .32 %/hoop, floor 78 %
    const lo = SPIKE_H + ry + 40, hi = VH - SPIKE_H - ry - 40;
    const base = prev ? clamp(prev.cy + rnd(-110, 110), lo, hi) : rnd(lo, hi);
    const h = { x, cy: cy ?? base, open, passed: false, i, comet: false };
    D.hoops.push(h);
    const kind = D.ride ? null : PLAN[i % 20];
    if (!prev || !kind) return;
    if (kind === 'comet') { h.comet = true; h.cy = clamp(h.cy, MID - 80, MID + 80); D.items.push({ k: 'comet', x: h.x + 20, y: h.cy }); }
    else D.items.push({ k: kind, x: (prev.x + h.x) / 2, y: clamp((prev.cy + h.cy) / 2 + rnd(-20, 20), SPIKE_H + 60, VH - SPIKE_H - 60) });
  }
  function flap() { D.vy = FLAP; D.flapT = .14; sfx('flap', .35); }
  const frame = document.getElementById('play-frame'), hint = document.getElementById('play-hint');
  function hintSet(playing) { hint.innerHTML = playing ? '<b>Tap</b>, <b>click</b> or <b>space</b> to jump' : '<b>Click</b> or press <b>space</b> to take over'; }
  function input() {
    D.idle = 0;
    if (D.dead) { if (D.deadT > .6) { D.auto = false; hintSet(true); demoReset(false); flap(); } return; }   // after a crash: a new run
    if (D.auto) { D.auto = false; hintSet(true); }                                    // take over the run as it is
    if (D.ride) return;                                                             // the comet flies itself
    flap();
  }
  frame.addEventListener('pointerdown', (e) => { e.preventDefault(); input(); });
  addEventListener('keydown', (e) => {
    if (e.code !== 'Space' && e.code !== 'ArrowUp') return;
    const r = frame.getBoundingClientRect();
    if (r.bottom < 0 || r.top > innerHeight) return;
    e.preventDefault(); input();
  });
  function banner(s, col, dur) { D.banner = { s, col, t: 0, dur }; }
  // mistakes.dart: a missed hoop or the spikes; the shield absorbs first, then the extra life
  function mistake(kind, fg) {
    if (D.dead || D.inv > 0 || D.ride) return;
    if (D.shield || D.life) {
      saveBurst(D.fx, BIRD_X, D.y, !D.shield);
      if (D.shield) D.shield = false; else D.life = false;
      sfx('save', .4); D.inv = 2; D.streak = 0; D.vy = kind === 'top' ? 200 : -300;
      return;
    }
    D.dead = true; D.deadT = 0; D.spin = rnd(6, 10) * (Math.random() < .5 ? -1 : 1);
    D.vy = kind === 'top' ? 120 : -260; sfx('die', .45); D.best = Math.max(D.best, D.score);
    if (kind === 'top' || kind === 'bottom') dustPuff(D.fx, BIRD_X, kind === 'top' ? SPIKE_H : VH - SPIKE_H, fg, kind !== 'top');
  }
  function collect(it) {
    it.got = true;
    if (it.k === 'heart') { D.life = true; sfx('heart', .4); }
    if (it.k === 'shield') { D.shield = true; sfx('shield', .4); }
    if (it.k === 'capsule') { D.slow = 8; sfx('slow', .4); }
    if (it.k === 'comet') startComet();
  }
  // comet_ride.dart: 10 s, 1.7 × cruise, the bird flies itself through the hoops' centres, hoops zigzag ±70 pt
  function startComet() {
    D.ride = { t: 0, len: 10, tilt: 0 }; sfx('comet', .4);
    let s = 1;
    D.hoops.filter((h) => h.x > BIRD_X + 1).forEach((h) => { h.cy = MID + 70 * s; s = -s; });
    D.items = D.items.filter((it) => it.x < BIRD_X);
    D.rideFrom = { x: BIRD_X, y: D.y };
  }
  function rideY() {
    const next = D.hoops.find((h) => h.x >= BIRD_X - .5);
    const prev = [...D.hoops].reverse().find((h) => h.x < BIRD_X - .5);
    const p = prev && (!D.rideFrom || prev.x > D.rideFrom.x - 999) ? { x: prev.x, cy: prev.cy } : { x: BIRD_X - 1, cy: D.rideFrom.y };
    if (!next) return D.y;
    const u = clamp((BIRD_X - p.x) / Math.max(1, next.x - p.x), 0, 1);
    return p.cy + (next.cy - p.cy) * (u * u * (3 - 2 * u));
  }
  function demoStep(dtReal) {
    D.t += dtReal; D.idle += dtReal;
    const slow = D.land > 0 ? .5 : D.slow > 0 ? .45 : 1;                           // landing slow-mo / Hourglass .45
    const dt = dtReal * slow;
    D.flapT = Math.max(0, D.flapT - dtReal); D.inv = Math.max(0, D.inv - dtReal); D.slow = Math.max(0, D.slow - dtReal); D.land = Math.max(0, D.land - dtReal);
    if (D.banner) { D.banner.t += dtReal; if (D.banner.t > D.banner.dur) D.banner = null; }
    poolStep(D.fx, dt);
    const fg = mix(STAGES[D.prev][1], STAGES[D.stage][1], D.stageT);
    if (D.miss) D.miss.t += dtReal;
    if (D.dead) {
      // §3.0.5 ballistic tumble: spin and fall
      D.deadT += dtReal; D.vy = Math.min(MAXFALL, D.vy + G * dt); D.y += D.vy * dt; D.spinA = (D.spinA || 0) + D.spin * dt;
      fireStep(D.fire, dt, BIRD_X, D.y, 0);
      if (D.auto && D.deadT > 1.4) demoReset(true);
      if (!D.auto && D.idle > 6) { D.auto = true; hintSet(false); demoReset(true); }
      return;
    }
    if (!D.auto && D.idle > 4) {                                                      // the visitor stopped: the autopilot takes the same run back
      D.auto = true; hintSet(false); D.giveUp = D.score + rnd(40, 90);
    }
    D.spinA = 0;
    const cruise = CRUISE * (D.ride ? (D.ride.t < .45 ? 1 + .7 * D.ride.t / .45 : D.ride.len - D.ride.t < .9 ? 1 + .7 * (D.ride.len - D.ride.t) / .9 : 1.7) : 1);
    if (D.ride) {
      D.ride.t += dt;
      const ny = rideY(); const vy = (ny - D.y) / Math.max(dt, 1e-4);
      D.ride.tilt = clamp(Math.atan2(vy, cruise), -35 * Math.PI / 180, 35 * Math.PI / 180);
      D.y = ny; D.vy = 0;
      if (Math.random() < dt / .034) D.speeds.push({ x: 340, y: rnd(SPIKE_H + 20, VH - SPIKE_H - 20), len: rnd(30, 110), t: 0 });
      if (D.ride.t >= D.ride.len) { D.ride = null; D.land = 1.5; D.inv = .6; flap(); sfx('cometEnd', .35); }
    } else {
      if (D.auto) {
        const next = D.hoops.find((h) => !h.passed && h.x > BIRD_X - 14) || { cy: MID, x: 999 };
        const it = D.items.find((i) => !i.got && i.x > BIRD_X - 4 && i.x < next.x - 60);
        const target = (it ? it.y : next.cy) + 8;
        const quit = D.score >= D.giveUp;
        if (!quit && D.y > target && D.vy > -60) flap();
      }
      D.vy = Math.min(MAXFALL, D.vy + G * dt);
      D.y += D.vy * dt;
    }
    D.speeds.forEach((s) => { s.t += dtReal; s.x = 340 - 460 * s.t / .26; }); D.speeds = D.speeds.filter((s) => s.t < .26);
    D.items.forEach((it) => { it.x -= cruise * dt; if (!it.got && Math.hypot(it.x - BIRD_X, it.y - D.y) - R <= 18) collect(it); });
    D.items = D.items.filter((it) => it.x > -60 && !it.got);
    const lvl = fireLevel(D.streak);
    fireStep(D.fire, dt, BIRD_X, D.y, D.ride ? 0 : lvl);
    D.trailOn = !!D.ride || lvl > 0;
    for (const h of D.hoops) {
      h.x -= cruise * dt;
      const ry = h.open / 2 + 7;
      if (!D.ride && !h.passed) for (const s of [-1, 1]) {
        // §3.0.4 rim touch: a knock, not a death
        const d = Math.hypot(BIRD_X - h.x, D.y - (h.cy + s * ry));
        if (d < R + 7) { D.vy = s < 0 ? Math.abs(D.vy) * .4 + 80 : -Math.abs(D.vy) * .4 - 120; D.y = h.cy + s * ry - s * (R + 7.5); D.streak = 0; sfx('rim', .3); }
      }
      if (!h.passed && h.x < BIRD_X) {
        h.passed = true;
        if (!D.ride && Math.abs(D.y - h.cy) > ry) { D.miss = { t: 0, h }; sfx('miss', .4); mistake('miss', fg); continue; }
        // PRD-2.2 §11 perfect zone: centred passes only (every comet pass is perfect)
        const perfect = !!D.ride || Math.abs(D.y - h.cy) < h.open * .2;
        D.streak = perfect ? D.streak + 1 : 0;
        D.score += perfect ? Math.max(2, D.streak) : 1;                              // PRD-2.2 §13 points
        D.coins.push({ x: h.x, y: D.y, t: 0, n: perfect ? 2 : 1 });
        if (perfect) { perfectBurst(D.fx, h.x, D.y, Math.min(D.streak, 3)); banner(streakName(D.streak), STREAK_C[(D.streak - 1) % 10], .9 + .16 * Math.min(Math.max(D.streak, 1), 6)); }
        sfx(perfect ? 'perfect' : 'point', .4);
        const st = Math.floor(h.i / 10) % STAGES.length;                             // a new colour stage every 10 hoops
        if (st !== D.stage) { D.prev = D.stage; D.stage = st; D.stageT = 0; }
      }
    }
    D.stageT = Math.min(1, D.stageT + dtReal / .6);
    while (D.hoops.length && D.hoops[0].x < -60) D.hoops.shift();
    const last = D.hoops[D.hoops.length - 1];
    if (last.x < VW + 80) addHoop(last.x + SPACING, D.ride ? (last.cy > MID ? MID - 70 : MID + 70) : undefined);
    if (!D.ride) {
      if (D.y - R < SPIKE_H - 4) mistake('top', fg);
      else if (D.y + R > VH - SPIKE_H + 4) mistake('bottom', fg);
      D.y = clamp(D.y, SPIKE_H - 10, VH - SPIKE_H + 10);
    }
  }
  function demoDraw(dt) {
    const x = demo.x;
    const bg = mix(STAGES[D.prev][0], STAGES[D.stage][0], D.stageT), fg = mix(STAGES[D.prev][1], STAGES[D.stage][1], D.stageT);
    x.fillStyle = bg; x.fillRect(0, 0, VW, VH);
    scoreCircle(x, 160, MID, D.score, fg, bg);
    if (D.banner) bannerDraw(x, D.banner);                                           // banners sit behind the gameplay (PRD-2.2 §12)
    x.strokeStyle = 'rgba(255,255,255,.7)'; x.lineWidth = 2;                         // comet speed streaks, under the hoops
    D.speeds.forEach((s) => { x.beginPath(); x.moveTo(s.x, s.y); x.lineTo(s.x + s.len, s.y); x.stroke(); });
    D.hoops.forEach((h) => { if (D.miss && D.miss.h === h) return; ringHalf(x, h.x, h.cy, h.open, false, h.passed && D.ride ? RING_GOLD : RING_PINK); });
    D.items.forEach((it) => (({ heart: heartPickup, shield: shieldPickup, capsule, comet: cometStar })[it.k])(x, it.x, it.y, D.t));
    trailStepDraw(x, D.trail, dt * (D.slow > 0 ? .45 : 1), D.trailOn && !D.dead, BIRD_X, D.y, CRUISE);
    fireDraw(x, D.fire, BIRD_X, D.y, D.dead || D.ride ? 0 : fireLevel(D.streak));
    if (D.ride) cometBack(x, BIRD_X, D.y, D.ride.tilt);
    const blink = D.inv > 0 && !D.ride && Math.floor(D.t * 12) % 2;
    birdAt(x, demoLook, BIRD_X, D.y, LOOK_SCALE * (D.ride ? .9 : 1), D.t, D.flapT > 0, D.dead ? D.spinA : D.ride ? D.ride.tilt : 0, blink ? .4 : 1);
    if (D.ride) cometFront(x, BIRD_X, D.y, 1 - D.ride.t / D.ride.len, Math.ceil(D.ride.len - D.ride.t));
    if (D.shield) shieldCircle(x, BIRD_X, D.y, D.t);
    if (D.life) paintHeart(x, BIRD_X, D.y - 41 + 4 * Math.sin(D.t * 4), 34, { shine: true, outline: 1.8 });
    D.hoops.forEach((h) => { if (D.miss && D.miss.h === h) return; ringHalf(x, h.x, h.cy, h.open, true, h.passed && D.ride ? RING_GOLD : RING_PINK); });
    if (D.miss) missFlash(x, D.miss, D.miss.h.x, D.miss.h.cy, D.miss.h.open);
    poolDraw(x, D.fx);
    coinPopups(x, D.coins, dt);
    spikeStrip(x, VW, 0, fg, true);
    spikeStrip(x, VW, VH - SPIKE_H, fg, false);
    if (D.auto || (D.dead && D.deadT > .6)) {                                       // the title art's "TAP TO JUMP"
      const a = .65 + .35 * Math.sin(D.t * 4);
      x.save(); x.globalAlpha = a; txt(x, 'TAP TO JUMP', 160, VH - SPIKE_H - 40, 26, PINK, 'ui', 'center', 1); x.restore();
    }
  }
  demoReset(true);

  // =====================================================================================
  // 2. how to play: three small runs on the first colour stage
  // =====================================================================================
  const how1 = setup('how1'), how2 = setup('how2'), how3 = setup('how3');
  const [S0BG, S0FG] = STAGES[0];
  const HOW_K = 1;
  function tile(x) { x.setTransform(1, 0, 0, 1, 0, 0); x.clearRect(0, 0, x.canvas.width, x.canvas.height); const d = Math.min(2, devicePixelRatio || 1); x.setTransform(d * HOW_K, 0, 0, d * HOW_K, d * 160 * (1 - HOW_K), d * 160 * (1 - HOW_K)); }
  const H1 = { y: 160, vy: 0, t: 0, next: .3, flapT: 0 };
  function how1Step(dt) {
    const s = H1; s.t += dt; s.flapT = Math.max(0, s.flapT - dt); s.next -= dt;
    if (s.y > 176 && s.next < 0) { s.vy = FLAP; s.flapT = .14; s.next = .2; }
    s.vy = Math.min(MAXFALL, s.vy + G * dt); s.y += s.vy * dt;
    const x = how1.x; tile(x);
    birdAt(x, { bird: 'mint', hat: 'party' }, 110, s.y, 2.6 * LOOK_SCALE, s.t, s.flapT > 0);
    const a = .65 + .35 * Math.sin(s.t * 4); x.save(); x.globalAlpha = a; txt(x, 'TAP TO JUMP', 160, 261, 19, PINK); x.restore();
  }
  const H2 = { t: 0, n: 0, last: -1, banner: null, fx: Pool(), fire: Fire(), trail: SKIN.Trail(), coins: [], score: 0 };
  function how2Step(dt) {
    const s = H2; s.t += dt;
    const period = 1.6, cyc = Math.floor(s.t / period), u = (s.t % period) / period;
    const bx = -30 + u * 380, by = 160;
    if (cyc !== s.last && bx >= 170) {
      s.last = cyc; s.n = s.n % 7 + 1; s.score += Math.max(2, s.n);
      s.banner = { s: streakName(s.n), col: STREAK_C[(s.n - 1) % 10], t: 0, dur: .9 + .16 * Math.min(s.n, 6) };
      perfectBurst(s.fx, 170, by, Math.min(s.n, 3)); s.coins.push({ x: 170, y: by, t: 0, n: 2 }); sfx('perfect', .2);
    }
    if (s.banner) { s.banner.t += dt; if (s.banner.t > s.banner.dur) s.banner = null; }
    const x = how2.x; tile(x);
    if (s.banner) bannerDraw(x, s.banner, 320, 34);
    ringHalf(x, 170, 160, 150, false, RING_PINK, 9);
    poolStep(s.fx, dt);
    const lvl = fireLevel(s.n);
    trailStepDraw(x, s.trail, dt, lvl > 0, bx, by, 0, 2.2);
    fireStep(s.fire, dt, bx, by, lvl, 2.2); fireDraw(x, s.fire, bx, by, lvl, 2.2);
    birdAt(x, { bird: 'classic', hat: 'cap' }, bx, by, 2.2 * LOOK_SCALE, s.t, (s.t * 3) % 1 < .2);
    ringHalf(x, 170, 160, 150, true, RING_PINK, 9);
    poolDraw(x, s.fx); coinPopups(x, s.coins, dt);
  }
  const H3 = { t: 0, fx: Pool(), puffed: -1, spin: 0 };
  function how3Step(dt) {
    const s = H3; s.t += dt;
    const period = 3, cyc = Math.floor(s.t / period), u = (s.t % period) / period;
    const x = how3.x; tile(x);
    let by, rot = 0, alive = true;
    if (u < .4) by = 250 - (u / .4) * (250 - SPIKE_H - 30);
    else { alive = false; const k = (u - .4) / .6; by = SPIKE_H + 30 + k * k * 330; rot = k * 9; }
    if (!alive && s.puffed !== cyc) { s.puffed = cyc; dustPuff(s.fx, 160, SPIKE_H, S0FG, false); sfx('die', .2); }
    poolStep(s.fx, dt); poolDraw(x, s.fx);
    if (by < 360) birdAt(x, { bird: 'lime', acc: 'shades' }, 160, by, 2.6 * LOOK_SCALE, s.t, alive && (s.t * 4) % 1 < .25, rot);
  }

  // =====================================================================================
  // 3. versus: a real run with the versus bar (versus_bar.dart §5.7) and the opponent's score replaying
  // =====================================================================================
  const vs = setup('vs');
  const V = { t: 0, y: 240, vy: 0, f: 0, hoops: [], me: 0, them: 0, themNext: 1.1, flash: 0, streak: 0, end: 0, fx: Pool(), coins: [] };
  function vsReset() { V.hoops = []; for (let i = 0; i < 3; i++) V.hoops.push({ x: 260 + i * 310, cy: rnd(200, 330), open: 118, passed: false }); V.me = 0; V.them = 0; V.themNext = 1.1; V.streak = 0; V.end = 0; }
  vsReset();
  function personGlyph(x, rx, ry, c) {
    const k = 25 / 24, ox = rx + 19 - 12 * k, oy = ry + 19 - 12 * k;
    x.fillStyle = c; x.beginPath(); x.arc(ox + 12 * k, oy + 8 * k, 4.5 * k, 0, TAU); x.fill();
    x.beginPath(); x.moveTo(ox + 3 * k, oy + 22 * k); x.arc(ox + 12 * k, oy + 22 * k, 9 * k, Math.PI, 0); x.closePath(); x.fill();
  }
  function vsStep(dt) {
    V.t += dt;
    const x = vs.x, [bg, fg] = STAGES[1], H = 520;
    const playing = V.end === 0;
    if (playing) {
      V.hoops.forEach((h) => { h.x -= CRUISE * dt; });
      if (V.hoops[0].x < -60) { const l = V.hoops[V.hoops.length - 1]; V.hoops.shift(); V.hoops.push({ x: l.x + 310, cy: clamp(l.cy + rnd(-110, 110), 170, 400), open: 118, passed: false }); }
      const next = V.hoops.find((h) => !h.passed && h.x > BIRD_X - 14) || { cy: 260 };
      if (V.y > next.cy + 6 && V.vy > -60) { V.vy = FLAP; V.f = .14; }
      V.vy = Math.min(MAXFALL, V.vy + G * dt); V.y += V.vy * dt; V.f = Math.max(0, V.f - dt);
      V.hoops.forEach((h) => { if (!h.passed && h.x < BIRD_X) { h.passed = true; const p = Math.abs(V.y - h.cy) < h.open * .2; V.streak = p ? V.streak + 1 : 0; V.me += p ? Math.max(2, V.streak) : 1; V.coins.push({ x: h.x, y: V.y, t: 0, n: p ? 2 : 1 }); if (p) perfectBurst(V.fx, h.x, V.y, Math.min(V.streak, 3)); } });
      V.themNext -= dt; if (V.themNext <= 0) { V.them += Math.random() < .45 ? 2 : 1; V.themNext = rnd(1.6, 2.4); V.flash = .45; }  // their recorded timeline
      V.flash = Math.max(0, V.flash - dt);
      if (V.me >= 25 || V.them >= 25) { V.end = .001; sfx('perfect', .3); }
    } else { V.end += dt; if (V.end > 2.8) vsReset(); }
    poolStep(V.fx, dt);
    x.fillStyle = bg; x.fillRect(0, 0, 320, H);
    scoreCircle(x, 160, H / 2, V.me, fg, bg);
    V.hoops.forEach((h) => ringHalf(x, h.x, h.cy, h.open, false));
    birdAt(x, { bird: 'classic', hat: 'cap', acc: 'shades' }, BIRD_X, V.y, LOOK_SCALE, V.t, V.f > 0);
    V.hoops.forEach((h) => ringHalf(x, h.x, h.cy, h.open, true));
    poolDraw(x, V.fx); coinPopups(x, V.coins, dt);
    spikeStrip(x, 320, 0, fg, true); spikeStrip(x, 320, H - SPIKE_H, fg, false);
    // the versus bar: you at x 60 (pink, dark-pink avatar outside), them at x 170 (stage fg, darker avatar outside)
    const top = 52, h = 38;
    x.fillStyle = '#EC008C'; x.fillRect(60, top, 90, h); x.fillStyle = '#C40073'; x.fillRect(60, top, h, h); personGlyph(x, 60, top, SOFT);
    txt(x, String(V.me), 60 + h + (90 - h) / 2, top + h / 2 + 1, 26, SOFT);
    x.fillStyle = fg; x.fillRect(170, top, 90, h); x.fillStyle = mix('#000000', fg, .7); x.fillRect(260 - h, top, h, h); personGlyph(x, 260 - h, top, bg);
    txt(x, String(V.them), 170 + (90 - h) / 2, top + h / 2 + 1, 26, bg);
    if (V.flash > 0) { x.lineWidth = 3; x.strokeStyle = rgba(GOLD, V.flash / .45); x.strokeRect(171.5, top + 1.5, 87, h - 3); }
    txt(x, 'VS', 160, top + h / 2 + 1, 15, PLUM, 'fredoka');
    x.fillStyle = '#FFFFFF'; x.fillRect(60, 92, 90, 22); x.fillRect(170, 92, 90, 22);
    txt(x, 'You', 105, 104, 15, PLUM, 'fredoka'); txt(x, 'RapidParrot411', 215, 104, 13, PLUM, 'fredoka');
    if (!playing) {                                                                  // the results title band (Config.uiAccent)
      const won = V.me >= V.them, k = Math.min(1, V.end * 5);
      x.save(); x.globalAlpha = k; x.fillStyle = ACCENT; x.fillRect(16, 330, 288, 62); txt(x, won ? 'YOU WIN!' : 'YOU LOSE', 160, 362, 36, '#FFFFFF', 'ui', 'center', 4); x.restore();
    }
  }

  // =====================================================================================
  // 4. skins parade: the shop's birds flying left to right
  // =====================================================================================
  const parade = setup('parade');
  const FLOCK = [
    { bird: 'classic', hat: 'cap', acc: 'shades' }, { bird: 'duck', hat: 'tophat' }, { bird: 'penguin', hat: 'beanie' },
    { bird: 'phoenix', acc: 'chain' }, { bird: 'zombie', acc: 'patch' }, { bird: 'galaxy', hat: 'halo' }, { bird: 'buzz', hat: 'crown' },
    { bird: 'robo', hat: 'prop' }, { bird: 'owl', hat: 'wizard' }, { bird: 'flamingo', acc: 'bowtie' }, { bird: 'ghost', hat: 'party' },
    { bird: 'toucan', hat: 'pirate' }, { bird: 'frost', acc: 'scarf' }, { bird: 'chick', hat: 'viking' }, { bird: 'rainbow', acc: 'hearts' }, { bird: 'golden', hat: 'cowboy' },
  ];
  let paradeT = 0;
  function paradeStep(dt) {
    paradeT += dt;
    const x = parade.x, W = parade.c.clientWidth || 1200;
    if (parade.w !== W) { const d = parade.d; parade.c.width = W * d; parade.w = W; parade.x.setTransform(d, 0, 0, d, 0, 0); }
    x.clearRect(0, 0, W, 330);
    const big = W < 700 ? 2.6 : 3.4, gap = W < 700 ? 150 : 200, total = FLOCK.length * gap, off = (paradeT * 52) % total;
    for (let i = 0; i < FLOCK.length; i++) {
      let px = (i * gap + off) % total - 100;                                       // moving right
      if (px > W + 100) continue;
      const bob = Math.sin(paradeT * 2.4 + i * 1.3) * 20, fl = ((paradeT * 2.2 + i * .37) % 1) < .22;
      birdAt(x, FLOCK[FLOCK.length - 1 - i], px, 160 + bob, big, paradeT, fl);
    }
  }

  // =====================================================================================
  // 5. ranks: emblem_art.js with the classic bird on the plate (as on the Levels screen)
  // =====================================================================================
  const grid = document.getElementById('rank-grid'), rankC = [];
  LEVELS.forEach((lv, i) => {
    const el = document.createElement('div'); el.className = 'rank';
    el.innerHTML = '<canvas width="200" height="200"></canvas><b>' + lv.n + '</b><small>best ' + lv.s + '+</small>';
    grid.appendChild(el);
    const c = el.querySelector('canvas'); c.id = 'rank' + i;
    rankC.push(setup(c.id));
  });
  let rankT = 0;
  function ranksStep(dt) {
    rankT += dt;
    rankC.forEach((r, i) => {
      if (!r.visible) return;
      const x = r.x; x.clearRect(0, 0, 200, 200);
      x.save(); x.translate(100, 108); x.scale(.82, .82);
      drawEmblem(x, i + 1, rankT + i * .7, {});
      x.save(); x.translate(0, -2); x.scale(1.4, 1.4); SKIN.drawLook(x, { bird: 'classic' }, rankT, ((rankT * 1.4 + i * .3) % 1) < .2); x.restore();
      x.restore();
    });
  }

  // =====================================================================================
  // 6. call to action: the bird on fire flying through a ring
  // =====================================================================================
  const cta = setup('cta');
  const C = { t: 0, fire: Fire(), trail: SKIN.Trail(), fx: Pool(), coins: [], last: -1 };
  function ctaStep(dt) {
    C.t += dt;
    const x = cta.x; x.clearRect(0, 0, 520, 260);
    const period = 2.4, cyc = Math.floor(C.t / period), u = (C.t % period) / period, bx = -60 + u * 640, by = 130;
    if (cyc !== C.last && bx > 260) { C.last = cyc; perfectBurst(C.fx, 260, by, 3); C.coins.push({ x: 260, y: by, t: 0, n: 2 }); }
    ringHalf(x, 260, 130, 150, false, RING_PINK, 12);
    poolStep(C.fx, dt);
    trailStepDraw(x, C.trail, dt, true, bx, by, 0, 2);
    fireStep(C.fire, dt, bx, by, 3, 2); fireDraw(x, C.fire, bx, by, 3, 2);
    birdAt(x, { bird: 'classic' }, bx, by, 2 * LOOK_SCALE, C.t, (C.t * 2.6) % 1 < .2);
    ringHalf(x, 260, 130, 150, true, RING_PINK, 12);
    poolDraw(x, C.fx); coinPopups(x, C.coins, dt);
  }

  // ---------- loop: only visible canvases animate ----------
  const jobs = [
    [demo, (dt) => { demoStep(dt); demoDraw(dt); }],
    [how1, how1Step], [how2, how2Step], [how3, how3Step], [vs, vsStep], [parade, paradeStep], [cta, ctaStep],
  ];
  const all = [...jobs.map((j) => j[0]), ...rankC];
  const io = new IntersectionObserver((es) => es.forEach((e) => { const j = all.find((s) => s.c === e.target); if (j) j.visible = e.isIntersecting; }), { rootMargin: '80px' });
  all.forEach((s) => io.observe(s.c));
  let last = performance.now();
  function tick(now) {
    const dt = Math.min(1 / 30, (now - last) / 1000); last = now;
    jobs.forEach(([s, f]) => { if (s.visible) f(dt); });
    if (rankC.some((r) => r.visible)) ranksStep(dt);
    requestAnimationFrame(tick);
  }
  window.__demo = { D, demoStep, demoDraw, jobs, ranksStep };
  Promise.all(['16px "Opificio Neue"', '600 16px "Fredoka"', '16px "LVDC Common2"'].map((f) => document.fonts.load(f).catch(() => {})))
    .then(() => document.fonts.ready).then(() => {
    if (REDUCED) {
      jobs.forEach(([s, f]) => { if (s !== demo) f(0.5); }); ranksStep(0); demoDraw(0);
      let lastR = performance.now();
      const loopR = (now) => { const dt = Math.min(1 / 30, (now - lastR) / 1000); lastR = now; if (!D.auto) demoStep(dt); demoDraw(dt); requestAnimationFrame(loopR); };
      requestAnimationFrame(loopR);
    } else requestAnimationFrame(tick);
  });
})();
