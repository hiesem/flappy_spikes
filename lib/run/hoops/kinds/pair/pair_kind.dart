import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../../game/sound.dart';
import '../../../../menu/wallet.dart';
import '../../../../versus/timeline.dart' show PointFlags;
import '../../../config/pair_config.dart';
import '../../../config/run_config.dart';
import '../../../director/plans.dart';
import '../../../effects/coin_icon.dart';
import '../../../effects/particle_pool.dart';
import '../../../effects/rising_word.dart';
import '../../../effects/shock_ring.dart';
import '../../../elements.dart';
import '../../../run_context.dart';
import '../../../run_events.dart';
import '../../../run_layers.dart';
import '../../hoop.dart';
import '../../hoop_kind.dart';
import '../../ring_painter.dart';
import '../normal.dart';
import '../ring_arcs.dart';
import '../switch/switch_kind.dart' show SwitchBit;
import 'gift_box.dart';
import 'gift_tag.dart';

/// Pairs of two powerup rings, design "Gift Box" (PRD-2 §3.21, §5.20):
/// two rings stacked at the same x ([Hoop.rings] = [−o/2, +o/2], o = 230 ×
/// viewHeight / 711; the director places and fits them), each holding a
/// gift box with a different reward ([PairRewards] in `SlotPlan.extra`:
/// [PairRewards.top] on ring 0, [PairRewards.bottom] on ring 1).
///
/// A pair is **one hoop**: flying through one ring scores like a normal
/// hoop (+1, coins, streak; perfect = no rim contact) and opens that ring's
/// box; flying through neither is a miss (`MistakeCause.pairMissed`, the
/// generic miss path). It resolves once at the plane: the other ring, box
/// and tag shrink to 60 % and fade out in 0.45 s.
///
/// Gifts: SHIELD arms the shield (`RunState.shield`; the circle observes
/// it); COMET starts the boost (`PickupCollected(comet, null)`, WP-3a's
/// contract); +10 COINS (`CoinSource.pair`, coins spray from the bird);
/// +5 SCORE (five points flagged `gift`); FEVER: the streak is set to at
/// least ×5 ([StreakAtLeast]) and the bird catches fire ([FeverIgnite]) —
/// on any pass through the ring (Q59).
class PairHoopKind extends HoopKind {
  @override
  HoopKindId get id => HoopKindId.pair;

  @override
  bool get usesTierLook => false;

  static final Expando<PairState> _states = Expando('pair');

  static PairState? stateOf(Hoop h) => _states[h];

  static PairRewards rewardsOf(Hoop h) {
    final e = h.plan.extra;
    return e is PairRewards
        ? e
        : const PairRewards(PairReward.coins, PairReward.score);
  }

  static PairReward rewardOf(Hoop h, int ring) {
    final r = rewardsOf(h);
    return ring == 0 ? r.top : r.bottom;
  }

  @override
  void onSpawn(Hoop h, RunContext c) {
    final r = rewardsOf(h);
    c.track('pair_spawned', {
      'reward_top': r.top.name,
      'reward_bottom': r.bottom.name,
    });
  }

  @override
  void buildVisual(Hoop h, RunContext c) {
    final state = PairState(h, c);
    _states[h] = state;
    h.add(state);
    h.front.add(state.pool);
    void back(Canvas canvas) {
      for (var i = 0; i < h.rings.length; i++) {
        state.withRing(canvas, i, () => state.paintBack(canvas, i));
      }
    }

    void front(Canvas canvas) {
      for (var i = 0; i < h.rings.length; i++) {
        state.withRing(canvas, i, () => state.paintFront(canvas, i));
      }
      state.paintBits(canvas);
    }

    h.paintBack = (canvas) {
      if (h.look.missed) {
        NormalHoopKind.paintRings(canvas, h, '', front: false);
        return;
      }
      if (h.rewardStripped) {
        // PRD-2.2 §27.3 the gift boxes fade, the rings stay plain.
        NormalHoopKind.paintStripped(
          canvas,
          h,
          c,
          front: false,
          reward: () => back(canvas),
        );
        return;
      }
      back(canvas);
    };
    h.front.paintFront = (canvas) {
      if (h.look.missed) {
        NormalHoopKind.paintRings(canvas, h, '', front: true);
        return;
      }
      if (h.rewardStripped) {
        NormalHoopKind.paintStripped(
          canvas,
          h,
          c,
          front: true,
          reward: () => front(canvas),
        );
        return;
      }
      front(canvas);
    };
  }

  /// §7 / §3.0.3 the comet takes the ring nearest its line.
  static int nearestRing(Hoop h, double birdY) {
    var best = 0;
    var bd = double.infinity;
    for (var i = 0; i < h.rings.length; i++) {
      final d = (h.position.y + h.rings[i] - birdY).abs();
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  @override
  void onPass(Hoop h, PassInfo p, RunContext c) {
    // PRD-2.2 §27.3 an activity stripped the gifts: a normal pass.
    if (h.rewardStripped) return;
    var ring = p.ring.clamp(0, h.rings.length - 1);
    if (p.duringRide) {
      final b = c.run.birdTrackPosition();
      if (b != null) ring = nearestRing(h, b.y);
    }
    final take = rewardOf(h, ring);
    final skip = rewardOf(h, 1 - ring);
    _states[h]?.pick(ring);
    c.track('pair_picked', {
      'reward': take.name,
      'skipped_reward': skip.name,
      'ring': ring == 0 ? 'top' : 'bottom',
      'perfect': p.perfect ? 1 : 0,
    });
    applyGift(take, c);
  }

  /// §3.21 what a gift does (also the test seam).
  static void applyGift(PairReward r, RunContext c) {
    c.sfx(PairConfig.style(r).sound);
    switch (r) {
      case PairReward.shield:
        c.s.shield = true;
      case PairReward.comet:
        c.emit(const PickupCollected(ElementId.comet, null));
      case PairReward.coins:
        c.earn(PairConfig.coins, CoinSource.pair);
        _coinSpray(c);
      case PairReward.score:
        c.addScore(PairConfig.score, flags: PointFlags.gift);
      case PairReward.fever:
        c.emit(const StreakAtLeast(PairConfig.feverStreak));
        c.emit(const FeverIgnite('pair'));
    }
  }

  /// §5.20 +10 COINS: coins spray from the bird — master #14's coin
  /// sprite (§3.0.9 #14, S6-43), never a code-drawn disc.
  static void _coinSpray(RunContext c) {
    final images = c.game.images;
    final pool = c.run.particles;
    if (pool.coinImage == null && images.containsKey(CoinIcon.asset)) {
      pool.coinImage = images.fromCache(CoinIcon.asset);
    }
    final b =
        c.run.birdTrackPosition() ??
        Vector2(c.s.camX + RunConfig.birdX, c.viewHeight / 2);
    final r = c.cosmetic;
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + (r.nextDouble() - .5) * 1.6;
      final s = 150 + r.nextDouble() * 120;
      c.run.particles.spawn(
        shape: ParticleShape.coin,
        x: b.x,
        y: b.y,
        vx: math.cos(a) * s,
        vy: math.sin(a) * s,
        w: 14,
        color: const Color(0xFFFFB529),
        life: .9,
        gravity: 500,
        fadePow: 2,
      );
    }
  }

  @override
  void onMiss(Hoop h, RunContext c) {
    if (!h.rewardStripped) c.track('pair_missed');
  }
}

/// Per-pair state (world time): the clock, each box's phase, the pick, the
/// fade of the skipped ring, the pick bits (lid, icon) and confetti.
class PairState extends Component {
  PairState(this.hoop, this.c)
    : seeds = [c.cosmetic.nextDouble() * 9, c.cosmetic.nextDouble() * 9];

  final Hoop hoop;
  final RunContext c;
  final List<double> seeds;

  double t = 0;

  /// The picked ring (−1 = none yet) and seconds since the pick.
  int picked = -1;
  double pickT = -1;

  final ParticlePool pool = ParticlePool(capacity: 40);
  final List<SwitchBit> _bits = [];

  double get ry => RingPainter.ryFor(hoop.opening);

  /// The skipped ring's draw scale / opacity (§5.20: 60 %, 0.45 s).
  (double, double) fadeOf(int ring) {
    if (picked < 0 || ring == picked) return (1, 1);
    final u = (pickT / PairConfig.skipFade).clamp(0.0, 1.0);
    return (1 - (1 - PairConfig.skipScale) * u, 1 - u);
  }

  void withRing(Canvas canvas, int i, void Function() draw) {
    final (scale, alpha) = fadeOf(i);
    if (alpha <= 0) return;
    canvas.save();
    canvas.translate(0, hoop.rings[i]);
    if (scale != 1) canvas.scale(scale);
    if (alpha < 1) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    }
    draw();
    if (alpha < 1) canvas.restore();
    canvas.restore();
  }

  /// §5.20 back half in the dark shade, then the box (behind the bird).
  void paintBack(Canvas canvas, int i) {
    final r = PairHoopKind.rewardOf(hoop, i);
    final st = PairConfig.style(r);
    RingPainter.paintHalf(
      canvas,
      centre: Offset.zero,
      opening: hoop.opening,
      front: false,
      colors: RingColors(st.main, st.dark),
      strokeWidth: PairConfig.ringStroke,
    );
    if (picked == i) return; // opened: the lid and icon flew out
    final bob = math.sin(t * 3 + seeds[i]) * PairConfig.boxBob;
    final tilt = math.sin(t * 1.7 + seeds[i]) * PairConfig.boxTilt;
    canvas.save();
    canvas.translate(0, bob);
    canvas.rotate(tilt);
    GiftBox.paint(canvas, r);
    canvas.restore();
  }

  /// §5.20 front half in the main colour + the white inner line; the tag.
  void paintFront(Canvas canvas, int i) {
    final r = PairHoopKind.rewardOf(hoop, i);
    final st = PairConfig.style(r);
    RingPainter.paintHalf(
      canvas,
      centre: Offset.zero,
      opening: hoop.opening,
      front: true,
      colors: RingColors(st.main, st.dark),
      strokeWidth: PairConfig.ringStroke,
    );
    RingArcs.stroke(
      canvas,
      RingArcs.half(ry - 1, front: true, x: RingArcs.rx - 1),
      const Color(0xFFFFFFFF),
      PairConfig.innerLine,
      cap: StrokeCap.butt,
    );
    final above = i == 0;
    GiftTag.paint(
      canvas,
      r,
      Offset(0, above ? -ry : ry),
      above: above,
      sway: math.sin(t * 2 + seeds[i]) * PairConfig.tagSway,
    );
  }

  void paintBits(Canvas canvas) {
    for (final b in _bits) {
      canvas.save();
      canvas.translate(b.x, b.y);
      canvas.rotate(b.rot);
      b.draw(canvas, b);
      canvas.restore();
    }
  }

  /// §5.20 pick feedback: the lid flies off, the icon jumps out, ≈ 22
  /// confetti squares and strips burst upward, a ring of light in the
  /// reward colour pulses out, the reward word pops up next to the bird;
  /// the box opens with a pop and the skipped ring fades with a grey puff
  /// and the soft "skipped" blip.
  void pick(int ring) {
    if (picked >= 0) return;
    picked = ring;
    pickT = 0;
    final r = PairHoopKind.rewardOf(hoop, ring);
    final st = PairConfig.style(r);
    final y = hoop.rings[ring];
    c.sfx(Sfx.pairBoxOpen);
    c.sfx(Sfx.pairSkipped);
    final rnd = c.cosmetic;
    _bits.add(
      SwitchBit(
        x: 0,
        y: y - 24,
        vx: -30,
        vy: -260,
        spin: -8,
        gravity: 700,
        life: .9,
        draw: (canvas, b) {
          canvas.save();
          canvas.scale(PairConfig.boxScale);
          canvas.translate(0, PairConfig.boxHalf + 2);
          GiftBox.paintLid(canvas, r);
          canvas.restore();
        },
      ),
    );
    _bits.add(
      SwitchBit(
        x: 0,
        y: y,
        vx: 30,
        vy: -120,
        life: 1,
        draw: (canvas, b) {
          canvas.saveLayer(
            null,
            Paint()..color = Color.fromRGBO(0, 0, 0, b.alpha),
          );
          GiftBox.icon(canvas, r, Offset.zero, 13);
          canvas.restore();
        },
      ),
    );
    final cols = [st.main, st.light, const Color(0xFFFFFFFF), st.dark];
    for (var i = 0; i < PairConfig.confetti; i++) {
      final a = -math.pi / 2 + (rnd.nextDouble() - .5) * 2.4;
      final s = 120 + rnd.nextDouble() * 180;
      final w = 4 + rnd.nextDouble() * 3;
      pool.spawn(
        x: 0,
        y: y - 10,
        vx: math.cos(a) * s,
        vy: math.sin(a) * s,
        w: w,
        h: i.isOdd ? w * 2.2 : w,
        color: cols[i % cols.length],
        life: .9,
        gravity: 500,
        rot: rnd.nextDouble() * 6,
        spin: (rnd.nextDouble() - .5) * 14,
      );
    }
    final at = hoop.frame().toWorld(Vector2(0, y));
    c.layers.fx.add(
      ShockRing().play(
        Offset(at.x, at.y),
        rx: 20,
        ry: ry,
        color: st.main,
        length: .6,
        scaleFrom: 1,
        scaleTo: 1,
        grow: 70,
        strokeFrom: 6,
        strokeTo: 1,
      ),
    );
    // The reward word next to the bird (screen space, floats up).
    final bird = c.game.runBirdPosition;
    final birdY = bird?.y ?? at.y - c.s.camY;
    // Next to the bird, above it — below it when that would sit in the
    // streak banner band (y ≈ 190, master #7) that shows on the same pass.
    var wordY = birdY - 34;
    if (wordY > PairConfig.bannerBandTop &&
        wordY < PairConfig.bannerBandBottom) {
      wordY = birdY + 46;
    }
    c.game.world.add(
      RisingWord(
        st.word,
        at: Vector2(RunConfig.birdX + 110, wordY),
        fontSize: st.word.length > 8 ? 24 : 30,
        fill: const Color(0xFFFFFFFF),
        fillBottom: st.light,
        outline: st.dark,
        outlineWidth: 7,
        life: PairConfig.wordLife,
        rise: 40,
        tilt: -.05,
        priority: RunLayer.fx + 1,
      ),
    );
    // The skipped ring's grey puff.
    final o = hoop.rings[1 - ring];
    for (var i = 0; i < 10; i++) {
      pool.spawn(
        shape: ParticleShape.circle,
        x: (rnd.nextDouble() - .5) * 20,
        y: o + (rnd.nextDouble() - .5) * ry * 1.5,
        vx: (rnd.nextDouble() - .5) * 40,
        vy: -20 - rnd.nextDouble() * 30,
        w: 10,
        color: PairConfig.puff,
        life: .7,
        scale1: 4,
      );
    }
  }

  @override
  void update(double dt) {
    t += dt;
    if (pickT >= 0) pickT += dt;
    for (var i = _bits.length - 1; i >= 0; i--) {
      final b = _bits[i];
      b.t += dt;
      if (b.t >= b.life) {
        _bits.removeAt(i);
        continue;
      }
      b.vy += b.gravity * dt;
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.rot += b.spin * dt;
    }
  }
}
