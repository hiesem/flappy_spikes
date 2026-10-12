import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/piggy_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/effects/hud_fetch.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/pickups/piggy_coin.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Records the destination rects of `drawImageRect` (the coin icon).
class _SpyCanvas implements Canvas {
  final List<Rect> images = [];

  @override
  void drawImageRect(Image image, Rect src, Rect dst, Paint paint) =>
      images.add(dst);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// PRD-2.2 §26 Piggy Bank coins 2× bigger: 16 pt coins, catch radius 14,
/// coins 45 pt apart (mock B), the fly-in leaves at 16 pt.
void main() {
  test('§26 coin 16 pt, catch radius 14 (the miss rule uses it too); spin, '
      'bulge 18, 4 per gap and the 0.35 s fly-in unchanged', () {
    expect(PiggyConfig.coinSize, 16);
    expect(PickupRadii.piggyCoin, 14);
    expect(PickupRadii.forElement(ElementId.piggyCoins), 14);
    expect(PiggyConfig.coinBulge, 18);
    expect(PiggyConfig.coinSpinRate, 4);
    expect(PiggyConfig.coinSpinPhase, .05);
    expect(RunConfig.piggyCoinsPerGap, 4);
    expect(CoinFetch.coinLife, .35);
    expect(PiggyConfig.fetchSeconds, .35);
    // The fly-in leaves at 16 pt and shrinks into the HUD piggy.
    expect(CoinFetch.coinSizeAt(0), 16);
    expect(CoinFetch.coinSizeAt(.5), lessThan(16));
    expect(CoinFetch.coinSizeAt(1), closeTo(16 * .4, 1e-9));
  });

  test('§26 follow-gap fields unchanged: 4 coins over (4 − 1) × 45 pt', () {
    final d = RunDirector(
      seed: 7,
      enabled: ElementId.values.toSet(),
      met: ElementId.values.toSet(),
      startHoopIndex: 30,
    );
    final fields = <GapItemPlan>[];
    for (var k = 0; k < 8; k++) {
      final ctx = DirectorContext.open(711, piggyRunning: true);
      final s = d.nextSlot(ctx);
      fields.addAll(
        d.nextGap(ctx, s).items.where((i) => i.kind == ElementId.piggyCoins),
      );
    }
    expect(fields, hasLength(4));
    for (final f in fields) {
      expect(f.extra, 4);
      expect(f.toTrackX! - f.trackX, closeTo(3 * 45, 1e-9));
    }
  });

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 11),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§26 a piggy coin paints at 16 pt; caught at a bird-edge distance of 14 '
    'pt, not at 15; coins 45 pt apart; the caught coin flies in from 16 pt',
    setUp: (g, _) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      run.events.emit(PickupCollected(ElementId.piggy, null));
      expect(run.state.piggy, isNotNull);
      final bird = run.birdTrackPosition()!;
      final x0 = bird.x + 200, y0 = bird.y;
      run.spawner.spawnItem(
        GapItemPlan(
          kind: ElementId.piggyCoins,
          trackX: x0,
          toTrackX: x0 + 135,
          y: y0,
          toY: y0,
          extra: 4,
        ),
      );
      await flushAndMount(game);
      final field = pickupsOf(game).whereType<PiggyCoin>().single;

      // 45 pt steps (approved mock B) across the 3 × 45 pt field, bulge 18
      // at u = (i + 1) / 5 (mock `-sin(u·π)·18`).
      for (var i = 0; i < 4; i++) {
        final u = (i + 1) / 5;
        final p = field.coinAt(i);
        expect(p.dx, closeTo(x0 + 45.0 * i, 1e-9));
        expect(p.dy, closeTo(y0 - 18 * math.sin(math.pi * u), 1e-9));
      }
      for (var i = 1; i < 4; i++) {
        expect(field.coinAt(i).dx - field.coinAt(i - 1).dx, closeTo(45, 1e-9));
      }

      // Paints at 16 pt.
      final spy = _SpyCanvas();
      field.render(spy);
      expect(spy.images, hasLength(4));
      for (final r in spy.images) {
        expect(r.width, 16);
        expect(r.height, 16);
      }

      // The catch: bird edge 15 pt away misses, 14 pt catches.
      const r = RunConfig.birdRadius;
      final c0 = field.coinAt(0);
      expect(field.touches(Vector2(c0.dx - r - 15, c0.dy), r), isFalse);
      expect(field.touches(Vector2(c0.dx - r - 14, c0.dy), r), isTrue);
      expect(field.lastCollectedAt, c0);

      // The caught coin flies into the HUD piggy, leaving at 16 pt.
      field.onCollect(run.ctx);
      run.events.emit(PickupCollected(ElementId.piggyCoins, field));
      await flushAndMount(game);
      final fetch = game.world.children.whereType<CoinFetch>().single;
      final fs = _SpyCanvas();
      fetch.render(fs);
      expect(fs.images.single.width, 16);
    },
  );
}
