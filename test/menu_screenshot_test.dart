import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/menu/skin_catalog.dart';
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

const Map<String, Object> mockPrefs = {
  'bestScore': 12,
  'gamesPlayed': 34,
  'coins': 1250,
};

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  /// Renders the current frame at [scale] x the 320 pt wide world and
  /// writes it as a PNG. Must run inside tester.runAsync.
  Future<void> capture(
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

  void homeShot(
    String name, {
    required double height,
    required Powerup slot,
    List<double> scales = const [1.5, 2],
  }) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame(mockPrefs, height),
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
        expect(game.menu.skins.hasNewBadge, isTrue);
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

  // Shop (S1-B) at 711: mock balance; pink/blue/green owned so the
  // featured skin is GRAPE as in the mock (its catalogue price is 200, the
  // mock shows 300). Placeholder store prices.
  FlameTester<FlappySpikesGame>(
    () => createTestGame({
      ...mockPrefs,
      'ownedSkins': ['pink', 'blue', 'green'],
    }, 711),
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
      stepGame(game, 0.6); // home fades out, Shop fades in
      await flushAndMount(game);
      expect(game.shopScreen, isNotNull);
      expect(game.homeScreen, isNull);
      await tester.runAsync(() => capture(game, 1.5, 'shop_711'));
      await tester.runAsync(() => capture(game, 2, 'shop_711@2x'));
    },
  );

  // Skins (K1) at 711 in the mock's state: balance 1 250; pink (equipped),
  // blue, green, purple and tophat owned, purple and tophat tagged NEW. NEW
  // marks skins that were affordable and unseen when the screen opened, so
  // purple / tophat start locked-but-new and are bought on the open screen
  // (2 050 - 200 - 600 = 1 250), then pink is re-equipped.
  FlameTester<FlappySpikesGame>(
    () => createTestGame({
      ...mockPrefs,
      'coins': 2050,
      'ownedSkins': ['pink', 'blue', 'green'],
      'seenSkins': [
        for (final skin in kSkins)
          if (skin.id != 'purple' && skin.id != 'tophat') skin.id,
      ],
    }, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'menu screenshot: skins_711',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      game.openSkins();
      await flushAndMount(game);
      stepGame(game, 0.6);
      await flushAndMount(game);
      final skins = game.menu.skins;
      expect(await skins.purchase('purple'), SkinPurchaseResult.purchased);
      expect(await skins.purchase('tophat'), SkinPurchaseResult.purchased);
      await skins.equip('pink');
      game.update(0);
      await flushAndMount(game);
      expect(game.menu.wallet.balance, 1250);
      final screen = game.skinsScreen!;
      expect(
        [
          for (final t in screen.tiles)
            if (t.isNew) t.skin.id,
        ],
        ['purple', 'tophat'],
      );
      await tester.runAsync(() => capture(game, 1.5, 'skins_711'));
      await tester.runAsync(() => capture(game, 2, 'skins_711@2x'));
    },
  );

  // Skin unlock dialogs over the Skins screen at 711: affordable (GRAPE)
  // and short (KING at 1 000 with 250 coins).
  for (final (name, coins, skin) in [
    ('skins_dialog_711', 1250, 'purple'),
    ('skins_dialog_short_711', 250, 'crown'),
  ]) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame({...mockPrefs, 'coins': coins}, 711),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'menu screenshot: $name',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        game.openSkins();
        await flushAndMount(game);
        stepGame(game, 0.6);
        await flushAndMount(game);
        game.tapSkin(skin);
        await flushAndMount(game);
        stepGame(game, 0.3);
        await flushAndMount(game);
        expect(game.skinDialog, isNotNull);
        await tester.runAsync(() => capture(game, 1.5, name));
      },
    );
  }

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
      game.openNoAdsPopup('home_tile');
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
