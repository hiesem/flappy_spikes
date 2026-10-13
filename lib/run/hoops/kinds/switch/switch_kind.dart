import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../../menu/wallet.dart';
import '../../../config/switch_config.dart';
import '../../../director/plans.dart';
import '../../../effects/coin_popup.dart';
import '../../../effects/particle_pool.dart';
import '../../../effects/pickup_touch_fx.dart';
import '../../../effects/rising_word.dart';
import '../../../elements.dart';
import '../../../hud/banners.dart';
import '../../../hud/run_hud.dart';
import '../../../mistakes.dart';
import '../../../pickups/pickup.dart';
import '../../../run_context.dart';
import '../../../run_events.dart';
import '../../../run_feature.dart';
import '../../../run_state.dart';
import '../../hoop.dart';
import '../../hoop_kind.dart';
import '../../ring_painter.dart';
import '../normal.dart';
import 'gift_wrap.dart';
import 'laser_gate.dart';
import 'lockdown.dart';
import 'power_iris.dart';
import 'snoozer.dart';
import '../../../../game/paints.dart';

/// One switch-ring design (PRD-2 §5.19, ARCH §1.5 "pluggable design"): the
/// closed barrier, the front decorations, the switch sprite, the open
/// timeline (≤ 0.8 s) and the crash effect. The rules are the kind's and
/// the same for all five.
abstract class SwitchDesignArt {
  const SwitchDesignArt();
  SwitchDesign get design;

  /// Behind the bird: the back half and the closed barrier.
  void paintBack(Canvas canvas, SwitchRingState s);

  /// Over the bird: the front half and the front decorations.
  void paintFront(Canvas canvas, SwitchRingState s);

  /// The switch pickup, centred at the origin; [on] 0..1 its ON state.
  void paintSwitch(Canvas canvas, SwitchPickup p);

  /// Under the switch (Power Iris: the cable to the ring), pickup-local.
  void paintUnder(Canvas canvas, SwitchPickup p) {}

  /// Per-frame timeline effects (s.hitT ≥ 0 after the touch).
  void tick(SwitchRingState s, double dt) {}

  /// The switch was touched.
  void onTouch(SwitchRingState s) {}

  /// The closed ring was reached (crash effect; the sound is shared).
  void onCrash(SwitchRingState s) {}

  static SwitchDesignArt of(SwitchDesign d) => switch (d) {
    SwitchDesign.lockdown => const LockdownArt(),
    SwitchDesign.laserGate => const LaserGateArt(),
    SwitchDesign.powerIris => const PowerIrisArt(),
    SwitchDesign.snoozer => const SnoozerArt(),
    SwitchDesign.giftWrap => const GiftWrapArt(),
  };

  /// The normal pink ring halves (Lockdown, Laser Gate, Gift Wrap).
  static void pinkHalf(
    Canvas canvas,
    SwitchRingState s, {
    required bool front,
  }) {
    RingPainter.paintHalf(
      canvas,
      centre: Offset.zero,
      opening: s.hoop.opening,
      front: front,
      colors: RingColors.pink,
    );
  }
}

/// Rings with an on/off switch (PRD-2 §3.20, §5.19): one kind, five
/// designs (`SlotPlan.extra`, picked by the director: equal chance, never
/// the same twice in a row per run, mixed in a run).
///
/// The ring spawns **closed** (`Hoop.open = false`); its switch pickup
/// floats in the gap before it (the director places it: 1.0 s × scroll ≥
/// 150 pt ahead, 70–100 pt above / below, ≤ 110 pt from the previous
/// hoop). Touching the switch opens the ring at once in the logic (the
/// design's animation ends ≤ 0.8 s later) and gives +1 coin; the streak is
/// untouched. Reaching the plane while closed is a mistake
/// ([PlaneVerdict.mistake] → `MistakeCause.closedSwitch`: crash, knock
/// straight back, death or a save — then the ring counts as passed with no
/// score). Open, it is a normal hoop: +1, coins, streak, rim bounce. Not
/// stage-tinted, no tier look; Big Hoops grows the ring (the switch stays
/// the same size); a comet opens a closed ring by itself.
class SwitchRingKind extends HoopKind {
  @override
  HoopKindId get id => HoopKindId.switchRing;

  @override
  bool get usesTierLook => false;

  static final Expando<SwitchRingState> _states = Expando('switchRing');

  static SwitchRingState? stateOf(Hoop h) => _states[h];

  static SwitchDesign designOf(Hoop h) {
    final e = h.plan.extra;
    return e is SwitchDesign ? e : SwitchDesign.lockdown;
  }

  /// Analytics name of a design (§6 `switchring_*` {design}).
  static String storageName(SwitchDesign d) => switch (d) {
    SwitchDesign.lockdown => 'lock',
    SwitchDesign.laserGate => 'laser',
    SwitchDesign.powerIris => 'iris',
    SwitchDesign.snoozer => 'sleepy',
    SwitchDesign.giftWrap => 'gift',
  };

  @override
  void onSpawn(Hoop h, RunContext c) {
    h.open = false;
    c.track('switchring_spawned', {'design': storageName(designOf(h))});
  }

  /// PRD-2.2 §15 the switch was created one gap before its ring (the plan
  /// ahead): the ring takes it now.
  @override
  void linkAttached(Hoop h, Pickup p, RunContext c) {
    if (p is! SwitchPickup) return;
    p.ring = h;
    stateOf(h)?.pickup = p;
  }

  @override
  void buildVisual(Hoop h, RunContext c) {
    final art = SwitchDesignArt.of(designOf(h));
    final state = SwitchRingState(h, c, art);
    _states[h] = state;
    h.add(state);
    h.add(state.backPool);
    h.front.add(state.frontPool);
    h.paintBack = (canvas) {
      if (h.look.missed) {
        NormalHoopKind.paintRings(canvas, h, '', front: false);
        return;
      }
      art.paintBack(canvas, state);
    };
    h.front.paintFront = (canvas) {
      if (h.look.missed) {
        NormalHoopKind.paintRings(canvas, h, '', front: true);
        return;
      }
      art.paintFront(canvas, state);
    };
  }

  @override
  PlaneVerdict onPlane(Hoop h, int ring, RunContext c) {
    if (h.open) return PlaneVerdict.pass;
    _states[h]?.crash();
    return PlaneVerdict.mistake;
  }

  @override
  ThemedDeath? themedDeath(Hoop h) =>
      ThemedDeath('switch_${storageName(designOf(h))}');

  @override
  void onPass(Hoop h, PassInfo p, RunContext c) {
    c.track('switchring_passed', {'design': storageName(designOf(h))});
  }

  /// §7 the autopilot steers to the switch first (while it is still ahead
  /// and the ring closed), then the ring.
  @override
  AutopilotTarget autopilotTarget(Hoop h, RunState s, double birdY) {
    final st = _states[h];
    final p = st?.pickup;
    final y = h.position.y;
    if (!h.open && p != null && !p.collected && !p.escaped) {
      return AutopilotTarget(y, preTarget: p.position.clone());
    }
    return AutopilotTarget(y);
  }
}

/// A short-lived drawn bit (flying chain link, falling padlock, bow,
/// ribbon) in ring-local coordinates.
class SwitchBit {
  SwitchBit({
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.rot = 0,
    this.spin = 0,
    this.gravity = 0,
    required this.life,
    required this.draw,
    this.fade = true,
  });
  double x, y, vx, vy, rot, spin, gravity, t = 0;
  final double life;
  final bool fade;
  final void Function(Canvas canvas, SwitchBit b) draw;
  double get alpha => fade ? (1 - t / life).clamp(0.0, 1.0) : 1;
}

/// Per-ring state (world time): the open timeline clock ([hitT], −1 until
/// the switch is touched), the crash clock, design scratch values, the
/// particle pools and the drawn bits, and the switch pickup it belongs to.
class SwitchRingState extends Component {
  SwitchRingState(this.hoop, this.c, this.art) : seed = c.cosmetic.nextInt(100);

  final Hoop hoop;
  final RunContext c;
  final SwitchDesignArt art;
  final int seed;

  SwitchPickup? pickup;

  /// Ring clock (s since spawn).
  double t = 0;

  /// Seconds since the switch was touched (−1 = closed).
  double hitT = -1;

  /// Seconds since the crash (−1 = none).
  double crashT = -1;

  /// The switch's position relative to the ring at the touch (key /
  /// scissors flights start there).
  Offset switchFrom = const Offset(-150, 0);

  final Map<String, double> fx = {};
  final List<SwitchBit> bits = [];
  final ParticlePool backPool = ParticlePool(capacity: 30);
  final ParticlePool frontPool = ParticlePool(capacity: 60);

  double get ry => RingPainter.ryFor(hoop.opening);

  /// The open animation has reached [at] (s after the touch).
  bool after(double at) => hitT >= at;

  /// One-shot edge: true the first time it is called with [key].
  bool once(String key) {
    if (fx.containsKey('once:$key')) return false;
    fx['once:$key'] = 1;
    return true;
  }

  double get(String k) => fx[k] ?? 0;

  /// The bird centre in ring-local coordinates (eyes, near effects).
  Offset? get birdLocal {
    final b = c.run.birdTrackPosition();
    if (b == null) return null;
    return Offset(b.x - hoop.position.x, b.y - hoop.position.y);
  }

  /// §3.20 the switch was touched (or a comet arrived): the ring is open in
  /// the logic at once; the design animates it.
  void open({bool byComet = false}) {
    if (hitT >= 0) return;
    hoop.open = true;
    hitT = 0;
    final p = pickup;
    if (p != null) {
      switchFrom = Offset(
        p.position.x - hoop.position.x,
        p.position.y - hoop.position.y,
      );
    }
    art.onTouch(this);
  }

  /// §3.20 the closed ring was reached.
  void crash() {
    if (crashT >= 0) return;
    crashT = 0;
    c.sfx(SwitchConfig.crashSound(art.design));
    art.onCrash(this);
  }

  @override
  void update(double dt) {
    t += dt;
    // §3.20 / §3.0.3 a closed ring already on screen when the comet arrives
    // opens by itself.
    if (!hoop.open && c.s.ride?.kind == RideKind.comet && hitT < 0) {
      open(byComet: true);
    }
    if (hitT >= 0) {
      hitT += dt;
      final d = art.design;
      if (hitT >= SwitchConfig.openSoundAt(d) && once('openSound')) {
        c.sfx(SwitchConfig.openSound(d));
      }
      final word = SwitchConfig.openWord(d);
      if (word != null && hitT >= SwitchConfig.openAt(d) && once('word')) {
        c.layers.fx.add(
          RisingWord(
            word.$1,
            at: Vector2(hoop.position.x, hoop.position.y - ry - 30),
            fontSize: SwitchConfig.wordSize,
            fill: word.$2,
            outline: const Color(0xFFFFFFFF),
            outlineWidth: SwitchConfig.wordOutline,
            life: SwitchConfig.wordLife,
          ),
        );
      }
    }
    if (crashT >= 0) crashT += dt;
    art.tick(this, dt);
    for (var i = bits.length - 1; i >= 0; i--) {
      final b = bits[i];
      b.t += dt;
      if (b.t >= b.life) {
        bits.removeAt(i);
        continue;
      }
      b.vy += b.gravity * dt;
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.rot += b.spin * dt;
    }
  }

  /// Paints the flying bits (front layer).
  void paintBits(Canvas canvas) {
    for (final b in bits) {
      canvas.save();
      canvas.translate(b.x, b.y);
      canvas.rotate(b.rot);
      b.draw(canvas, b);
      canvas.restore();
    }
  }

  /// A burst of squares into [pool] (the mocks' `burst`).
  void burst(
    ParticlePool pool,
    Offset at,
    int n,
    List<Color> cols, {
    double speed = 170,
    double sMin = 5,
    double sMax = 9,
    double gravity = 0,
    bool up = false,
    double? life,
  }) {
    final r = c.cosmetic;
    for (var i = 0; i < n; i++) {
      final a = up
          ? -math.pi / 2 + (r.nextDouble() - .5) * 2.2
          : r.nextDouble() * math.pi * 2;
      final v = speed * (.4 + r.nextDouble() * .8);
      pool.spawn(
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * v,
        vy: math.sin(a) * v,
        w: sMin + r.nextDouble() * (sMax - sMin),
        color: cols[i % cols.length],
        life: life ?? (.55 + r.nextDouble() * .35),
        gravity: gravity,
        rot: r.nextDouble() * 6,
        spin: (r.nextDouble() - .5) * 12,
      );
    }
  }
}

/// The switch pickup kind (PRD-2 §3.20): the director's switch
/// `GapItemPlan` (attached to its switch ring's slot) becomes a
/// [SwitchPickup] linked to that ring.
class SwitchPickupKind extends PickupKind {
  @override
  ElementId get element => ElementId.switchRing;

  @override
  Pickup build(GapItemPlan p, RunContext c) {
    Hoop? ring;
    for (final h in c.run.spawner.hoops.toList().reversed) {
      if (h.plan.kind == HoopKindId.switchRing && h.plan.attached.contains(p)) {
        ring = h;
        break;
      }
    }
    final design = p.extra is SwitchDesign
        ? p.extra! as SwitchDesign
        : (ring == null
              ? SwitchDesign.lockdown
              : SwitchRingKind.designOf(ring));
    // PRD-2.2 §15 planned one gap ahead: the ring is not spawned yet (it is
    // linked when it is, `SwitchRingKind.linkAttached`); its plan places
    // the Power Iris cable meanwhile.
    final ahead = c.run.spawner.plannedAhead;
    final pickup = SwitchPickup(p, design, ring)
      ..ringPlan = ahead != null && ahead.attached.contains(p) ? ahead : null;
    final st = ring == null ? null : SwitchRingKind.stateOf(ring);
    st?.pickup = pickup;
    return pickup;
  }
}

/// §5.19 the switch (key / button / lever / alarm clock / scissors,
/// ≈ 40–46 pt): bobs ±4 pt at 0.6 Hz with a soft halo in the design's
/// colour and a white / pale-gold twinkle every ≈ 0.28 s. Hit radius 18 pt
/// (§3.0.3). A touch: the shared touch fx (white flash, gold ring, 9
/// squares), "+1 ●", +1 coin, the design's touch sound, the ring opens.
/// The Laser button and the Iris lever stay to show ON (0.3 s / 1.1 s),
/// then fade out (0.35 s, ×1.4); the key and the scissors fly to the ring
/// (drawn by the ring), the alarm clock fades at once.
class SwitchPickup extends Pickup {
  SwitchPickup(GapItemPlan p, this.design, this.ring)
    : super(
        id: ElementId.switchRing,
        hitRadius: PickupRadii.switchPickup,
        plan: p,
        position: Vector2(p.trackX, p.y ?? 0),
        size: Vector2.all(46),
      ) {
    art = SwitchDesignArt.of(design);
  }

  final SwitchDesign design;

  /// The switch ring (PRD-2.2 §15: null until its hoop spawns).
  Hoop? ring;

  /// PRD-2.2 §15 the ring's plan while its hoop is not spawned yet.
  SlotPlan? ringPlan;
  late final SwitchDesignArt art;

  static final _touch = PickupTouchFx.newPool();
  static final _popups = CoinPopup.newPool();

  /// Seconds alive / since the touch (−1 = untouched).
  double t = 0, touchT = -1;

  /// ON state 0..1 (button pressed, lever up).
  double get on => touchT < 0 ? 0 : (touchT / .12).clamp(0.0, 1.0);

  final ParticlePool _twinkles = ParticlePool(capacity: 10);
  late final math.Random _r = math.Random(plan.hashCode);
  double _twinkleAcc = 0;

  SwitchRingState? get ringState =>
      ring == null ? null : SwitchRingKind.stateOf(ring!);

  /// Hidden after the touch (the key / scissors are drawn by the ring).
  bool get _flies =>
      design == SwitchDesign.lockdown || design == SwitchDesign.giftWrap;

  @override
  Future<void> onLoad() async {
    add(_twinkles);
  }

  @override
  void update(double dt) {
    super.update(dt);
    t += dt;
    if (touchT >= 0) {
      touchT += dt;
      final end = SwitchConfig.stay(design) + SwitchConfig.fade;
      if (touchT >= end) removeFromParent();
      return;
    }
    _twinkleAcc += dt;
    if (_twinkleAcc >= SwitchConfig.twinkleEvery) {
      _twinkleAcc = 0;
      final r = _r;
      final a = r.nextDouble() * math.pi * 2;
      _twinkles.spawn(
        shape: ParticleShape.twinkle,
        x: size.x / 2 + math.cos(a) * 24,
        y: size.y / 2 + math.sin(a) * 24,
        w: 7,
        color: r.nextBool() ? const Color(0xFFFFFFFF) : const Color(0xFFFFE6A8),
        life: .6,
      );
    }
  }

  @override
  void onCollect(RunContext c) {
    touchT = 0;
    final at = Offset(position.x, position.y);
    c.layers.fx.add(
      _touch.obtain().play(
        at,
        PickupTouchSpec.switchTouch,
        pool: c.run.particles,
        random: c.cosmetic,
      ),
    );
    // PRD-2.3 §14.2 the switch pays 0 by default: no coin popup then.
    final coins = SwitchConfig.coins;
    if (coins > 0) c.layers.fx.add(_popups.obtain().play(at, coins));
    c.earn(coins, CoinSource.switchRing);
    c.sfx(SwitchConfig.touchSound(design));
    c.track('switchring_switch_taken', {
      'design': SwitchRingKind.storageName(design),
    });
    ringState?.open();
    if (_flies) removeFromParent();
  }

  /// Bob offset (pt) now.
  double get bob =>
      SwitchConfig.bob * math.sin(t * SwitchConfig.bobHz * 2 * math.pi);

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    art.paintUnder(canvas, this);
    var alpha = 1.0, scale = 1.0;
    if (touchT >= 0) {
      final f = ((touchT - SwitchConfig.stay(design)) / SwitchConfig.fade)
          .clamp(0.0, 1.0);
      alpha = 1 - f;
      scale = 1 + (SwitchConfig.fadeScale - 1) * f;
    }
    canvas.translate(0, touchT >= 0 ? 0 : bob);
    if (alpha < 1) {
      canvas.saveLayer(null, layerPaint(alpha));
    }
    canvas.scale(scale);
    art.paintSwitch(canvas, this);
    if (alpha < 1) canvas.restore();
    canvas.restore();
  }
}

/// The switch rings' run-side reactions (PRD-2 §3.20, §5.19, §6): the red
/// crash banner with the design's word on a death (LOCKED! / ZAPPED! /
/// SHUT! / HMPF! / WRAPPED!; in a world banner host so the HUD's death
/// clear keeps it) and `switchring_closed_hit` {design, used}.
class SwitchRingFeature extends RunFeature {
  RunContext? _c;

  @override
  void attach(RunContext c) {
    _c = c;
    c.events
      ..on<RunDied>(_onDied)
      ..on<MistakeSaved>(_onSaved);
  }

  static SwitchDesign? _designOf(Mistake m) {
    final h = m.hoop;
    if (m.cause != MistakeCause.closedSwitch ||
        h == null ||
        h.kind is! SwitchRingKind) {
      return null;
    }
    return SwitchRingKind.designOf(h);
  }

  void _onSaved(MistakeSaved e) {
    final d = _designOf(e.mistake);
    if (d == null) return;
    _c?.track('switchring_closed_hit', {
      'design': SwitchRingKind.storageName(d),
      'used': e.by,
    });
  }

  void _onDied(RunDied e) {
    final c = _c;
    final d = _designOf(e.mistake);
    if (c == null || d == null) return;
    c.track('switchring_closed_hit', {
      'design': SwitchRingKind.storageName(d),
      'used': 'none',
    });
    // PRD-2.2 §12.2: the run's banner host (in the banner layer, behind the
    // gameplay); the crash word is shown on the death itself, so it survives
    // the death's clear.
    RunHud.ensureFor(c.run).banners.show(
      ElementBanner(SwitchConfig.crashWord(d), color: SwitchConfig.crashRed)
        ..survivesDeath = true,
    );
  }

  @override
  void detach() {
    final c = _c;
    if (c != null) {
      c.events
        ..off<RunDied>(_onDied)
        ..off<MistakeSaved>(_onSaved);
    }
    _c = null;
  }
}
