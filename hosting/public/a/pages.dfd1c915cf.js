(() => {
  'use strict';
  // The small animations on the content pages, 404 and CTA blocks (PRD-2.3 §5.10, §11.5). Everything is drawn with the
  // game's own painters: paint.js (the helper block of game.js, window.FS), skin_art.js (SKIN) and emblem_art.js.
  // A canvas names its painter in data-paint="name[:arg]". Only visible canvases animate; reduced motion draws one frame.
  const {
    REDUCED, IMG, PINK, PLUM, GOLD, SOFT, TAU, STAGES, SPIKE_H, LOOK_SCALE, RING_PINK, RING_GOLD,
    clamp, rnd, mix, rgba, txt, birdAt, ringHalf, spikeStrip, tinted, scoreCircle, bannerDraw, streakName, STREAK_C,
    Pool, poolStep, poolDraw, Fire, fireLevel, fireStep, fireDraw, trailStepDraw, perfectBurst, dustPuff, coinPopups, missFlash,
    heartPickup, shieldPickup, cometStar, capsule, shieldCircle, paintHeart, cometBack, cometFront,
  } = window.FS;
  const G = 1250, FLAP = -370, MAXFALL = 650, CRUISE = 150, BIRD_X = 70;     // RunConfig (as in game.js)
  const [S0BG, S0FG] = STAGES[0];
  const img = (src) => { const i = new Image(); i.src = src; return i; };
  const OLD = { bird: img('/a/bird.72505e325b.png'), flap: img('/a/bird_flap.2b2b211bc7.png'), top: img('/a/pipe_top.7b77131e45.png'), bottom: img('/a/pipe_bottom.a17b734e29.png') };

  function prep(c) {
    const w = +c.getAttribute('width'), h = +c.getAttribute('height'), d = Math.min(2, devicePixelRatio || 1);
    c.width = w * d; c.height = h * d;
    const x = c.getContext('2d');
    return { c, x, w, h, d, visible: true, t: 0, clear() { x.setTransform(1, 0, 0, 1, 0, 0); x.clearRect(0, 0, c.width, c.height); x.setTransform(d, 0, 0, d, 0, 0); } };
  }

  const P = {};
  // the bird flapping in place (game.js how1)
  P.flap = (s, dt) => {
    const st = s.st || (s.st = { y: s.h / 2, vy: 0, next: .3, flapT: 0 });
    st.flapT = Math.max(0, st.flapT - dt); st.next -= dt;
    if (st.y > s.h / 2 + 16 && st.next < 0) { st.vy = FLAP; st.flapT = .14; st.next = .2; }
    st.vy = Math.min(MAXFALL, st.vy + G * dt); st.y += st.vy * dt;
    s.clear(); birdAt(s.x, s.arg ? { bird: s.arg } : { bird: 'mint', hat: 'party' }, s.w / 2, st.y, 2.6 * LOOK_SCALE, s.t, st.flapT > 0);
    const a = .65 + .35 * Math.sin(s.t * 4); s.x.save(); s.x.globalAlpha = a; txt(s.x, 'TAP TO FLAP!', s.w / 2, s.h - 40, 19, PINK); s.x.restore();
  };
  // perfects in a row and the fire (game.js how2)
  P.perfect = (s, dt) => {
    const st = s.st || (s.st = { n: 0, last: -1, banner: null, fx: Pool(), fire: Fire(), trail: SKIN.Trail(), coins: [] });
    const period = 1.6, cyc = Math.floor(s.t / period), u = (s.t % period) / period, cx = s.w / 2 + 10, bx = -30 + u * (s.w + 60), by = s.h / 2;
    if (cyc !== st.last && bx >= cx) {
      st.last = cyc; st.n = st.n % 7 + 1;
      st.banner = { s: streakName(st.n), col: STREAK_C[(st.n - 1) % 10], t: 0, dur: .9 + .16 * Math.min(st.n, 6) };
      perfectBurst(st.fx, cx, by, Math.min(st.n, 3)); st.coins.push({ x: cx, y: by, t: 0, n: 2 });
    }
    if (st.banner) { st.banner.t += dt; if (st.banner.t > st.banner.dur) st.banner = null; }
    const x = s.x; s.clear();
    if (st.banner) bannerDraw(x, st.banner, s.w, 34);
    ringHalf(x, cx, by, 150, false, RING_PINK, 9);
    poolStep(st.fx, dt);
    const lvl = fireLevel(st.n);
    trailStepDraw(x, st.trail, dt, lvl > 0, bx, by, 0, 2.2);
    fireStep(st.fire, dt, bx, by, lvl, 2.2); fireDraw(x, st.fire, bx, by, lvl, 2.2);
    birdAt(x, { bird: 'classic', hat: 'cap' }, bx, by, 2.2 * LOOK_SCALE, s.t, (s.t * 3) % 1 < .2);
    ringHalf(x, cx, by, 150, true, RING_PINK, 9);
    poolDraw(x, st.fx); coinPopups(x, st.coins, dt);
  };
  // one touch of the spikes: the crash tumble and dust puff (game.js how3; also the 404 page)
  P.crash = (s, dt) => {
    const st = s.st || (s.st = { fx: Pool(), puffed: -1 });
    const period = 3, cyc = Math.floor(s.t / period), u = (s.t % period) / period, top = SPIKE_H, col = s.c.dataset.color || S0FG;
    const x = s.x; s.clear();
    if (s.arg === 'strip') spikeStrip(x, s.w, 0, col, true);
    let by, rot = 0, alive = true;
    const start = s.h - 70;
    if (u < .4) by = start - (u / .4) * (start - top - 30);
    else { alive = false; const k = (u - .4) / .6; by = top + 30 + k * k * (s.h + 40); rot = k * 9; }
    if (!alive && st.puffed !== cyc) { st.puffed = cyc; dustPuff(st.fx, s.w / 2, top, col, false); }
    poolStep(st.fx, dt); poolDraw(x, st.fx);
    if (by < s.h + 40) birdAt(x, { bird: s.bird || 'lime', acc: 'shades' }, s.w / 2, by, 2.6 * LOOK_SCALE, s.t, alive && (s.t * 4) % 1 < .25, rot);
  };
  // a pickup on its own, at 2x (heart_pickup / shield_pickup / comet_star / capsule)
  const PICK = { heart: heartPickup, shield: shieldPickup, comet: cometStar, capsule };
  P.pickup = (s) => {
    s.clear(); s.x.save(); s.x.translate(s.w / 2 - (s.arg === 'comet' ? 30 : 0), s.h / 2); s.x.scale(2, 2);
    PICK[s.arg](s.x, 0, 0, s.t); s.x.restore();
  };
  // the shield circle around the bird; the extra-life heart above it
  P.shielded = (s) => {
    s.clear(); const x = s.x; x.save(); x.translate(s.w / 2, s.h / 2 + 6); x.scale(1.6, 1.6);
    birdAt(x, { bird: 'classic' }, 0, 0, LOOK_SCALE, s.t, (s.t * 2) % 1 < .2);
    shieldCircle(x, 0, 0, s.t); x.restore();
  };
  P.life = (s) => {
    s.clear(); const x = s.x; x.save(); x.translate(s.w / 2, s.h / 2 + 22); x.scale(1.6, 1.6);
    birdAt(x, { bird: 'classic' }, 0, 0, LOOK_SCALE, s.t, (s.t * 2) % 1 < .2);
    paintHeart(x, 0, -41 + 4 * Math.sin(s.t * 4), 34, { shine: true, outline: 1.8 }); x.restore();
  };
  // the comet ride: the gold shell, the tilt and the countdown ring (comet_ride.dart)
  P.comet = (s, dt) => {
    s.clear(); const x = s.x, left = 1 - (s.t % 10) / 10, tilt = .35 * Math.sin(s.t * 2);
    x.save(); x.translate(s.w / 2 + 20, s.h / 2 - 8 + 10 * Math.sin(s.t * 2)); x.scale(1.5, 1.5);
    cometBack(x, 0, 0, tilt); birdAt(x, { bird: 'classic' }, 0, 0, LOOK_SCALE * .9, s.t, false, tilt); cometFront(x, 0, 0, left, Math.ceil(left * 10));
    x.restore();
  };
  // a miss: white flash, red shock ring, grey ghost ring (miss_flash.dart)
  P.miss = (s, dt) => {
    s.clear(); const m = { t: (s.t % 2) }; const x = s.x;
    if (!missFlash(x, m, s.w / 2, s.h / 2, 118)) { ringHalf(x, s.w / 2, s.h / 2, 118, false); ringHalf(x, s.w / 2, s.h / 2, 118, true); }
  };
  // coins: a pass pays +1, a perfect +2 (coin_popup.dart)
  P.coins = (s, dt) => {
    const st = s.st || (s.st = { list: [], fx: Pool(), last: -1, k: 0 });
    const period = 1.5, cyc = Math.floor(s.t / period), u = (s.t % period) / period, cx = s.w / 2, cy = s.h / 2 + 18, bx = -30 + u * (s.w + 60);
    if (cyc !== st.last && bx >= cx) { st.last = cyc; st.k ^= 1; st.list.push({ x: cx, y: cy - 20, t: 0, n: st.k ? 2 : 1 }); if (st.k) perfectBurst(st.fx, cx, cy, 1); }
    s.clear(); poolStep(st.fx, dt);
    ringHalf(s.x, cx, cy, 130, false, RING_PINK, 9);
    birdAt(s.x, { bird: 'golden' }, bx, cy + (st.k ? 0 : 0), 2 * LOOK_SCALE, s.t, (s.t * 3) % 1 < .2);
    ringHalf(s.x, cx, cy, 130, true, RING_PINK, 9);
    poolDraw(s.x, st.fx); coinPopups(s.x, st.list, dt);
  };
  // a skin item: a bird, a hat / gear on the classic bird, a hoop around the bird, a trail behind it
  P.bird = (s) => { s.clear(); s.x.save(); s.x.translate(s.w / 2, s.h / 2 + 4); birdAt(s.x, { bird: s.arg }, 0, 0, s.w / 56, s.t + s.seed, ((s.t + s.seed) * 1.3) % 1 < .18); s.x.restore(); };
  P.hat = (s) => { s.clear(); s.x.save(); s.x.translate(s.w / 2, s.h / 2 + 12); birdAt(s.x, { bird: 'classic', hat: s.arg }, 0, 0, s.w / 62, s.t + s.seed, false); s.x.restore(); };
  P.acc = (s) => { s.clear(); s.x.save(); s.x.translate(s.w / 2, s.h / 2 + 4); birdAt(s.x, { bird: 'classic', acc: s.arg }, 0, 0, s.w / 62, s.t + s.seed, ((s.t + s.seed) * 1.3) % 1 < .18); s.x.restore(); };
  P.hoop = (s) => {
    s.clear(); const x = s.x, ry = s.h * .36;
    SKIN.hoopHalf(x, s.arg, s.w / 2, s.h / 2, ry, s.t, false, 8);
    birdAt(x, { bird: 'classic' }, s.w / 2 - 6, s.h / 2, LOOK_SCALE * 1.2, s.t, false);
    SKIN.hoopHalf(x, s.arg, s.w / 2, s.h / 2, ry, s.t, true, 8);
  };
  P.trail = (s, dt) => {
    const st = s.st || (s.st = SKIN.Trail());
    const k = 1.2, bx = s.w * .66, by = s.h / 2 + 6 * Math.sin(s.t * 3);
    SKIN.trailEmit(st, s.arg, bx - 18 * k, by, dt, 2 * k * LOOK_SCALE, -120); SKIN.trailStep(st, dt);
    s.clear(); SKIN.trailDraw(s.x, st, s.arg, 2 * k * LOOK_SCALE, { x: bx, y: by });
    birdAt(s.x, { bird: 'classic' }, bx, by, LOOK_SCALE * k, s.t, (s.t * 2.4) % 1 < .2);
  };
  // a rank emblem with the classic bird on its plate (as on the Levels screen)
  P.emblem = (s) => {
    s.clear(); const x = s.x, k = s.w / 200;
    x.save(); x.scale(k, k); x.translate(100, 108); x.scale(.82, .82);
    drawEmblem(x, +s.arg, s.t + s.seed, {});
    x.save(); x.translate(0, -2); x.scale(1.4, 1.4); SKIN.drawLook(x, { bird: 'classic' }, s.t, ((s.t * 1.4 + s.seed) % 1) < .2); x.restore();
    x.restore();
  };
  // a flock of birds flying left to right (game.js parade)
  const FLOCK = [
    { bird: 'classic', hat: 'cap', acc: 'shades' }, { bird: 'duck', hat: 'tophat' }, { bird: 'penguin', hat: 'beanie' },
    { bird: 'phoenix', acc: 'chain' }, { bird: 'zombie', acc: 'patch' }, { bird: 'galaxy', hat: 'halo' }, { bird: 'buzz', hat: 'crown' },
    { bird: 'robo', hat: 'prop' }, { bird: 'owl', hat: 'wizard' }, { bird: 'flamingo', acc: 'bowtie' }, { bird: 'ghost', hat: 'party' },
    { bird: 'toucan', hat: 'pirate' }, { bird: 'frost', acc: 'scarf' }, { bird: 'chick', hat: 'viking' }, { bird: 'rainbow', acc: 'hearts' }, { bird: 'golden', hat: 'cowboy' },
  ];
  P.parade = (s) => {
    const W = s.c.clientWidth || s.w;
    if (s.w !== W) { s.c.width = W * s.d; s.w = W; }
    s.clear();
    const big = W < 700 ? 2.2 : 2.8, gap = W < 700 ? 130 : 170, total = FLOCK.length * gap, off = (s.t * 52) % total;
    for (let i = 0; i < FLOCK.length; i++) {
      const px = (i * gap + off) % total - 100;
      if (px > W + 100) continue;
      const bob = Math.sin(s.t * 2.4 + i * 1.3) * 16, fl = ((s.t * 2.2 + i * .37) % 1) < .22;
      birdAt(s.x, FLOCK[FLOCK.length - 1 - i], px, s.h / 2 + bob, big, s.t, fl);
    }
  };
  // the call to action: the bird on fire flying through a ring (game.js §6)
  P.cta = (s, dt) => {
    const C = s.st || (s.st = { fire: Fire(), trail: SKIN.Trail(), fx: Pool(), coins: [], last: -1 });
    const x = s.x; s.clear();
    const period = 2.4, cyc = Math.floor(s.t / period), u = (s.t % period) / period, bx = -60 + u * 640, by = 130;
    if (cyc !== C.last && bx > 260) { C.last = cyc; perfectBurst(C.fx, 260, by, 3); C.coins.push({ x: 260, y: by, t: 0, n: 2 }); }
    ringHalf(x, 260, 130, 150, false, RING_PINK, 12);
    poolStep(C.fx, dt);
    trailStepDraw(x, C.trail, dt, true, bx, by, 0, 2);
    fireStep(C.fire, dt, bx, by, 3, 2); fireDraw(x, C.fire, bx, by, 3, 2);
    birdAt(x, { bird: 'classic' }, bx, by, 2 * LOOK_SCALE, s.t, (s.t * 2.6) % 1 < .2);
    ringHalf(x, 260, 130, 150, true, RING_PINK, 12);
    poolDraw(x, C.fx); coinPopups(x, C.coins, dt);
  };
  // the versus lane: a real run with the versus bar (versus_bar.dart §5.7) and the opponent's score replaying (game.js §3)
  function personGlyph(x, rx, ry, c) {
    const k = 25 / 24, ox = rx + 19 - 12 * k, oy = ry + 19 - 12 * k;
    x.fillStyle = c; x.beginPath(); x.arc(ox + 12 * k, oy + 8 * k, 4.5 * k, 0, TAU); x.fill();
    x.beginPath(); x.moveTo(ox + 3 * k, oy + 22 * k); x.arc(ox + 12 * k, oy + 22 * k, 9 * k, Math.PI, 0); x.closePath(); x.fill();
  }
  P.vs = (s, dt) => {
    const V = s.st || (s.st = { y: 240, vy: 0, f: 0, end: 0, fx: Pool(), coins: [] });
    if (!V.hoops) { V.hoops = []; for (let i = 0; i < 3; i++) V.hoops.push({ x: 260 + i * 310, cy: rnd(200, 330), open: 118, passed: false }); V.me = 0; V.them = 0; V.themNext = 1.1; V.streak = 0; V.end = 0; V.flash = 0; }
    const x = s.x, [bg, fg] = STAGES[1], H = 520;
    const playing = V.end === 0;
    if (playing) {
      V.hoops.forEach((h) => { h.x -= CRUISE * dt; });
      if (V.hoops[0].x < -60) { const l = V.hoops[V.hoops.length - 1]; V.hoops.shift(); V.hoops.push({ x: l.x + 310, cy: clamp(l.cy + rnd(-110, 110), 170, 400), open: 118, passed: false }); }
      const next = V.hoops.find((h) => !h.passed && h.x > BIRD_X - 14) || { cy: 260 };
      if (V.y > next.cy + 6 && V.vy > -60) { V.vy = FLAP; V.f = .14; }
      V.vy = Math.min(MAXFALL, V.vy + G * dt); V.y += V.vy * dt; V.f = Math.max(0, V.f - dt);
      V.hoops.forEach((h) => { if (!h.passed && h.x < BIRD_X) { h.passed = true; const p = Math.abs(V.y - h.cy) < h.open * .2; V.streak = p ? V.streak + 1 : 0; V.me += p ? Math.max(2, V.streak) : 1; V.coins.push({ x: h.x, y: V.y, t: 0, n: p ? 2 : 1 }); if (p) perfectBurst(V.fx, h.x, V.y, Math.min(V.streak, 3)); } });
      V.themNext -= dt; if (V.themNext <= 0) { V.them += Math.random() < .45 ? 2 : 1; V.themNext = rnd(1.6, 2.4); V.flash = .45; }
      V.flash = Math.max(0, V.flash - dt);
      if (V.me >= 25 || V.them >= 25) V.end = .001;
    } else { V.end += dt; if (V.end > 2.8) V.hoops = null; }
    if (!V.hoops) return;
    poolStep(V.fx, dt);
    x.fillStyle = bg; x.fillRect(0, 0, 320, H);
    scoreCircle(x, 160, H / 2, V.me, fg, bg);
    V.hoops.forEach((h) => ringHalf(x, h.x, h.cy, h.open, false));
    birdAt(x, { bird: 'classic', hat: 'cap', acc: 'shades' }, BIRD_X, V.y, LOOK_SCALE, s.t, V.f > 0);
    V.hoops.forEach((h) => ringHalf(x, h.x, h.cy, h.open, true));
    poolDraw(x, V.fx); coinPopups(x, V.coins, dt);
    spikeStrip(x, 320, 0, fg, true); spikeStrip(x, 320, H - SPIKE_H, fg, false);
    const top = 52, h = 38;
    x.fillStyle = '#EC008C'; x.fillRect(60, top, 90, h); x.fillStyle = '#C40073'; x.fillRect(60, top, h, h); personGlyph(x, 60, top, SOFT);
    txt(x, String(V.me), 60 + h + (90 - h) / 2, top + h / 2 + 1, 26, SOFT);
    x.fillStyle = fg; x.fillRect(170, top, 90, h); x.fillStyle = mix('#000000', fg, .7); x.fillRect(260 - h, top, h, h); personGlyph(x, 260 - h, top, bg);
    txt(x, String(V.them), 170 + (90 - h) / 2, top + h / 2 + 1, 26, bg);
    if (V.flash > 0) { x.lineWidth = 3; x.strokeStyle = rgba(GOLD, V.flash / .45); x.strokeRect(171.5, top + 1.5, 87, h - 3); }
    txt(x, 'VS', 160, top + h / 2 + 1, 15, PLUM, 'fredoka');
    x.fillStyle = '#FFFFFF'; x.fillRect(60, 92, 90, 22); x.fillRect(170, 92, 90, 22);
    txt(x, 'You', 105, 104, 15, PLUM, 'fredoka'); txt(x, 'RapidParrot411', 215, 104, 13, PLUM, 'fredoka');
    if (!playing) {
      const won = V.me >= V.them, k = Math.min(1, V.end * 5);
      x.save(); x.globalAlpha = k; x.fillStyle = '#FF4FB7'; x.fillRect(16, 330, 288, 62); txt(x, won ? 'YOU WIN!' : 'YOU LOSE', 160, 362, 36, '#FFFFFF', 'ui', 'center', 4); x.restore();
    }
  };
  // 2014 and 2026 side by side: the original bird between the original pipes, and today's bird in a hoop.
  // data-paint="then" shows both halves; "then:old" and "then:new" show one of them on the whole canvas.
  function scene2014(x, s, x0, W, H, fg) {
    const gap = 105, gy = H / 2 + 6, pw = 88, ph = 513.5, px = x0 + ((W + 40) - (s.t * 60) % (W + 140)) + 10;
    const pt = tinted(OLD.top, fg, pw, ph), pb = tinted(OLD.bottom, fg, pw, ph);
    if (pt) x.drawImage(pt, px, gy - gap / 2 - ph, pw, ph);
    if (pb) x.drawImage(pb, px, gy + gap / 2, pw, ph);
    const fl = (s.t * 2.5) % 1 < .2, oi = fl ? OLD.flap : OLD.bird;
    if (oi.complete) x.drawImage(oi, x0 + W * .32 - 23, gy - 15 + 10 * Math.sin(s.t * 2.5), 46.5, 29.5);
    spikeStrip(x, x0 + W, 0, fg, true); spikeStrip(x, x0 + W, H - SPIKE_H, fg, false);
    txt(x, '2014', x0 + W / 2, H - SPIKE_H - 22, 22, PINK);
  }
  function scene2026(x, s, x0, W, H, fg) {
    const hx = x0 + W * .5, hy = H / 2 + 6;
    ringHalf(x, hx, hy, 92, false);
    birdAt(x, { bird: 'classic' }, hx - 4 + 10 * Math.sin(s.t * 1.3), hy + 8 * Math.sin(s.t * 2.5), LOOK_SCALE * 1.15, s.t, (s.t * 2.5) % 1 < .2);
    ringHalf(x, hx, hy, 92, true);
    spikeStrip(x, x0 + W, 0, fg, true); spikeStrip(x, x0 + W, H - SPIKE_H, fg, false);
    txt(x, '2026', x0 + W / 2, H - SPIKE_H - 22, 22, PINK);
  }
  P.then = (s) => {
    const x = s.x, W = s.w, H = s.h, half = W / 2, [bg, fg] = STAGES[0];
    s.clear();
    x.fillStyle = bg; x.fillRect(0, 0, W, H);
    if (s.arg === 'old') { scene2014(x, s, 0, W, H, fg); return; }
    if (s.arg === 'new') { scene2026(x, s, 0, W, H, fg); return; }
    x.save(); x.beginPath(); x.rect(0, 0, half - 3, H); x.clip(); scene2014(x, s, 0, half, H, fg); x.restore();
    x.fillStyle = PLUM; x.fillRect(half - 3, 0, 6, H);
    x.save(); x.beginPath(); x.rect(half + 3, 0, half - 3, H); x.clip(); x.translate(0, 0); scene2026(x, s, half, half, H, fg); x.restore();
  };

  // the special rings, one small loop each (how to play): the bird flies through, the ring does its trick
  const RING_RED = ['#E8141C', '#A00010'], RING_GREY = ['#9AA5AD', '#6B7C88'], RING_VIOLET = ['#9B30D9', '#5E1A8C'];
  function flyBy(s, period = 2.2) { const u = (s.t % period) / period; return { u, bx: -24 + u * (s.w + 48) }; }
  const RINGS = {
    bullseye(s, x, cx, cy) {
      const { bx } = flyBy(s), pulse = 1 + .12 * Math.sin(s.t * 6);
      ringHalf(x, cx, cy, 70, false);
      x.fillStyle = '#FFFFFF'; x.beginPath(); x.ellipse(cx, cy, 7 * pulse, 24 * pulse, 0, 0, TAU); x.fill();
      x.fillStyle = PINK; x.beginPath(); x.ellipse(cx, cy, 4 * pulse, 13 * pulse, 0, 0, TAU); x.fill();
      x.fillStyle = GOLD; x.beginPath(); x.ellipse(cx, cy, 2, 5, 0, 0, TAU); x.fill();
      birdAt(x, { bird: 'classic' }, bx, cy, LOOK_SCALE * .62, s.t, (s.t * 3) % 1 < .2);
      ringHalf(x, cx, cy, 70, true);
    },
    train(s, x, cx, cy) {
      const { bx } = flyBy(s, 2.6);
      [-34, 0, 34].forEach((d) => ringHalf(x, cx + d, cy, 52, false, RING_PINK, 6));
      birdAt(x, { bird: 'classic' }, bx, cy, LOOK_SCALE * .55, s.t, (s.t * 3) % 1 < .2);
      [-34, 0, 34].forEach((d) => ringHalf(x, cx + d, cy, 52, true, RING_PINK, 6));
    },
    spring(s, x, cx, cy) {
      const u = (s.t % 1.8) / 1.8, sq = u < .25 ? Math.sin(u / .25 * Math.PI) : 0, ry = cy - 8 + sq * 10;
      x.strokeStyle = '#13B48D'; x.lineWidth = 4; x.lineJoin = 'round'; x.beginPath();
      for (let i = 0; i <= 6; i++) x.lineTo(cx + (i % 2 ? 9 : -9), ry + 44 + i * (5 - sq * 2)); x.stroke();
      ringHalf(x, cx, ry, 62, false, ['#13B48D', '#00695C']);
      const by = u < .25 ? ry : ry - Math.sin((u - .25) / .75 * Math.PI) * 46;
      birdAt(x, { bird: 'classic' }, cx, by, LOOK_SCALE * .6, s.t, false, -.3 * Math.sin((u - .25) / .75 * Math.PI));
      ringHalf(x, cx, ry, 62, true, ['#13B48D', '#00695C']);
      if (u > .2 && u < .7) { x.save(); x.globalAlpha = 1 - (u - .2) / .5; txt(x, 'BOING!', cx, 18, 15, '#13B48D'); x.restore(); }
    },
    switch(s, x, cx, cy) {
      const open = (s.t % 3) > 1.3, cols = open ? RING_PINK : RING_GREY;
      ringHalf(x, cx, cy, 70, false, cols, 7, open ? null : [5, 5]);
      x.fillStyle = open ? GOLD : '#6B7C88'; x.beginPath(); x.arc(cx, cy - 50, 8, 0, TAU); x.fill();
      x.strokeStyle = '#FFFFFF'; x.lineWidth = 2.5; x.stroke();
      if (!open) { x.strokeStyle = '#6B7C88'; x.lineWidth = 4; x.beginPath(); x.moveTo(cx, cy - 34); x.lineTo(cx, cy + 34); x.stroke(); }
      if (open) { const k = ((s.t % 3) - 1.3) / 1.7; birdAt(x, { bird: 'classic' }, -20 + k * (s.w + 40), cy, LOOK_SCALE * .62, s.t, (s.t * 3) % 1 < .2); }
      else birdAt(x, { bird: 'classic' }, 22, cy + 6 * Math.sin(s.t * 4), LOOK_SCALE * .62, s.t, (s.t * 3) % 1 < .2);
      ringHalf(x, cx, cy, 70, true, cols, 7, open ? null : [5, 5]);
    },
    saw(s, x, cx, cy) {
      const { bx } = flyBy(s, 2.4), ry = 42, n = 14;
      ringHalf(x, cx, cy, 70, false, ['#FFD54A', '#E0A800']);
      birdAt(x, { bird: 'classic' }, bx, cy, LOOK_SCALE * .55, s.t, (s.t * 3) % 1 < .2);
      ringHalf(x, cx, cy, 70, true, ['#FFD54A', '#E0A800']);
      x.fillStyle = '#FFB529';
      for (let i = 0; i < n; i++) {
        const a = i / n * TAU + s.t * 2.2, px = cx + Math.cos(a) * 12, py = cy + Math.sin(a) * ry, ox = Math.cos(a) * 9, oy = Math.sin(a) * 9;
        x.beginPath(); x.moveTo(px - oy * .4, py + ox * .4); x.lineTo(px + ox, py + oy); x.lineTo(px + oy * .4, py - ox * .4); x.fill();
      }
      if ((s.t * 5) % 1 < .5) { x.strokeStyle = '#FFFFFF'; x.lineWidth = 2; x.beginPath(); x.moveTo(cx - 10, cy - 50); x.lineTo(cx - 2, cy - 44); x.lineTo(cx - 8, cy - 40); x.stroke(); }
    },
    pair(s, x, cx, cy) {
      const pick = Math.floor(s.t / 2.4) % 2, { u } = flyBy(s, 2.4), lx = cx - 26, rx = cx + 26;
      [lx, rx].forEach((px, i) => {
        ringHalf(x, px, cy + 8, 46, false, RING_PINK, 6);
        const gy = cy - 40 + 3 * Math.sin(s.t * 3 + i);
        x.fillStyle = i ? '#1E9BE0' : PINK; x.fillRect(px - 9, gy - 8, 18, 16); x.fillStyle = GOLD; x.fillRect(px - 2, gy - 8, 4, 16); x.fillRect(px - 9, gy - 2, 18, 4);
        x.beginPath(); x.arc(px - 4, gy - 11, 4, 0, TAU); x.arc(px + 4, gy - 11, 4, 0, TAU); x.fill();
      });
      const tx = pick ? rx : lx, bx = -20 + u * (s.w + 40), by = cy + 8 + (bx < tx ? (tx - lx) * 0 : 0);
      birdAt(x, { bird: 'classic' }, bx, by, LOOK_SCALE * .5, s.t, (s.t * 3) % 1 < .2);
      [lx, rx].forEach((px) => ringHalf(x, px, cy + 8, 46, true, RING_PINK, 6));
    },
    fever(s, x, cx, cy) {
      const { bx } = flyBy(s), g = .5 + .5 * Math.sin(s.t * 7);
      x.save(); x.shadowColor = '#FF3B30'; x.shadowBlur = 10 + 10 * g; ringHalf(x, cx, cy, 74, false, RING_RED, 8); x.restore();
      birdAt(x, { bird: 'classic' }, bx, cy, LOOK_SCALE * .6, s.t, (s.t * 3) % 1 < .2);
      x.save(); x.shadowColor = '#FF3B30'; x.shadowBlur = 10 + 10 * g; ringHalf(x, cx, cy, 74, true, RING_RED, 8); x.restore();
    },
    spin(s, x, cx, cy) {
      const a = s.t * 3.2, r = 38, cols = [PINK, GOLD, '#1E9BE0', '#13B48D', '#9B30D9', '#FF7A1A'];
      for (let i = 0; i < 6; i++) { x.fillStyle = cols[i]; x.beginPath(); x.moveTo(cx, cy + 6); x.arc(cx, cy + 6, r, a + i * TAU / 6, a + (i + 1) * TAU / 6); x.fill(); }
      x.strokeStyle = '#FFFFFF'; x.lineWidth = 4; x.beginPath(); x.arc(cx, cy + 6, r, 0, TAU); x.stroke();
      x.fillStyle = '#FFFFFF'; x.beginPath(); x.arc(cx, cy + 6, 8, 0, TAU); x.fill();
      x.fillStyle = PLUM; x.beginPath(); x.moveTo(cx - 8, cy - 40); x.lineTo(cx + 8, cy - 40); x.lineTo(cx, cy - 26); x.fill();
    },
    portal(s, x, cx, cy) {
      const { bx } = flyBy(s, 2.4);
      for (let i = 5; i >= 0; i--) {
        const k = ((i / 6) + s.t * .5) % 1;
        x.fillStyle = rgba(i % 2 ? '#9B30D9' : '#7C4DFF', .25 + .5 * (1 - k)); x.beginPath(); x.ellipse(cx, cy, 6 + 10 * k, 12 + 34 * k, 0, 0, TAU); x.fill();
      }
      ringHalf(x, cx, cy, 72, false, RING_VIOLET);
      if (bx < cx) birdAt(x, { bird: 'classic' }, bx, cy, LOOK_SCALE * .6 * clamp((cx - bx) / 40, .1, 1), s.t, (s.t * 3) % 1 < .2);
      ringHalf(x, cx, cy, 72, true, RING_VIOLET);
    },
  };
  P.ring = (s) => { s.clear(); RINGS[s.arg](s, s.x, s.w / 2, s.h / 2 + 4); };

  // ---------- the versus bar mock-up and the nickname: plain HTML that counts and changes ----------
  function stepper(fn, every) { if (REDUCED) return; let on = true; document.addEventListener('visibilitychange', () => { on = !document.hidden; }); setInterval(() => on && fn(), every); }
  document.querySelectorAll('[data-vsbar]').forEach((bar) => {
    const me = bar.querySelector('.you b'), them = bar.querySelector('.them b'), box = bar.querySelector('.them .box');
    let a = +me.textContent, b = +them.textContent, k = 0;
    stepper(() => {
      k++;
      if (a >= 40 || b >= 40) { a = 0; b = 0; }
      if (k % 2) { a += Math.random() < .5 ? 2 : 1; me.textContent = a; }
      else { b += Math.random() < .45 ? 2 : 1; them.textContent = b; box.classList.add('flash'); setTimeout(() => box.classList.remove('flash'), 450); }
    }, 900);
  });
  const ADJ = ['Rapid', 'Brave', 'Lucky', 'Swift', 'Mighty', 'Happy', 'Sunny', 'Zippy'], BIRD = ['Parrot', 'Falcon', 'Robin', 'Toucan', 'Owl', 'Puffin', 'Finch', 'Heron'];
  document.querySelectorAll('[data-nick]').forEach((el) => {
    stepper(() => { el.textContent = ADJ[Math.floor(Math.random() * ADJ.length)] + BIRD[Math.floor(Math.random() * BIRD.length)] + (100 + Math.floor(Math.random() * 900)); }, 1600);
  });

  // ---------- plumbing: only visible canvases animate; reduced motion draws one frame ----------
  const all = [...document.querySelectorAll('canvas[data-paint]')].map((c, i) => {
    const [name, arg] = c.dataset.paint.split(':');
    const s = prep(c); s.name = name; s.arg = arg; s.seed = i * .37; s.bird = c.dataset.bird;
    return s;
  }).filter((s) => P[s.name]);
  if (!all.length) return;
  const io = new IntersectionObserver((es) => es.forEach((e) => { const s = all.find((j) => j.c === e.target); if (s) s.visible = e.isIntersecting; }), { rootMargin: '80px' });
  all.forEach((s) => io.observe(s.c));
  const fonts = Promise.all(['16px "Opificio Neue"', '600 16px "Fredoka"', '16px "LVDC Common2"'].map((f) => document.fonts.load(f).catch(() => {})));
  const imgs = Promise.all([...Object.values(OLD), ...Object.values(IMG)].map((i) => i.complete ? 0 : new Promise((r) => { i.onload = i.onerror = r; })));
  Promise.all([fonts, imgs]).then(() => {
    if (REDUCED) { all.forEach((s) => { s.t = 1.2; P[s.name](s, 1 / 60); }); return; }
    let last = performance.now();
    const tick = (now) => {
      const dt = Math.min(1 / 30, (now - last) / 1000); last = now;
      for (const s of all) if (s.visible) { s.t += dt; P[s.name](s, dt); }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  });
})();
