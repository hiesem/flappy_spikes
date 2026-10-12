import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show loadFonts, mockPrefs;

/// PRD-2.2 §7.5.4 / §7.12: renders the run with the lowered bottom strip at
/// the visible heights a banner leaves (663 / 596 / 524) — play, revive,
/// bonus and results — to `build/p22_banner_shots/` for comparison with the
/// approved mock frames `design/menu_v2/run_banner/*_{663,596,524}.png`
/// (960 px wide = 3× the 320 pt world). Each frame is the game view only
/// (the mock's frames too); `*_strip.png` adds the slot under it (the empty
/// strip grey + a 320 × 50 white test banner) as the app shell draws it.
const String _outDir = 'build/p22_banner_shots';
const double _scale = 3;

Future<void> _shot(FlappySpikesGame g, String name, {double? banner}) async {
  final visible = g.visibleHeight;
  final gameSize = Vector2(320 * _scale, (visible * _scale).roundToDouble());
  g.onGameResize(gameSize);
  final extra = banner == null ? 0.0 : (banner * _scale).roundToDouble();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, gameSize.x, gameSize.y),
    ui.Paint()..color = g.backgroundColor(),
  );
  g.render(canvas);
  if (banner != null) {
    final top = gameSize.y;
    canvas.drawRect(
      ui.Rect.fromLTWH(0, top, gameSize.x, extra),
      ui.Paint()..color = g.bannerStripColor.value,
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(
        (gameSize.x - 320 * _scale) / 2,
        top + (extra - 50 * _scale) / 2,
        320 * _scale,
        50 * _scale,
      ),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
  }
  final image = await recorder.endRecording().toImage(
    gameSize.x.toInt(),
    (gameSize.y + extra).toInt(),
  );
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  final file = File('$_outDir/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  debugPrint('SHOT ${file.path}');
}

void main() {
  for (final (screen, banner) in const [(711.0, 48.0), (640.0, 44.0), (568.0, 44.0)]) {
    final tag = (screen - banner).round();
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {...mockPrefs, 'feathers': 3},
        worldHeight: screen,
        monetization: Monetization(
          banner: FakeBannerAds(enabled: true, heightDp: banner, widthDp: 320),
        ),
      ),
      gameSize: Vector2(320, screen - banner),
    ).testGameWidget(
      '§7.5.4 banner strip shots at $tag',
      setUp: (g, tester) async {
        await loadFonts();
        await g.ready();
        await preloadImages(g);
        await flushAndMount(g);
      },
      verify: (g, tester) async {
        final run = await startRun(g);
        await flyRun(g, maxSeconds: 6, untilHoops: 3);
        await tester.runAsync(() => _shot(g, 'play_$tag'));
        await tester.runAsync(() => _shot(g, 'play_${tag}_strip', banner: banner));
        run.state.invulnerable = 0;
        for (var i = 0; i < 8; i++) {
          run.debugPass(perfect: true);
        }
        killRun(g);
        await flushAndMount(g);
        stepGame(g, 1.5);
        await flushAndMount(g);
        await tester.runAsync(() => _shot(g, 'revive_$tag'));
        await tester.runAsync(
          () => _shot(g, 'revive_${tag}_strip', banner: banner),
        );
        await declineRevive(g);
        stepGame(g, 1.5);
        await flushAndMount(g);
        await tester.runAsync(() => _shot(g, 'bonus_$tag'));
        final b = g.bonusScreen!;
        for (final i in [0, 1, 2]) {
          b.tapTile(i);
          stepGame(g, 1.2);
          await flushAndMount(g);
        }
        for (var i = 0; i < 600 && !b.noThanksShown; i++) {
          g.update(1 / 60);
        }
        b.tapNoThanks();
        await flushAndMount(g);
        stepGame(g, 4);
        await flushAndMount(g);
        await tester.runAsync(() => _shot(g, 'results_$tag'));
        await tester.runAsync(
          () => _shot(g, 'results_${tag}_strip', banner: banner),
        );
        expect(g.state, GameState.results);
      },
    );
  }
}
