import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/run/config/results_config.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

/// PRD-2.2 §31.5: the balloon bonus and results pages always use the first
/// stage's palette (#F1F1F1 background, #828282 foreground) whatever stage
/// the run ended on; the run's squeezed walls never cover them; the LEVEL UP
/// rays are ≈ 280 pt long, unclipped and fade radially. Frame captures go to
/// `build/menu_shots/p22/s31/` (never committed).
const double _scale = 2; // device px per point

/// Stage index 6 (hoops 60–69) is the cyan stage 30 (PRD-2 §3.0.1).
const int _cyanStageHoops = 60;

/// Straight RGBA of the current frame at [_scale] (the shots' render path).
Future<Uint8List> _frame(FlappySpikesGame game) async {
  final size = Vector2(
    Config.worldWidth * _scale,
    (game.viewHeight * _scale).roundToDouble(),
  );
  // Resize right before rendering: the harness reverts earlier resizes.
  game.onGameResize(size);
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.x, size.y),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  final image = await rec.endRecording().toImage(
    size.x.toInt(),
    size.y.toInt(),
  );
  final raw = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  return raw!.buffer.asUint8List();
}

/// The colour of the frame at world point ([x], [y]) (pt, top-left origin).
ui.Color _pixel(Uint8List px, double x, double y) {
  final w = (Config.worldWidth * _scale).round();
  final i = ((y * _scale).round() * w + (x * _scale).round()) * 4;
  return ui.Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]);
}

/// Drives the run to the cyan stage 30 (60 hoops), then dies, declines the
/// revive offer and waits for the results page.
Future<ResultsScreen> _endOnCyan(FlappySpikesGame game) async {
  final run = await startRun(game);
  for (var i = 0; i < _cyanStageHoops; i++) {
    run.debugPass();
  }
  await stepSeconds(game, .6); // past the colour crossfade
  await flushAndMount(game);
  killRunThroughSaves(game);
  await declineRevive(game);
  await flushAndMount(game);
  expect(game.state, GameState.results);
  await stepSeconds(game, 1); // the page fades in on its own clock
  return game.resultsScreen!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('§31.1 the approved grey', () {
    test('the page palette is the first stage (#F1F1F1 / #828282)', () {
      expect(kPostRunPalette.background, const ui.Color(0xFFF1F1F1));
      expect(kPostRunPalette.foreground, const ui.Color(0xFF828282));
      expect(kPostRunPalette, kPalettes[0]);
    });

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'a run ending on stage 30 (cyan): the results page paints #F1F1F1 and '
      'its strip #828282, not the stage colours; the next run is back on '
      'its stage colours',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await loadFonts();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        await tester.runAsync(() async {
          final page = await _endOnCyan(game);
          expect(game.stageKey, 30);
          expect(game.foregroundColor, isNot(kPostRunPalette.foreground));
          expect(game.postRunPageUp, isTrue);

          // No ray is up here (the LEVEL UP rays are checked separately).
          page.stage.rays = 0;
          final frame = await _frame(game);
          expect(
            _pixel(frame, 2, 300),
            kPostRunPalette.background,
            reason: 'page background',
          );
          expect(
            _pixel(frame, 5, 5),
            kPostRunPalette.foreground,
            reason: 'top strip in the approved grey',
          );

          game.replay();
          await stepSeconds(game, .5);
          await flushAndMount(game);
          expect(game.postRunPageUp, isFalse);
          expect(game.stageKey, 0);
          expect(game.foregroundColor, kPalettes[0]!.foreground);
        });
      },
    );
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'the empty banner strip under the page is the page grey (#828282) on '
      'stage 30, and returns to the stage colour on the next home arrival',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await loadFonts();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        await tester.runAsync(() async {
          await _endOnCyan(game);
          expect(game.postRunPageUp, isTrue, reason: 'page flag');
          expect(
            game.bannerStripColor.value,
            kPostRunPalette.foreground,
            reason: 'the banner strip follows the page',
          );
          game.replay();
          await stepSeconds(game, .5);
          await flushAndMount(game);
          expect(game.bannerStripColor.value, kPalettes[0]!.foreground);
        });
      },
    );
  });

  group('§31.2 squeeze walls never cover the pages', () {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'a death during a squeeze: the page strips draw their normal reach, '
      'no squeezed wall overlaps the page; the revive UI is in the viewport '
      'above the walls',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await loadFonts();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(game);
          // A squeezed wall (the run's own squeeze inset) on the bird's way.
          run.state.squeeze.inset = 40;
          await flushAndMount(game);
          stepGame(game, .2);
          final strips = game.world.children.query<SpikeStrip>().toList();
          expect(strips, hasLength(2));
          expect(game.state, GameState.playing);
          expect(
            strips.every((s) => s.squeezedReach == s.toothReach + 40),
            isTrue,
            reason: 'the walls are squeezed while the run is on',
          );

          killRunThroughSaves(game);
          await flushAndMount(game);
          // The revive offer, if any, comes first; decline it.
          if (game.state == GameState.reviving) {
            await declineRevive(game);
            await flushAndMount(game);
          }
          await stepSeconds(game, 1); // the page fades in
          expect(game.state, GameState.results);
          for (final s in strips) {
            expect(s.onPage, isTrue);
            expect(
              s.squeezedReach,
              s.toothReach,
              reason: 'no squeeze on the page',
            );
          }
        });
      },
    );
  });

  group('§31.3 level-up rays', () {
    test('≈ 280 pt, a radial fade: 35 % at the emblem, 19 % at 45 %, 0 at '
        'the tip', () {
      expect(ResultsConfig.rayRadius, 280);
      expect(ResultsConfig.rayAlpha, closeTo(.35, 1e-12));
      expect(ResultsConfig.rayAlphaMid, closeTo(.19, 1e-12));
      expect(ResultsConfig.rayFadeMid, closeTo(.45, 1e-12));
      expect(ResultsScreen.rayFade(0), closeTo(1, 1e-12));
      expect(
        ResultsScreen.rayFade(ResultsConfig.rayFadeMid),
        closeTo(ResultsConfig.rayAlphaMid / ResultsConfig.rayAlpha, 1e-12),
      );
      expect(ResultsScreen.rayFade(1), 0);
      expect(ResultsScreen.rayFade(1.2), 0, reason: 'nothing past the tip');
    });

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'the rays are drawn by the page, not clipped to the stage rectangle, '
      'and reach past it',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await loadFonts();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        await tester.runAsync(() async {
          final page = await _endOnCyan(game);
          page.stage.rays = 1;
          // A ring 200 pt from the plate centre (past the old 150 pt rays,
          // and above the stage rectangle): the wedges reach it.
          final k = ResultsConfig.scaleFor(game.viewHeight);
          final centre = page.content.position.toOffset() +
              ResultsConfig.plateCentre * k;
          final frame = await _frame(game);
          final bg = kPostRunPalette.background;
          var tinted = 0;
          var outsideStage = 0;
          for (var a = 0; a < 36; a++) {
            final angle = a * 2 * 3.14159265 / 36;
            final p = centre + ui.Offset.fromDirection(angle, 200 * k);
            final stageTop = (page.content.position.y +
                ResultsConfig.stage.top * k);
            final stageBottom = (page.content.position.y +
                ResultsConfig.stage.bottom * k);
            if (p.dy < stageTop || p.dy > stageBottom) outsideStage++;
            final c = _pixel(frame, p.dx, p.dy);
            if (c != bg) tinted++;
          }
          expect(outsideStage, greaterThan(0));
          expect(tinted, greaterThan(4), reason: 'the rays reach 200 pt');
          await captureShot(game, 2, 'p22/s31/results_rays_711');
        });
      },
    );
  });
}
