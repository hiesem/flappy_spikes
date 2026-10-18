import 'dart:math' as math;
import 'dart:ui';

import '../../skins/art/trail.dart';
import '../config/trail_config.dart';
import 'block_trail.dart';
import 'particle_pool.dart';

/// Picks what the bird leaves behind while it is "on fire" (streak tier 3+,
/// comet, portal rides) — ARCH §3 "Skin interplay": the **equipped trail**
/// (`TrailEmitter`, PRD-menu-v2 §3.8: the tier-3 block trail became the
/// equipped trail item, default Classic flame) or the master [BlockTrail]
/// when the equipped trail is `blocks` (Pixel blocks) or when
/// [useEquippedTrail] is switched off.
///
/// WP-TRAIL (owner 2026-10-18): the trail lies along the bird's **real
/// path**, like a snake following its tail. The emitter runs in its
/// world-locked mode: the caller [shift]s everything already drawn with the
/// world's motion on screen, and emits at the [update] `tail` point (on the
/// bird's past path, [TrailConfig.runBack] behind it) along the flight
/// `heading`. Climbs, dives, loops and diagonal flight all keep the trail
/// on the path. The blocks of the block trail stay where they were spawned
/// (no 70 pt drift; the pool moves with the world).
///
/// PRD-2.2 §21.1: every trail is drawn at 2× the old scale — the equipped
/// trail at [k] = [TrailConfig.runScale] (≈ 1.97, was the look scale
/// ≈ 0.98) and the block trail at [TrailConfig.blockScale] — except the
/// Rainbow ribbon and the Afterimage copies, which keep the shop preview's
/// size relative to the bird ([TrailConfig.birdScaleIds]). Everything is
/// also scaled with the bird's drawn scale (`scale`: rides, comet, Mini
/// Bird).
///
/// WP-TRAIL hide rule (with `BirdAttachment`): while the bird is drawn the
/// trail emits from it and is drawn with its opacity; when the bird is
/// hidden ([detach]) emission stops, particles age out where they are and a
/// path trail fades out in place over [TrailConfig.detachFade]; when the
/// bird is back a fresh trail starts from it.
class TierTrail {
  TierTrail({
    required String trailId,
    math.Random? random,
    LookPaint? lookPainter,
  }) : _trailId = trailId,
       _blocks = BlockTrail(random: random),
       _emitter = TrailEmitter(
         trailId,
         random: random,
         lookPainter: lookPainter,
       )..worldLocked = true;

  /// ARCH §3 switch: true = the equipped trail shows in runs; false = the
  /// block trail always (if the owner decides otherwise).
  static bool useEquippedTrail = true;

  /// Equipped trail id of the blocks item (uses [BlockTrail] itself).
  static const String blocksId = 'blocks';

  /// Pixels per bird art unit at bird scale 1 ([TrailConfig.scaleFor]).
  double get k => TrailConfig.scaleFor(_trailId);

  final BlockTrail _blocks;
  final TrailEmitter _emitter;
  String _trailId;

  /// Bird's drawn scale at the last emission (the paint scale).
  double _scale = 1;

  /// Bird's drawn opacity while attached.
  double _opacity = 1;

  /// Whether the trail emitted last frame (attached to the bird).
  bool _attached = false;

  /// Whether the trail was detached by a hidden bird (fading / faded).
  bool _detached = false;

  /// The path fade after a [detach] (1 → 0 over [TrailConfig.detachFade]).
  double _fade = 1;

  static final Paint _layer = Paint();

  String get trailId => _trailId;
  set trailId(String id) {
    _trailId = id;
    _emitter.trailId = id;
  }

  /// Whether this trail draws master #10 blocks (into the shared pool).
  bool get usesBlocks => !useEquippedTrail || _trailId == blocksId;

  TrailEmitter get emitter => _emitter;

  /// The bird scale the trail is painted at (tests).
  double get paintScale => _scale;

  /// Whether the trail is detached from a hidden bird (tests).
  bool get detached => _detached;

  /// The whole trail's drawn opacity now (tests): the bird's while
  /// attached; the path fade while detached (path trails; particles fade
  /// on their own).
  double get drawAlpha {
    if (_attached) return _opacity;
    if (_detached && TrailEmitter.isPathTrail(_trailId)) return _fade;
    return 1;
  }

  /// Emits for [dt] while [active] (tier 3+, comet, ride; bird drawn) and
  /// advances the equipped trail's own particles. [tail] is the emission
  /// point on the bird's past path (default: [TrailConfig.runBack] behind
  /// [bird] along [heading]); [scale] / [opacity] are the bird's drawn
  /// scale / opacity and [angle] its drawn angle (Afterimage copies).
  void update(
    ParticlePool pool,
    double dt,
    Offset bird,
    double heading, {
    required bool active,
    Offset? tail,
    double scale = 1,
    double opacity = 1,
    double angle = 0,
  }) {
    final head =
        tail ??
        Offset(
          bird.dx - math.cos(heading) * TrailConfig.runBack * scale,
          bird.dy - math.sin(heading) * TrailConfig.runBack * scale,
        );
    if (active && _detached) {
      // The bird is back: a fresh trail starts from it.
      _detached = false;
      _fade = 1;
      if (TrailEmitter.isPathTrail(_trailId)) {
        _emitter.clear();
      } else {
        _emitter.breakStroke();
      }
      _blocks.reset();
    }
    _attached = active;
    if (active) {
      _scale = scale;
      _opacity = opacity.clamp(0.0, 1.0);
    } else {
      _emitter.breakStroke();
    }
    if (_detached && _fade > 0 && dt > 0) {
      _fade = math.max(0, _fade - dt / TrailConfig.detachFade);
    }
    if (usesBlocks) {
      if (active) {
        _blocks.update(
          pool,
          dt,
          head.translate(
            math.cos(heading) * TrailConfig.runBack * scale,
            math.sin(heading) * TrailConfig.runBack * scale,
          ),
          heading,
          scale: TrailConfig.blockScale * scale,
          back: TrailConfig.runBack * scale,
          drift: 0,
        );
      } else {
        _blocks.reset();
      }
      return;
    }
    if (active) {
      _emitter.emit(
        head,
        dt,
        k: k * scale,
        vx: 0,
        heading: heading,
        angle: angle,
      );
    }
    _emitter.step(dt);
  }

  /// WP-TRAIL: the world moved by ([dx], [dy]) on screen this frame: the
  /// trail already drawn moves with it (stays where the bird was).
  void shift(ParticlePool pool, double dx, double dy) {
    _emitter.shift(dx, dy);
    pool.shift(dx, dy);
  }

  /// WP-TRAIL: the bird was hidden (ride barrel / volcano / rocket, Black
  /// Hole, phoenix): stop emitting; the shed trail stays in place and a
  /// path trail fades out there.
  void detach() {
    if (_detached) return;
    _detached = true;
    _attached = false;
    _fade = 1;
    _emitter.breakStroke();
  }

  /// Audit A2-1: the trail switched off (streak break, death, end of a
  /// ride): the path history (ribbon / Afterimage / 2.3 path trails) goes
  /// while live particles fade out (the shop preview's switch-off,
  /// [TrailEmitter.resetPath]). Not for a hidden bird ([detach]).
  void dropPath() {
    _emitter.resetPath();
    _detached = false;
    _fade = 1;
  }

  /// Paints the equipped trail (the blocks are painted by the pool) at the
  /// bird's scale, in one layer only while it fades (no layer per
  /// particle).
  void paint(Canvas canvas) {
    if (usesBlocks) return;
    final a = drawAlpha;
    if (a <= 0) return;
    final layer = a < .999;
    if (layer) {
      canvas.saveLayer(
        null,
        _layer..color = Color.fromRGBO(255, 255, 255, a),
      );
    }
    _emitter.paint(canvas, k: k * _scale);
    if (layer) canvas.restore();
  }

  void clear() {
    _blocks.reset();
    _emitter.clear();
    _detached = false;
    _attached = false;
    _fade = 1;
  }
}
