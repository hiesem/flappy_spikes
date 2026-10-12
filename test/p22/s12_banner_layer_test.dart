import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/score_hud.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/parts_config.dart';
import 'package:flappy_spikes/run/config/streak_config.dart';
import 'package:flappy_spikes/run/hud/banner_layer.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/collect_layer.dart';
import 'package:flappy_spikes/run/hud/fever_banner.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/run_layers.dart';
import 'package:flappy_spikes/run/run_scaled_world.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

/// PRD-2.2 §12.4: every run banner (and the collect stickers) is drawn in the
/// run's banner layer, behind the bird, the hoops and the pickups, above the
/// big score circle; the HUD's top row stays on top; the layer follows the
/// run's lifecycle, the run's timing and the screen. Screenshots of a streak
/// banner with the bird in front go to `build/menu_shots/p22/`.
const double _scale = 2; // device px per point

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

/// The colour of the frame at world point ([x], [y]).
ui.Color _pixel(Uint8List px, double x, double y) {
  final w = (Config.worldWidth * _scale).round();
  final i = ((y * _scale).round() * w + (x * _scale).round()) * 4;
  return ui.Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]);
}

/// Fixes the run bird at [y] (pt), upright, fully opaque (look_visual_test).
void _pinBird(FlappySpikesGame game, {double? y}) {
  final bird = game.world.children.query<Bird>().single;
  bird.body
    ..gravityScale = Vector2.zero()
    ..linearVelocity.setZero()
    ..angularVelocity = 0
    ..setTransform(Vector2(Config.birdX, y ?? game.viewHeight / 2), 0);
  bird.lookComponent.playFlap();
  game.update(0);
  bird.setSpriteOpacity(1);
}

/// The y of the streak band's top edge (PRD-2.2 §7.5.4: the band is at y 190).
const double _bandTop = PartsConfig.bannerTop;

void _bannerTests(double viewHeight) {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: viewHeight),
    gameSize: Vector2(Config.worldWidth, viewHeight),
  ).testGameWidget(
    '§12 the streak band in front of the bird ($viewHeight pt): the bird and '
    'the band keep their own pixels where they overlap',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await loadFonts();
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      await tester.runAsync(() async {
        final run = await startRun(game);
        final hud = RunHud.of(run)!;
        final banners = hud.banners;
        final bandY = _bandTop + 16; // inside the band, over the bird

        _pinBird(game, y: bandY);
        banners.show(StreakBanner(12));
        await flushAndMount(game); // lifecycle queue: the band mounts
        stepGame(game, .3); // the band has scaled in and holds
        _pinBird(game, y: bandY);
        final withBand = await _frame(game);
        expect(
          _pixel(withBand, 290, bandY),
          StreakConfig.colourFor(12),
          reason: 'the band is drawn across the screen',
        );
        // The shot shows the band with the bird in front of it.
        await captureShot(game, 2, 'p22/s12_cosmic_${viewHeight.toInt()}');

        banners.clear();
        game.update(0);
        expect(banners.current, isNull);
        _pinBird(game, y: bandY);
        final withoutBand = await _frame(game);

        // The bird (drawn at its body centre) is the same with the band
        // behind it: the band is not in front of the bird.
        expect(
          _pixel(withBand, Config.birdX, bandY),
          _pixel(withoutBand, Config.birdX, bandY),
        );
      });
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('§12 order and placement', () {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    ).testGameWidget(
      'the banner layer sits between the score circle and the gameplay',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await loadFonts();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(game);
          final hud = RunHud.of(run)!;
          final score = game.world.children.query<ScoreHud>().single;
          final bird = game.world.children.query<Bird>().single;
          final layer = hud.bannerLayer;

          expect(RunLayer.banners, -60);
          expect(layer.priority, RunLayer.banners);
          expect(layer.parent, game.world, reason: 'in the world, not the HUD');
          expect(hud.parent, game.camera.viewport);
          expect(score.priority, RunLayer.scoreCircle);
          expect(layer.priority, greaterThan(score.priority));
          expect(layer.priority, lessThan(RunLayer.guides));
          for (final track in run.layers.all) {
            expect(layer.priority, lessThan(track.priority), reason: track.name);
          }
          expect(layer.priority, lessThan(RunLayer.strips));
          expect(layer.priority, lessThan(bird.priority));
          expect(layer.priority, lessThan(RunLayer.fx));
          expect(layer.priority, greaterThan(RunLayer.backdrop));
        });
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    ).testGameWidget(
      'every banner kind lands in the layer; the switch banner uses the same '
      'host; the stickers and labels are in the layer, the tray stays in the HUD',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await loadFonts();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(game);
          final hud = RunHud.of(run)!;
          final banners = hud.banners;
          expect(identical(RunHud.ensureFor(run).banners, banners), isTrue);
          expect(banners.parent, hud.bannerLayer);

          banners.show(StreakBanner(3));
          expect(banners.current, isA<StreakBanner>());
          banners.showFever(FeverBanner());
          expect(banners.fever, isNotNull);
          banners.show(ElementBanner('BULLSEYE!'));
          expect(banners.current, isA<ElementBanner>());
          await flushAndMount(game); // mount the queued banners
          final inLayer = hud.bannerLayer.descendants().toList();
          expect(inLayer, contains(banners.current));
          expect(inLayer, contains(banners.fever));

          // The collect layer keeps its slot, particles and rings in the HUD;
          // only its stickers are drawn by the banner layer.
          final collect = CollectLayer.ensureFor(run);
          expect(collect.parent, hud);
          expect(collect.bannerLayer, same(hud.bannerLayer));
          expect(hud.bannerLayer.children.whereType<CollectLayer>(), isEmpty);
        });
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    ).testGameWidget(
      'the top row (heart, pause) stays in the HUD above the world',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await loadFonts();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(game);
          final hud = RunHud.of(run)!;
          expect(hud.heart.parent, hud);
          expect(hud.pauseButton.parent, hud);
          expect(hud.parent, game.camera.viewport);
          expect(hud.banners.parent, isNot(hud));
        });
      },
    );
  });

  group('§12 kinds and lifecycle', () {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    ).testGameWidget(
      'a death clears the band; a banner that survives the death stays',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await loadFonts();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(game);
          final hud = RunHud.of(run)!;
          final banners = hud.banners;

          final crash = ElementBanner('CRASH')..survivesDeath = true;
          banners.show(crash);
          banners.clear();
          expect(banners.current, same(crash));
          banners.show(StreakBanner(2));
          banners.clear();
          expect(banners.current, isNull);

          banners.show(StreakBanner(4));
          await flushAndMount(game);
          killRun(game);
          game.update(0);
          expect(run.dying, isTrue);
          expect(banners.current, isNull, reason: 'the death clears the band');
          expect(hud.bannerLayer.parent, game.world);

          // After a revive the band works again, in the same layer.
          banners.show(StreakBanner(5));
          expect(banners.current, isA<StreakBanner>());
          expect(banners.parent, hud.bannerLayer);
        });
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    ).testGameWidget(
      'a replay leaves exactly one banner layer: the new run\'s',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await loadFonts();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(game);
          final first = RunHud.of(run)!;
          first.banners.show(StreakBanner(2));
          game.replay();
          await stepSeconds(game, .5);
          await flushAndMount(game);
          final again = await startRun(game);
          await flushAndMount(game);
          final second = RunHud.of(again)!;
          expect(identical(first, second), isFalse);
          expect(first.isRemoved, isTrue);
          expect(first.bannerLayer.isRemoved, isTrue);
          expect(game.world.children.query<RunBannerLayer>().toList(), [
            second.bannerLayer,
          ]);
          expect(second.banners.current, isNull, reason: 'no stale banner');
        });
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    ).testGameWidget(
      'pausing freezes a banner; the Hourglass does not slow it (real time)',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await loadFonts();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(game);
          final banner = StreakBanner(3); // 1.38 s on screen
          RunHud.of(run)!.banners.show(banner);
          await flushAndMount(game);
          stepGame(game, .2);
          final t0 = banner.time;
          expect(t0, closeTo(.2, .02));

          game.pause();
          stepGame(game, 1);
          expect(banner.time, t0, reason: 'frozen while paused');
          game.resume();

          stepGame(game, .2);
          final t1 = banner.time;
          expect(t1 - t0, closeTo(.2, .02), reason: 'real time after resume');

          // Slow motion: the world runs at 0.45 x, the banner does not.
          (game.world as RunScaledWorld).timeScaleSource = () => .45;
          stepGame(game, .3);
          expect(banner.time - t1, closeTo(.3, .02));
        });
      },
    );
  });

  group('§12 the band stays on screen', () {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    ).testGameWidget(
      'a screen shake of the world does not move the band',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await loadFonts();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(game);
          final banners = RunHud.of(run)!.banners;
          banners.show(StreakBanner(3));
          await flushAndMount(game);
          stepGame(game, .3);
          final colour = StreakConfig.colourFor(3);

          final still = await _frame(game);
          expect(_pixel(still, 4, _bandTop + 2), colour);

          game.camera.viewfinder.position = Vector2(7, -11);
          game.update(0);
          final shaken = await _frame(game);
          expect(_pixel(shaken, 4, _bandTop + 2), colour);
          game.camera.viewfinder.position = Vector2.zero();
        });
      },
    );
  });

  group('§12 the bird in front of a streak band (screenshots)', () {
    _bannerTests(568);
    _bannerTests(711);
  });
}
