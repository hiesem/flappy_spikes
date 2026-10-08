import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/revive_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/screens/phoenix_rise.dart';
import 'package:flappy_spikes/run/screens/revive_ladder.dart';
import 'package:flappy_spikes/run/screens/revive_screen.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-2d PRD-2 §3.14 / §5.9 revive v2 and the §7 revive test list: the
/// price ladder, the ≥ 6 hoops rule, the phoenix (safe line, drift to
/// x 70, scroll at 1.65 s, 2 s invulnerability, Black Hole re-form),
/// collectables lost / timed powerups ended at death, squeeze reset.
void main() {
  // ------------------------------------------------------------ the ladder
  group('§3.14 price ladder', () {
    RunState fresh() => RunState(seed: 1, viewHeight: 711);

    test('§3.14 ad → 250 → 500 → 1 000 → 2 000 → 4 000 (doubling, no '
        'cap) within one game', () {
      final s = fresh();
      final seen = <String>[];
      for (var i = 0; i < 6; i++) {
        final o = ReviveLadder.offer(s, adReady: true);
        seen.add(o.toString());
        ReviveLadder.record(s, o);
      }
      expect(seen, ['ad', '250', '500', '1000', '2000', '4000']);
      expect(ReviveLadder.coinPrice(10), 250 * 1024);
    });

    test('§3.14 the ladder resets with every new game', () {
      final a = fresh();
      ReviveLadder.record(a, ReviveLadder.offer(a, adReady: true));
      ReviveLadder.record(a, ReviveLadder.offer(a, adReady: true));
      expect(ReviveLadder.offer(a, adReady: true).price, 500);
      expect(ReviveLadder.offer(fresh(), adReady: true).isAd, isTrue);
    });

    test('§3.14 no ad available (or a no-ads owner) on the 1st offer: '
        '"NO AD AVAILABLE" + 250, then 500, 1 000', () {
      final s = fresh();
      final first = ReviveLadder.offer(s, adReady: false);
      expect(first, const ReviveOffer.coins(250, noAdLabel: true));
      // Asked again for the same death (after the Shop): same offer.
      expect(ReviveLadder.offer(s, adReady: true).price, 250);
      ReviveLadder.record(s, first);
      final second = ReviveLadder.offer(s, adReady: true);
      expect(second, const ReviveOffer.coins(500));
      ReviveLadder.record(s, second);
      expect(ReviveLadder.offer(s, adReady: true).price, 1000);
    });

    test('§3.14 knobs (reviveMinHoops 6, 250 first coin step, 5 s + 1 s, '
        'phoenix 1.65 s, 2 s invulnerability)', () {
      expect(ReviveConfig.minHoops, 6);
      expect(ReviveConfig.firstCoinPrice, 250);
      expect(ReviveConfig.offerSeconds, 5);
      expect(ReviveConfig.emptyHold, 1);
      expect(ReviveConfig.phoenixLength, 1.65);
      expect(ReviveConfig.invulnerable, 2);
      expect(formatCoins(1000), '1 000');
      expect(formatCoins(1253), '1 253');
      expect(formatCoins(250), '250');
    });
  });

  // ------------------------------------------------------------ flow tests
  Future<void> boot(FlappySpikesGame g) async {
    await g.ready();
    await preloadImages(g);
  }

  /// Passes [hoops] hoops (test seam) and kills the run; steps through the
  /// tumble until the offer / results.
  Future<RunController> dieAfter(
    FlappySpikesGame g,
    int hoops, {
    Mistake? mistake,
  }) async {
    final run = g.run ?? await startRun(g);
    run.state.invulnerable = 0; // a fresh phoenix's 2 s would absorb it
    for (var i = 0; i < hoops; i++) {
      run.debugPass(perfect: true);
    }
    if (mistake != null) {
      run.mistake(mistake);
      var t = 0.0;
      while (g.state == GameState.dying && t < 3) {
        g.update(1 / 60);
        t += 1 / 60;
      }
    } else {
      killRun(g);
    }
    await flushAndMount(g);
    return run;
  }

  void step(FlappySpikesGame g, double seconds) {
    for (var t = 0.0; t < seconds - 1e-9; t += 1 / 60) {
      g.update(1 / 60);
    }
  }

  /// Runs the offer to the end of the phoenix.
  Future<void> throughPhoenix(FlappySpikesGame g) async {
    for (var i = 0; i < 400 && g.state == GameState.reviving; i++) {
      g.update(1 / 60);
      if (i % 10 == 0) await flushAndMount(g);
    }
  }

  for (final h in [568.0, 711.0]) {
    final spy = AnalyticsSpy();
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, services: spy),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§3.14 ($h) ≤ 5 hoops: the tumble then results — no offer, no ladder '
      'step; ≥ 6 hoops: the offer',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await dieAfter(game, 5);
        expect(game.state, GameState.results);
        expect(game.reviveScreen, isNull);
        expect(run.state.adStepAvailableThisGame, isTrue);
        expect(run.state.coinRevives, 0);
        expect(
          analyticsLog(spy).map((e) => e.$1),
          isNot(contains('revive_offered')),
        );
        game.goHome();
        step(game, 1);
        await flushAndMount(game);
        spy.events.clear();
        final run2 = await startRun(game);
        await dieAfter(game, 6);
        expect(game.state, GameState.reviving);
        final screen = game.reviveScreen!;
        expect(screen.offer.isAd, isTrue);
        expect(run2.ended, isFalse, reason: 'the run ends only on decline');
        expect(
          analyticsLog(spy).where((e) => e.$1 == 'revive_offered').length,
          1,
        );
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        worldHeight: h,
        services: spy,
        prefs: const {'coins': 1000},
      ),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§3.14 / §5.9 ($h) ad revive → phoenix → straight back in at 1.65 s '
      '(safe line, x 70, 2 s invulnerability); the 2nd death costs 250, the '
      '3rd 500; games played counted once',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final ads = game.monetization.ads as FakeRewardedAds;
        spy.events.clear();
        final sfx = sfxLog(game);
        final run = await dieAfter(game, 8);
        final played = game.storage.gamesPlayed;
        final screen = game.reviveScreen!;
        expect(screen.offer.isAd, isTrue);
        step(game, .5); // the offer fades in
        screen.tapHeart();
        expect(game.reviveScreen!.phase, RevivePhase.ad);
        // Ad + 0.2 s, then the phoenix.
        for (var i = 0; i < 60 && screen.phoenix == null; i++) {
          game.update(1 / 60);
          await flushAndMount(game);
        }
        expect(ads.placements, [AdPlacement.revive]);
        final phoenix = screen.phoenix!;
        await flushAndMount(game);
        final clockAtStart = run.state.runClock;
        expect(run.state.revivesThisGame, 1);
        expect(run.state.adStepAvailableThisGame, isFalse);
        expect(run.state.firstSlotAfterRevive, isTrue);
        // The world does not scroll before 1.65 s.
        var t = 0.0;
        while (game.state == GameState.reviving && t < 3) {
          game.update(1 / 60);
          t += 1 / 60;
          if (game.state == GameState.reviving) {
            expect(run.state.runClock, clockAtStart);
          }
        }
        expect(t, closeTo(ReviveConfig.phoenixLength, 2 / 60));
        expect(game.state, GameState.playing);
        final bird = game.runBird!;
        expect(bird.body.position.x, closeTo(RunConfig.birdX, 1e-6));
        expect(bird.dead, isFalse);
        expect(bird.body.position.y, closeTo(phoenix.safeY, 2));
        expect(bird.body.linearVelocity.y, lessThan(0), reason: 'flaps up');
        expect(run.state.invulnerable, closeTo(2, .05));
        // §5.9 sounds: ignite at 0, burst at 1.0, flap when play resumes.
        final i0 = sfx.indexOf('rvIgnite');
        expect(i0, greaterThanOrEqualTo(0));
        expect(sfx.indexOf('rvBurst'), greaterThan(i0));
        expect(sfx.lastIndexOf('flap'), greaterThan(sfx.indexOf('rvBurst')));
        step(game, .5);
        expect(run.state.runClock, greaterThan(clockAtStart));
        final log = analyticsLog(spy).map((e) => e.$1).toList();
        expect(
          log,
          containsAll([
            'revive_offered',
            'revive_ad_started',
            'revive_ad_completed',
          ]),
        );

        // 2nd death: 250 coins.
        game.runDebug.god = false;
        await dieAfter(game, 0);
        expect(game.state, GameState.reviving);
        final s2 = game.reviveScreen!;
        expect(s2.offer, const ReviveOffer.coins(250));
        expect(s2.locked, isFalse);
        step(game, .5);
        final bal = game.menu.wallet.balance;
        s2.tapHeart();
        await flushAndMount(game);
        expect(game.menu.wallet.balance, bal - 250);
        expect(sfx, contains('rvPay'));
        step(game, 1.1); // 10 coins, 0.5 s each, 0.05 s apart
        expect(sfx.where((e) => e == 'bnCoin').length, 10);
        await throughPhoenix(game);
        expect(game.state, GameState.playing);
        expect(run.state.revivesThisGame, 2);
        expect(
          analyticsLog(spy).where((e) => e.$1 == 'revive_coins').first.$2,
          {'price': 250, 'revive_index': 2},
        );
        // 3rd death: 500 — then No thanks → results, persistence once.
        await dieAfter(game, 0);
        final s3 = game.reviveScreen!;
        expect(s3.offer.price, 500);
        step(game, .5);
        s3.tapNoThanks();
        step(game, .5);
        await flushAndMount(game);
        expect(game.state, GameState.results);
        expect(game.storage.gamesPlayed, played + 1);
        expect(run.summarize().revives, 2);
      },
    );
  }

  final spy = AnalyticsSpy();
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(services: spy, prefs: const {'coins': 180}),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    '§3.14 no ad: "NO AD AVAILABLE" at 250; not enough coins: locked (tap '
    'shakes, no spend); GET COINS opens the Shop over the paused game '
    '(countdown paused, music × 0.5), back returns with the gold heart',
    setUp: (g, _) async {
      (g.monetization.ads as FakeRewardedAds).mode = FakeAdMode.unavailable;
      await boot(g);
    },
    verify: (game, _) async {
      await dieAfter(game, 7);
      final screen = game.reviveScreen!;
      expect(screen.offer, const ReviveOffer.coins(250, noAdLabel: true));
      step(game, .5);
      expect(screen.locked, isTrue);
      final start = game.menu.wallet.balance;
      expect(screen.need, 250 - start);
      final sfx = sfxLog(game);
      screen.tapHeart();
      expect(sfx.last, 'rvLocked');
      expect(game.menu.wallet.balance, start);
      expect(screen.phase, RevivePhase.offer);
      expect(analyticsLog(spy).map((e) => e.$1), contains('revive_locked_tap'));
      step(game, 1);
      final left = screen.countdown;
      screen.tapGetCoins();
      await flushAndMount(game);
      expect(game.reviveShopOpen, isTrue);
      expect(game.shopScreen, isNotNull);
      expect(game.sound.musicDuck, ReviveConfig.shopMusicDuck);
      step(game, 3);
      await flushAndMount(game);
      expect(screen.countdown, left, reason: 'the countdown waits');
      expect(game.state, GameState.reviving);
      // Bought coins in the Shop, then back.
      await game.menu.wallet.add(500, CoinSource.iap);
      game.closeShop();
      step(game, .4);
      await flushAndMount(game);
      expect(game.reviveShopOpen, isFalse);
      expect(game.sound.musicDuck, 1);
      expect(screen.phase, RevivePhase.offer);
      expect(screen.locked, isFalse, reason: 'the gold heart is offered');
      screen.tapHeart();
      await flushAndMount(game);
      expect(game.menu.wallet.balance, start + 500 - 250);
      await throughPhoenix(game);
      expect(game.state, GameState.playing);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(services: spy),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    '§3.14 countdown: 5 s drain + 1 s empty, then results by itself; an ad '
    'closed early brings the offer back with the remaining time',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      spy.events.clear();
      final ads = game.monetization.ads as FakeRewardedAds
        ..mode = FakeAdMode.fail;
      await dieAfter(game, 6);
      final screen = game.reviveScreen!;
      step(game, 2);
      final before = screen.countdown;
      screen.tapHeart();
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
        await flushAndMount(game);
      }
      expect(ads.shown, 1);
      expect(screen.phase, RevivePhase.offer);
      expect(screen.offer.isAd, isTrue);
      // Paused while the ad was up (0.22 s fade + the ad), running again.
      expect(
        screen.countdown,
        closeTo(before + 30 / 60 - ReviveConfig.adHideDelay, 2 / 60),
      );
      step(game, ReviveConfig.offerSeconds - screen.countdown + .05);
      expect(screen.drain, 1);
      expect(
        game.state,
        GameState.reviving,
        reason: 'the empty heart stays 1 s',
      );
      step(game, 1.5);
      await flushAndMount(game);
      expect(game.state, GameState.results);
      expect(analyticsLog(spy).map((e) => e.$1), contains('revive_timeout'));
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§3.14 death: egg / piggy / jar lost, timed powerup ended, fire out; '
    'revive: a running squeeze slides open in 0.5 s, the next one 60–120 s '
    'later; score, coins and hearts kept',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final s = run.state;
      final ended = <PowerupEnded>[];
      run.events.on<PowerupEnded>(ended.add);
      s
        ..egg = EggState()
        ..piggy = PiggyState()
        ..jar = JarState()
        ..timed = TimedPowerupState(type: TimedPowerup.hourglass, duration: 8)
        ..timeScale = .45
        ..onFire = true
        ..hearts = 2;
      s.squeeze
        ..phase = SqueezePhase.hold
        ..inset = 40;
      await dieAfter(game, 6);
      expect(s.egg, isNull);
      expect(s.piggy, isNull);
      expect(s.jar, isNull);
      expect(s.timed, isNull);
      expect(ended.single.type, TimedPowerup.hourglass);
      expect(s.timeScale, 1);
      expect(s.onFire, isFalse);
      expect(s.streak, 0);
      final score = s.score, coins = s.coinsThisRun;
      final screen = game.reviveScreen!;
      step(game, .5);
      screen.tapHeart();
      for (var i = 0; i < 60 && screen.phoenix == null; i++) {
        game.update(1 / 60);
        await flushAndMount(game);
      }
      expect(s.squeeze.phase, SqueezePhase.idle);
      expect(s.squeeze.nextAt - s.runClock, inInclusiveRange(60, 120));
      step(game, .25);
      expect(s.squeeze.inset, inExclusiveRange(0, 40));
      step(game, .3);
      expect(s.squeeze.inset, 0);
      await throughPhoenix(game);
      expect(s.score, score);
      expect(s.coinsThisRun, coins);
      expect(s.hearts, 2);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§5.9 phoenix: rises from the floor to the safe line (the next hoop '
    'ahead), drifting back to x 70, burst at 1.0 s; Black Hole death '
    're-forms from a shock ring at the last position',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      await startRun(game);
      step(game, 1.2);
      final run = await dieAfter(
        game,
        6,
        mistake: const Mistake(
          MistakeCause.saw,
          themed: ThemedDeath('blackHole', noBody: true),
        ),
      );
      final screen = game.reviveScreen!;
      final bird = game.runBird!;
      final restY = bird.body.position.y;
      expect(restY, greaterThan(run.state.viewHeight / 2));
      step(game, .5);
      screen.tapHeart();
      for (var i = 0; i < 60 && screen.phoenix == null; i++) {
        game.update(1 / 60);
        await flushAndMount(game);
      }
      final p = screen.phoenix!;
      await flushAndMount(game);
      final ahead = run.spawner.hoops
          .where((h) => !h.resolved && h.planeX > run.state.camX + 66)
          .firstOrNull;
      expect(p.safeY, closeTo(reviveSafeLine(run), 1e-9));
      if (ahead != null) {
        expect(p.safeY, closeTo(ahead.frame().centre.y, 60));
      }
      step(game, .3);
      expect(bird.body.position.y, closeTo(restY, 2), reason: 'flames catch');
      step(game, .45);
      expect(p.burst, isFalse);
      step(game, .3);
      expect(p.burst, isTrue);
      expect(bird.body.position.x, closeTo(RunConfig.birdX, 1e-6));
      expect(bird.body.position.y, closeTo(p.safeY, 5));
      expect(bird.dead, isFalse, reason: 'the X eyes open at the burst');
      await throughPhoenix(game);
      expect(bird.spriteOpacity, 1);
    },
  );
}
