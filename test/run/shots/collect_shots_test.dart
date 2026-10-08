import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/collect_layer.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/screens/bonus_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-4a screenshot check (ARCH §7.1): the golden feather (§5.14: in the
/// field, the fetch into the tray, the 3rd feather's set-complete), the
/// puzzle piece (§5.15: field, fetch, 4/4 + coin badge) and the balloon
/// bonus screen (§5.14: start, pop, the ad offer, NEXT after 6 pops).
/// Compare with `design/menu_v2/feather_*.png`, `puzzle_*.png` and
/// `balloon_*.png`. Writes PNGs to `build/shots/run/collect/` (never
/// committed); nothing is asserted beyond "rendered".
const String outDir = 'build/shots/run/collect';

Future<void> _fonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  await Future.wait([lvdc.load(), opificio.load(), fredoka.load()]);
}

Future<void> _shot(FlappySpikesGame game, double scale, String name) async {
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

Future<void> _untilSlot(FlappySpikesGame g, double t) async {
  final layer = CollectLayer.of(g.run!)!;
  for (var i = 0; i < 600 && (layer.slot.current == null || layer.slot.time < t); i++) {
    g.update(1 / 60);
    if (i % 10 == 9) await flushAndMount(g);
  }
}

void main() {
  setUpAll(_fonts);

  for (final h in [711.0, 568.0]) {
    final tag = h.round();
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, seed: 5, prefs: {'feathers': 1}),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.14 feather field / fetch ($tag)',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        game.runDebug.god = true;
        final run = await startRun(
          game,
          startHoopIndex: ElementId.feather.firstPossible!,
          force: [ElementId.feather],
        );
        await flyUntil(game, (r) {
          return r.spawner.pickups.any(
            (p) => p.id == ElementId.feather && p.position.x - r.state.camX < 230,
          );
        });
        await tester.runAsync(() => _shot(game, 2, 'feather_field_$tag'));
        final p = await collectPickup(game, ElementId.feather, reforce: false);
        expect(p, isNotNull);
        await _untilSlot(game, .5);
        await tester.runAsync(() => _shot(game, 2, 'feather_fly_$tag'));
        expect(run.state.featherSpawned, isTrue);
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, seed: 5, prefs: {'feathers': 2}),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.14 feather set complete ($tag)',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        game.runDebug.god = true;
        await startRun(
          game,
          startHoopIndex: ElementId.feather.firstPossible!,
          force: [ElementId.feather],
        );
        final p = await collectPickup(game, ElementId.feather, reforce: false);
        expect(p, isNotNull);
        await _untilSlot(game, 1.45);
        await tester.runAsync(() => _shot(game, 2, 'feather_complete_$tag'));
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: h,
        seed: 5,
        prefs: {'puzzlePieces': 1, 'puzzleRound': 1},
      ),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.15 puzzle field / fetch ($tag)',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        game.runDebug.god = true;
        await startRun(
          game,
          startHoopIndex: ElementId.puzzlePiece.firstPossible!,
          force: [ElementId.puzzlePiece],
        );
        await flyUntil(game, (r) {
          return r.spawner.pickups.any(
            (p) =>
                p.id == ElementId.puzzlePiece &&
                p.position.x - r.state.camX < 230,
          );
        });
        await tester.runAsync(() => _shot(game, 2, 'puzzle_field_$tag'));
        final Pickup? p = await collectPickup(
          game,
          ElementId.puzzlePiece,
          reforce: false,
        );
        expect(p, isNotNull);
        await _untilSlot(game, .55);
        await tester.runAsync(() => _shot(game, 2, 'puzzle_fly_$tag'));
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: h,
        seed: 5,
        prefs: {'puzzlePieces': 7, 'puzzleRound': 0},
      ),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.15 puzzle complete ($tag)',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        game.runDebug.god = true;
        await startRun(
          game,
          startHoopIndex: ElementId.puzzlePiece.firstPossible!,
          force: [ElementId.puzzlePiece],
        );
        final p = await collectPickup(
          game,
          ElementId.puzzlePiece,
          reforce: false,
        );
        expect(p, isNotNull);
        await _untilSlot(game, 2.9);
        await tester.runAsync(() => _shot(game, 2, 'puzzle_complete_$tag'));
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, seed: 5, prefs: {'feathers': 3}),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§5.14 balloon bonus ($tag)',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        await startRun(game);
        killRun(game);
        await flushAndMount(game);
        expect(game.state, GameState.bonus);
        final b = game.bonusScreen!;
        await stepSeconds(game, .5);
        await tester.runAsync(() => _shot(game, 2, 'balloon_start_$tag'));
        b.tapTile(4);
        await stepSeconds(game, .7);
        await tester.runAsync(() => _shot(game, 2, 'balloon_pop_$tag'));
        await stepSeconds(game, 1);
        b.tapTile(0);
        await stepSeconds(game, 1.2);
        b.tapTile(8);
        await stepSeconds(game, 2.5);
        await stepSeconds(game, 3.2);
        expect(b.phase, isNot(BonusPhase.pick));
        await tester.runAsync(() => _shot(game, 2, 'balloon_offer_$tag'));
        await b.tapOffer();
        await stepSeconds(game, 1.6);
        for (final i in [1, 2, 3]) {
          b.tapTile(i);
          await stepSeconds(game, 1.2);
        }
        await stepSeconds(game, 3);
        await tester.runAsync(() => _shot(game, 2, 'balloon_next_$tag'));
      },
    );
  }
}
