import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import '../../game/sound.dart';
import '../config/feather_config.dart';
import '../effects/fetch_flight.dart';
import '../elements.dart';
import '../hud/collect_layer.dart';
import '../pickups/feather_pickup.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../../game/paints.dart';

/// Golden feathers in the run (PRD-2 §3.15, §5.14).
///
/// A touched feather is **banked at once**: `storage.feathers` + 1 (max 3,
/// persistent; a death or an app kill a second later keeps it), sound
/// `col_feather_get`, `feather_collected {count}`. It then flies (the shared
/// [FetchFlight], `FetchSpec.feather`) into its slot of the feather tray
/// ([FeatherTrayItem] in the shared collect slot) — slot sounds, punch,
/// gold ring and sparkles on landing; the 3rd plays the set-complete
/// celebration and the BONUS UNLOCKED! sticker. The bonus screen itself is
/// the post-run flow's (`screens/bonus_screen.dart`). Feathers touch
/// nothing else: score, coins, streak and duel stay as they are.
class FeathersFeature extends RunFeature {
  RunContext? _c;

  /// Feathers collected in this run (the director spawns at most one; a
  /// debug force may add more).
  int collected = 0;

  @override
  void attach(RunContext c) {
    _c = c;
    c.events.on<PickupCollected>(_onPickup);
  }

  void _onPickup(PickupCollected e) {
    if (e.element != ElementId.feather) return;
    final c = _c;
    if (c == null) return;
    final storage = c.game.storage;
    final count = math.min(FeatherConfig.maxHeld, storage.feathers + 1);
    collected++;
    unawaited(storage.saveFeathers(count));
    c.sfx(Sfx.colFeatherGet);
    c.track('feather_collected', {'count': count});

    final layer = CollectLayer.ensureFor(c.run);
    final item = FeatherTrayItem(layer: layer, count: count, random: c.cosmetic);
    layer.slot.request(item);

    final p = e.pickup;
    if (p == null) return;
    final s = c.s;
    final from = Offset(p.position.x - s.camX, p.position.y - s.camY);
    final to = Offset(
      CollectConfig.slotX + FeatherTrayItem.slotX(count - 1),
      CollectConfig.slotY,
    );
    layer.add(
      FetchFlight(
        from: from,
        to: to,
        spec: FetchSpec.feather,
        pool: layer.pool,
        random: c.cosmetic,
        priority: 4,
        art: (canvas, scale, rotation) =>
            FeatherArt.paintAt(canvas, Offset.zero, scale, rotation),
      ),
    );
  }

  @override
  void detach() {
    _c?.events.off<PickupCollected>(_onPickup);
    _c = null;
  }
}

/// §5.14 the feather tray in the collect slot: 132 × 48 panel with three
/// 36 pt slots; the feathers already held show at once, the new one lands
/// 0.76 s after the touch (punch ×1.38, gold ring 6 → 28, 6 sparkles,
/// `col_feather_slot1/2/3`). The 3rd feather: 0.24 s later the tray
/// flashes gold, the three bounce 0.09 s apart, 26 confetti, a ring
/// 20 → 90 and the sticker; the tray holds until 3.4 s (else 2.15 s).
class FeatherTrayItem extends CollectTimeline {
  FeatherTrayItem({
    required this.layer,
    required this.count,
    required math.Random random,
  }) : _r = random;

  final CollectLayer layer;

  /// Feathers held after this one (1..3).
  final int count;
  final math.Random _r;

  final List<double?> _punch = [null, null, null];
  double? _done;

  bool get complete => count >= FeatherConfig.maxHeld;

  /// Time the set-complete flash started (null before / without it).
  double? get doneAt => _done;

  static double slotX(int k) => -FeatherConfig.slotStep + FeatherConfig.slotStep * k;

  @override
  double get fadeAt =>
      complete ? FeatherConfig.fadeAtComplete : FeatherConfig.fadeAt;

  bool have(int k, double t) =>
      k < count - 1 || (k == count - 1 && t >= FeatherConfig.landAt);

  @override
  void cues(CollectLayer layer, double prev, double t) {
    bool at(double x) => CollectTimeline.crossed(prev, t, x);
    final centre = layer.slotCentre;
    if (at(FeatherConfig.landAt)) {
      final k = count - 1;
      layer.game.sound.play(switch (count) {
        1 => Sfx.colFeatherSlot1,
        2 => Sfx.colFeatherSlot2,
        _ => Sfx.colFeatherSlot3,
      });
      _punch[k] = t;
      final p = centre + Offset(slotX(k), 0);
      layer.ring(
        p,
        from: FeatherConfig.landRingFrom,
        to: FeatherConfig.landRingTo,
      );
      layer.sparkles(p);
    }
    if (!complete) return;
    const done = FeatherConfig.landAt + FeatherConfig.completeDelay;
    if (at(done)) {
      _done = t;
      layer.confetti(centre, FeatherConfig.confetti, _r);
      layer.ring(
        centre,
        from: FeatherConfig.completeRingFrom,
        to: FeatherConfig.completeRingTo,
        stroke: 4,
        length: .6,
      );
    }
    for (var k = 0; k < 3; k++) {
      if (at(done + k * FeatherConfig.bounceGap)) _punch[k] = t;
    }
    if (at(done + FeatherConfig.stickerDelay)) {
      sticker(
        layer,
        FeatherConfig.stickerText,
        Offset(
          CollectConfig.slotX,
          CollectConfig.slotY +
              FeatherConfig.trayHeight / 2 +
              FeatherConfig.stickerGap,
        ),
      );
    }
  }

  final Paint _fill = Paint();

  @override
  void paint(Canvas canvas, double alpha, double t) {
    fadeStickers(alpha);
    canvas.saveLayer(null, layerPaint(alpha));
    const w = FeatherConfig.trayWidth, h = FeatherConfig.trayHeight;
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawRect(rect, _fill..color = layer.mix(FeatherConfig.panelMix));
    final done = _done;
    if (done != null && t >= done) {
      final dk = math.exp(-(t - done) * 3);
      _fill.color = const Color(0xFFFFB529).withValues(alpha: dk * .85);
      canvas.drawRect(rect, _fill);
    }
    final ghost = layer.mix(FeatherConfig.ghostMix);
    for (var k = 0; k < 3; k++) {
      final x = slotX(k);
      const s = FeatherConfig.slotSize;
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, 0), width: s, height: s),
        _fill..color = layer.mix(FeatherConfig.slotMix),
      );
      final pk = CollectTimeline.punch(
        t,
        _punch[k],
        FeatherConfig.punch,
        FeatherConfig.punchLength,
      );
      final held = have(k, t);
      FeatherArt.paintAt(
        canvas,
        Offset(x, 0),
        FeatherConfig.slotScale * pk,
        FeatherConfig.slotTilt,
        ghost: held ? null : ghost,
        outline: FeatherConfig.slotOutline,
      );
    }
    canvas.restore();
  }
}
