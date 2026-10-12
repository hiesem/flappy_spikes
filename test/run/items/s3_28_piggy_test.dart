import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart' show Powerup;
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/hud_config.dart';
import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/piggy_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/run_badges.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/items/piggy.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/pickups/piggy_coin.dart';
import 'package:flappy_spikes/run/pickups/piggy_pickup.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3e: the Piggy Bank (PRD-2 §3.28 rules, §5.27 look / sound).
void main() {
  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  PiggyFeature featureOf(RunController r) =>
      r.features.whereType<PiggyFeature>().single;

  /// Spawns a piggy pickup on the flight line [lead] pt ahead of the bird.
  void spawnPiggy(RunController run, {double lead = 150}) {
    final bird = run.birdTrackPosition()!;
    run.spawner.spawnItem(
      GapItemPlan(kind: ElementId.piggy, trackX: bird.x + lead, y: bird.y),
    );
  }

  /// Hand-flies (`god` mode) until [done], the bird glued to the piggy.
  Future<void> flyToPiggy(
    FlappySpikesGame game,
    RunController run,
    bool Function() done, {
    int frames = 300,
  }) async {
    for (var f = 0; f < frames && !done(); f++) {
      final piggy = pickupsOf(game).whereType<PiggyPickup>().firstOrNull;
      if (piggy != null) {
        game.runBird!.setFlight(y: piggy.position.y, vy: 0);
      }
      game.update(1 / 60);
      if (f % 10 == 0) await flushAndMount(game);
    }
  }

  group('§3.28 / §5.27 Piggy Bank rules (pure)', () {
    test(
      '§3.28 exactly 20 coins, 4 in the own gap, pays ×2 of what you '
      'caught; gap 12 weight 10 ≥ 30 apart; hit radii 18 / 14 (PRD-2.2 §26)',
      () {
        expect(PiggyConfig.total, 20);
        expect(PiggyConfig.ownGapCoins, 4);
        expect(RunConfig.piggyCoinsPerGap, 4);
        expect(RunConfig.piggyFollowGaps, 4);
        expect(PiggyConfig.ownGapCoins +
            RunConfig.piggyCoinsPerGap * RunConfig.piggyFollowGaps, 20);
        expect(PiggyConfig.ownGapStart, 20);
        expect(PiggyConfig.ownGapEnd, 40);
        expect(PiggyConfig.coinBulge, 18);
        expect(PiggyConfig.payoutMult, 2);
        expect(ElementId.piggy.firstPossible, 12);
        expect(ElementId.piggy.kind, ElementKind.gap);
        expect(ElementId.piggy.storageId, 'piggy');
        final rule = DirectorTables.prd2.gapItems[ElementId.piggy]!;
        expect(rule.from, 12);
        expect(rule.weight, 10);
        expect(rule.minSince, 30);
        expect(PickupRadii.piggy, 18);
        expect(PickupRadii.piggyCoin, 14); // PRD-2.2 §26 (PRD-2: 10)
        expect(PickupRadii.forElement(ElementId.piggy), 18);
        expect(PickupRadii.forElement(ElementId.piggyCoins), 14);
        expect(pickupKindFor(ElementId.piggy), isA<PiggyPickupKind>());
        expect(pickupKindFor(ElementId.piggyCoins), isA<PiggyCoinKind>());
        expect(registeredPickupElements(), contains(ElementId.piggy));
        expect(registeredPickupElements(), contains(ElementId.piggyCoins));
        expect(ElementId.piggyCoins.kind, ElementKind.gap);
        expect(PiggyConfig.bannerText, 'PIGGY BANK');
        expect(
          PiggyConfig.bannerSub,
          '20 coins appear · catch them all for the full ×2',
        );
        expect(PiggyConfig.payoutSub, ' / 20 coins · pays ×2');
      },
    );

    test(
      '§5.27 look: pig art, 1.25× pickup / 1.4× HUD at (46,216), HUD '
      'numbers and smash colours',
      () {
        expect(PiggyConfig.body, const Color(0xFFFF8AC4));
        expect(PiggyConfig.snout, const Color(0xFFFF6FB0));
        expect(PiggyConfig.legs, const Color(0xFFE05A99));
        expect(PiggyConfig.nostril, const Color(0xFFB0306E));
        expect(PiggyConfig.eye, const Color(0xFF3E1028));
        expect(PiggyConfig.bodyRx, 13);
        expect(PiggyConfig.bodyRy, 10);
        expect(PiggyConfig.pickupScale, 1.25);
        expect(PiggyConfig.hudScale, 1.4);
        expect(PiggyConfig.bobAmp, 3);
        expect(PiggyConfig.bobOmega, 3);
        expect(PiggyConfig.haloColor, const Color(0xFFFF8AC4));
        expect(PiggyConfig.haloR, 26);
        expect(PiggyConfig.haloAlpha, .5);
        expect(PiggyConfig.coinSize, 16); // PRD-2.2 §26 (PRD-2: 8)
        expect(PiggyConfig.fetchSeconds, .35);
        expect(PiggyConfig.hudPigX, 46);
        expect(PiggyConfig.hudPigY, 216 - HudConfig.collectLift); // S6-F03
        expect(PiggyConfig.hudTextX, 68);
        expect(PiggyConfig.hudTextY, 209 - HudConfig.collectLift); // S6-F03
        expect(PiggyConfig.hudTextSize, 16);
        expect(PiggyConfig.hudBarX, 68);
        expect(PiggyConfig.hudBarY, 220 - HudConfig.collectLift); // S6-F03
        expect(PiggyConfig.hudBarW, 90);
        expect(PiggyConfig.hudBarH, 8);
        expect(PiggyConfig.hudBarRadius, 4);
        expect(PiggyConfig.hudMissedY, 236 - HudConfig.collectLift); // S6-F03
        expect(PiggyConfig.hudMissedSize, 11);
        expect(PiggyConfig.smashPieces, 22);
        expect(PiggyConfig.smashSpeed, 200);
        expect(PiggyConfig.smashColors, hasLength(3));
        expect(PiggyConfig.bannerColor, const Color(0xFFFF6FB0));
        expect(PiggyConfig.payoutColor, const Color(0xFFFFB529));
      },
    );
  });

  late AnalyticsSpy spy;
  FlameTester<FlappySpikesGame> tester({
    double worldHeight = 711,
    int seed = 11,
  }) => FlameTester<FlappySpikesGame>(
    () {
      spy = AnalyticsSpy();
      return createRunTestGame(
        worldHeight: worldHeight,
        seed: seed,
        services: spy,
      );
    },
    gameSize: Vector2(320, worldHeight),
  );

  tester().testGameWidget(
    '§3.28 grabbing the piggy starts the bank: PIGGY BANK, the badge, '
    'piggyOink + piggy_collected and the 4 own-gap coins on the line',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      final sfx = sfxLog(game);
      spawnPiggy(run);
      await flushAndMount(game);
      final piggyX = pickupsOf(game)
          .firstWhere((p) => p.id == ElementId.piggy)
          .position
          .x;
      await flyToPiggy(game, run, () => run.state.piggy != null);
      expect(run.state.piggy, isNotNull);
      expect(sfx, contains('piggyOink'));
      expect(
        analyticsLog(spy).map((e) => e.$1),
        contains('piggy_collected'),
      );
      final banner = RunHud.ensureFor(run).banners.current;
      expect(banner, isNotNull);
      expect(banner!.text, 'PIGGY BANK');
      expect(banner.color, PiggyConfig.bannerColor);
      await flushAndMount(game); // the badge / field were add()-ed
      expect(
        RunHud.ensureFor(run).children.whereType<PiggyBadge>(),
        hasLength(1),
      );
      // The own-gap field (PRD-2.2 §26: coins 45 pt apart, mock B): 4 coins
      // from 20 pt after the piggy on the line toward the next hoop; when
      // they would not end 40 pt before it, in the gap after it.
      final field = pickupsOf(game).whereType<PiggyCoin>().single;
      expect(field.count, 4);
      final next = run.spawner.nextHoopAhead()!;
      final x0 = field.plan!.trackX, x1 = field.plan!.toTrackX!;
      final y0 = field.plan!.y!, y1 = field.plan!.toY!;
      expect(x1 - x0, closeTo(3 * 45, 1e-6));
      final own = x1 <= next.plan.trackX - 40 + 1e-6;
      if (own) {
        expect(x0, closeTo(piggyX + 20, 1e-6));
      } else {
        expect(x0, greaterThan(next.plan.lastRingX + 40));
      }
      for (var i = 0; i < 4; i++) {
        final u = (i + 1) / 5;
        final coin = field.coinAt(i);
        expect(coin.dx, closeTo(x0 + 45.0 * i, 1e-6));
        expect(
          coin.dy,
          closeTo(
            y0 +
                (y1 - y0) * i / 3 -
                PiggyConfig.coinBulge * math.sin(math.pi * u),
            1e-6,
          ),
        );
      }
    },
  );

  tester(worldHeight: 568, seed: 3).testGameWidget(
    '§3.28 caught coins go into the bank (not the wallet) and all 20 resolve '
    'the smash: +32 for 16 caught, piggy_paid, piggySmash',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final sfx = sfxLog(game);
      final earned = <CoinsEarned>[];
      run.events.on<CoinsEarned>(earned.add);
      run.events.emit(PickupCollected(ElementId.piggy, null));
      expect(run.state.piggy, isNotNull);
      final coins0 = run.state.coinsThisRun;
      final wallet0 = game.menu.wallet.balance;
      // 16 caught: the bank, never the wallet.
      for (var i = 0; i < 16; i++) {
        run.events.emit(PickupCollected(ElementId.piggyCoins, null));
      }
      expect(run.state.piggy!.caught, 16);
      expect(run.state.coinsThisRun, coins0);
      expect(game.menu.wallet.balance, wallet0);
      expect(earned, isEmpty);
      // 4 more pass uncaught: missed, and the bank resolves.
      for (var i = 0; i < 4; i++) {
        run.events.emit(PickupEscaped(ElementId.piggyCoins));
      }
      expect(run.state.piggy, isNull);
      expect(run.state.coinsThisRun - coins0, 32); // 16 × 2
      expect(game.menu.wallet.balance - wallet0, 32);
      expect(earned.single.amount, 32);
      expect(earned.single.source, CoinSource.piggy);
      expect(earned.single.eggX2, isFalse);
      expect(featureOf(run).paid, 1);
      expect(sfx, contains('piggyCoin'));
      expect(sfx, contains('piggyMiss'));
      expect(sfx, contains('piggySmash'));
      expect(RunHud.ensureFor(run).children.whereType<PiggyBadge>(), isEmpty);
      final banner = RunHud.ensureFor(run).banners.current;
      expect(banner, isNotNull);
      expect(banner!.text, '+32');
      expect(banner.color, PiggyConfig.payoutColor);
      final paid = analyticsLog(
        spy,
      ).firstWhere((e) => e.$1 == 'piggy_paid');
      expect(paid.$2, equals(<String, Object>{'caught': 16, 'payout': 32}));
    },
  );

  tester(worldHeight: 711, seed: 29).testGameWidget(
    '§3.28 the chick\'s ×2 stacks on the pay-out: 10 caught / 10 missed pays '
    '20 ×2 = 40',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final earned = <CoinsEarned>[];
      run.events.on<CoinsEarned>(earned.add);
      run.events.emit(PickupCollected(ElementId.piggy, null));
      run.state.egg = EggState()..stage = EggStage.chick;
      final coins0 = run.state.coinsThisRun;
      for (var i = 0; i < 10; i++) {
        run.events.emit(PickupCollected(ElementId.piggyCoins, null));
      }
      for (var i = 0; i < 10; i++) {
        run.events.emit(PickupEscaped(ElementId.piggyCoins));
      }
      expect(run.state.piggy, isNull);
      expect(run.state.coinsThisRun - coins0, 40);
      expect(earned.single.amount, 40);
      expect(earned.single.eggX2, isTrue);
      expect(RunHud.ensureFor(run).banners.current!.text, '+20');
    },
  );

  tester(worldHeight: 568, seed: 5).testGameWidget(
    '§3.28 Q66 a shield save keeps the bank; a death that brings up the '
    'revive offer loses it (no pay-out), even after a revive',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game, starter: Powerup.shield);
      expect(run.state.shield, isTrue);
      run.events.emit(PickupCollected(ElementId.piggy, null));
      for (var i = 0; i < 4; i++) {
        run.events.emit(PickupCollected(ElementId.piggyCoins, null));
      }
      await flushAndMount(game); // the badge was add()-ed
      // A save keeps the bank (only a death clears it).
      run.state.invulnerable = 0;
      run.mistake(const Mistake(MistakeCause.missedHoop));
      expect(run.state.saves, 1);
      expect(run.state.piggy, isNotNull);
      expect(run.state.piggy!.caught, 4);
      expect(
        RunHud.ensureFor(run).children.whereType<PiggyBadge>(),
        hasLength(1),
      );
      // A death with ≥ 6 hoops: the offer comes up and the bank is gone.
      run.state.hoopsPassed = 6;
      run.state.invulnerable = 0;
      run.state.shield = false;
      killRun(game);
      expect(game.state, GameState.reviving);
      expect(run.state.piggy, isNull);
      expect(featureOf(run).paid, 0);
      expect(RunHud.ensureFor(run).children.whereType<PiggyBadge>(), isEmpty);
      await declineRevive(game);
      expect(run.state.piggy, isNull);
      expect(run.ended, isTrue);
    },
  );

  tester().testGameWidget(
    '§3.0.3 a portal ride clears the on-screen coins without counting them '
    'missed; the director places them again and the bank resolves at 20 '
    'caught or missed (S6-41)',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      run.events.emit(PickupCollected(ElementId.piggy, null));
      for (var i = 0; i < 8; i++) {
        run.events.emit(PickupCollected(ElementId.piggyCoins, null));
      }
      // A 4-coin field ahead of the bird is cleared by a portal ride.
      final bird = run.birdTrackPosition()!;
      run.spawner.spawnItem(
        GapItemPlan(
          kind: ElementId.piggyCoins,
          trackX: bird.x + 200,
          toTrackX: bird.x + 380,
          extra: 4,
        ),
      );
      await flushAndMount(game);
      run.spawner.clearAhead();
      expect(run.state.piggy!.missed, 0);
      // The 4 cleared coins are owed again (placed after the landing): no
      // follow gap was planned yet, so 4 × 4 follow coins + the 4 cleared.
      expect(
        run.director.piggyCoinsOwed,
        RunConfig.piggyFollowGaps * RunConfig.piggyCoinsPerGap + 4,
      );
      // 8 more caught = 16: not 20 resolved yet, so no early pay-out.
      final coins0 = run.state.coinsThisRun;
      for (var i = 0; i < 8; i++) {
        run.events.emit(PickupCollected(ElementId.piggyCoins, null));
      }
      expect(run.state.piggy, isNotNull);
      expect(featureOf(run).paid, 0);
      // The re-placed 4 are caught: the bank pays 20 caught × 2.
      for (var i = 0; i < 4; i++) {
        run.events.emit(PickupCollected(ElementId.piggyCoins, null));
      }
      expect(run.state.piggy, isNull);
      expect(run.state.coinsThisRun - coins0, 40);
      expect(featureOf(run).paid, 1);
    },
  );
}
