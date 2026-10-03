import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
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
