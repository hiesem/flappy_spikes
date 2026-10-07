import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/components/ui/bird_idle.dart';
import 'package:flappy_spikes/components/ui/coin_fly.dart';
import 'package:flappy_spikes/components/ui/live_effects.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart' hide escape;

import 'helpers.dart';
import 'shop_flow_test.dart' show openShop, shopTest;

/// PRD-menu-v2 §8: the live home & Shop (idle effects, GET, coin fly,
/// reduce motion, pause under popups).
void main() {
  group('LiveCurves timing (§8.1)', () {
    test('light streak sweeps -70 % -> 135 % in the first 28 % of 6.4 s', () {
      expect(LiveCurves.streak(0), closeTo(-0.7, 1e-4));
      // Half-way through the sweep (ease-in-out is symmetric).
      expect(LiveCurves.streak(6.4 * .14), closeTo(0.325, 1e-6));
      expect(LiveCurves.streak(6.4 * .28 + .01), isNull); // resting
      expect(LiveCurves.streak(6.0), isNull);
      // Next loop.
      expect(LiveCurves.streak(6.4), closeTo(-0.7, 1e-4));
      // Cascade delay: nothing before it, then the same sweep shifted.
      expect(LiveCurves.streak(0.5, delay: 0.7), isNull);
      expect(
        LiveCurves.streak(0.7 + 6.4 * .14, delay: 0.7),
        closeTo(0.325, 1e-6),
      );
    });

    test('pulse peaks at mid-loop of 3.2 s; camera nods -10° / +6°', () {
      expect(LiveCurves.pulse(0), 0);
      expect(LiveCurves.pulse(1.6), closeTo(1, 1e-4));
      expect(LiveCurves.pulse(0.8), closeTo(0.5, 1e-4));
      expect(LiveCurves.pulse(3.2), closeTo(0, 1e-4));
      expect(LiveCurves.cameraNod(1.0), 0); // before 40 %
      expect(LiveCurves.cameraNod(1.6), closeTo(-10, 1e-4));
      expect(LiveCurves.cameraNod(1.92), closeTo(6, 1e-4));
      expect(LiveCurves.cameraNod(3.1), closeTo(0, 0.1));
    });

    test('wobbles, wiggles and the glint hit their keyframes', () {
      final tag = LiveCurves.newTagWobble(4.4 * .78);
      expect(tag.scale, closeTo(1.14, 1e-4));
      expect(tag.degrees, closeTo(5, 1e-4));
      expect(LiveCurves.newTagWobble(4.4 * .86).degrees, closeTo(-3, 1e-4));
      expect(LiveCurves.newTagWobble(1).scale, 1);
      final pack = LiveCurves.packTagWiggle(6 * .86);
      expect(pack.scale, closeTo(1.07, 1e-4));
      expect(pack.degrees, closeTo(-2, 1e-4));
      expect(LiveCurves.packTagWiggle(6 * .92).degrees, closeTo(1, 1e-4));
      final trophy = LiveCurves.trophyWiggle(10 * .92);
      expect(trophy.degrees, closeTo(-8, 1e-4));
      expect(LiveCurves.trophyWiggle(10 * .96).degrees, closeTo(5, 1e-4));
      expect(LiveCurves.trophyWiggle(5).degrees, 0);
      expect(LiveCurves.glint(1).opacity, 0);
      expect(LiveCurves.glint(8.4 * .91).opacity, closeTo(1, 1e-4));
      expect(LiveCurves.glint(8.4 * .91).degrees, closeTo(45, 1e-4));
      expect(LiveCurves.glint(8.4 * .97).opacity, closeTo(0, 1e-4));
      expect(LiveCurves.packHop(0.175), closeTo(-4, 1e-4));
      expect(LiveCurves.packHop(0.4), 0);
    });
  });

  group('BirdIdle (§8.2)', () {
    test('random actions every 6–12 s after the first at 4.4 s', () {
      for (var seed = 0; seed < 20; seed++) {
        final bird = BirdIdle(random: math.Random(seed));
        final fired = <double>[];
        var t = 0.0;
        BirdIdleAction? seen;
        double? gap;
        while (t < 200) {
          bird.step(1 / 60);
          t += 1 / 60;
          if (!identical(bird.lastGap, gap)) {
            gap = bird.lastGap;
            fired.add(t);
            seen = bird.lastAction;
            expect(gap, inInclusiveRange(6, 12));
          }
        }
        expect(seen, isNotNull);
        expect(fired.first, closeTo(4.4, 1 / 60 + 1e-4));
        for (var i = 1; i < fired.length; i++) {
          expect(fired[i] - fired[i - 1], inInclusiveRange(6 - .02, 12 + .02));
        }
      }
    });

    test('tap hop: -204 pt/s kick, 700 pt/s² gravity, 7 squares', () {
      final bird = BirdIdle(random: math.Random(1));
      bird.hop(1.2, burst: true);
      expect(bird.velocity, -204);
      expect(bird.particles, hasLength(7));
      expect(bird.scaleX, closeTo(1.12, 1e-4)); // take-off stretch
      bird.step(0.1);
      expect(bird.velocity, closeTo(-204 + 70, 1e-4));
      // Airtime ≈ 2 * 204 / 700 = 0.58 s; then it lands with a squash.
      for (var i = 0; i < 60; i++) {
        bird.step(0.01);
      }
      expect(bird.airborne, isFalse);
      expect(bird.scaleX, lessThan(1));
      expect(bird.particles, isEmpty); // 0.5 s life
    });

    test('reduce motion: bob and flap only — no actions, no blinks', () {
      final bird = BirdIdle(random: math.Random(3));
      var flaps = 0;
      var bobbed = false;
      for (var i = 0; i < 60 * 40; i++) {
        bird.step(1 / 60, still: true);
        expect(bird.blinking, isFalse);
        if (bird.flap) flaps++;
        if (bird.offset.dy.abs() > 2) bobbed = true;
      }
      expect(bird.lastAction, isNull);
      expect(bobbed, isTrue);
      expect(flaps, greaterThan(0));
    });

    test('calm (featured) bird only leans or blinks', () {
      final bird = BirdIdle(random: math.Random(5), calm: true, firstAction: 8);
      final actions = <BirdIdleAction>{};
      for (var i = 0; i < 60 * 300; i++) {
        bird.step(1 / 60);
        final a = bird.lastAction;
        if (a != null) actions.add(a);
        expect(bird.airborne, isFalse);
      }
      expect(actions, {BirdIdleAction.lean, BirdIdleAction.blink});
    });
  });

  group('CoinFly', () {
    test('6 coins, 0.65 s each, 70 ms apart; onDone once after the last', () {
      var done = 0;
      final landed = <int>[];
      final fly = CoinFly(
        coin: Sprite(_onePixel),
        from: const ui.Rect.fromLTWH(186, 212, 112, 32),
        to: const ui.Offset(280, 68),
        random: math.Random(1),
        onLand: landed.add,
        onDone: () => done++,
      );
      expect(fly.totalDuration, closeTo(0.25 + 5 * 0.07 + 0.65, 1e-4));
      expect(fly.progressOf(0, 0.2), isNull);
      final start = fly.poseOf(0, 0);
      expect(start.opacity, 0);
      expect(start.scale, closeTo(0.6, 1e-4));
      final end = fly.poseOf(0, 1);
      expect(end.position, const ui.Offset(280, 68));
      expect(end.scale, closeTo(0.8, 1e-4));
      for (var i = 0; i < 100; i++) {
        fly.update(1 / 60);
      }
      expect(landed, [0, 1, 2, 3, 4, 5]);
      expect(done, 1);
    });
  });

  test(
    'LookPainter blink draws the eye closed (signature compatible)',
    () async {
      Future<List<int>> draw({bool blink = false}) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)..translate(22, 18);
        if (blink) {
          LookPainter.paint(canvas, Look.defaults, blink: true);
        } else {
          LookPainter.paint(canvas, Look.defaults);
        }
        final image = await recorder.endRecording().toImage(44, 36);
        final data = await image.toByteData();
        return data!.buffer.asUint8List();
      }

      final open = await draw();
      final closed = await draw(blink: true);
      expect(closed, isNot(equals(open)));
      // Eye centre (28, 12): white open, body colour when closed.
      int at(List<int> px, int x, int y) => px[(y * 44 + x) * 4];
      expect(at(open, 28, 11), 255);
      expect(at(closed, 28, 11), isNot(255));
    },
  );

  group('Home (§8.2)', () {
    shopTest(
      'slot pulses + streaks + nods; NEW tag and trophy wiggle; glint',
      prefs: const {'coins': 1250},
      verify: (game, spy, ads, iap, tester) async {
        final home = game.homeScreen!;
        stepGame(game, 1.6 - home.clock.t);
        final slot = home.slotButton;
        expect(slot.pulse.k, closeTo(1, 0.02));
        expect(slot.pulse.scale, closeTo(1.035, 0.001));
        expect(slot.cameraNod.angle, closeTo(-10 * math.pi / 180, 0.02));
        // 1.6 s: still sweeping (the sweep is the first 1.79 s) ...
        expect(slot.streak.progress, isNotNull);
        stepGame(game, 2.0 - home.clock.t);
        expect(slot.streak.progress, isNull); // ... then resting
        stepGame(game, 6.4 + .9 - home.clock.t);
        expect(slot.streak.progress, isNotNull);
        // NEW tag (hasNewBadge on a fresh install) at its pop.
        stepGame(game, 8.8 + 4.4 * .78 - home.clock.t);
        expect(home.skinsTile.tag, 'NEW');
        expect(home.skinsTile.tagWobble.scale, closeTo(1.14, 0.01));
        stepGame(game, 10 * .92 + 10 - home.clock.t);
        expect(
          home.trophyWiggle.angle,
          closeTo(-8 * math.pi / 180, 0.02),
        );
        // The pill's glint near its peak (8.4 s loop).
        stepGame(game, 8.4 * 3 + 8.4 * .91 - home.clock.t);
        expect(game.coinPill.glintOpacity, closeTo(1, 0.05));
      },
    );

    shopTest(
      'reduce motion: no pulse / streak / wobble / glint / bird action',
      verify: (game, spy, ads, iap, tester) async {
        game.reduceMotionOverride = true;
        final home = game.homeScreen!;
        for (var i = 0; i < 60 * 30; i++) {
          game.update(1 / 60);
          expect(home.slotButton.pulse.k, 0);
          expect(home.slotButton.streak.progress, isNull);
          expect(home.slotButton.cameraNod.isIdentity, isTrue);
          expect(home.skinsTile.tagWobble.isIdentity, isTrue);
          expect(home.trophyWiggle.isIdentity, isTrue);
          expect(game.coinPill.glintOpacity, 0);
          expect(home.bird.idle.blinking, isFalse);
        }
        expect(home.bird.idle.lastAction, isNull);
        // Bob still runs.
        expect(home.bird.idle.time, greaterThan(29));
      },
    );

    shopTest(
      'idle motion pauses while the No-ads popup is on top',
      verify: (game, spy, ads, iap, tester) async {
        final home = game.homeScreen!;
        stepGame(game, 1);
        game.openNoAdsPopup();
        await flushAndMount(game);
        expect(game.noAdsPopup, isNotNull);
        expect(game.liveMotionPaused, isTrue);
        final t = home.clock.t;
        final birdT = home.bird.idle.time;
        final glint = game.coinPill.glintOpacity;
        stepGame(game, 5);
        expect(home.clock.t, t);
        expect(home.bird.idle.time, birdT);
        expect(game.coinPill.glintOpacity, glint);
        game.closeNoAdsPopup();
        await flushAndMount(game);
        expect(game.liveMotionPaused, isFalse);
        stepGame(game, 1);
        expect(home.clock.t, closeTo(t + 1, 0.02));
      },
    );

    shopTest(
      'sounds: START flap + bird hop, gear sk_tab, tile sk_tap, slot bn_adbtn',
      verify: (game, spy, ads, iap, tester) async {
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        final home = game.homeScreen!;

        // Tap on the bird: hop + flap.mp3 + 7 squares.
        home.bird.onTapDown(_tapDown());
        expect(sounds, [Sfx.flap]);
        expect(home.bird.idle.velocity, -204);
        expect(home.bird.idle.particles, hasLength(7));
        // PRD-home-v3 §3.3: LEVELS opens 0.17 s later; back home.
        stepGame(game, 0.2);
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.levels);
        game.closeLevels();
        expect(sounds.last, Sfx.skClose);
        await flushAndMount(game);
        stepGame(game, 0.6);
        await flushAndMount(game);

        sounds.clear();
        game.openShop(sfx: Sfx.skTap); // the Shop tile's call
        expect(sounds, [Sfx.skTap]);
        await flushAndMount(game);
        stepGame(game, 0.6);
        sounds.clear();
        game.closeShop();
        expect(sounds, [Sfx.skClose]);
        await flushAndMount(game);
        stepGame(game, 0.6);
        await flushAndMount(game);

        sounds.clear();
        game.openSettings();
        expect(sounds, [Sfx.skTab]);
        game.closeSettings();
        await flushAndMount(game);
        stepGame(game, 0.6);
        await flushAndMount(game);

        sounds.clear();
        ads.mode = FakeAdMode.unavailable;
        await game.tapPowerupSlot();
        expect(sounds, [Sfx.bnAdBtn]);

        sounds.clear();
        final bird = game.homeScreen!.bird;
        await game.startRun();
        expect(sounds, [Sfx.flap]);
        expect(bird.idle.velocity, closeTo(-153, 1e-4));
        expect(game.state, GameState.playing);
      },
    );

    shopTest(
      'press: a button shrinks to 93 % in 0.1 s and the gear box follows',
      verify: (game, spy, ads, iap, tester) async {
        final home = game.homeScreen!;
        final tile = home.shopTile;
        tile.onTapDown(_tapDown());
        stepGame(game, 0.05, dt: 0.01);
        expect(tile.pressScale, closeTo(0.965, 0.001));
        stepGame(game, 0.06, dt: 0.01);
        expect(tile.pressScale, closeTo(0.93, 1e-4));
        tile.onTapCancel(TapCancelEvent(1));
        stepGame(game, 0.2);
        expect(tile.pressScale, 1);

        home.gearButton.onTapDown(_tapDown());
        stepGame(game, 0.2);
        expect(game.cornerBox.pressScale, closeTo(0.93, 1e-4));
      },
    );
  });

  group('Shop (§8.3)', () {
    shopTest(
      'GET: 112 x 32 bold chip that pulses to 105 % and nods',
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        final row = shop.freeCoins;
        expect(row.chipText, 'GET');
        expect(row.chip!.size, Vector2(112, 32));
        expect(row.chipLabel!.strokeWidth, Config.shopGetStroke);
        stepGame(game, 1.6 - shop.clock.t);
        expect(row.pulse.scale, closeTo(1.05, 0.002));
        expect(row.cameraNod.angle, closeTo(-10 * math.pi / 180, 0.02));
        // Mock rect: 8 pt from the row's right edge, centred.
        final rect = row.chipRect!;
        expect(rect.right, closeTo(306 - 8, 1e-6));
        expect(rect.top, closeTo(206 + (44 - 32) / 2, 1e-6));
      },
    );

    shopTest(
      'price streaks cascade 0 / 0.7 / 1.14 / 1.58 / 2.02 / 2.5 s; tags wiggle',
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        expect(shop.banner.streak.delay, 0);
        expect(shop.packs.map((p) => p.streak.delay), [0.7, 1.14, 1.58, 2.02]);
        expect(shop.featured.streak.delay, 2.5);
        // 6.4 s loops: at t = 6.4 + 0.75 the first two run, the rest wait.
        stepGame(game, 6.4 + 0.75 - shop.clock.t);
        expect(shop.banner.streak.progress, isNotNull);
        expect(shop.packs[0].streak.progress, isNotNull);
        expect(shop.packs[3].streak.progress, isNull);
        expect(shop.featured.streak.progress, isNull);
        stepGame(game, 6.4 + 2.6 - shop.clock.t);
        expect(shop.featured.streak.progress, isNotNull);
        // MOST POPULAR at its peak.
        stepGame(game, 12 + 6 * .86 - shop.clock.t);
        expect(shop.packs[1].tagWiggle.scale, closeTo(1.07, 0.01));
        expect(shop.packs[0].tagWiggle.isIdentity, isTrue); // no tag
      },
    );

    shopTest(
      'pack press: sk_tap and the coin stack hops 4 pt',
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        final pack = shop.packs[1];
        pack.onTapDown(_tapDown());
        stepGame(game, LiveCurves.packHopDuration / 2, dt: 0.0175);
        expect(pack.stackHop, closeTo(-4, 0.01));
        pack.onTapUp(_tapUp());
        expect(sounds.first, Sfx.skTap);
        await _settle(game, tester);
        stepGame(game, 0.5);
        expect(pack.stackHop, 0);
      },
    );

    shopTest(
      'GET reward: 6 coins fly in, the pill counts +40 in 0.4 s, sounds in order',
      prefs: const {'coins': 1250},
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        game.coinFlyRandom = math.Random(7);
        await game.claimFreeCoins();
        await flushAndMount(game);
        expect(game.menu.wallet.balance, 1290);
        final fly = game.coinFly!;
        expect(fly.count, 6);
        // The pill waits for the coins.
        stepGame(game, 0.5);
        expect(game.coinPill.shownBalance, 1250);
        expect(sounds, [Sfx.bnAdBtn]);
        stepGame(game, fly.totalDuration - 0.5 + 0.02);
        expect(fly.landed, 6);
        expect(game.coinFly, isNull);
        expect(sounds, [Sfx.bnAdBtn, Sfx.bnCoin]);
        // Coin pop and the 0.4 s count.
        stepGame(game, 0.15);
        expect(game.coinPill.coinScale, greaterThan(1.2));
        expect(game.coinPill.shownBalance, inExclusiveRange(1250, 1290));
        await flushAndMount(game);
        stepGame(game, 0.3);
        await flushAndMount(game);
        expect(game.coinPill.shownBalance, 1290);
        expect(game.coinPill.coinScale, 1);
        expect(sounds, [Sfx.bnAdBtn, Sfx.bnCoin, Sfx.skProgress]);
        expect(shop.freeCoins.chipText, '05:00');
      },
    );

    shopTest(
      'reduce motion: GET, streaks and tags rest',
      verify: (game, spy, ads, iap, tester) async {
        game.reduceMotionOverride = true;
        final shop = await openShop(game);
        for (var i = 0; i < 60 * 13; i++) {
          game.update(1 / 60);
          expect(shop.freeCoins.pulse.k, 0);
          expect(shop.freeCoins.cameraNod.isIdentity, isTrue);
          expect(shop.banner.streak.progress, isNull);
          for (final pack in shop.packs) {
            expect(pack.streak.progress, isNull);
            expect(pack.tagWiggle.isIdentity, isTrue);
          }
          expect(shop.featured.streak.progress, isNull);
        }
      },
    );

    shopTest(
      'back sk_close, Remove ads sk_dialog, featured sk_tap',
      verify: (game, spy, ads, iap, tester) async {
        final shop = await openShop(game);
        final sounds = <Sfx>[];
        game.sound.onPlay = sounds.add;
        unawaited(game.buyNoAds('shop_banner'));
        expect(sounds.first, Sfx.skDialog);
        await _settle(game, tester);
        // The No-ads celebration is up (PRD-home-v3 §7): collect it first.
        expect(game.noAdsCelebration, isNotNull);
        game.handleBack();
        await _settle(game, tester);
        sounds.clear();
        final item = shop.featured.item!;
        game.openFeaturedItem(item);
        expect(sounds, [Sfx.skTap]);
      },
    );
  });
}

/// Lets the fake store's zero-length round trip land (see
/// shop_flow_test.dart `settle`).
Future<void> _settle(FlappySpikesGame game, WidgetTester tester) async {
  for (var round = 0; round < 3; round++) {
    for (var i = 0; i < 20; i++) {
      await Future<void>.value();
    }
    await tester.binding.delayed(Duration.zero);
  }
  await flushAndMount(game);
}

TapDownEvent _tapDown() => TapDownEvent(1, _FakeGame(), TapDownDetails());

TapUpEvent _tapUp() =>
    TapUpEvent(1, _FakeGame(), TapUpDetails(kind: ui.PointerDeviceKind.touch));

class _FakeGame extends FlameGame {}

final ui.Image _onePixel = () {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
  return recorder.endRecording().toImageSync(1, 1);
}();
