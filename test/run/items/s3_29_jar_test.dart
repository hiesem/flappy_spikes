import 'dart:ui' show Color;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart' show Powerup;
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/hud_config.dart';
import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/jar_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/run_badges.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/items/jar.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/pickups/firefly_swarm.dart';
import 'package:flappy_spikes/run/pickups/jar_pickup.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3e: the Firefly Jar (PRD-2 §3.29 rules, §5.28 look / sound).
void main() {
  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  JarFeature featureOf(RunController r) =>
      r.features.whereType<JarFeature>().single;

  /// Spawns a jar pickup on the flight line [lead] pt ahead of the bird.
  void spawnJar(RunController run, {double lead = 150}) {
    final bird = run.birdTrackPosition()!;
    run.spawner.spawnItem(
      GapItemPlan(kind: ElementId.jar, trackX: bird.x + lead, y: bird.y),
    );
  }

  /// Hand-flies (`god` mode) until [done], the bird glued to the jar.
  Future<void> flyToJar(
    FlappySpikesGame game,
    RunController run,
    bool Function() done, {
    int frames = 300,
  }) async {
    for (var f = 0; f < frames && !done(); f++) {
      final jar = pickupsOf(game).whereType<JarPickup>().firstOrNull;
      if (jar != null) game.runBird!.setFlight(y: jar.position.y, vy: 0);
      game.update(1 / 60);
      if (f % 10 == 0) await flushAndMount(game);
    }
  }

  group('§3.29 / §5.28 Firefly Jar rules (pure)', () {
    test(
      '§3.29 20 caught fills the jar (+25), 3 escapes break it; gap 15 '
      'weight 10 ≥ 30 apart; catch radius 16',
      () {
        expect(JarConfig.total, 20);
        expect(JarConfig.maxEscapes, 3);
        expect(JarConfig.reward, 25);
        expect(RunConfig.fireflySwarm, 7);
        expect(JarConfig.catchRadius, 16);
        expect(ElementId.jar.firstPossible, 15);
        expect(ElementId.jar.kind, ElementKind.gap);
        expect(ElementId.jar.storageId, 'jar');
        final rule = DirectorTables.prd2.gapItems[ElementId.jar]!;
        expect(rule.from, 15);
        expect(rule.weight, 10);
        expect(rule.minSince, 30);
        expect(PickupRadii.jar, 18);
        expect(PickupRadii.firefly, 16);
        expect(PickupRadii.forElement(ElementId.jar), 18);
        expect(PickupRadii.forElement(ElementId.fireflySwarm), 16);
        expect(pickupKindFor(ElementId.jar), isA<JarPickupKind>());
        expect(pickupKindFor(ElementId.fireflySwarm), isA<FireflySwarmKind>());
        expect(registeredPickupElements(), contains(ElementId.jar));
        expect(registeredPickupElements(), contains(ElementId.fireflySwarm));
        expect(ElementId.fireflySwarm.kind, ElementKind.gap);
        expect(JarConfig.bannerText, 'FIREFLY JAR');
        expect(JarConfig.bannerSub, 'catch 20 · let 3 escape and it breaks');
        expect(JarConfig.fullText, 'JAR FULL!');
        expect(JarConfig.fullSub, '20 fireflies · +25 coins');
        expect(JarConfig.brokeText, 'JAR BROKE');
        expect(JarConfig.brokeSub, '3 fireflies got away');
      },
    );

    test(
      '§5.28 look: the weaving swarm stays inside the ±45 pt band; jar '
      'colours, HUD numbers and burst',
      () {
        expect(JarConfig.weaveRate, 1.3);
        expect(JarConfig.weaveAx, 24);
        expect(JarConfig.weaveBx, 8);
        expect(JarConfig.weaveAy, 22);
        expect(JarConfig.weaveAx + JarConfig.weaveBx, lessThanOrEqualTo(JarConfig.weaveBand));
        expect(JarConfig.weaveAy, lessThanOrEqualTo(JarConfig.weaveBand));
        expect(JarConfig.weaveBand, 45);
        expect(JarConfig.pickupScale, 1.05);
        expect(JarConfig.hudJarX, 46);
        expect(JarConfig.hudJarY, 218 - HudConfig.collectLift); // S6-F03
        expect(JarConfig.hudJarScale, .95);
        expect(JarConfig.hudTextX, 66);
        expect(JarConfig.hudTextY, 210 - HudConfig.collectLift); // S6-F03
        expect(JarConfig.hudTextSize, 14);
        expect(JarConfig.bannerColor, const Color(0xFF7CB518));
        expect(JarConfig.brokeGrey, const Color(0xFF9E9E9E));
        expect(JarConfig.burstLime, const Color(0xFFE6FF6B));
        expect(JarConfig.fullPieces, 20);
        expect(JarConfig.fullSpeed, 180);
        expect(JarConfig.bobAmp, 5);
        expect(JarConfig.bobOmega, 2.6);
        expect(JarConfig.swayAmp, .12);
        expect(JarConfig.swayOmega, 2);
        expect(JarConfig.rays, 10);
        expect(JarConfig.rayOmega, .6);
        expect(JarConfig.rayLength, 36);
        expect(JarConfig.innerFlies, 4);
        expect(JarConfig.dotR, 2.6);
        expect(JarConfig.flyHaloR, 14);
        expect(JarConfig.markX, 72);
        expect(JarConfig.markY, 228 - HudConfig.collectLift); // S6-F03
        expect(JarConfig.markStep, 16);
        expect(JarConfig.markRed, const Color(0xFFFF3B5C));
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711, seed: 3),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      '§3.29 a swarm of 7 weaves inside ±45 pt of the line',
      setUp: (g, _) => boot(g),
      verify: (game, _) async {
        final run = await startRun(game);
        run.events.emit(PickupCollected(ElementId.jar, null));
        final bird = run.birdTrackPosition()!;
        run.spawner.spawnItem(
          GapItemPlan(
            kind: ElementId.fireflySwarm,
            trackX: bird.x + 160,
            toTrackX: bird.x + 380,
            y: bird.y,
            toY: bird.y,
            extra: RunConfig.fireflySwarm,
          ),
        );
        await flushAndMount(game);
        final swarm = pickupsOf(game).whereType<FireflySwarm>().single;
        expect(swarm.count, 7);
        expect(swarm.phases, hasLength(7));
        for (var f = 0; f < 240; f++) {
          swarm.update(1 / 60);
          for (var i = 0; i < swarm.count; i++) {
            final p = swarm.flyAt(i);
            expect((p.dx - swarm.position.x).abs(), lessThanOrEqualTo(JarConfig.weaveBand));
            expect((p.dy - swarm.position.y).abs(), lessThanOrEqualTo(JarConfig.weaveBand));
          }
        }
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
    '§3.29 grabbing the animated jar starts it: FIREFLY JAR, the badge, '
    'jarPickup + jar_collected',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      final sfx = sfxLog(game);
      spawnJar(run);
      await flushAndMount(game);
      final pickup = pickupsOf(game).whereType<JarPickup>().single;
      expect(pickup.hitRadius, PickupRadii.jar);
      await flyToJar(game, run, () => run.state.jar != null);
      expect(run.state.jar, isNotNull);
      expect(sfx, contains('jarPickup'));
      expect(analyticsLog(spy).map((e) => e.$1), contains('jar_collected'));
      final banner = RunHud.ensureFor(run).banners.current;
      expect(banner, isNotNull);
      expect(banner!.text, 'FIREFLY JAR');
      expect(banner.color, JarConfig.bannerColor);
      await flushAndMount(game);
      expect(
        RunHud.ensureFor(run).children.whereType<JarBadge>(),
        hasLength(1),
      );
    },
  );

  tester().testGameWidget(
    '§3.29 fireflies only appear after the jar is grabbed (the director '
    'fills the next gaps with swarms)',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      var swarms = 0;
      run.events.on<ElementSpawned>((e) {
        if (e.element == ElementId.fireflySwarm) swarms++;
      });
      await flyRun(game, maxSeconds: 30, untilHoops: 6);
      expect(swarms, 0, reason: 'no swarms before the jar');
      run.events.emit(PickupCollected(ElementId.jar, null));
      expect(run.state.jar, isNotNull);
      await flyRun(game, maxSeconds: 30, untilHoops: 10);
      expect(swarms, greaterThan(0), reason: 'swarms after the jar');
    },
  );

  tester(worldHeight: 568, seed: 29).testGameWidget(
    '§3.29 20 caught = JAR FULL: +25 coins (jar), jarFull, the banner and '
    'the badge gone',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final sfx = sfxLog(game);
      final earned = <CoinsEarned>[];
      run.events.on<CoinsEarned>(earned.add);
      run.events.emit(PickupCollected(ElementId.jar, null));
      final coins0 = run.state.coinsThisRun;
      final wallet0 = game.menu.wallet.balance;
      for (var i = 0; i < JarConfig.total; i++) {
        run.events.emit(PickupCollected(ElementId.fireflySwarm, null));
      }
      expect(run.state.jar, isNull);
      expect(run.state.coinsThisRun - coins0, 25);
      expect(game.menu.wallet.balance - wallet0, 25);
      expect(earned.single.amount, 25);
      expect(earned.single.source, CoinSource.jar);
      expect(featureOf(run).fullJars, 1);
      expect(featureOf(run).brokenJars, 0);
      expect(sfx, contains('jarTwinkle'));
      expect(sfx, contains('jarFull'));
      final banner = RunHud.ensureFor(run).banners.current;
      expect(banner, isNotNull);
      expect(banner!.text, 'JAR FULL!');
      expect(banner.color, JarConfig.bannerColor);
      expect(RunHud.ensureFor(run).children.whereType<JarBadge>(), isEmpty);
      final result = analyticsLog(
        spy,
      ).firstWhere((e) => e.$1 == 'jar_result');
      expect(result.$2, equals(<String, Object>{'result': 'full', 'caught': 20}));
    },
  );

  tester(worldHeight: 568, seed: 5).testGameWidget(
    '§3.29 3 escapes = JAR BROKE: no reward, jarBreak, the grey banner',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final sfx = sfxLog(game);
      run.events.emit(PickupCollected(ElementId.jar, null));
      for (var i = 0; i < 4; i++) {
        run.events.emit(PickupCollected(ElementId.fireflySwarm, null));
      }
      final coins0 = run.state.coinsThisRun;
      for (var i = 0; i < JarConfig.maxEscapes; i++) {
        run.events.emit(PickupEscaped(ElementId.fireflySwarm));
      }
      expect(run.state.jar, isNull);
      expect(run.state.coinsThisRun, coins0); // no reward
      expect(featureOf(run).brokenJars, 1);
      expect(featureOf(run).fullJars, 0);
      expect(sfx, contains('jarEscape'));
      expect(sfx, contains('jarBreak'));
      final banner = RunHud.ensureFor(run).banners.current;
      expect(banner, isNotNull);
      expect(banner!.text, 'JAR BROKE');
      expect(banner.color, JarConfig.brokeGrey);
      final result = analyticsLog(
        spy,
      ).firstWhere((e) => e.$1 == 'jar_result');
      expect(result.$2, equals(<String, Object>{'result': 'broken', 'caught': 4}));
    },
  );

  tester().testGameWidget(
    '§3.29 Q68 an extra life / shield save keeps the jar; a death that '
    'brings up the revive offer loses it (no reward), even after a revive',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game, starter: Powerup.shield);
      expect(run.state.shield, isTrue);
      run.events.emit(PickupCollected(ElementId.jar, null));
      run.events.emit(PickupCollected(ElementId.fireflySwarm, null));
      await flushAndMount(game);
      expect(RunHud.ensureFor(run).children.whereType<JarBadge>(), hasLength(1));
      // A save keeps the jar.
      run.state.invulnerable = 0;
      run.mistake(const Mistake(MistakeCause.missedHoop));
      expect(run.state.saves, 1);
      expect(run.state.jar, isNotNull);
      expect(run.state.jar!.caught, 1);
      // A death with ≥ 6 hoops: the offer comes up and the jar is gone.
      run.state.hoopsPassed = 6;
      run.state.invulnerable = 0;
      run.state.shield = false;
      killRun(game);
      expect(game.state, GameState.reviving);
      expect(run.state.jar, isNull);
      expect(featureOf(run).fullJars, 0);
      expect(featureOf(run).brokenJars, 0);
      expect(RunHud.ensureFor(run).children.whereType<JarBadge>(), isEmpty);
      await declineRevive(game);
      expect(run.state.jar, isNull);
      expect(run.ended, isTrue);
    },
  );

  tester().testGameWidget(
    '§3.0.3 a portal ride clears the swarms on screen without counting '
    'escapes; the jar keeps its caught count and still fills',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      run.events.emit(PickupCollected(ElementId.jar, null));
      for (var i = 0; i < 5; i++) {
        run.events.emit(PickupCollected(ElementId.fireflySwarm, null));
      }
      final bird = run.birdTrackPosition()!;
      run.spawner.spawnItem(
        GapItemPlan(
          kind: ElementId.fireflySwarm,
          trackX: bird.x + 160,
          toTrackX: bird.x + 380,
          extra: RunConfig.fireflySwarm,
        ),
      );
      await flushAndMount(game);
      run.spawner.clearAhead();
      expect(run.state.jar!.escaped, 0);
      expect(run.state.jar, isNotNull);
      final coins0 = run.state.coinsThisRun;
      for (var i = 0; i < 15; i++) {
        run.events.emit(PickupCollected(ElementId.fireflySwarm, null));
      }
      expect(run.state.jar, isNull);
      expect(run.state.coinsThisRun - coins0, 25);
      expect(featureOf(run).fullJars, 1);
    },
  );
}
