import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Renders the 2.0 menu screens to `build/menu_shots/` for pixel comparison
/// against the approved mocks in `design/menu_v2/` (home_v2_a.png /
/// home_v2_b.png are 480 x 1067 = 1.5x of 320 x 711).
///
/// Mock state: balance 1 250, best 12, games 34, NEW badge on Skins (an
/// affordable, unseen skin). Same render path as
/// screenshot_generator_test.dart (game.render into a PictureRecorder).
Future<void> loadFonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  await Future.wait([lvdc.load(), opificio.load()]);
}

const String outDir = 'build/menu_shots';

/// Renders the current frame at [scale] x the 320 pt wide world and
/// writes it as a PNG. Must run inside tester.runAsync.
Future<void> captureShot(
  FlappySpikesGame game,
  double scale,
  String name,
) async {
  final shotSize = Vector2(
    320 * scale,
    (game.viewHeight * scale).roundToDouble(),
  );
  // Resize right before rendering: the harness reverts earlier resizes.
  game.onGameResize(shotSize);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, shotSize.x, shotSize.y),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  final image = await recorder.endRecording().toImage(
    shotSize.x.toInt(),
    shotSize.y.toInt(),
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


const Map<String, Object> mockPrefs = {
  'bestScore': 12,
  'gamesPlayed': 34,
  'claimedLevels': ['1'], // no LEVEL UP popup over the captures
  'coins': 1250,
};

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  Future<void> capture(FlappySpikesGame game, double scale, String name) =>
      captureShot(game, scale, name);

  void homeShot(
    String name, {
    required double height,
    required Powerup slot,
    List<double> scales = const [1.5, 2],
    Map<String, Object> prefs = const {},
  }) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame({...mockPrefs, ...prefs}, height),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      'menu screenshot: $name',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        game.menu.slot.debugForce = slot;
        game.menu.slot.rollForArrival();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        expect(game.state, GameState.start);
        expect(game.menu.items.hasNewBadge, isTrue);
        final home = game.homeScreen!;
        expect(home.slotButton.shown, slot);
        for (final scale in scales) {
          final suffix = scale == 2 ? '' : '@${scale}x';
          await tester.runAsync(() => capture(game, scale, '$name$suffix'));
        }
      },
    );
  }

  homeShot('home_711_bighoops', height: 711, slot: Powerup.bigHoops);
  homeShot('home_711_shield', height: 711, slot: Powerup.shield);
  homeShot('home_568', height: 568, slot: Powerup.bigHoops);
  // No-ads owner: check in the tile's icon slot, "AD-FREE" label, dimmed.
  homeShot(
    'home_711_noads_owned',
    height: 711,
    slot: Powerup.bigHoops,
    scales: const [1.5],
    prefs: const {'noAds': true},
  );

  // Shop (S1-B) at 711: mock balance; the featured item is the first
  // unowned item of the 2.0 update (Lemonade, 150). Placeholder store
  // prices.
  FlameTester<FlappySpikesGame>(
    () => createTestGame(mockPrefs, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'menu screenshot: shop_711',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.openShop();
      await flushAndMount(game);
      // Home fades out, Shop fades in.
      stepGame(game, Config.uiFadeDuration + 0.1);
      await flushAndMount(game);
      expect(game.shopScreen, isNotNull);
      expect(game.homeScreen, isNull);
      await tester.runAsync(() => capture(game, 1.5, 'shop_711'));
      await tester.runAsync(() => capture(game, 2, 'shop_711@2x'));
    },
  );

  // Shop banner for a No-ads owner: check in the icon slot, "AD-FREE".
  FlameTester<FlappySpikesGame>(
    () => createTestGame({...mockPrefs, 'noAds': true}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'menu screenshot: shop_711_noads_owned',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.openShop();
      await flushAndMount(game);
      stepGame(game, Config.uiFadeDuration + 0.1);
      await flushAndMount(game);
      expect(game.shopScreen!.banner.owned, isTrue);
      await tester.runAsync(
        () => capture(game, 1.5, 'shop_711_noads_owned@1.5x'),
      );
    },
  );

  // The skin shop is captured by skin_shop_screenshot_test.dart.

  // No-ads popup (P1) over the home screen at 711.
  FlameTester<FlappySpikesGame>(
    () => createTestGame(mockPrefs, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'menu screenshot: popup_711',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.openNoAdsPopup();
      await flushAndMount(game);
      stepGame(game, 0.3);
      await flushAndMount(game);
      expect(game.noAdsPopup, isNotNull);
      await tester.runAsync(() => capture(game, 1.5, 'popup_711'));
      await tester.runAsync(() => capture(game, 2, 'popup_711@2x'));
    },
  );

  // Shop at 568, scrolled to the end (restore link).
  FlameTester<FlappySpikesGame>(
    () => createTestGame(mockPrefs, 568),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'menu screenshot: shop_568',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.openShop();
      await flushAndMount(game);
      stepGame(game, 0.6);
      await flushAndMount(game);
      await tester.runAsync(() => capture(game, 1.5, 'shop_568_top'));
      final scroll = game.shopScreen!.scroll;
      scroll.offset = scroll.maxOffset;
      await tester.runAsync(() => capture(game, 1.5, 'shop_568_end'));
    },
  );

  // Game-over panel with the interim "+N" coin line (1.0 panel geometry).
  FlameTester<FlappySpikesGame>(
    () => createTestGame(mockPrefs, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'menu screenshot: gameover_coins_711',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.onScreenTap();
      stepGame(game, 0.2, flapBelow: 340);
      game.score = 9;
      game.onBirdHit();
      await flushAndMount(game);
      stepGame(game, 1.2);
      await tester.runAsync(() => capture(game, 1.5, 'gameover_coins_711'));
    },
  );
}
