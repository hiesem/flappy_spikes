import 'dart:ui' show Color;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart' show Powerup;
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/director_tables.dart';
import 'package:flappy_spikes/run/config/egg_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/text_pop.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/normal.dart';
import 'package:flappy_spikes/run/hud/run_badges.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/items/egg.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/pickups/egg_pickup.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/screens/revive_ladder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3e: the Egg and the ×2 chick (PRD-2 §3.27 rules, §5.26 look / sound).
void main() {
  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  EggFeature featureOf(RunController r) =>
      r.features.whereType<EggFeature>().single;

  /// A stand-in hoop for the rim event (only its identity matters).
  Hoop fakeHoop() => Hoop(
    plan: const SlotPlan(
      index: 99,
      kind: HoopKindId.normal,
      element: ElementId.normalHoop,
      trackX: 0,
      centreY: 355,
      opening: 140,
      advance: 310,
    ),
    kind: NormalHoopKind(),
  );

  /// Spawns an egg on the flight line [lead] pt ahead of the bird.
  void spawnEgg(RunController run, {double lead = 150}) {
    final bird = run.birdTrackPosition()!;
    run.spawner.spawnItem(
      GapItemPlan(kind: ElementId.egg, trackX: bird.x + lead, y: bird.y),
    );
  }

  /// Flies hand-guided (`god` mode) until [done], the bird glued to the egg
  /// pickup's line.
  Future<void> flyToEgg(
    FlappySpikesGame game,
    RunController run,
    bool Function() done, {
    int frames = 300,
  }) async {
    for (var f = 0; f < frames && !done(); f++) {
      final egg = pickupsOf(game).whereType<EggPickup>().firstOrNull;
      if (egg != null && !egg.collected) {
        game.runBird!.setFlight(y: egg.position.y, vy: 0);
      }
      game.update(1 / 60);
      if (f % 10 == 0) await flushAndMount(game);
    }
  }

  group('§3.27 / §5.26 Egg rules (pure)', () {
    test('§3.27 5 rings, gap 10, weight 12, ≥ 15 apart, one egg / chick, '
        'hit radius 16', () {
      expect(EggConfig.rings, 5);
      expect(ElementId.egg.firstPossible, 10);
      expect(ElementId.egg.kind, ElementKind.gap);
      expect(ElementId.egg.storageId, 'egg');
      final rule = DirectorTables.prd2.gapItems[ElementId.egg]!;
      expect(rule.from, 10);
      expect(rule.weight, 12);
      expect(rule.minSince, 15);
      expect(PickupRadii.egg, 16);
      expect(PickupRadii.forElement(ElementId.egg), 16);
      expect(pickupKindFor(ElementId.egg), isA<EggPickupKind>());
      expect(registeredPickupElements(), contains(ElementId.egg));
      expect(EggConfig.pickupPop, 'EGG! hatches in 5 rings');
    });

    test('§5.26 look: cream 8 × 10 oval at 1.3× with three speckles and a '
        'warm halo, zig-zag cracks, chick at 48 %, gold ×2 pill 64 × 24', () {
      expect(EggConfig.ovalRx, 8);
      expect(EggConfig.ovalRy, 10);
      expect(EggConfig.oval, const Color(0xFFFFF3D6));
      expect(EggConfig.pickupScale, 1.3);
      expect(EggConfig.speckles, hasLength(3));
      expect(EggConfig.speckle, const Color(0xFFE8C58A));
      expect(EggConfig.haloR, 22);
      expect(EggConfig.haloAlpha, .6);
      expect(EggConfig.crackColor, const Color(0xFF8D6E3F));
      expect(EggConfig.crackWidth, 1.2);
      expect(EggConfig.wobbleSeconds, .4);
      expect(EggConfig.onBirdDy, -22);
      expect(EggConfig.chickScale, .48);
      expect(EggConfig.chickBehind, 36);
      expect(EggConfig.chickBelow, 10);
      expect(EggConfig.hudW, 64);
      expect(EggConfig.hudH, 24);
      expect(EggConfig.hatchPieces, 12);
      expect(EggConfig.bobAmp, 3);
      expect(EggConfig.byeText, 'bye!');
      expect(EggConfig.hatchText, 'HATCHED!');
      expect(
        EggConfig.hatchSub,
        '×2 on every coin while the chick flies with you',
      );
      expect(EggConfig.lostText, '×2 LOST');
      expect(EggConfig.lostSub, 'you touched a rim · the chick flew off');
      expect(EggConfig.lostGrey, const Color(0xFF9E9E9E));
    });
  });

  late AnalyticsSpy spy;
  FlameTester<FlappySpikesGame> tester() => FlameTester<FlappySpikesGame>(
    () {
      spy = AnalyticsSpy();
      return createRunTestGame(worldHeight: 711, seed: 5, services: spy);
    },
    gameSize: Vector2(320, 711),
  );

  tester().testGameWidget(
    '§3.27 the pickup goes on the bird\'s back: "EGG! hatches in 5 rings", '
    'egg_pickup + egg_collected, no extra coin pickups',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      final sfx = sfxLog(game);
      final coins0 = run.state.coinsThisRun;
      spawnEgg(run);
      await flushAndMount(game);
      final pickup = pickupsOf(game).whereType<EggPickup>().single;
      expect(pickup.hitRadius, PickupRadii.egg);
      await flyToEgg(game, run, () => run.state.egg != null);
      final egg = run.state.egg;
      expect(egg, isNotNull);
      expect(egg!.stage, EggStage.egg);
      expect(egg.cracks, 0);
      // The egg is carried, not banked: no coins for the pickup itself.
      expect(pickup.collected, isTrue);
      await flushAndMount(game);
      expect(
        run.layers.fx.children.whereType<TextPop>().map((p) => p.text),
        contains('EGG! hatches in 5 rings'),
      );
      expect(sfx, contains('eggPickup'));
      expect(
        analyticsLog(spy).map((e) => e.$1),
        contains('egg_collected'),
      );
      expect(run.state.coinsThisRun - coins0, 0);
    },
  );

  tester().testGameWidget(
    '§3.27 every ring cracks it (PRD-2.2 §23: a ride ring does not): '
    'countdown 4…1, a crack '
    'sound each; 5 rings hatch the chick with HATCHED! and the ×2 badge',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      final sfx = sfxLog(game);
      spawnEgg(run);
      await flushAndMount(game);
      await flyToEgg(game, run, () => run.state.egg != null);
      expect(run.state.egg, isNotNull);
      // PRD-2.2 §23 (changed from §3.27): a portal-ride ring no longer
      // cracks the egg.
      run.events.emit(HoopPassed(null, perfect: true, duringRide: true));
      expect(run.state.egg!.cracks, 0);
      for (var i = 0; i < 4; i++) {
        run.events.emit(HoopPassed(null, perfect: true));
        expect(run.state.egg!.cracks, i + 1);
        await flushAndMount(game);
      }
      expect(
        run.layers.fx.children.whereType<TextPop>().map((p) => p.text),
        containsAll(<String>['4', '3', '2', '1']),
      );
      expect(sfx.where((n) => n == 'eggCrack').length, 4);
      // The 5th ring hatches it.
      run.events.emit(HoopPassed(null, perfect: true));
      expect(run.state.egg!.stage, EggStage.chick);
      await flushAndMount(game);
      expect(sfx, contains('eggHatch'));
      final banner = RunHud.ensureFor(run).banners.current;
      expect(banner, isNotNull);
      expect(banner!.text, 'HATCHED!');
      expect(
        analyticsLog(spy).map((e) => e.$1),
        contains('egg_hatched'),
      );
      expect(
        RunHud.ensureFor(run).children.whereType<EggBadge>().length,
        1,
      );
      // Hatching is driven by the feature: the countdown pops stop at 4.
      expect(
        run.layers.fx.children.whereType<TextPop>().map((p) => p.text),
        isNot(contains('0')),
      );
    },
  );

  tester().testGameWidget(
    'PRD-2.3 §14.3 the chick doubles no coins (ring coins and every bonus '
    'pay their own amount) and adds +1 point per hoop passed '
    '(chick_lost points_added)',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      spawnEgg(run);
      await flushAndMount(game);
      await flyToEgg(game, run, () => run.state.egg != null);
      for (var i = 0; i < EggConfig.rings; i++) {
        run.events.emit(HoopPassed(null, perfect: true));
      }
      expect(run.state.egg!.stage, EggStage.chick);
      final feature = featureOf(run);
      final earned = <CoinsEarned>[];
      run.events.on<CoinsEarned>(earned.add);
      final wallet0 = game.menu.wallet.balance;
      final coins0 = run.state.coinsThisRun;
      for (final (n, source) in [
        (1, CoinSource.hoop),
        (2, CoinSource.perfect),
        (2, CoinSource.starTrail),
        (10, CoinSource.piggy),
        (8, CoinSource.jar),
      ]) {
        run.ctx.earn(n, source);
      }
      expect(run.state.coinsThisRun - coins0, 1 + 2 + 2 + 10 + 8);
      expect(game.menu.wallet.balance - wallet0, 1 + 2 + 2 + 10 + 8);
      expect(earned.map((e) => e.amount).toList(), [1, 2, 2, 10, 8]);
      expect(earned.any((e) => e.eggX2), isFalse);
      // +1 point per hoop passed while the chick flies: a non-perfect pass
      // scores 1 + 1.
      final score0 = run.state.score;
      run.events.emit(HoopPassed(null, perfect: false));
      expect(run.state.score - score0, 2);
      run.events.emit(HoopPassed(null, perfect: true));
      expect(feature.pointsAdded, 2);
    },
  );

  tester().testGameWidget(
    '§3.27 a rim touch scares the chick away: "bye!", the +1 LOST banner '
    '(PRD-2.3 §14.3), egg_bye and chick_lost(rim) with points_added; no '
    '+1 after',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      final sfx = sfxLog(game);
      spawnEgg(run);
      await flushAndMount(game);
      await flyToEgg(game, run, () => run.state.egg != null);
      for (var i = 0; i < EggConfig.rings; i++) {
        run.events.emit(HoopPassed(null, perfect: true));
      }
      expect(run.state.egg!.stage, EggStage.chick);
      run.events.emit(HoopPassed(null, perfect: true)); // +1 point
      run.events.emit(
        RimTouched(fakeHoop(), Vector2(200, 300), Vector2(0, 1)),
      );
      expect(run.state.egg, isNull);
      expect(sfx, contains('eggBye'));
      final banner = RunHud.ensureFor(run).banners.current;
      expect(banner, isNotNull);
      expect(banner!.text, '+1 LOST');
      expect(banner.color, EggConfig.lostGrey);
      final lost = analyticsLog(
        spy,
      ).where((e) => e.$1 == 'chick_lost').toList();
      expect(lost, hasLength(1));
      expect(lost.single.$2, equals({'cause': 'rim', 'points_added': 1}));
      // The chick is gone: no +1 any more.
      final score0 = run.state.score;
      run.events.emit(HoopPassed(null, perfect: false));
      expect(run.state.score - score0, 1);
    },
  );

  tester().testGameWidget(
    '§3.27 a crash before hatching breaks the egg (no chick_lost); a crash '
    'with the chick loses it (chick_lost crash)',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      spawnEgg(run);
      await flushAndMount(game);
      await flyToEgg(game, run, () => run.state.egg != null);
      // Carry it (3 rings), then crash: the egg is gone, silently.
      for (var i = 0; i < 3; i++) {
        run.events.emit(HoopPassed(null, perfect: true));
      }
      expect(run.state.egg!.cracks, 3);
      game.runDebug.god = false;
      killRun(game);
      expect(run.state.egg, isNull);
      expect(
        analyticsLog(spy).map((e) => e.$1),
        isNot(contains('chick_lost')),
      );
      expect(RunHud.ensureFor(run).children.whereType<EggBadge>(), isEmpty);
    },
  );

  tester().testGameWidget(
    '§3.27 Q66 an extra life / shield save loses the chick too, and a death '
    'that brings up the revive offer loses it even after a revive',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game, starter: Powerup.shield);
      game.runDebug.god = true;
      expect(run.state.shield, isTrue);
      spawnEgg(run);
      await flushAndMount(game);
      await flyToEgg(game, run, () => run.state.egg != null);
      for (var i = 0; i < EggConfig.rings; i++) {
        run.events.emit(HoopPassed(null, perfect: true));
      }
      expect(run.state.egg!.stage, EggStage.chick);
      // A save (the shield absorbs it) loses the chick (Q66).
      game.runDebug.god = false;
      run.state.invulnerable = 0;
      run.mistake(const Mistake(MistakeCause.missedHoop));
      expect(run.state.saves, 1);
      expect(run.state.egg, isNull);
      expect(
        analyticsLog(spy).where((e) => e.$1 == 'chick_lost').single.$2,
        equals({'cause': 'crash', 'coins_doubled': 0}),
      );
      // A fresh chick, then a death with ≥ 6 hoops: the offer comes up and
      // the chick is already gone; reviving does not bring it back.
      run.events.emit(PickupCollected(ElementId.egg, null));
      for (var i = 0; i < EggConfig.rings; i++) {
        run.events.emit(HoopPassed(null, perfect: true));
      }
      expect(run.state.egg!.stage, EggStage.chick);
      run.state.hoopsPassed = 6; // ≥ ReviveConfig.minHoops
      run.state.invulnerable = 0;
      run.state.shield = false;
      killRun(game);
      expect(game.state, GameState.reviving);
      expect(ReviveLadder.eligible(run.state), isTrue);
      expect(run.state.egg, isNull);
      expect(RunHud.ensureFor(run).children.whereType<EggBadge>(), isEmpty);
      await declineRevive(game);
      expect(run.state.egg, isNull);
      expect(run.ended, isTrue);
    },
  );
}
