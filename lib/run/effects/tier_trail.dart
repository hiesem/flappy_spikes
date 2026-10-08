import 'dart:math' as math;
import 'dart:ui';

import '../../skins/art/trail.dart';
import '../config/parts_config.dart';
import 'block_trail.dart';
import 'particle_pool.dart';

/// Picks what the bird leaves behind while it is "on fire" (streak tier 3+,
/// comet, portal rides) — ARCH §3 "Skin interplay": the **equipped trail**
/// (`TrailEmitter`, PRD-menu-v2 §3.8: the tier-3 block trail became the
/// equipped trail item, default Classic flame) or the master [BlockTrail]
/// when the equipped trail is `blocks` (Pixel blocks) or when
/// [useEquippedTrail] is switched off.
///
/// Both use the master #10 flight-direction rule for the emission point:
/// 26 pt behind the bird along [heading]. The equipped trail's particles
/// drift with the world scroll (`TrailEmitter` has horizontal drift only).
class TierTrail {
  TierTrail({
    required String trailId,
    math.Random? random,
    LookPaint? lookPainter,
    this.k = 29.5 / 30,
  }) : _trailId = trailId,
       _blocks = BlockTrail(random: random),
       _emitter = TrailEmitter(
         trailId,
         random: random,
         lookPainter: lookPainter,
       );

  /// ARCH §3 switch: true = the equipped trail shows in runs; false = the
  /// block trail always (if the owner decides otherwise).
  static bool useEquippedTrail = true;

  /// Equipped trail id of the blocks item (uses [BlockTrail] itself).
  static const String blocksId = 'blocks';

  /// Pixels per bird art unit (the bird's look scale).
  final double k;

  final BlockTrail _blocks;
  final TrailEmitter _emitter;
  String _trailId;

  String get trailId => _trailId;
  set trailId(String id) {
    _trailId = id;
    _emitter.trailId = id;
  }

  /// Whether this trail draws master #10 blocks (into the shared pool).
  bool get usesBlocks => !useEquippedTrail || _trailId == blocksId;

  TrailEmitter get emitter => _emitter;

  /// Emits for [dt] while [active] (tier 3+, comet, ride) and advances the
  /// equipped trail's own particles. [scrollVx] is the world scroll (pt/s,
  /// negative = moving left) for the equipped trail's drift.
  void update(
    ParticlePool pool,
    double dt,
    Offset bird,
    double heading, {
    required bool active,
    double scrollVx = -150,
  }) {
    if (usesBlocks) {
      if (active) {
        _blocks.update(pool, dt, bird, heading);
      } else {
        _blocks.reset();
      }
      return;
    }
    if (active) {
      final head = Offset(
        bird.dx - math.cos(heading) * PartsConfig.trailBack,
        bird.dy - math.sin(heading) * PartsConfig.trailBack,
      );
      _emitter.emit(head, dt, k: k, vx: scrollVx);
    }
    _emitter.step(dt);
  }

  /// Paints the equipped trail (the blocks are painted by the pool).
  void paint(Canvas canvas) {
    if (!usesBlocks) _emitter.paint(canvas, k: k);
  }

  void clear() {
    _blocks.reset();
    _emitter.clear();
  }
}
