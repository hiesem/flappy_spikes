import 'dart:math' as math;
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flappy_spikes/run/config/parts_config.dart';
import 'package:flappy_spikes/run/effects/block_trail.dart';
import 'package:flappy_spikes/run/effects/coin_popup.dart';
import 'package:flappy_spikes/run/effects/dust_puff.dart';
import 'package:flappy_spikes/run/effects/easing.dart';
import 'package:flappy_spikes/run/effects/fetch_flight.dart';
import 'package:flappy_spikes/run/effects/gold_sticker.dart';
import 'package:flappy_spikes/run/effects/invuln_flash.dart';
import 'package:flappy_spikes/run/effects/particle_pool.dart';
import 'package:flappy_spikes/run/effects/perfect_burst.dart';
import 'package:flappy_spikes/run/effects/pickup_touch_fx.dart';
import 'package:flappy_spikes/run/effects/ring_tier_fx.dart';
import 'package:flappy_spikes/run/effects/run_shake.dart';
import 'package:flappy_spikes/run/effects/screen_edge_glow.dart';
import 'package:flappy_spikes/run/effects/shock_ring.dart';
import 'package:flappy_spikes/run/effects/spike_teeth.dart';
import 'package:flappy_spikes/run/effects/tier_trail.dart';
import 'package:flappy_spikes/run/effects/twinkle.dart';
import 'package:flappy_spikes/run/hoops/ring_painter.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/collect_slot.dart';
import 'package:flutter_test/flutter_test.dart';

class _Item extends CollectSlotItem {
  _Item(this.fadeAt);
  @override
  final double fadeAt;
  bool gone = false;
  @override
  void paint(Canvas canvas, double alpha, double t) {}
  @override
  void onGone() => gone = true;
}

void _step(Component c, double seconds, {double dt = 1 / 60}) {
  for (var t = 0.0; t < seconds - 1e-9; t += dt) {
    c.update(dt);
  }
}

void main() {
  group('§3.0.9 #1 spike strip', () {
    test('§3.0.9 #1 44 pt = band 26 + teeth 18, period 40, tips at 20 + 40k', () {
      expect(SpikeTeethPainter.height, 44);
      expect(SpikeTeethPainter.band + SpikeTeethPainter.depth, 44);
      expect(SpikeTeethPainter.period, 40);
      expect(SpikeTeethPainter.firstTip(0), 20);
      expect(SpikeTeethPainter.firstTip(-15), 5);
      expect(SpikeTeethPainter.firstTip(25), 5);
    });
  });

  group('§3.0.9 #3 ring', () {
    test('§3.0.9 #3 24 pt wide, stroke 7, half height = opening / 2 + 7', () {
      expect(RingPainter.rx * 2, 24);
      expect(RingPainter.stroke, 7);
      expect(RingPainter.ryFor(118), 66);
      expect(RingPainter.ryFor(92), 53);
      final (top, bottom) = RingPainter.rimEnds(118);
      // The gap between the r-7 rim-end circles is the opening.
      expect((bottom.dy - 7) - (top.dy + 7), 118);
    });

    test('§3.5 tier colours: skin at 0–1, gold at 2, bright gold at 3+', () {
      expect(RingPainter.colorsForTier(0), isNull);
      expect(RingPainter.colorsForTier(1), isNull);
      expect(RingPainter.colorsForTier(2), RingColors.gold);
      expect(RingPainter.colorsForTier(3), RingColors.brightGold);
      expect(RingPainter.colorsForTier(9), RingColors.brightGold);
      expect(RingColors.pink.front, const Color(0xFFEC008C));
      expect(RingColors.pink.back, const Color(0xFFB0006B));
      expect(RingColors.gold.back, const Color(0xFFD48A00));
      expect(RingColors.brightGold.front, const Color(0xFFFFD54A));
    });
  });

  group('§3.0.9 #7 streak banner', () {
    test('§3.0.9 #7 ten names, fixed sizes, colours, capped at IMMORTAL ×10', () {
      expect(StreakBanner.names, hasLength(10));
      for (var t = 1; t <= 10; t++) {
        final b = StreakBanner(t);
        expect(b.fontSize, PartsConfig.bannerFontSizes[t - 1]);
        expect(b.position.y, 190);
      }
      expect(StreakBanner(1).text, 'PERFECT');
      expect(StreakBanner(5).color, const Color(0xFF7A0044));
      expect(StreakBanner(14).text, 'IMMORTAL ×10');
      expect(StreakBanner(14).fontSize, 30);
    });

    test('§3.0.9 #7 duration 0.9 + 0.16 × min(tier, 6): 1.06 … 1.86 s', () {
      expect(StreakBanner.durationFor(1), closeTo(1.06, 1e-9));
      expect(StreakBanner.durationFor(6), closeTo(1.86, 1e-9));
      expect(StreakBanner.durationFor(10), closeTo(1.86, 1e-9));
    });

    test('§3.0.9 #7 scales in over 12 %, holds to 75 %, scales out', () {
      final b = StreakBanner(3);
      final d = b.duration;
      expect(b.curveAt(0).$1, 0);
      expect(b.curveAt(d * .06).$1, closeTo(.5, 1e-9));
      expect(b.curveAt(d * .12).$1, closeTo(1, 1e-9));
      expect(b.curveAt(d * .5), (1.0, 1.0));
      expect(b.curveAt(d * .75), (1.0, 1.0));
      expect(b.curveAt(d).$1, 0);
      expect(b.curveAt(d).$2, 0);
    });

    testWithFlameGame('§5.6 banners replace each other, never stack', (
      game,
    ) async {
      final host = BannerHost();
      await game.ensureAdd(host);
      host.showStreak(1);
      await game.ready();
      host.showStreak(2);
      await game.ready();
      expect(host.children.whereType<RunBanner>(), hasLength(1));
      expect((host.current! as StreakBanner).tier, 2);
      expect(host.busy, isTrue);
      _step(game, 2);
      expect(host.busy, isFalse);
      expect(host.children, isEmpty);
    });
  });

  group('§3.0.9 #8 coin popup', () {
    test('§3.0.9 #8 1.1 s, scale 0.7 → 1.1 → 1, rises 40 pt, fades', () {
      final p = CoinPopup()..play(const Offset(84, 300), 2);
      expect(p.duration, 1.1);
      expect(p.position, Vector2(84, 300));
      expect(PartsConfig.popupOffset, const Offset(-10, -70));
      expect(PartsConfig.popupFontSize, 28);
      expect(PartsConfig.popupCoinSize, 24);
      expect(PartsConfig.popupRise, 40);
      p.time = 0;
      expect(p.done, isFalse);
      p.time = 1.1;
      expect(p.done, isTrue);
    });

    test('ARCH §3 effect pool recycles finished popups', () async {
      final pool = CoinPopup.newPool();
      final game = FlameGame();
      final a = pool.obtain()..play(Offset.zero, 1);
      a.coinImage = null;
      await game.add(a);
      game.update(0);
      expect(pool.freeCount, 0);
      a.update(1.2);
      game.update(0);
      expect(pool.freeCount, 1);
      expect(identical(pool.obtain(), a), isTrue);
    });
  });

  group('§3.0.9 #9 perfect burst', () {
    test('§3.0.9 #9 8 + 3 × min(tier, 3) squares: 11 / 14 / 17', () {
      expect(PerfectBurst.countFor(1), 11);
      expect(PerfectBurst.countFor(2), 14);
      expect(PerfectBurst.countFor(3), 17);
      expect(PerfectBurst.countFor(10), 17);
    });

    test('§3.0.9 #9 5–8 pt, 25–55 pt, 350–600 ms, no rotation, 3 colours', () {
      final pool = ParticlePool();
      PerfectBurst.emit(pool, const Offset(10, 20), 3, math.Random(1));
      expect(pool.alive, 17);
      final colors = <Color>{};
      for (final p in pool.particles) {
        expect(p.w, inInclusiveRange(5, 8));
        expect(p.h, inInclusiveRange(5, 8));
        expect(p.life, inInclusiveRange(.35, .6));
        final dist = math.sqrt(p.vx * p.vx + p.vy * p.vy) * p.life;
        expect(dist, inInclusiveRange(25 - 1e-6, 55 + 1e-6));
        expect(p.spin, 0);
        expect(p.rot, 0);
        colors.add(p.color);
      }
      expect(colors, PerfectBurst.colors.toSet());
    });
  });

  group('§3.0.9 #10 block trail', () {
    test('§3.0.9 #10 30 per second, 8–13 pt, 0.9 → 0 in 450 ms', () {
      final pool = ParticlePool();
      final trail = BlockTrail(random: math.Random(2));
      var n = 0;
      for (var i = 0; i < 60; i++) {
        n += trail.update(pool, 1 / 60, Offset.zero, 0);
      }
      expect(n, inInclusiveRange(29, 30));
      for (final p in pool.particles) {
        expect(p.w, inInclusiveRange(8, 13));
        expect(p.life, .45);
        expect(p.alpha0, .9);
        expect(p.alpha1, 0);
      }
    });

    test('§3.0.9 #10 spawned 26 pt behind along the flight direction, drifts 70 pt opposite', () {
      for (final h in [0.0, -math.pi / 4, math.pi / 3, math.pi]) {
        final pool = ParticlePool();
        BlockTrail(random: math.Random(3)).update(pool, .04, const Offset(100, 200), h);
        final p = pool.particles.first;
        final hx = math.cos(h), hy = math.sin(h);
        // Along-heading distance −26, sideways within ±8.
        final dx = p.x - 100, dy = p.y - 200;
        expect(dx * hx + dy * hy, closeTo(-26, 1e-9));
        expect((dx * -hy + dy * hx).abs(), lessThanOrEqualTo(8));
        expect(p.vx * p.life, closeTo(-hx * 70, 1e-9));
        expect(p.vy * p.life, closeTo(-hy * 70, 1e-9));
      }
    });

    test('ARCH §3 tier trail: blocks item and the switch use the block trail', () {
      expect(TierTrail(trailId: 'blocks').usesBlocks, isTrue);
      expect(TierTrail(trailId: 'flame').usesBlocks, isFalse);
      TierTrail.useEquippedTrail = false;
      expect(TierTrail(trailId: 'flame').usesBlocks, isTrue);
      TierTrail.useEquippedTrail = true;
    });
  });

  group('§3.0.9 #11 ring tier looks', () {
    test('§5.3 sparkles at 7 / 16 / 38 per second, sizes per tier', () {
      for (final (tier, rate) in [(1, 7), (2, 16), (3, 38), (7, 38)]) {
        final fx = RingTierFx(random: math.Random(tier))..tier = tier;
        var spawned = 0;
        for (var i = 0; i < 60; i++) {
          final before = fx.pool.alive;
          fx.update(1 / 60);
          // Particles never die inside 0.35 s; count births in the first part.
          if (i < 20) spawned += math.max(0, fx.pool.alive - before);
        }
        final stars = fx.pool.particles.where((p) => p.shape == ParticleShape.twinkle);
        final (lo, hi) = PartsConfig.sparkleSize[math.min(tier, 3) - 1];
        for (final s in stars) {
          expect(s.w, inInclusiveRange(lo.roundToDouble(), hi.roundToDouble()));
          expect(s.life, inInclusiveRange(.5, .9));
        }
        final perSecond = spawned * 3;
        final flames = tier >= 3 ? 1.5 : 1.0; // half the sparkles add a flame
        expect(perSecond, closeTo(rate * flames, rate * flames * .35));
      }
    });

    test('§5.3 flame flicks and glow only from tier 3; glow fades in 0.25 s', () {
      final fx2 = RingTierFx(random: math.Random(4))..tier = 2;
      final fx3 = RingTierFx(random: math.Random(4))..tier = 3;
      for (var i = 0; i < 30; i++) {
        fx2.update(1 / 60);
        fx3.update(1 / 60);
      }
      expect(fx2.pool.particles.any((p) => p.shape == ParticleShape.triangle), isFalse);
      expect(fx3.pool.particles.any((p) => p.shape == ParticleShape.triangle), isTrue);
      expect(fx2.glow, 0);
      expect(fx3.glow, 1);
      final f = RingTierFx()..tier = 3;
      f.update(.125);
      expect(f.glow, closeTo(.5, 1e-9));
      expect(f.glowSize.width, 96);
      expect(RingTierFx(opening: 78).glowSize.height, closeTo(152, 1e-9));
    });

    test('§3.5 a streak break clears every effect at once', () {
      final fx = RingTierFx(random: math.Random(5))..tier = 3;
      fx.update(.5);
      expect(fx.pool.alive, greaterThan(0));
      fx.tier = 0;
      expect(fx.pool.alive, 0);
      expect(fx.glow, 0);
      expect(fx.ringColors, isNull);
    });

    test('§5.3 twinkle: scale 0 → 1.1 → 0, 0° → 90°, opacity 0 → 1 → 0', () {
      expect(Twinkle.curve(0), (0.0, 0.0, 0.0));
      final (s, a, o) = Twinkle.curve(.4);
      expect(s, closeTo(1.1, 1e-9));
      expect(a, closeTo(math.pi / 4, 1e-9));
      expect(o, closeTo(1, 1e-9));
      expect(Twinkle.curve(1).$2, closeTo(math.pi / 2, 1e-9));
      expect(Twinkle.curve(1).$3, 0);
    });
  });

  group('§3.0.9 dust puff and the pool', () {
    test('§3.0.9 dust: 12–22 round particles 4–9 pt, up 10–90 pt/s, 0.6–1 s', () {
      final pool = ParticlePool();
      DustPuff.emit(pool, Offset.zero, const Color(0xFF828282), math.Random(6));
      expect(pool.alive, 22);
      DustPuff.emit(pool, Offset.zero, const Color(0xFF828282), math.Random(6), count: 12);
      expect(pool.alive, 34);
      for (final p in pool.particles) {
        expect(p.shape, ParticleShape.circle);
        expect(p.w / 2, inInclusiveRange(4, 9));
        expect(p.vx.abs(), lessThanOrEqualTo(140));
        expect(p.vy, inInclusiveRange(-90, -10));
        expect(p.life, inInclusiveRange(.6, 1));
        expect(p.alpha0, .8);
      }
    });

    test('§5.4 the pool caps particles at 130 and recycles them', () {
      final pool = ParticlePool();
      expect(pool.capacity, 130);
      for (var i = 0; i < 20; i++) {
        PerfectBurst.emit(pool, Offset.zero, 3, math.Random(i));
      }
      expect(pool.alive, 130);
      pool.step(.7);
      expect(pool.alive, 0);
    });
  });

  group('ARCH §3 extra shared parts', () {
    test('§5.1 pass pulse: ring shape, 4 pt, scale 0.8 → 1.9, 0.55 s', () {
      final r = ShockRing()..passPulse(Offset.zero, opening: 92);
      expect(r.duration, .55);
      expect(r.valuesAt(0), (.8, 4.0, .9));
      expect(r.valuesAt(1).$1, 1.9);
      expect(r.valuesAt(1).$3, 0);
      expect(r.ry, RingPainter.ryFor(92) + 2);
      final m = ShockRing()..missWave(Offset.zero, opening: 92);
      expect(m.valuesAt(0), (1.0, 6.0, 1.0));
      expect(m.valuesAt(1).$1, 2.6);
      expect(m.valuesAt(1).$2, 1);
      expect(m.color, const Color(0xFFFF1F3D));
    });

    test('§5.5 invulnerability flash: 100 % / 25 % every 0.1 s for 2 s', () {
      final f = InvulnFlash()..start();
      expect(f.opacityAt(.05), 1);
      expect(f.opacityAt(.15), .25);
      expect(f.opacityAt(.25), 1);
      expect(f.opacityAt(1.95), .25);
      expect(f.opacityAt(2), 1);
      f.update(2.1);
      expect(f.running, isFalse);
      expect(f.opacity, 1);
    });

    test('§5.13 edge glow: miss pulse peaks at 0.55 halfway through 0.7 s', () {
      final g = ScreenEdgeGlow.miss(Vector2(320, 711));
      expect(g.envelope, 0);
      g.update(.35);
      expect(g.envelope, closeTo(.55, 1e-9));
    });

    test('RunShake: kicks decay linearly, sustains hold', () {
      final s = RunShake(random: math.Random(1))..feverPass();
      expect(s.amplitude, 6);
      s.update(.1);
      expect(s.amplitude, closeTo(4, 1e-9));
      expect(s.offset.dx.abs(), lessThanOrEqualTo(4));
      s.update(.3);
      expect(s.amplitude, 0);
      expect(s.offset, Offset.zero);
      s.sustain = RunShake.squeezeClosing;
      s.update(.1);
      expect(s.amplitude, 2.2);
      expect(RunShake.squeezeWarning(.6), closeTo(2.6, 1e-9));
    });

    test('§5.14 fetch flight starts at the pickup, ends in the slot', () {
      final f = FetchFlight(
        from: const Offset(84, 400),
        to: const Offset(160, 230),
        art: (c, s, r) {},
      );
      expect(FetchSpec.feather.total, closeTo(.76, 1e-9));
      expect(f.at(0).$1, const Offset(84, 400));
      final end = f.at(FetchSpec.feather.total);
      expect(end.$1.dx, closeTo(160, 1e-9));
      expect(end.$1.dy, closeTo(230, 1e-9));
      expect(end.$2, closeTo(.82, 1e-9));
      expect(f.control.dx, 84 - 36);
    });

    test('§5.14 pickup touch: feather flash 8 → 30 in 0.22 s, ring 8 → 34', () {
      final fx = PickupTouchFx()..play(Offset.zero, PickupTouchSpec.feather);
      expect(fx.flashAt(0)!.$1, 8);
      expect(fx.flashAt(.11)!.$1, closeTo(19, 1e-9));
      expect(fx.flashAt(.22), isNull);
      expect(fx.ringAt(0)!.$1, 8);
      expect(fx.ringAt(.449)!.$1, closeTo(34, .05));
      expect(Ease.cubicInOut(.5), .5);
      final pool = ParticlePool();
      PickupTouchFx.emitSquares(pool, Offset.zero, PickupTouchSpec.puzzlePiece, math.Random(1));
      expect(pool.alive, 16);
    });

    test('§5.10 gold sticker: −4°, pops from 0.3 in 0.38 s', () {
      final s = GoldSticker.newBest();
      expect(s.popAt(0).$1, closeTo(.3, 1e-9));
      final (scale, rot, alpha) = s.popAt(.38);
      expect(scale, closeTo(1, 1e-6));
      expect(rot, closeTo(-4 * math.pi / 180, 1e-6));
      expect(alpha, 1);
    });

    testWithFlameGame('Q37 / Q42 collect slot: one at a time, waits for the banner', (
      game,
    ) async {
      final banners = BannerHost();
      final slot = CollectSlot(banners: banners);
      await game.ensureAddAll([banners, slot]);
      game.update(0);
      banners.showStreak(1);
      await game.ready();
      final a = _Item(2.15), b = _Item(2.15);
      slot.request(a);
      slot.request(b);
      expect(slot.current, isNull, reason: 'waits for the banner');
      _step(game, 1.2);
      expect(slot.current, a);
      expect(slot.waiting, 1);
      _step(game, 2.15 + .3);
      expect(a.gone, isTrue);
      expect(slot.current, b, reason: 'the second waits until the first faded');
      expect(slot.alphaAt(a, .1), closeTo(.5, 1e-9));
      expect(slot.alphaAt(a, 2.3), closeTo(.5, 1e-9));
      expect(CollectSlot.offsetFor(0), -10);
      expect(CollectSlot.offsetFor(1), 0);
    });
  });
}
