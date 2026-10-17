import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../../skins/art/look_painter.dart';
import '../config/capsule_config.dart';
import '../effects/bird_attachment.dart';
import '../effects/easing.dart';
import '../effects/screen_edge_glow.dart';
import '../run_context.dart';
import '../run_state.dart';
import 'timed_powerup.dart';
import '../run_scaled_world.dart';

/// Hourglass (PRD-2 §3.30, §5.29): slow motion for a random 10–20 s (real
/// time). The whole world, bird included, runs at 45 % speed through
/// `RunState.timeScale` (the run world's `RunScaledWorld.updateTree` and
/// `RunClock` read it, so scroll, gravity, flap, spawns, moving rings,
/// animations and every runClock timer slow; the HUD stays real time). The
/// slow-down eases in over 0.2 s and back out at the end.
///
/// Feedback: a 10 % blue tint + dark-blue vignette ([ScreenEdgeGlow
/// .hourglass], following the slow-down), a fading ghost trail of birds
/// behind the bird, a thin blue clock ring with a turning hand around the
/// bird, a tick-tock every 0.6 s, the music at 72 %
/// (`SoundService.setMusicRate`), the tape-slowdown sweep on start and the
/// speed-up sweep at the end.
///
/// A portal ride pauses it: the time scale and the music go back to 1 at
/// once (no slow-motion rides) and the slow-down eases in again after the
/// landing. A death puts everything back at once.
class HourglassFeature extends TimedPowerupEffect {
  @override
  TimedPowerup get type => TimedPowerup.hourglass;

  /// The current time scale this feature writes (1 = not slowing).
  double scale = 1;
  double _from = 1, _to = 1, _easeT = 1;

  /// True while this feature owns `RunState.timeScale` (active or easing
  /// back out).
  bool owning = false;

  double _tick = 0;
  double _ghostAcc = 0;

  /// Ghosts (track x, y, angle, age) — the fading-birds trail.
  final List<HourglassGhost> ghosts = [];

  ScreenEdgeGlow? glow;
  HourglassTrail? trail;

  /// Ticks played this powerup (tests).
  int ticks = 0;

  void _easeTo(double target) {
    _from = scale;
    _to = target;
    _easeT = 0;
  }

  void _setScale(double v) {
    scale = v;
    _from = _to = v;
    _easeT = 1;
    _write();
  }

  void _write() {
    final ctx = c;
    if (ctx == null) return;
    // PRD-2.2 §17.2 a comet landing at the same time: the lower scale wins.
    final s = ctx.s..hourglassScale = scale;
    final v = math.min(scale, s.landingScale);
    s.timeScale = v;
    ctx.run.clock.timeScale = v;
  }

  @override
  void onStart() {
    final ctx = c!;
    owning = true;
    _tick = 0;
    _ghostAcc = 0;
    ticks = 0;
    _easeTo(CapsuleConfig.hourglassScale);
    ctx.sfx(Sfx.hourglassStart);
    ctx.game.sound.setMusicRate(CapsuleConfig.hourglassMusicRate);
    _ensureVisuals(ctx);
  }

  void _ensureVisuals(RunContext ctx) {
    final g = glow;
    if (g == null || g.isRemoved || g.isRemoving) {
      glow =
          ScreenEdgeGlow.hourglass(Vector2(ctx.game.viewWidth, ctx.viewHeight))
            ..position.x = -ctx.game.extraWidth // WP-TAB: the whole screen
            ..priority = CapsuleConfig.glowPriority
            ..intensity = 0;
      ctx.game.world.addRun(glow!);
    }
    final t = trail;
    if (t == null || t.isRemoved || t.isRemoving) {
      trail = HourglassTrail(this);
      ctx.layers.back.add(trail!);
    }
  }

  @override
  void onPause() {
    _setScale(1);
    c?.game.sound.setMusicRate(1);
  }

  @override
  void onResume() {
    _easeTo(CapsuleConfig.hourglassScale);
    c?.game.sound.setMusicRate(CapsuleConfig.hourglassMusicRate);
  }

  @override
  void onEnd({required bool death}) {
    final ctx = c;
    if (death || ctx == null) {
      reset();
      return;
    }
    _easeTo(1);
    ctx.sfx(Sfx.hourglassEnd);
    ctx.game.sound.setMusicRate(1);
  }

  /// §5.29 the vignette strength now: 0 at full speed, 1 at 45 %.
  double get slowness =>
      ((1 - scale) / (1 - CapsuleConfig.hourglassScale)).clamp(0.0, 1.0);

  @override
  void step(double gameDt, double realDt) {
    final ctx = c;
    if (ctx == null || !owning) return;
    if (_easeT < 1) {
      _easeT = math.min(1, _easeT + realDt / CapsuleConfig.hourglassEase);
      scale = _from + (_to - _from) * Ease.cubicInOut(_easeT);
      _write();
    }
    glow?.intensity = slowness;
    if (on) {
      _tick += realDt;
      while (_tick >= CapsuleConfig.hourglassTick) {
        _tick -= CapsuleConfig.hourglassTick;
        ticks++;
        ctx.sfx(Sfx.hourglassTick);
      }
      _ghostAcc += realDt * CapsuleConfig.ghostRate;
      final bird = ctx.game.runBird;
      final pos = ctx.run.birdTrackPosition();
      while (_ghostAcc >= 1) {
        _ghostAcc -= 1;
        if (pos != null && ctx.s.ride == null && ctx.game.runBirdPresented) {
          ghosts.add(
            HourglassGhost(
              pos.x,
              pos.y,
              bird != null && bird.isLoaded ? bird.body.angle : 0,
            ),
          );
        }
      }
    }
    for (final g in ghosts) {
      g.age += realDt;
    }
    ghosts.removeWhere((g) => g.age >= CapsuleConfig.ghostLife);
    // Fully back to normal speed: drop the visuals.
    if (!active && _easeT >= 1 && scale == 1 && ghosts.isEmpty) {
      owning = false;
      _removeVisuals();
    }
  }

  void _removeVisuals() {
    glow?.removeFromParent();
    glow = null;
    trail?.removeFromParent();
    trail = null;
  }

  @override
  void reset() {
    final ctx = c;
    if (owning && ctx != null) {
      _setScale(1);
      ctx.game.sound.setMusicRate(1);
    }
    scale = 1;
    owning = false;
    ghosts.clear();
    _removeVisuals();
  }
}

/// One fading bird of the ghost trail (track coordinates).
class HourglassGhost {
  HourglassGhost(this.x, this.y, this.angle);
  final double x, y, angle;
  double age = 0;
}

/// §5.29 behind the bird (`RunTrack.back`): the ghost trail of fading
/// birds (25 % → 0 over 0.5 s, left behind in the world) and, while the
/// Hourglass runs, the thin blue clock ring (r 26, 2 pt) with a hand that
/// turns once over the whole duration.
class HourglassTrail extends Component with BirdAttachment {
  HourglassTrail(this.owner);

  final HourglassFeature owner;

  @override
  FlappySpikesGame? get birdGame => owner.c?.game;

  /// The ghosts are left behind in the world; only the clock is worn.
  @override
  bool get hidesWholly => false;

  /// Audit HIDE: whether [render] draws the clock ring round the bird now.
  bool get paintsClock =>
      owner.on &&
      owner.c?.s.ride == null &&
      birdPresented &&
      owner.c?.run.birdTrackPosition() != null;

  final Paint _layer = Paint();
  final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = CapsuleConfig.clockStroke
    ..color = CapsuleConfig.clockColor
    ..strokeCap = StrokeCap.round;

  @override
  void render(Canvas canvas) {
    final ctx = owner.c;
    if (ctx == null) return;
    final look = ctx.game.menu.items.look;
    final k = Config.lookScale * ctx.s.birdScale;
    final gold = ctx.game.runBird?.lookComponent.goldTier ?? false;
    for (final g in owner.ghosts) {
      final a =
          CapsuleConfig.ghostAlpha * (1 - g.age / CapsuleConfig.ghostLife);
      if (a <= 0) continue;
      canvas.save();
      canvas.translate(g.x, g.y);
      canvas.rotate(g.angle);
      // LookPainter draws the art-box centre at the origin; the body centre
      // (21, 18) sits 1 art unit left of it.
      canvas.translate(k, 0);
      canvas.scale(k);
      canvas.saveLayer(
        const Rect.fromLTWH(-30, -30, 60, 60),
        _layer..color = Color.fromRGBO(0, 0, 0, a.clamp(0.0, 1.0)),
      );
      LookPainter.paint(canvas, look, gold: gold);
      canvas.restore();
      canvas.restore();
    }
    if (!owner.on || ctx.s.ride != null || !birdPresented) return;
    final pos = ctx.run.birdTrackPosition();
    if (pos == null) return;
    final centre = Offset(pos.x, pos.y);
    canvas.drawCircle(centre, CapsuleConfig.clockRadius, _ring);
    final d = owner.duration <= 0 ? 1.0 : owner.duration;
    final a = -math.pi / 2 + owner.elapsed / d * 2 * math.pi;
    canvas.drawLine(
      centre,
      centre + Offset(math.cos(a), math.sin(a)) * CapsuleConfig.clockHand,
      _ring,
    );
  }
}
