import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../../game/sound.dart';
import '../../../menu/wallet.dart';
import '../../config/special_hoops_config.dart';
import '../../effects/dashed_path.dart';
import '../../hud/banners.dart';
import '../../hud/run_hud.dart';
import '../../physics/hoop_frame.dart';
import '../../run_context.dart';
import '../hoop.dart';
import '../hoop_kind.dart';
import 'normal.dart';

/// Bullseye Ring (PRD-2 §3.24, §5.23; lab mock `screen_lab3_hoops.html`
/// `?only=bull`): a normal hoop (score, coins, streak, rim bounce, tier
/// look) with a **target** at its centre and two dashed guide lines marking
/// the **bullseye band ±12 pt** (fixed as openings shrink, Q63).
///
/// Crossing the plane with the bird's centre inside the band is a
/// **BULLSEYE**: +3 coins ([CoinSource.bullseye]), the target flashes
/// bigger, a red / white burst, the banner "BULLSEYE!" "+3 coins", the dart
/// thunk + chord and `bullseye_hit`. Anywhere else in the opening is a
/// normal pass. The target and the band lines are drawn behind the bird.
class BullseyeHoopKind extends HoopKind {
  @override
  HoopKindId get id => HoopKindId.bullseye;

  @override
  bool get usesTierLook => true;

  static final Expando<_BullState> _states = Expando('bullseye');

  /// §3.24 The bird centre [bird] (track coordinates) is inside the hit
  /// band ([BullseyeConfig.band], `point_bullseye_band`, default ±12 pt)
  /// of [f]'s ring (measured in the ring's local frame, like the pass
  /// test).
  static bool isBullseye(HoopFrame f, Vector2 bird, {int ring = 0}) =>
      (f.toLocal(bird).y - f.rings[ring]).abs() <= BullseyeConfig.band;

  /// The hit flash left on [h] (0 = none; tests).
  static double flashOf(Hoop h) => _states[h]?.flash ?? 0;

  @override
  void buildVisual(Hoop h, RunContext c) {
    final skin = c.game.menu.items.look.hoop;
    final state = _BullState();
    _states[h] = state;
    h.add(state);
    h.paintBack = (canvas) {
      NormalHoopKind.paintRings(canvas, h, skin, front: false, t: c.s.runClock);
      paintTarget(
        canvas,
        Offset(0, h.rings.first),
        guide: c.game.foregroundColor,
        flash: state.flash,
      );
    };
    h.front.paintFront = (canvas) => NormalHoopKind.paintRings(
      canvas,
      h,
      skin,
      front: true,
      t: c.s.runClock,
    );
  }

  /// §5.23 the band lines (stage foreground 45 %, from 46 pt before the
  /// ring to 8 pt before its centre, at ±12 pt) and the target (white /
  /// red rings at 15 / 11 / 7 / 3.5 pt, squashed to 62 % width; a hit
  /// grows it by 1 + [flash]) around [centre] (hoop-local).
  static void paintTarget(
    Canvas canvas,
    Offset centre, {
    required Color guide,
    double flash = 0,
  }) {
    final color = guide.withValues(alpha: guide.a * BullseyeConfig.guideAlpha);
    for (final s in const [-1.0, 1.0]) {
      final y = centre.dy + s * BullseyeConfig.drawBand;
      DashedPathPainter.line(
        canvas,
        Offset(centre.dx - BullseyeConfig.guideFrom, y),
        Offset(centre.dx - BullseyeConfig.guideTo, y),
        color: color,
        width: BullseyeConfig.guideWidth,
        dashes: BullseyeConfig.guideDash,
      );
    }
    final grow = 1 + flash;
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(BullseyeConfig.targetSquash * grow, grow);
    final paint = Paint();
    for (final (r, col) in BullseyeConfig.target) {
      canvas.drawCircle(Offset.zero, r, paint..color = col);
    }
    canvas.restore();
  }

  /// PRD-2.2 §11.1–2 (fix S7-04) whether the crossing [offset]
  /// (`Hoop.passOffset`, ring-local, like the perfect band) is inside the
  /// hit band ([BullseyeConfig.band], default ±12 pt).
  static bool isBullseyeOffset(double offset) =>
      offset.abs() <= BullseyeConfig.band;

  @override
  void onPass(Hoop h, PassInfo p, RunContext c) {
    // PRD-2.2 §11.1–2 (fix S7-04): judged at the crossing (the offset the
    // controller recorded), not at the frame's end position; the frame
    // position is only the fallback for a pass without a crossing offset.
    final off = h.passOffset;
    if (off != null) {
      if (!isBullseyeOffset(off)) return;
    } else {
      final bird = c.run.birdTrackPosition();
      if (bird == null || !isBullseye(h.frame(), bird, ring: p.ring)) return;
    }
    _states[h]?.flash = BullseyeConfig.flashGrow;
    c.earn(BullseyeConfig.coins, CoinSource.bullseye);
    c.sfx(Sfx.bullThunk);
    c.sfx(Sfx.bullChord);
    RunHud.ensureFor(c.run).banners.show(
      ElementBanner(
        'BULLSEYE!',
        color: BullseyeConfig.red,
        subtitle: BullseyeConfig.coins == 1
            ? '+1 coin'
            : '+${BullseyeConfig.coins} coins',
      ),
    );
    final at = h.frame().toWorld(Vector2(0, h.rings[p.ring]));
    final r = c.cosmetic;
    for (var i = 0; i < BullseyeConfig.burst; i++) {
      final a = r.nextDouble() * 2 * math.pi;
      final v = BullseyeConfig.burstSpeed * (.5 + r.nextDouble() * .7);
      c.run.particles.spawn(
        x: at.x,
        y: at.y,
        vx: math.cos(a) * v,
        vy: math.sin(a) * v,
        w: 4 + r.nextDouble() * 3,
        color: i.isEven ? BullseyeConfig.red : const Color(0xFFFFFFFF),
        life: .45 + r.nextDouble() * .25,
        damp: 2.4,
      );
    }
    c.track('bullseye_hit');
  }
}

/// Per-hoop hit flash (world time: pauses with the run).
class _BullState extends Component {
  double flash = 0;

  @override
  void update(double dt) {
    if (flash > 0) {
      flash = math.max(0, flash - dt);
    }
  }
}
