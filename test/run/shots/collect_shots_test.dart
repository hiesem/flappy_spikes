import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/egg_config.dart';
import 'package:flappy_spikes/run/config/star_trail_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/text_pop.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/pickups/jar_pickup.dart';
import 'package:flappy_spikes/run/pickups/piggy_coin.dart';
import 'package:flappy_spikes/run/pickups/piggy_pickup.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3e screenshot check (ARCH §7.1): real run frames of the four
/// collectables — the Star Trail arc (`lab_trail.png`), the ×2 chick and its
/// pill (`lab_egg3.png`), the Piggy Bank HUD with coin fields
/// (`lab_piggy3.png`) and the animated Firefly Jar pickup (`lab_flies3.png`).
///
/// The elements are spawned on the flight line and the bird is hand-flown
/// (`god` mode) into the mock's framing, so the shot shows the art at colour
/// stage 0 with no streak fire or banner over it. Writes PNGs to
/// `build/shots/run/collect/` (never committed); nothing is asserted beyond
/// "rendered".
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

/// Same render path as `captureShot` (menu_screenshot_test.dart): resize
/// right before rendering (the harness reverts earlier resizes).
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

/// Spawns one gap item from [dx0] to [dx1] on the flat line ahead of the
/// bird.
void _spawn(
  RunController run,
  ElementId kind, {
  required double dx0,
  double? dx1,
  int extra = 0,
}) {
  final bird = run.birdTrackPosition()!;
  run.spawner.spawnItem(
    GapItemPlan(
      kind: kind,
      trackX: bird.x + dx0,
      toTrackX: dx1 == null ? null : bird.x + dx1,
      y: bird.y,
      toY: bird.y,
      extra: extra == 0 ? null : extra,
    ),
  );
}

/// Steps [frames] with the bird glued ([glue] returns its y).
Future<void> _fly(
  FlappySpikesGame game,
  double Function(FlappySpikesGame) glue,
  int frames,
) async {
  for (var f = 0; f < frames; f++) {
    game.runBird!.setFlight(y: glue(game), vy: 0);
    game.update(1 / 60);
    if (f % 10 == 0) await flushAndMount(game);
  }
}

/// Steps until the next hoop's plane is well ahead (clear air for a shot).
Future<void> _waitClear(FlappySpikesGame game, RunController run) async {
  var frames = 0;
  while (frames++ < 600) {
    final next = run.spawner.nextHoopAhead();
    final bird = run.birdTrackPosition();
    if (next == null ||
        bird == null ||
        next.planeX - bird.x > 150) {
      return;
    }
    game.runBird!.setFlight(y: game.runBird!.body.position.y, vy: 0);
    game.update(1 / 60);
    if (frames % 10 == 0) await flushAndMount(game);
  }
}

/// A clean frame: no banner over the art.
Future<void> _clean(FlappySpikesGame game, RunController run) async {
  RunHud.ensureFor(run).banners.clear();
  await flushAndMount(game);
  run.debugFreeze();
}

void main() {
  setUpAll(_fonts);

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 11),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§5.25 lab_trail → collect_trail_711',
    setUp: (g, _) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
    },
    verify: (game, tester) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      // Let the home screen finish hiding before framing the trail.
      await _fly(game, (g) => g.runBird!.body.position.y, 90);
      _spawn(run, ElementId.starTrail, dx0: 45, dx1: 215, extra: StarTrailConfig.stars);
      await flushAndMount(game);
      await _clean(game, run);
      await tester.runAsync(() => _shot(game, 1.5, 'collect_trail_711'));
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 568, seed: 11),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    '§5.25 lab_trail → collect_trail_568',
    setUp: (g, _) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
    },
    verify: (game, tester) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      await _fly(game, (g) => g.runBird!.body.position.y, 90);
      _spawn(run, ElementId.starTrail, dx0: 45, dx1: 215, extra: StarTrailConfig.stars);
      await flushAndMount(game);
      await _clean(game, run);
      await tester.runAsync(() => _shot(game, 1.5, 'collect_trail_568'));
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 11),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§5.26 lab_egg3 → collect_egg_711',
    setUp: (g, _) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
    },
    verify: (game, tester) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      // Let the home screen finish hiding, then wait for a stretch of clear
      // air so the bird cannot graze a rim while the chick settles.
      await _fly(game, (g) => g.runBird!.body.position.y, 90);
      await _waitClear(game, run);
      run.events.emit(PickupCollected(ElementId.egg, null));
      for (var i = 0; i < EggConfig.rings; i++) {
        run.events.emit(HoopPassed(null, perfect: true));
      }
      expect(run.state.egg?.stage, EggStage.chick);
      // Drop the pickup pop ("EGG! hatches in 5 rings") so it does not run
      // over the art, then let the hatch burst fade.
      await flushAndMount(game);
      for (final pop in run.layers.fx.children.whereType<TextPop>().toList()) {
        pop.removeFromParent();
      }
      await _fly(game, (g) => g.runBird!.body.position.y, 44);
      expect(run.state.egg, isNotNull, reason: 'chick was scared away');
      // Any countdown / pickup pop has drifted by now: drop them all.
      await flushAndMount(game);
      for (final pop in run.layers.fx.children.whereType<TextPop>().toList()) {
        pop.removeFromParent();
      }
      await _clean(game, run);
      await tester.runAsync(() => _shot(game, 1.5, 'collect_egg_711'));
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 11),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§5.27 lab_piggy3 → collect_piggy_711',
    setUp: (g, _) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
    },
    verify: (game, tester) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      await _fly(game, (g) => g.runBird!.body.position.y, 90);
      await _waitClear(game, run);
      _spawn(run, ElementId.piggy, dx0: 60);
      await flushAndMount(game);
      // Fly into the piggy.
      await _fly(game, (g) {
        final piggy = pickupsOf(g).whereType<PiggyPickup>().firstOrNull;
        return piggy?.position.y ?? g.runBird!.body.position.y;
      }, 120);
      expect(run.state.piggy, isNotNull);
      // Chase the own-gap field until a couple of bank coins are caught and
      // at least two are still ahead (the mock shows both).
      var frames = 0;
      // PRD-2.3 §10.2 moved the course 90 pt: the hand-flown chase now
      // meets hoop 1's rim; fly through the rims (no rim knocks) for it.
      while (frames++ < 360) {
        run.state.invulnerable = 1;
        final field = pickupsOf(game).whereType<PiggyCoin>().firstOrNull;
        double? ty;
        var ahead = 0;
        final bx = run.birdTrackPosition()!.x;
        if (field != null) {
          for (var i = 0; i < field.count; i++) {
            if (field.caught[i] || field.missed[i]) continue;
            final c = field.coinAt(i);
            if (c.dx > bx + 6) {
              ahead++;
              ty ??= c.dy;
            }
          }
        }
        if ((run.state.piggy?.caught ?? 0) >= 2 && ahead >= 1) break;
        game.runBird!.setFlight(
          y: ty ?? game.runBird!.body.position.y,
          vy: 0,
        );
        game.update(1 / 60);
        if (frames % 10 == 0) await flushAndMount(game);
      }
      expect(run.state.piggy!.caught, greaterThanOrEqualTo(2));
      run.state.invulnerable = 0;
      await _clean(game, run);
      await tester.runAsync(() => _shot(game, 1.5, 'collect_piggy_711'));
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 11),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§5.28 lab_flies3 → collect_jar_711',
    setUp: (g, _) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
    },
    verify: (game, tester) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      await _fly(game, (g) => g.runBird!.body.position.y, 90);
      // Jar ~100 pt ahead → ~170 pt on screen (the mock's framing).
      _spawn(run, ElementId.jar, dx0: 100);
      await flushAndMount(game);
      final jar = pickupsOf(game).whereType<JarPickup>().single;
      await _fly(game, (g) => jar.position.y, 6);
      await _clean(game, run);
      await tester.runAsync(() => _shot(game, 1.5, 'collect_jar_711'));
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 568, seed: 11),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    '§5.28 lab_flies3 → collect_jar_568',
    setUp: (g, _) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
    },
    verify: (game, tester) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      await _fly(game, (g) => g.runBird!.body.position.y, 90);
      _spawn(run, ElementId.jar, dx0: 100);
      await flushAndMount(game);
      final jar = pickupsOf(game).whereType<JarPickup>().single;
      await _fly(game, (g) => jar.position.y, 6);
      await _clean(game, run);
      await tester.runAsync(() => _shot(game, 1.5, 'collect_jar_568'));
    },
  );
}
