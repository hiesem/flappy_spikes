import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-2d screenshot check (ARCH §7.1): the §5.7 HUD row (G1 solo / versus,
/// G2 extra life, G3 pause) and the §5.9 revive screen (ad, coins, locked,
/// no ad, phoenix ignite / burst) at 568 and 711. Compare by eye with
/// `design/menu_v2/game_versus_g1.png`, `game_versus_g2.png`,
/// `game_versus_pause.png` and `revive_v2_{ad,coin,lock,ignite,burst}.png`
/// (480 wide = 1.5×). Writes PNGs to `build/shots/run/revive_hud/` (never
/// committed).
const String outDir = 'build/shots/run/revive_hud';

Future<void> _fonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  await Future.wait([lvdc.load(), opificio.load(), fredoka.load()]);
}

/// Same render path as `captureShot` (menu_screenshot_test.dart): resize
/// right before rendering (the harness reverts earlier resizes).
Future<void> shot(FlappySpikesGame game, double scale, String name) async {
  final size = Vector2(320 * scale, (game.viewHeight * scale).roundToDouble());
  game.onGameResize(size);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.x, size.y),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  final image = await recorder.endRecording().toImage(
    size.x.toInt(),
    size.y.toInt(),
  );
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  final file = File('$outDir/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  debugPrint('SHOT ${file.path}: ${bytes.length} bytes');
  expect(bytes.length, greaterThan(10000));
}

void main() {
  setUpAll(_fonts);

  void hold(FlappySpikesGame g, double seconds, double y) {
    for (var t = 0.0; t < seconds; t += 1 / 60) {
      if (g.state == GameState.playing) g.runBird!.setFlight(y: y, vy: 0);
      g.update(1 / 60);
    }
  }

  void step(FlappySpikesGame g, double seconds) {
    for (var t = 0.0; t < seconds - 1e-9; t += 1 / 60) {
      g.update(1 / 60);
    }
  }

  Future<void> die(FlappySpikesGame g) async {
    final run = g.run!;
    for (var i = 0; i < 26 - run.state.hoopsPassed; i++) {
      run.debugPass(perfect: i.isEven);
    }
    run.state.invulnerable = 0;
    killRun(g);
    await flushAndMount(g);
    step(g, .6);
    await flushAndMount(g);
  }

  OpponentRun molly() => OpponentRun(
    uid: 'm',
    name: 'Molly',
    score: 31,
    best: 31,
    level: 4,
    timeline: RunTimeline()
      ..addPoint(.1)
      ..addPoint(.2)
      ..end(60),
  );

  for (final h in [568.0, 711.0]) {
    final tag = h.round();

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: h,
        versus: FakeVersusService(pool: [molly()]),
      ),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.7 HUD G1 versus / G2 extra life / G3 pause at $tag',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (game, tester) async {
        final run = await startRun(game);
        hold(game, 1.2, h / 2 + 40);
        run.state.hearts = 2;
        await flushAndMount(game);
        await tester.runAsync(() => shot(game, 1.5, 'hud_g1_versus_$tag'));
        run.state
          ..hearts = 0
          ..extraLife = true;
        hold(game, .5, h / 2 + 40);
        await tester.runAsync(() => shot(game, 1.5, 'hud_g2_extra_$tag'));
        run.state.extraLife = false;
        game.pause();
        await flushAndMount(game);
        step(game, .3);
        await tester.runAsync(() => shot(game, 1.5, 'hud_g3_pause_$tag'));
        game.openRunSettings();
        await flushAndMount(game);
        step(game, .4);
        await flushAndMount(game);
        await tester.runAsync(() => shot(game, 1.5, 'pause_settings_$tag'));
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.7 solo HUD at $tag',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (game, tester) async {
        final run = await startRun(game);
        hold(game, 1.2, h / 2 + 40);
        run.state.hearts = 1;
        await flushAndMount(game);
        await tester.runAsync(() => shot(game, 1.5, 'hud_solo_$tag'));
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, prefs: const {'coins': 1253}),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.9 revive: ad heart, then the phoenix (ignite, burst) at $tag',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (game, tester) async {
        await startRun(game);
        hold(game, 1.5, h / 2);
        await die(game);
        final screen = game.reviveScreen!;
        await tester.runAsync(() => shot(game, 1.5, 'revive_ad_$tag'));
        screen.tapHeart();
        for (var i = 0; i < 40 && screen.phoenix == null; i++) {
          game.update(1 / 60);
          await flushAndMount(game);
        }
        await flushAndMount(game);
        step(game, .45);
        await tester.runAsync(() => shot(game, 1.5, 'revive_ignite_$tag'));
        step(game, .3);
        await tester.runAsync(() => shot(game, 1.5, 'revive_rise_$tag'));
        step(game, .3);
        await tester.runAsync(() => shot(game, 1.5, 'revive_burst_$tag'));
      },
    );

    for (final (name, coins, adStep) in [
      ('coin', 1253, false),
      ('lock', 180, false),
      ('noad', 1253, true),
    ]) {
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: h, prefs: {'coins': coins}),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        '§5.9 revive: $name heart at $tag',
        setUp: (g, _) async {
          if (adStep) {
            (g.monetization.ads as FakeRewardedAds).mode =
                FakeAdMode.unavailable;
          }
          await g.ready();
          await preloadImages(g);
        },
        verify: (game, tester) async {
          final run = await startRun(game);
          hold(game, 1.5, h / 2);
          if (!adStep) run.state.adStepAvailableThisGame = false;
          await die(game);
          // The mock's balances (passes earn coins).
          final w = game.menu.wallet;
          await w.spend(w.balance - coins, 'test');
          step(game, .1);
          await tester.runAsync(() => shot(game, 1.5, 'revive_${name}_$tag'));
          if (name == 'lock') {
            game.reviveScreen!.tapGetCoins();
            await flushAndMount(game);
            step(game, .5);
            await flushAndMount(game);
            await tester.runAsync(() => shot(game, 1.5, 'revive_shop_$tag'));
          }
          if (name == 'coin') {
            game.reviveScreen!.tapHeart();
            await flushAndMount(game);
            step(game, .35);
            await tester.runAsync(() => shot(game, 1.5, 'revive_pay_$tag'));
          }
        },
      );
    }
  }
}
