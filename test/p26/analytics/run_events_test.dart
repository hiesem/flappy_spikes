import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/director/director_context.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/items/analytics_router.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// PRD-2.6 WP-A1/A2: `run_fail` for every mistake that would end the run,
/// the per-run `run_extra`, and the extended `run_end` (≤ 25 parameters).
void main() {
  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  List<Map<String, Object>> events(AnalyticsSpy spy, String name) => [
    for (final e in spy.events)
      if (e.$1 == name) e.$2!,
  ];

  /// Steps through the death tumble to the revive offer / results.
  Future<void> settleDeath(FlappySpikesGame game) async {
    for (var t = 0.0; t < 3 && game.state == GameState.dying; t += 1 / 60) {
      game.update(1 / 60);
    }
    await flushAndMount(game);
  }

  /// Runs the phoenix to the end (the run plays again).
  Future<void> throughPhoenix(FlappySpikesGame game) async {
    for (var i = 0; i < 400 && game.state == GameState.reviving; i++) {
      game.update(1 / 60);
      if (i % 10 == 0) await flushAndMount(game);
    }
    await flushAndMount(game);
  }

  group('run_fail outcomes', () {
    final spy = AnalyticsSpy();
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        services: spy,
        worldHeight: 711,
        prefs: const {'coins': 1000},
      ),
      gameSize: Vector2(320, 711),
    );

    tester.testGameWidget(
      'one run_fail per shield save and one per extra-life save, with the '
      '22 PRD fields',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game);
        run.state
          ..shield = true
          ..extraLife = true;
        expect(
          run.mistake(const Mistake(MistakeCause.spikes)),
          MistakeOutcome.saved,
        );
        run.state.invulnerable = 0;
        expect(
          run.mistake(const Mistake(MistakeCause.missedHoop)),
          MistakeOutcome.saved,
        );
        final fails = events(spy, 'run_fail');
        expect(fails, hasLength(2));
        expect(fails.map((e) => e['outcome']), ['shield', 'life']);
        for (final fail in fails) {
          expect(fail.keys, AnalyticsRouter.failKeys);
        }
        expect(fails.first['cause'], 'spikes');
        expect(fails.last['cause'], 'missed_hoop');
        expect(fails.first['squeeze_idx'], -1);
        expect(fails.first['ride_exit'], -1);
        expect(fails.first['run_no'], 1);
        expect(fails.first['gb'], '1');
        expect(fails.first['level'], 0);
        expect(fails.first['showcase'], 0);
        expect(fails.first['mode'], 'versus');
      },
    );

    tester.testGameWidget(
      'an ignored mistake sends nothing; a death sends exactly one '
      'run_fail with outcome end',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game);
        run.state.invulnerable = 2;
        expect(
          run.mistake(const Mistake(MistakeCause.spikes)),
          MistakeOutcome.ignored,
        );
        expect(events(spy, 'run_fail'), isEmpty);
        run.state.invulnerable = 0;
        expect(
          run.mistake(const Mistake(MistakeCause.spikes)),
          MistakeOutcome.died,
        );
        expect(events(spy, 'run_fail'), isEmpty, reason: 'not final yet');
        await settleDeath(game);
        expect(events(spy, 'run_fail'), hasLength(1));
        expect(events(spy, 'run_fail').single['outcome'], 'end');
        expect(game.state, GameState.results);
      },
    );

    tester.testGameWidget(
      'a rewarded-ad revive converts the pending death to revive_ad before '
      'run_end, exactly once',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final ads = game.monetization.ads as FakeRewardedAds;
        final run = await startRun(game);
        run.state.invulnerable = 0;
        for (var i = 0; i < 6; i++) {
          run.debugPass(perfect: true);
        }
        expect(
          run.mistake(const Mistake(MistakeCause.missedHoop)),
          MistakeOutcome.died,
        );
        await settleDeath(game);
        expect(game.state, GameState.reviving);
        final screen = game.reviveScreen!;
        expect(screen.offer.isAd, isTrue);
        for (var i = 0; i < 30; i++) {
          game.update(1 / 60);
        }
        screen.tapHeart();
        for (var i = 0; i < 60 && screen.phoenix == null; i++) {
          game.update(1 / 60);
          await flushAndMount(game);
        }
        expect(ads.placements, contains(AdPlacement.revive));
        await throughPhoenix(game);
        expect(game.state, GameState.playing);
        expect(events(spy, 'run_fail'), hasLength(1));
        expect(events(spy, 'run_fail').single['outcome'], 'revive_ad');
        expect(events(spy, 'run_end'), isEmpty);
        // The run_end revival counters count the paid revive.
        game.endRun(run.endRun());
        final end = events(spy, 'run_end').single;
        expect(end['revives_ad'], 1);
        expect(end['revives_coin'], 0);
      },
    );

    tester.testGameWidget(
      'a coin revive converts the pending death to revive_coins; a free '
      'revive is revive_free and counts in neither paid counter',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        // The revive screen reads availability in onLoad, so switch before
        // the tumble settles into the offer.
        (game.monetization.ads as FakeRewardedAds).mode =
            FakeAdMode.unavailable;
        final run = await startRun(game);
        run.state.invulnerable = 0;
        for (var i = 0; i < 6; i++) {
          run.debugPass(perfect: true);
        }
        expect(
          run.mistake(const Mistake(MistakeCause.missedHoop)),
          MistakeOutcome.died,
        );
        await settleDeath(game);
        final screen = game.reviveScreen!;
        // No ad is available, so the first offer is the 250-coin rung.
        expect(game.state, GameState.reviving);
        for (var i = 0; i < 30; i++) {
          game.update(1 / 60);
        }
        expect(screen.offer.isCoins, isTrue);
        expect(screen.offer.price, 250);
        screen.tapHeart();
        // The coin fly is the payment's 1.1 s; the phoenix follows.
        for (var i = 0; i < 400 && game.state == GameState.reviving; i++) {
          game.update(1 / 60);
          if (i % 10 == 0) await flushAndMount(game);
        }
        await throughPhoenix(game);
        expect(game.state, GameState.playing);
        expect(events(spy, 'run_fail').single['outcome'], 'revive_coins');
        game.endRun(run.endRun());
        final end = events(spy, 'run_end').single;
        expect(end['revives_coin'], 1);
        expect(end['revives_ad'], 0);
      },
    );

    tester.testGameWidget(
      'a zero-price coin revive is revive_free and counts in neither paid '
      'counter',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game);
        // A free showcase revive (state-only until WP-B wires the offer)
        // reports revive_free and stays out of the paid counters. It arrives
        // as a zero-price coin revive, the future showcase offer shape.
        run.pipeline.onResolved?.call(
          const Mistake(MistakeCause.spikes),
          MistakeResolution.end,
        );
        run.events.emit(const Revived(ReviveKind.coins, 0));
        expect(events(spy, 'run_fail').single['outcome'], 'revive_free');
        game.endRun(run.endRun());
        final end = events(spy, 'run_end').single;
        expect(end['revives_coin'], 0);
        expect(end['revives_ad'], 0);
      },
    );
  });

  group('run_extra and run_end', () {
    final spy = AnalyticsSpy();
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(services: spy, worldHeight: 711),
      gameSize: Vector2(320, 711),
    );

    tester.testGameWidget(
      '10 perfect passes send no perfect_pass; run_extra carries the tier '
      'counts plus rides, squeezes, max speed, bonuses and formations',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game);
        for (var i = 0; i < 10; i++) {
          run.debugPass(perfect: true);
          game.update(1 / 60);
        }
        expect(spy.events.where((e) => e.$1 == 'perfect_pass'), isEmpty);

        run.events.emit(const RideEnded(RideKind.comet));
        run.ctx.earn(3, CoinSource.bonus);
        run.ctx.earn(5, CoinSource.hoop);
        run.events.emit(
          const HighlightStarted('ride', scripted: false, hoop: 4),
        );
        run.state.squeeze
          ..phase = SqueezePhase.warning
          ..index = 2;
        run.events.emit(const SqueezePhaseChanged(SqueezePhase.warning, 2));
        game.update(1 / 60);
        final maxSpeed = run.state.forwardSpeed.round();
        run.state.squeeze.phase = SqueezePhase.idle;
        expect(
          run.mistake(const Mistake(MistakeCause.spikes)),
          MistakeOutcome.died,
        );
        await settleDeath(game);
        await declineRevive(game);
        expect(events(spy, 'run_fail'), hasLength(1));

        final extra = events(spy, 'run_extra').single;
        expect(extra, hasLength(lessThanOrEqualTo(25)));
        for (var tier = 1; tier <= 10; tier++) {
          expect(extra['perfect_$tier'], 1, reason: 'tier $tier');
        }
        expect(extra['ride_hoops'], 0);
        expect(extra['squeezes'], 1);
        expect(extra['max_speed'], maxSpeed);
        expect(extra['coins_bonus'], 3);
        expect(extra['formations'], 0);
        expect(extra['downgraded'], 0);

        final end = events(spy, 'run_end').single;
        expect(end, hasLength(lessThanOrEqualTo(25)));
        expect(end['hb'], '10-14');
        expect(end['highlights'], 1);
        expect(end['mode'], 'versus');
        expect(end['showcase'], 0);
        expect(end['level'], 0);
        expect(end['lvl_pts_before'], 0);
        expect(end['beat_best_hoop'], -1);
        expect(end['revives_ad'], 0);
        expect(end['revives_coin'], 0);
        expect(end['calm_count'], greaterThanOrEqualTo(0));
        expect(end['max_hazard_x10'], greaterThanOrEqualTo(0));
        // PRD-2.6: clean_passes stays (budget allows it), the old
        // opening_end / speed_end / games_played fields made room.
        expect(end, contains('clean_passes'));
        expect(end, isNot(contains('opening_end')));
        expect(end, isNot(contains('speed_end')));
        expect(end, isNot(contains('games_played')));
      },
    );

    tester.testGameWidget(
      'ride_hoops counts perfect and non-perfect ride passes only',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game);
        run.events.emit(
          const HoopPassed(null, perfect: true, duringRide: true),
        );
        run.events.emit(
          const HoopPassed(null, perfect: false, duringRide: true),
        );
        run.events.emit(
          const HoopPassed(null, perfect: false, duringRide: false),
        );
        run.events.emit(
          const HoopPassed(null, perfect: true, duringRide: false),
        );
        game.endRun(run.endRun());
        expect(events(spy, 'run_extra').single['ride_hoops'], 2);
      },
    );

    tester.testGameWidget(
      'run_extra reports the director downgrade count for this run',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game);
        // Exercise real planning and its hazard budget, without a debug
        // setter or relying on the starting slots to need downgrades.
        for (var i = 0; i < 400; i++) {
          final ctx = DirectorContext.open(711);
          final plan = run.director.nextSlot(ctx);
          run.director.nextGap(ctx, plan);
        }
        final downgraded = run.director.downgrades;
        expect(downgraded, greaterThan(0));
        game.endRun(run.endRun());
        expect(events(spy, 'run_extra').single['downgraded'], downgraded);
      },
    );
  });
}
