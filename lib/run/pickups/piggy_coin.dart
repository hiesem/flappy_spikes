import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/flappy_game.dart';
import '../config/piggy_config.dart';
import '../config/run_config.dart';
import '../director/plans.dart';
import '../effects/coin_icon.dart';
import '../effects/particle_pool.dart' show ParticleShape;
import '../elements.dart';
import '../run_context.dart';
import '../run_events.dart';
import 'pickup.dart';

/// The Piggy Bank's coin fields (PRD-2 §3.28): each `piggyCoins` gap item
/// (the 4 own-gap coins the feature adds, then one field per follow gap)
/// becomes a [PiggyCoin] field. The director's `GapItemPlan` carries the
/// count in `extra` and the field's span in `trackX` / `toTrackX`; the
/// coins follow the line with an 18 pt upward bulge.
class PiggyCoinKind extends PickupKind {
  @override
  ElementId get element => ElementId.piggyCoins;

  @override
  Pickup build(GapItemPlan p, RunContext c) => PiggyCoin(p, c);
}

/// §5.27 / §3.28 a field of `extra` spinning coins. Catching one — the bird
/// within 10 pt (§3.0.3) — puts it in the bank; a coin that passes the bird
/// uncaught is **missed** and gone (each one emits `PickupEscaped`). While
/// the piggy is gone (`RunState.piggy == null`, e.g. after a death or a
/// portal ride cleared them) the remaining coins fly away unjudged. Caught
/// coins are animated into the HUD piggy by `PiggyFeature`.
class PiggyCoin extends Pickup with HasGameReference<FlappySpikesGame> {
  PiggyCoin(GapItemPlan p, this.c)
    : count = p.extra is int ? p.extra! as int : PiggyConfig.ownGapCoins,
      caught = List<bool>.filled(
        p.extra is int ? p.extra! as int : PiggyConfig.ownGapCoins,
        false,
      ),
      missed = List<bool>.filled(
        p.extra is int ? p.extra! as int : PiggyConfig.ownGapCoins,
        false,
      ),
      super(
        id: ElementId.piggyCoins,
        hitRadius: _halfSpan(p),
        plan: p,
        position: Vector2(_midX(p), p.y ?? 0),
        size: Vector2.all(PickupRadii.piggyCoin * 2),
        anchor: Anchor.topLeft,
      );

  final RunContext c;

  /// Coins in this field (mock: 4 / gap).
  final int count;
  final List<bool> caught;
  final List<bool> missed;

  int _hit = -1;
  double _t = 0;
  Image? _image;

  static double _span(GapItemPlan p) => (p.toTrackX ?? p.trackX) - p.trackX;
  static double _halfSpan(GapItemPlan p) =>
      _span(p).abs() / 2 + PickupRadii.piggyCoin;
  static double _midX(GapItemPlan p) => (p.trackX + (p.toTrackX ?? p.trackX)) / 2;

  /// The track position of coin [i]: u = (i + 1) / (n + 1) along the field,
  /// the line plus the 18 pt upward bulge.
  Offset coinAt(int i) {
    final u = (i + 1) / (count + 1);
    final x0 = plan!.trackX, x1 = plan!.toTrackX ?? plan!.trackX;
    final y0 = plan!.y ?? 0, y1 = plan!.toY ?? y0;
    return Offset(
      x0 + (x1 - x0) * u,
      y0 + (y1 - y0) * u - math.sin(math.pi * u) * PiggyConfig.coinBulge,
    );
  }

  int get caughtCount {
    var n = 0;
    for (final b in caught) {
      if (b) n++;
    }
    return n;
  }

  int get missedCount {
    var n = 0;
    for (final b in missed) {
      if (b) n++;
    }
    return n;
  }

  /// The track position of the coin collected last (for the HUD flight).
  Offset? get lastCollectedAt =>
      _hit >= 0 && _hit < count ? coinAt(_hit) : null;

  bool get done => caughtCount + missedCount >= count;

  @override
  Future<void> onLoad() async {
    _image = await CoinIcon.load(game.images);
  }

  @override
  bool touches(Vector2 birdTrack, double birdR) {
    if (escaped || done) return false;
    for (var i = 0; i < count; i++) {
      if (caught[i] || missed[i]) continue;
      final p = coinAt(i);
      if (birdTrack.distanceTo(Vector2(p.dx, p.dy)) - birdR <=
          PickupRadii.piggyCoin) {
        _hit = i;
        return true;
      }
    }
    return false;
  }

  @override
  bool isPast(double birdTrackX, double birdR) => done;

  @override
  void onCollect(RunContext c) {
    if (_hit < 0 || _hit >= count) return;
    caught[_hit] = true;
    // One coin per frame; the field stays collectable for the rest.
    collected = false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (escaped) return;
    final s = c.s;
    if (s.piggy == null) {
      // The bank is gone (death, pay-out, portal): the rest fly away.
      _flyAway();
      return;
    }
    final bird = c.run.birdTrackPosition();
    if (bird == null) return;
    final r = RunConfig.birdRadius * s.birdScale;
    for (var i = 0; i < count; i++) {
      if (caught[i] || missed[i]) continue;
      final p = coinAt(i);
      if (p.dx + r + PickupRadii.piggyCoin < bird.x) {
        missed[i] = true;
        c.emit(const PickupEscaped(ElementId.piggyCoins));
      }
    }
  }

  void _flyAway() {
    for (var i = 0; i < count; i++) {
      if (caught[i] || missed[i]) continue;
      missed[i] = true;
      final p = coinAt(i);
      c.run.particles.spawn(
        shape: ParticleShape.circle,
        x: p.dx,
        y: p.dy,
        vy: -30,
        w: PiggyConfig.coinSize,
        color: PiggyConfig.haloColor,
        life: .5,
      );
    }
    if (done) escaped = true;
  }

  @override
  void render(Canvas canvas) {
    final image = _image;
    if (image == null) return;
    for (var i = 0; i < count; i++) {
      if (caught[i] || missed[i]) continue;
      final p = coinAt(i);
      canvas.save();
      canvas.translate(p.dx - position.x, p.dy - position.y);
      canvas.scale(
        math
            .cos(_t * PiggyConfig.coinSpinRate + p.dx * PiggyConfig.coinSpinPhase)
            .abs()
            .clamp(.15, 1.0),
        1,
      );
      CoinIcon.paint(canvas, image, Offset.zero, PiggyConfig.coinSize);
      canvas.restore();
    }
  }
}
