import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/physics_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/effects/miss_flash.dart';
import 'package:flappy_spikes/run/effects/screen_edge_glow.dart';
import 'package:flappy_spikes/run/effects/shock_ring.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/normal.dart';
import 'package:flappy_spikes/run/hoops/ring_painter.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-1a flow tests: hoops replace pipes in the real game (PRD-2 §3.0.1,
/// §3.0.4, §3.0.5, §3.1, §3.2, §5.1, §5.13).
void main() {
  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  Hoop firstHoop(RunController run) => run.spawner.hoops.first;

  for (final h in [568.0, 711.0]) {
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h),
      gameSize: Vector2(320, h),
    );

    tester.testGameWidget(
      '§3.0.1 ($h) the first hoop spawns 60 pt past the right edge at the '
      'first tap, at the exact centre, normal kind, and reaches the bird '
      '≈ 2.1 s later',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await startRun(game);
        final hoop = firstHoop(run);
        expect(hoop.kind, isA<NormalHoopKind>());
        expect(hoop.planeX - run.state.camX, closeTo(320 + 60, 3));
        expect(hoop.position.y, closeTo(h / 2, 1e-6));
        expect(hoop.opening, RunConfig.opening0);
        // Hold level at the centre: the pass comes ≈ 310 / 150 s later.
        run.events.recordLog = true;
        var t = 0.0;
        while (run.state.hoopsPassed == 0 && t < 3) {
          game.runBird!.setFlight(y: h / 2, vy: 0);
          game.update(1 / 60);
          t += 1 / 60;
        }
        expect(t, closeTo(310 / 150, 0.1));
        // §3.0.1 the world scrolls at the bird's forward speed (cruise).
        expect(run.state.forwardSpeed, closeTo(RunConfig.cruise(t), .5));
      },
    );

    tester.testGameWidget(
      '§3.0.4 ($h) a rim touch bounces, the world jolts back, the pass still '
      'scores +1 with 1 coin and is not perfect',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await startRun(game);
        run.events.recordLog = true;
        final hoop = firstHoop(run);
        final rimY = hoop.position.y - (hoop.opening / 2 + 7);
        final wallet = game.menu.wallet.balance;
        var minForward = 999.0;
        for (var i = 0; i < 240 && run.state.hoopsPassed == 0; i++) {
          // Level, 10 pt inside the top rim end, until it is touched.
          if (!hoop.touched) game.runBird!.setFlight(y: rimY + 10, vy: 0);
          game.update(1 / 60);
          if (run.state.forwardSpeed < minForward) {
            minForward = run.state.forwardSpeed;
          }
          if (game.state != GameState.playing) break;
        }
        expect(hoop.touched, isTrue);
        expect(run.state.rimTouches, 1);
        expect(run.events.log.whereType<RimTouched>(), isNotEmpty);
        expect(minForward, lessThan(0), reason: 'knocked back (§3.0.4 4)');
        expect(game.state, GameState.playing, reason: 'a rim never kills');
        final passed = run.events.log.whereType<HoopPassed>().single;
        expect(passed.perfect, isFalse);
        expect(passed.rimTouched, isTrue);
        expect(run.state.score, 1);
        expect(game.menu.wallet.balance, wallet + 1);
        expect(run.state.coinsThisRun, 1);
        // §3.0.4 4 the forward speed recovers to cruise.
        stepGame(game, .3, flapBelow: h / 2);
        expect(
          run.state.forwardSpeed,
          closeTo(RunConfig.cruise(run.state.runClock), .5),
        );
      },
    );

    tester.testGameWidget(
      '§3.0.4 ($h) a bird pressed against the inside of the bottom rim end '
      'passes',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await startRun(game);
        run.events.recordLog = true;
        final hoop = firstHoop(run);
        final rimY = hoop.position.y + (hoop.opening / 2 + 7);
        for (var i = 0; i < 240 && run.state.hoopsPassed == 0; i++) {
          if (!hoop.touched) game.runBird!.setFlight(y: rimY - 12, vy: 0);
          game.update(1 / 60);
          if (game.state != GameState.playing) break;
        }
        expect(hoop.touched, isTrue);
        expect(run.events.log.whereType<HoopMissed>(), isEmpty);
        expect(run.events.log.whereType<HoopPassed>(), hasLength(1));
      },
    );

    tester.testGameWidget(
      '§3.2 / §5.1 ($h) a perfect pass pays 2 coins at once (no point.mp3); '
      'no coins at game over; the dead bird rests on the floor spikes',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final sfx = sfxLog(game);
        final run = await startRun(game);
        run.events.recordLog = true;
        final wallet = game.menu.wallet.balance;
        while (run.state.hoopsPassed == 0) {
          game.runBird!.setFlight(y: h / 2, vy: 0);
          game.update(1 / 60);
        }
        final passed = run.events.log.whereType<HoopPassed>().single;
        expect(passed.perfect, isTrue);
        expect(game.menu.wallet.balance, wallet + 2);
        expect(
          run.events.log.whereType<CoinsEarned>().single.source,
          CoinSource.perfect,
        );
        expect(sfx, isNot(contains('point')));
        expect(run.state.perfectPasses, 1);

        // Fall onto the floor spikes.
        var t = 0.0;
        while (game.state == GameState.playing && t < 5) {
          game.update(1 / 60);
          t += 1 / 60;
        }
        expect(game.state, GameState.dying);
        expect(game.runBird!.dead, isTrue);
        expect(sfx, contains('gameover'));
        // The post-run flow comes after the tumble (≤ 1.5 s).
        var d = 0.0;
        while (game.state == GameState.dying && d < 2) {
          game.update(1 / 60);
          d += 1 / 60;
        }
        expect(d, lessThanOrEqualTo(PhysicsConfig.resultsDelay + 1e-6));
        await flushAndMount(game);
        expect(game.state, GameState.results);
        expect(game.world.children.query<ResultsScreen>(), hasLength(1));
        expect(
          game.menu.wallet.balance,
          wallet + 2,
          reason: 'no "1 coin per point" at game over any more',
        );
        // The bird stays on screen, lying on the floor tooth line.
        stepGame(game, 3);
        final bird = game.runBird!;
        expect(bird.spriteOpacity, 1);
        expect(
          bird.body.position.y,
          closeTo(h - 44 - RunConfig.birdRadius + 2, 1e-3),
        );
        expect(bird.body.position.x, inInclusiveRange(24, 290));
        expect(run.tumble!.settledFlat, isTrue);
      },
    );
  }

  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  );

  tester.testGameWidget(
    '§3.0.5 the world eases to a stop over 0.4 s; the dead bird passes '
    'through hoops',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      await flyRun(game, untilHoops: 2);
      final speed = run.state.forwardSpeed;
      final cam0 = run.state.camX;
      game.onBirdHit(MistakeCause.spikes);
      expect(game.state, GameState.dying);
      stepGame(game, .5);
      expect(run.state.camX - cam0, closeTo(speed * .4 / 2, 3));
      final cam1 = run.state.camX;
      stepGame(game, .5);
      expect(run.state.camX, cam1);
      expect(run.state.hoopsPassed, 2, reason: 'nothing scores while dead');
    },
  );

  tester.testGameWidget(
    '§5.13 a miss plays the shock-ring miss flash: white flash, red '
    'shockwave, edge glow, miss_shock, then a grey dashed ghost',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final sfx = sfxLog(game);
      final run = await startRun(game);
      run.events.recordLog = true;
      final hoop = firstHoop(run);
      while (run.events.log.whereType<HoopMissed>().isEmpty) {
        game.runBird!.setFlight(y: 120, vy: 0);
        game.update(1 / 60);
      }
      await flushAndMount(game);
      expect(sfx, contains('missShock'));
      expect(hoop.look.missed, isTrue);
      expect(hoop.look.colors, RingColors.white);
      expect(run.layers.fx.children.whereType<MissFlash>(), hasLength(1));
      expect(run.layers.fx.children.whereType<ShockRing>(), isNotEmpty);
      expect(game.world.children.whereType<ScreenEdgeGlow>(), hasLength(1));
      expect(
        run.events.log.whereType<RunDied>().single.mistake.cause,
        MistakeCause.missedHoop,
      );
      stepGame(game, 1);
      await flushAndMount(game);
      expect(hoop.look.dash, [6, 6]);
      expect(hoop.look.colors!.front.a, closeTo(.35, .01));
      expect(game.world.children.whereType<ScreenEdgeGlow>(), isEmpty);
      expect(hoop.isMounted, isTrue, reason: 'the ghost stays in the world');
    },
  );

  tester.testGameWidget(
    '§3.1 a non-perfect pass plays point.mp3 and the §5.1 pulse',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final sfx = sfxLog(game);
      final run = await startRun(game);
      final pulses = run.layers.fx.children.whereType<ShockRing>().length;
      run.debugPass();
      await flushAndMount(game);
      expect(sfx, contains('point'));
      expect(run.state.score, 1);
      expect(game.score, 1);
      expect(
        run.layers.fx.children.whereType<ShockRing>().length,
        pulses,
        reason: 'no hoop, no pulse (the seam pass)',
      );
    },
  );

  tester.testGameWidget(
    '§3.0.1 the colour stage changes every 10 hoops passed (palettes in '
    'order, gold last)',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      for (var i = 0; i < 9; i++) {
        run.debugPass();
      }
      expect(game.stageKey, 0);
      run.debugPass();
      expect(game.stageKey, 5);
      for (var i = 0; i < 90; i++) {
        run.debugPass();
      }
      expect(run.state.hoopsPassed, 100);
      expect(game.stageKey, 50, reason: 'hoops 100–109 are the gold stage');
      for (var i = 0; i < 10; i++) {
        run.debugPass();
      }
      expect(game.stageKey, 0, reason: 'stage 11 wraps to the first');
      stepGame(game, 2);
      expect(game.stageBackground, paletteForStage(0).background);
    },
  );

  tester.testGameWidget(
    '§3.0.5 a spike save (invulnerable) bounces off the floor tooth line '
    'and stays on screen',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      run.state.invulnerable = 2;
      var minVy = 0.0;
      for (var i = 0; i < 90; i++) {
        game.update(1 / 60);
        final vy = game.runBird!.body.linearVelocity.y;
        if (vy < minVy) minVy = vy;
        expect(
          game.runBird!.body.position.y + RunConfig.birdRadius,
          lessThanOrEqualTo(711 - 44 + 1),
        );
      }
      expect(game.state, GameState.playing);
      expect(minVy, lessThan(-200), reason: 'sent up at vy −222');
    },
  );
}
