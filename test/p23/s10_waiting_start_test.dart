// PRD-2.3 §10.4: the waiting start (§10.1), hoop 0 at its fixed spot
// (§10.2), the first-run instructions (§10.3) and the tap reminder (§10.3b).
//
// Goldens: flutter test --update-goldens test/p23/s10_waiting_start_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/home_mode.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/hoops/hoop_kind.dart';
import 'package:flappy_spikes/run/hud/first_run_hint.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter/painting.dart' show Canvas, Paint, Rect;
import 'package:flutter/services.dart';
import 'package:flappy_spikes/run/items/big_hoops.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<void> _loadFonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  await Future.wait([lvdc.load(), opificio.load(), fredoka.load()]);
}

Future<void> _boot(FlappySpikesGame game) async {
  await game.ready();
  game.sound.enabled = false;
  await preloadImages(game);
}

/// Steps [seconds] of game time in 1/60 s frames (no taps).
Future<void> _wait(FlappySpikesGame g, double seconds) async {
  final n = (seconds * 60).round();
  for (var i = 0; i < n; i++) {
    g.update(1 / 60);
    if (i % 10 == 9) await flushAndMount(g);
  }
}

double _birdY(FlappySpikesGame g) => g.runBirdPosition!.y;

int _count(AnalyticsSpy spy, String name) =>
    spy.events.where((e) => e.$1 == name).length;

const _seen = {'firstRunHintSeen': true};

OpponentRun _opponent() => OpponentRun(
  uid: 'u1',
  name: 'BrightOwl',
  score: 3,
  best: 9,
  level: 1,
  timeline: RunTimeline()
    ..addPoint(1)
    ..addPoint(2)
    ..addPoint(3)
    ..end(4),
);

/// The frame as an image (the screenshot pattern of
/// `menu_screenshot_test.dart`, at 1×).
Future<ui.Image> _frame(FlappySpikesGame g) async {
  final size = Vector2(320, g.viewHeight.roundToDouble());
  g.onGameResize(size);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.x, size.y),
    Paint()..color = g.backgroundColor(),
  );
  g.render(canvas);
  return recorder.endRecording().toImage(size.x.toInt(), size.y.toInt());
}

/// Also writes a 2× PNG for the visual check against the design.
Future<void> _evidence(FlappySpikesGame g, String name) async {
  final size = Vector2(640, (g.viewHeight * 2).roundToDouble());
  g.onGameResize(size);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.x, size.y),
    Paint()..color = g.backgroundColor(),
  );
  g.render(canvas);
  final image = await recorder.endRecording().toImage(
    size.x.toInt(),
    size.y.toInt(),
  );
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  final f = File('build/p23_shots/$name.png');
  await f.parent.create(recursive: true);
  await f.writeAsBytes(bytes);
}

void main() {
  group('§10.1 the waiting start', () {
    final spy = AnalyticsSpy();
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(services: spy),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );

    tester.testGameWidget(
      'after START the clock stays 0, the world does not scroll and the bird '
      'only hovers (±6 pt) for 5 s; the first tap starts, flaps and emits '
      'RunStarted once; run_start moves to the tap',
      setUp: (game, _) => _boot(game),
      verify: (game, _) async {
        spy.events.clear();
        final run = await openRun(game);
        expect(game.state, GameState.playing);
        expect(run.waiting, isTrue);
        expect(run.started, isFalse);
        expect(game.runBird!.hovering, isTrue);
        final mid = game.viewHeight / 2;
        var minY = double.infinity, maxY = -double.infinity;
        for (var i = 0; i < 300; i++) {
          game.update(1 / 60);
          final y = _birdY(game);
          minY = y < minY ? y : minY;
          maxY = y > maxY ? y : maxY;
          expect(game.runBirdPosition!.x, Config.birdX);
        }
        expect(run.state.runClock, 0);
        expect(run.clock.running, isFalse);
        expect(run.state.camX, 0);
        expect(minY, greaterThanOrEqualTo(mid - 6 - 1e-6));
        expect(maxY, lessThanOrEqualTo(mid + 6 + 1e-6));
        expect(maxY - minY, greaterThan(10)); // it does hover
        expect(_count(spy, 'run_start'), 0);

        var started = 0;
        run.events.on<RunStarted>((_) => started++);
        game.onPlayfieldTap();
        expect(run.started, isTrue);
        expect(run.clock.running, isTrue);
        expect(started, 1);
        expect(game.runBirdVelocityY!, lessThan(0)); // the first flap
        expect(game.runBird!.hovering, isFalse);
        expect(_count(spy, 'run_start'), 1);
        game.onPlayfieldTap(); // a normal flap now
        expect(started, 1);
        await _wait(game, 0.5);
        expect(run.state.runClock, greaterThan(0.4));
        expect(run.state.camX, greaterThan(0));
      },
    );

    tester.testGameWidget(
      'a pause while waiting pauses like a run, and does not start it',
      setUp: (game, _) => _boot(game),
      verify: (game, _) async {
        final run = await openRun(game);
        await _wait(game, 0.5); // the HUD row fades in
        game.pause(); // the pause button's action
        expect(game.state, GameState.paused);
        expect(run.started, isFalse);
        game.onScreenTap(); // a tap on the pause card does nothing
        expect(run.started, isFalse);
        game.resume();
        expect(game.state, GameState.playing);
        expect(run.waiting, isTrue);
        expect(run.clock.running, isFalse);
        game.onPlayfieldTap();
        expect(run.started, isTrue);
      },
    );
  });

  group('§10.1 versus', () {
    final versus = FakeVersusService(pool: [_opponent()]);
    final spy = AnalyticsSpy();
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(versus: versus, services: spy, prefs: _seen),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );

    tester.testGameWidget(
      "the opponent's score stays 0 until the tap; §10.3b the reminder "
      'count starts after the VS screen',
      setUp: (game, _) async {
        await _boot(game);
        await game.versus.prefetch();
      },
      verify: (game, _) async {
        expect(game.homeMode, HomeMode.versus);
        final run = await openRun(game);
        expect(run.setup.opponent, isNotNull);
        expect(run.waitingBegun, isTrue);
        // The VS intro took seconds; the count starts only now.
        expect(run.waitClock, lessThan(.5));
        final bar = game.runHud!.versus!;
        await _wait(game, 3.5);
        expect(bar.theirScore, 0);
        expect(game.firstRunHint!.shown, isFalse);
        await _wait(game, 0.6);
        expect(game.firstRunHint!.shown, isTrue);
        expect(
          spy.events.where((e) => e.$1 == 'tap_reminder_shown').single.$2,
          {'mode': 'versus'},
        );
        game.onPlayfieldTap();
        await flyRun(game, maxSeconds: 3);
        expect(bar.theirScore, greaterThan(0));
      },
    );
  });

  group('§10.2 hoop 0 at its fixed spot', () {
    for (final h in [568.0, 640.0, 711.0]) {
      final tester = FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: h),
        gameSize: Vector2(Config.worldWidth, h),
      );
      tester.testGameWidget(
        'at $h pt: x 290, y = middle + 16, opening 118, plain and still, '
        'there before the tap; hoop 1 at x 600',
        setUp: (game, _) => _boot(game),
        verify: (game, _) async {
          final run = await openRun(game);
          final hoops = hoopsOf(game).toList();
          expect(hoops, hasLength(1));
          final h0 = hoops.single;
          expect(h0.plan.index, 0);
          expect(h0.planeX, RunConfig.hoop0X);
          expect(h0.position.y, game.viewHeight / 2 + 16);
          expect(h0.opening, 118);
          expect(h0.kind.id, HoopKindId.normal);
          expect(h0.plan.motion, isNull);
          expect(h0.plan.tiltDeg, 0);
          expect(h0.plan.attached, isEmpty);
          expect(run.spawner.plannedAhead!.trackX, 600);
          await _wait(game, 2);
          expect(h0.planeX, 290);
          expect(h0.position.y, game.viewHeight / 2 + 16);
        },
      );
    }

    final big = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );
    big.testGameWidget(
      'Big Hoops: hoop 0 is big (177) and gold already on the waiting '
      'screen (owner 2026-10-19, deviation from PRD-2.3 §0 item 3)',
      setUp: (game, _) => _boot(game),
      verify: (game, _) async {
        game.storage.armedPowerup = Powerup.bigHoops.name;
        final run = await openRun(game);
        expect(run.setup.starter, Powerup.bigHoops);
        expect(run.waiting, isTrue, reason: 'still the waiting screen');
        final h0 = hoopsOf(game).first;
        expect(h0.opening, closeTo(177, 1e-9));
        expect(BigHoopsFeature.isGold(h0), isTrue);
        expect(h0.position.y, game.viewHeight / 2 + 16, reason: 'same spot');
      },
    );

    final dbg = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );
    dbg.testGameWidget(
      'a startHoopIndex run keeps the off-screen first hoop',
      setUp: (game, _) => _boot(game),
      verify: (game, _) async {
        await startRun(game, startHoopIndex: 20);
        expect(
          hoopsOf(game).first.planeX,
          RunConfig.worldWidth + RunConfig.firstHoopOffscreen,
        );
      },
    );
  });

  group('§10.3 first-run instructions', () {
    final spy = AnalyticsSpy();
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(services: spy),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );

    tester.testGameWidget(
      'shows only while firstRunHintSeen is false; the first tap fades it '
      'out (0.35 s) but saves nothing (PRD-2.3.1 §10: hoop 0 saves it); the '
      'second run, with no hoop passed, shows the instructions again',
      setUp: (game, _) => _boot(game),
      verify: (game, _) async {
        expect(game.storage.firstRunHintSeen, isFalse);
        await openRun(game);
        final hint = game.firstRunHint!;
        expect(hint.mode, FirstRunHintMode.firstRun);
        expect(hint.shown, isTrue);
        expect(game.world.children.whereType<FirstRunVeil>(), hasLength(1));
        await _wait(game, 8);
        // Not on the very first run: no reminder on top of it.
        expect(_count(spy, 'tap_reminder_shown'), 0);
        game.onPlayfieldTap();
        expect(game.storage.firstRunHintSeen, isFalse);
        expect(hint.dismissed, isTrue);
        await _wait(game, 0.2);
        expect(hint.opacity, closeTo(1 - 0.2 / 0.35, 0.02));
        await _wait(game, 0.2);
        await flushAndMount(game);
        expect(hint.isRemoved, isTrue);
        expect(game.world.children.whereType<FirstRunVeil>(), isEmpty);
        // The second run (no hoop 0 passed): the instructions again.
        killRun(game);
        await declineRevive(game);
        game.replay();
        await flushAndMount(game);
        await _wait(game, .5);
        await openRun(game);
        expect(game.firstRunHint!.mode, FirstRunHintMode.firstRun);
      },
    );

    final restart = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(prefs: _seen),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );
    restart.testGameWidget(
      'after a restart of the app (flag saved) it does not show',
      setUp: (game, _) => _boot(game),
      verify: (game, _) async {
        await openRun(game);
        expect(game.firstRunHint!.mode, FirstRunHintMode.reminder);
        expect(game.firstRunHint!.shown, isFalse);
      },
    );

    final upgrade = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(prefs: const {'gamesPlayed': 12}),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );
    upgrade.testGameWidget(
      'a save that has played before (1.x / 2.x upgrade) counts as seen',
      setUp: (game, _) => _boot(game),
      verify: (game, _) async {
        expect(game.storage.firstRunHintSeen, isTrue);
      },
    );
  });

  group('§10.3b the tap reminder', () {
    final spy = AnalyticsSpy();
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(services: spy, prefs: _seen),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );

    tester.testGameWidget(
      'no tap for 4 s: hand + banner fade in over 0.3 s (no veil, bands or '
      'path), once per wait; the tap fades it out over 0.2 s and flaps at '
      'once',
      setUp: (game, _) => _boot(game),
      verify: (game, _) async {
        spy.events.clear();
        await openRun(game);
        final hint = game.firstRunHint!;
        expect(hint.mode, FirstRunHintMode.reminder);
        await _wait(game, 3.9);
        expect(hint.shown, isFalse);
        await _wait(game, 0.15);
        expect(hint.shown, isTrue);
        expect(hint.opacity, lessThan(1));
        await _wait(game, 0.3);
        expect(hint.opacity, 1);
        expect(hint.children, isEmpty); // no AVOID THE SPIKES bands
        expect(game.world.children.whereType<FirstRunVeil>(), isEmpty);
        await _wait(game, 10);
        expect(_count(spy, 'tap_reminder_shown'), 1);
        expect(spy.events.firstWhere((e) => e.$1 == 'tap_reminder_shown').$2, {
          'mode': 'versus',
        });
        game.onPlayfieldTap();
        expect(game.run!.started, isTrue);
        expect(game.runBirdVelocityY!, lessThan(0));
        await _wait(game, 0.1);
        expect(hint.opacity, closeTo(1 - 0.25, 0.02)); // ease-in: 1 − u²
        await _wait(game, 0.12);
        await flushAndMount(game);
        expect(hint.isRemoved, isTrue);
      },
    );

    tester.testGameWidget(
      'a tap at 3.9 s: no reminder',
      setUp: (game, _) => _boot(game),
      verify: (game, _) async {
        spy.events.clear();
        await openRun(game);
        final hint = game.firstRunHint!;
        await _wait(game, 3.9);
        game.onPlayfieldTap();
        await flushAndMount(game);
        expect(hint.isRemoved, isTrue);
        await flyRun(game, maxSeconds: 3);
        expect(_count(spy, 'tap_reminder_shown'), 0);
      },
    );

    tester.testGameWidget(
      'a pause holds the count; the reminder hides while paused',
      setUp: (game, _) => _boot(game),
      verify: (game, _) async {
        final run = await openRun(game);
        final hint = game.firstRunHint!;
        await _wait(game, 3);
        game.pause();
        await _wait(game, 5);
        expect(run.waitClock, closeTo(3, .05));
        expect(hint.shown, isFalse);
        game.resume();
        await _wait(game, 0.9);
        expect(hint.shown, isFalse);
        await _wait(game, 0.2);
        expect(hint.shown, isTrue);
        game.pause();
        await _wait(game, 1);
        expect(hint.isRemoved, isFalse);
        game.resume();
      },
    );

    final tuned = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(prefs: _seen),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );
    tuned.testGameWidget(
      'Config.tapReminderDelay is 4.0 by default (`ui_tap_reminder_s`)',
      setUp: (game, _) => _boot(game),
      verify: (game, _) async {
        expect(Config.tapReminderDelay, 4.0);
      },
    );
  });

  group('§10.4 goldens', () {
    setUpAll(_loadFonts);
    for (final h in [568.0, 711.0]) {
      for (final reminder in [false, true]) {
        final name = '${reminder ? 'tap_reminder' : 'first_run'}_${h.toInt()}';
        final tester = FlameTester<FlappySpikesGame>(
          () => createRunTestGame(
            worldHeight: h,
            prefs: reminder ? _seen : const {},
          ),
          gameSize: Vector2(Config.worldWidth, h),
        );
        tester.testGameWidget(
          name,
          setUp: (game, _) => _boot(game),
          verify: (game, t) async {
            final RunController run = await openRun(game);
            // First run: a moment into the loop (both FLAPs drawn);
            // reminder: 4 s + the fade-in, the same loop phase.
            await _wait(game, reminder ? 4.0 + 2.2 : 2.2);
            expect(run.waiting, isTrue);
            final image = await t.runAsync(() async {
              await _evidence(game, name);
              return _frame(game);
            });
            await expectLater(
              image!,
              matchesGoldenFile('goldens/s10_$name.png'),
            );
            image.dispose();
          },
        );
      }
    }
  });
}
