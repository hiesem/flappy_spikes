import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/egg_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/particle_pool.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/normal.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/items/egg.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §23: a rim touch breaks the egg; ride rings don't count.
void main() {
  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  EggFeature featureOf(RunController r) =>
      r.features.whereType<EggFeature>().single;

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

  late AnalyticsSpy spy;
  FlameTester<FlappySpikesGame> tester() => FlameTester<FlappySpikesGame>(
    () {
      spy = AnalyticsSpy();
      return createRunTestGame(worldHeight: 711, seed: 5, services: spy);
    },
    gameSize: Vector2(320, 711),
  );

  /// Puts an egg on the bird's back (as the pickup does) and cracks it
  /// [cracks] times with normal passes.
  void carryEgg(RunController run, {int cracks = 0}) {
    run.events.emit(PickupCollected(ElementId.egg, null));
    for (var i = 0; i < cracks; i++) {
      run.events.emit(HoopPassed(null, perfect: true));
    }
  }

  tester().testGameWidget(
    '§23.3 with the egg at 2 cracks a rim touch breaks it: egg gone, shell '
    'pieces, egg_crack once, no banner, egg_broken {rim, 2}; the touched '
    'hoop does not crack',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      carryEgg(run, cracks: 2);
      expect(run.state.egg!.cracks, 2);
      final sfx = sfxLog(game);
      final crack0 = sfx.where((n) => n == 'eggCrack').length;
      final banner0 = RunHud.ensureFor(run).banners.current;
      final pool = featureOf(run).bursts!.pool;
      final alive0 = pool.alive;
      final hoop = fakeHoop();
      run.events.emit(RimTouched(hoop, Vector2(200, 300), Vector2(0, 1)));
      expect(run.state.egg, isNull);
      expect(featureOf(run).broken, 1);
      // Shell triangles + yolk pieces, falling with gravity.
      expect(pool.alive - alive0, EggConfig.breakPieces);
      final pieces = pool.particles.skip(alive0).toList();
      expect(pieces.every((p) => p.shape == ParticleShape.triangle), isTrue);
      expect(pieces.every((p) => p.gravity > 0), isTrue);
      expect(
        pieces.map((p) => p.color).toSet(),
        containsAll(EggConfig.breakColors.toSet()),
      );
      expect(sfx.where((n) => n == 'eggCrack').length - crack0, 1);
      expect(sfx, isNot(contains('eggBye')));
      expect(RunHud.ensureFor(run).banners.current, same(banner0));
      final broken = analyticsLog(
        spy,
      ).where((e) => e.$1 == 'egg_broken').toList();
      expect(broken, hasLength(1));
      expect(broken.single.$2, equals({'cause': 'rim', 'cracks': 2}));
      expect(
        analyticsLog(spy).map((e) => e.$1),
        isNot(contains('chick_lost')),
      );
      // The touched hoop's pass that follows cracks nothing, even if a new
      // egg was picked up in between.
      carryEgg(run);
      run.events.emit(HoopPassed(hoop, perfect: false, rimTouched: true));
      expect(run.state.egg!.cracks, 0);
      run.events.emit(HoopPassed(fakeHoop(), perfect: true));
      expect(run.state.egg!.cracks, 1);
    },
  );

  tester().testGameWidget(
    '§23.3 a clean off-centre pass (§11) cracks the egg and does not break it',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      carryEgg(run, cracks: 1);
      run.events.emit(HoopPassed(fakeHoop(), perfect: false));
      expect(run.state.egg, isNotNull);
      expect(run.state.egg!.cracks, 2);
      expect(featureOf(run).broken, 0);
    },
  );

  tester().testGameWidget(
    '§23.3 ride rings neither crack nor break the egg (event level: a portal '
    'ring pass and a rim contact during a ride)',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      carryEgg(run, cracks: 3);
      run.state.ride = RideState(kind: RideKind.portal, rideId: RideId.space);
      run.events.emit(HoopPassed(fakeHoop(), perfect: true, duringRide: true));
      run.events.emit(
        RimTouched(fakeHoop(), Vector2(200, 300), Vector2(0, 1)),
      );
      expect(run.state.egg, isNotNull);
      expect(run.state.egg!.cracks, 3);
      run.state.ride = null;
    },
  );

  tester().testGameWidget(
    '§23.3 a forced comet ride: its rings neither crack nor break the egg',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: ElementId.comet.firstPossible!,
        force: [ElementId.comet],
      );
      final comet = run.features.whereType<CometFeature>().single;
      await flyUntil(game, (_) => comet.active, maxSeconds: 40);
      expect(comet.active, isTrue);
      // Carried in from before the ride (2 cracks).
      run.state.egg = EggState()..cracks = 2;
      final passes0 = run.state.hoopsPassed;
      await flyUntil(game, (r) => r.state.ride == null, maxSeconds: 30);
      expect(run.state.hoopsPassed, greaterThan(passes0),
          reason: 'the comet passed rings');
      expect(run.state.egg, isNotNull);
      expect(run.state.egg!.cracks, 2);
    },
  );

  tester().testGameWidget(
    '§23.3 after hatching a rim touch still loses the chick with +1 LOST (PRD-2.3 §14.3)',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.runDebug.god = true;
      carryEgg(run, cracks: EggConfig.rings);
      expect(run.state.egg!.stage, EggStage.chick);
      run.events.emit(
        RimTouched(fakeHoop(), Vector2(200, 300), Vector2(0, 1)),
      );
      expect(run.state.egg, isNull);
      expect(RunHud.ensureFor(run).banners.current?.text, '+1 LOST');
      expect(featureOf(run).broken, 0);
    },
  );

  tester().testGameWidget(
    '§23.3 a crash before hatching still loses the egg (unchanged)',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      carryEgg(run, cracks: 3);
      killRun(game);
      expect(run.state.egg, isNull);
      expect(featureOf(run).broken, 0);
      expect(
        analyticsLog(spy).map((e) => e.$1),
        isNot(contains('egg_broken')),
      );
    },
  );
}
