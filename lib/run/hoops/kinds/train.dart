import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../game/sound.dart';
import '../../../menu/wallet.dart';
import '../../config/special_hoops_config.dart';
import '../../effects/dashed_path.dart';
import '../../hud/banners.dart';
import '../../hud/run_hud.dart';
import '../../run_context.dart';
import '../hoop.dart';
import '../../director/plans.dart';
import '../hoop_kind.dart';
import '../ring_painter.dart';
import 'normal.dart';

/// One ring of a Ring Train after the first: the train's [spec] and the
/// ring number [k] (1, 2). The first ring's plan carries the director's
/// [TrainSpec] itself (k 0).
class TrainRing {
  const TrainRing(this.spec, this.k);
  final TrainSpec spec;
  final int k;

  @override
  bool operator ==(Object other) =>
      other is TrainRing && other.spec == spec && other.k == k;

  @override
  int get hashCode => Object.hash(spec, k);

  @override
  String toString() => 'TrainRing($k)';
}

/// Ring Train (PRD-2 §3.22, §5.21; lab mock `?only=train`): three normal
/// rings **56 pt apart**, each **±16 pt** further in one steady direction
/// (the director's [TrainSpec]), linked by a dotted track — **one slot**:
/// the director counts it once and places the next hoop the usual spacing
/// after the third ring.
///
/// - **Each ring is a normal hoop** (its own [Hoop]: pass test, rim bounce,
///   +1 score, coins, streak, tier look); missing any of them is a miss.
/// - **Combo:** three progress dots above the train fill gold as rings are
///   passed and passed rings turn gold. All three passed → **+3 coins**
///   ([CoinSource.train]), banner **TRAIN ×3** "all three rings · +3
///   coins", the rising finish and `train_completed`. A rim touch still
///   counts; a miss (saved by a life / shield) breaks the combo (Q61).
/// - **Sounds:** one note per ring (C5 / E5 / G5), the finish (high C,
///   C-major chord, rising whistle).
/// - The score points of train rings carry the versus `train` flag (the
///   0.9 s gap check skips them; WP-3c region in `scoring.dart`).
class TrainHoopKind extends HoopKind {
  @override
  HoopKindId get id => HoopKindId.train;

  @override
  bool get usesTierLook => true;

  static final Expando<TrainGroup> _groups = Expando('train');

  /// The train [h] belongs to (null for other kinds).
  static TrainGroup? groupOf(Hoop h) => _groups[h];

  /// The ring number of [h] in its train (0..2).
  static int ringOf(SlotPlan p) => switch (p.extra) {
    TrainRing(:final k) => k,
    _ => 0,
  };

  static TrainSpec? _specOf(SlotPlan p) => switch (p.extra) {
    TrainSpec s => s,
    TrainRing(:final spec) => spec,
    _ => null,
  };

  /// §3.22 rings 2 and 3: [TrainSpec.dx] further right and [TrainSpec.dy]
  /// further in [TrainSpec.dir] each.
  @override
  List<SlotPlan> extraHoops(SlotPlan p) {
    final spec = p.extra;
    if (spec is! TrainSpec) return const [];
    return [
      for (var k = 1; k < TrainConfig.rings; k++)
        SlotPlan(
          index: p.index,
          kind: p.kind,
          element: p.element,
          trackX: p.trackX + k * spec.dx,
          centreY: p.centreY + k * spec.dy * spec.dir,
          opening: p.opening,
          advance: p.advance,
          extra: TrainRing(spec, k),
          forced: p.forced,
          duringRide: p.duringRide,
        ),
    ];
  }

  @override
  void buildVisual(Hoop h, RunContext c) {
    final spec = _specOf(h.plan);
    final k = ringOf(h.plan);
    final group = spec == null ? TrainGroup() : TrainGroup.forSpec(spec);
    group.hoops.add(h);
    _groups[h] = group;
    if (k == 0) h.add(_TrackClock(group));
    final skin = c.game.menu.items.look.hoop;
    void rings(Canvas canvas, {required bool front}) {
      final passed = group.passedRings.contains(k) && !h.look.missed;
      if (!passed) {
        NormalHoopKind.paintRings(
          canvas,
          h,
          skin,
          front: front,
          t: c.s.runClock,
        );
        return;
      }
      // §5.21 passed rings turn gold (bright gold stays at tier 3+).
      final colors = h.look.colors == RingColors.brightGold
          ? RingColors.brightGold
          : RingColors.gold;
      RingPainter.paintHalf(
        canvas,
        centre: Offset(0, h.rings.first),
        opening: h.opening,
        front: front,
        colors: colors,
      );
    }

    h.paintBack = (canvas) {
      if (k == 0) paintTrack(canvas, h, group, c.game.foregroundColor);
      rings(canvas, front: false);
    };
    h.front.paintFront = (canvas) => rings(canvas, front: true);
  }

  /// §5.21 the dotted track (stage foreground 50 %, 2.5 pt, 6/6, moving
  /// toward the bird at 40 pt/s) from 34 pt before the first ring through
  /// every ring centre to 34 pt after the last, and the three progress dots
  /// (6.5 pt, 20 pt above the highest ring) — grey 40 % → gold. Drawn by
  /// the first ring, in its local coordinates.
  static void paintTrack(Canvas canvas, Hoop first, TrainGroup g, Color fg) {
    final pts = [
      for (final h in g.hoops)
        Offset(
          h.position.x - first.position.x,
          h.position.y - first.position.y,
        ),
    ];
    if (pts.isEmpty) return;
    final path = Path()
      ..moveTo(pts.first.dx - TrainConfig.trackOverhang, pts.first.dy);
    for (final p in pts) {
      path.lineTo(p.dx, p.dy);
    }
    path.lineTo(pts.last.dx + TrainConfig.trackOverhang, pts.last.dy);
    DashedPathPainter.stroke(
      canvas,
      path,
      color: fg.withValues(alpha: fg.a * TrainConfig.trackAlpha),
      phase: g.trackPhase,
    );
    var top = double.infinity;
    for (final h in g.hoops) {
      top = math.min(
        top,
        h.position.y - first.position.y - RingPainter.ryFor(h.opening),
      );
    }
    final y = top - TrainConfig.dotAbove;
    final paint = Paint();
    for (var j = 0; j < TrainConfig.rings; j++) {
      paint.color = j < g.passedRings.length
          ? TrainConfig.gold
          : TrainConfig.dotEmpty;
      canvas.drawCircle(
        Offset(j * (g.spec?.dx ?? 56), y),
        TrainConfig.dotSize / 2,
        paint,
      );
    }
  }

  @override
  void onPass(Hoop h, PassInfo p, RunContext c) {
    final g = _groups[h];
    if (g == null) return;
    final k = ringOf(h.plan);
    g.passedRings.add(k);
    final n = g.passedRings.length;
    c.sfx(
      const [Sfx.trainNote1, Sfx.trainNote2, Sfx.trainNote3][math.min(n, 3) -
          1],
    );
    final bird = c.game.runBirdPosition;
    if (bird != null) {
      final r = c.cosmetic;
      final at = c.geo.toTrack(bird);
      for (var i = 0; i < 8; i++) {
        final a = r.nextDouble() * 2 * math.pi;
        final v = 120 * (.5 + r.nextDouble() * .7);
        c.run.particles.spawn(
          x: at.x,
          y: at.y,
          vx: math.cos(a) * v,
          vy: math.sin(a) * v,
          w: 4 + r.nextDouble() * 3,
          color: i.isEven ? TrainConfig.gold : const Color(0xFFFFFFFF),
          life: .4 + r.nextDouble() * .2,
          damp: 2.4,
        );
      }
    }
    if (k == TrainConfig.rings - 1 && !g.broken && n == TrainConfig.rings) {
      g.completed = true;
      c.earn(TrainConfig.comboCoins, CoinSource.train);
      c.sfx(Sfx.trainFinish);
      RunHud.ensureFor(c.run).banners.show(
        ElementBanner(
          TrainConfig.bannerText,
          color: TrainConfig.gold,
          subtitle: TrainConfig.bannerSub,
        ),
      );
      c.track('train_completed');
    }
  }

  @override
  void onMiss(Hoop h, RunContext c) => _groups[h]?.broken = true;
}

/// The shared state of one train's three hoops.
class TrainGroup {
  TrainGroup({this.spec});

  static final Expando<TrainGroup> _bySpec = Expando('trainGroup');

  /// The group of the train planned with [spec] (the three plans share the
  /// director's [TrainSpec] instance).
  factory TrainGroup.forSpec(TrainSpec spec) =>
      _bySpec[spec] ??= TrainGroup(spec: spec);

  final TrainSpec? spec;

  /// The hoops in ring order.
  final List<Hoop> hoops = [];

  /// Ring numbers passed so far.
  final Set<int> passedRings = {};

  /// A ring was missed: no combo.
  bool broken = false;

  /// All three passed (the combo was paid).
  bool completed = false;

  /// The track's dash phase (pt).
  double trackPhase = 0;
}

/// Moves the track dashes toward the bird (world time).
class _TrackClock extends Component {
  _TrackClock(this.g);
  final TrainGroup g;

  @override
  void update(double dt) {
    g.trackPhase = (g.trackPhase + TrainConfig.trackSpeed * dt) % 1200;
  }
}
