import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/hoop_kind.dart';
import 'package:flappy_spikes/run/hoops/kinds/registry.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/pickups/registry.dart';
import 'package:flappy_spikes/run/run_context.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_layers.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

class _TestKind extends HoopKind {
  _TestKind(this.id);
  @override
  final HoopKindId id;
  @override
  bool get usesTierLook => true;
  @override
  void buildVisual(Hoop h, RunContext c) {}
}

class _TestPickup extends Pickup {
  _TestPickup(GapItemPlan p)
    : super(
        id: p.kind,
        hitRadius: PickupRadii.forElement(p.kind) ?? 16,
        plan: p,
        position: Vector2(p.trackX, p.y ?? 300),
      );

  int collects = 0;

  @override
  void onCollect(RunContext c) => collects++;
}

class _TestPickupKind extends PickupKind {
  _TestPickupKind(this.element);
  @override
  final ElementId element;
  @override
  Pickup build(GapItemPlan p, RunContext c) => _TestPickup(p);
}

/// Switches hoops on for one test (as WP-1a's registration will).
void registerTestKinds({Set<HoopKindId> hoops = const {HoopKindId.normal}}) {
  for (final id in hoops) {
    testHoopKinds[id] = () => _TestKind(id);
  }
  testPickupKinds[ElementId.heart] = () => _TestPickupKind(ElementId.heart);
  addTearDown(() {
    testHoopKinds.clear();
    testPickupKinds.clear();
  });
}

void main() {
  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    game.sound.enabled = false;
    await preloadImages(game);
  }

  group('§3.0 run core with the normal hoop (WP-0b plumbing, WP-1a course)', () {
    final spy = AnalyticsSpy();
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(services: spy, seed: 99),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );

    tester.testGameWidget(
      '§3.0.1 START builds a RunController; the hoops play; the run keeps '
      'the score, ends through the mistake pipeline (after the tumble) and '
      'reports run_end',
      setUp: (game, _) => boot(game),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game);
        expect(run.setup.seed, 99);
        expect(run.started, isTrue);
        expect(run.spawner.live, isTrue);
        expect(game.isScrolling, isTrue);
        run.events.recordLog = true;

        final flight = await flyRun(game, maxSeconds: 30, untilHoops: 2);
        expect(hoopsOf(game), isNotEmpty);
        expect(flight.hoops, greaterThanOrEqualTo(2));
        expect(run.state.score, game.score);
        expect(run.clock.t, greaterThan(2));
        // §3.0.1 the camera is the bird's forward motion. PRD-2.3 §14.4:
        // the cruise follows the hoop index (150 → 150.9 over hoops 0–2).
        expect(
          run.state.camX,
          closeTo(run.clock.t * RunConfig.cruise(run.state.hoopIndex), 5),
        );

        killRun(game, MistakeCause.spikes);
        await flushAndMount(game);
        expect(game.state, GameState.results);
        expect(run.ended, isTrue);
        expect(run.events.log.whereType<RunDied>(), hasLength(1));
        expect(run.events.log.whereType<RunEnded>(), hasLength(1));
        expect(game.world.children.query<ResultsScreen>(), hasLength(1));

        final names = analyticsLog(spy).map((e) => e.$1).toList();
        expect(names, containsAllInOrder(['run_end', 'run_director_hoops', 'run_director_items']));
        final end = analyticsLog(spy).firstWhere((e) => e.$1 == 'run_end').$2!;
        expect(end['cause'], 'spikes');
        expect(end['hoops'], flight.hoops);
        for (final n in ['run_director_hoops', 'run_director_items']) {
          final p = analyticsLog(spy).firstWhere((e) => e.$1 == n).$2!;
          expect(p.length, lessThanOrEqualTo(25));
        }

        game.goHome();
        await flushAndMount(game);
        expect(game.run, isNull);
        expect(game.state, GameState.start);
      },
    );

    tester.testGameWidget(
      '§7 the autopilot flies the hoop course',
      setUp: (game, _) => boot(game),
      verify: (game, _) async {
        await startRun(game);
        final flight = await flyRun(game, maxSeconds: 40, untilHoops: 8);
        expect(flight.hoops, greaterThanOrEqualTo(8), reason: flight.trace.join('\n'));
      },
    );
  });

  group('§3.0.3 spawner with registered kinds', () {
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711),
      gameSize: Vector2(Config.worldWidth, 711),
    );

    tester.testGameWidget(
      '§3.0.1 the first hoop spawns 60 pt past the right edge at the first '
      'tap; the next ones every 310 pt; layers follow the camera; met '
      'elements are stored when they come on screen',
      setUp: (game, _) => boot(game),
      verify: (game, _) async {
        registerTestKinds();
        game.runDebug.god = true; // the test kinds have no visuals
        final run = await startRun(game);
        expect(run.spawner.live, isTrue);
        expect(run.state.forwardSpeed, RunConfig.cruiseSpeed);
        final first = hoopsOf(game).single;
        expect(first.planeX, 380);
        expect(first.position.y, 711 / 2);
        expect(game.storage.metElements, isEmpty, reason: 'not on screen yet');

        await flyRun(game, maxSeconds: 3.5);
        final hoops = hoopsOf(game).toList();
        expect(hoops.length, greaterThanOrEqualTo(2));
        for (var k = 1; k < hoops.length; k++) {
          expect(hoops[k].planeX - hoops[k - 1].planeX, RunConfig.spacing);
        }
        expect(run.layers.back.position.x, closeTo(-run.state.camX, 1e-2));
        expect(run.layers.front.position.x, closeTo(-run.state.camX, 1e-2));
        expect(game.storage.metElements, contains('normal_hoop'));
        expect(run.state.camX, greaterThan(RunConfig.cruiseSpeed * 3.4));
        // PRD-2.2 §15: the director plans one slot ahead of the spawned ones.
        expect(run.state.hoopIndex, run.director.hoopIndex - 1);
        expect(
          run.layers.back.children.whereType<Hoop>().length,
          hoopsOf(game).length,
        );
        expect(game.world.children.whereType<RunTrack>(), hasLength(4));
      },
    );

    tester.testGameWidget(
      '§3.0.3 pickups: hit test (distance − bird r ≤ radius), collected once, '
      'ElementSpawned → met',
      setUp: (game, _) => boot(game),
      verify: (game, _) async {
        registerTestKinds();
        game.runDebug.god = true;
        final run = await startRun(game, force: [ElementId.heart]);
        run.events.recordLog = true;
        // The forced heart sits in gap 0, on the line to hoop 1.
        await flyRun(game, maxSeconds: 3);
        final heart = pickupsOf(game).whereType<_TestPickup>().single;
        expect(heart.plan!.kind, ElementId.heart);
        final bird = run.birdTrackPosition()!;
        heart.position.setValues(bird.x + 16 + 14.75 - 0.5, bird.y);
        game.update(0);
        expect(heart.collected, isTrue);
        expect(heart.collects, 1);
        expect(run.events.log.whereType<PickupCollected>(), hasLength(1));
        game.update(1 / 60);
        expect(heart.collects, 1);
        await flyRun(game, maxSeconds: 0.5);
        expect(game.storage.metElements, contains('heart'));
      },
    );

    tester.testGameWidget(
      '§3.0.8 the debug force queue from home goes into the next run',
      setUp: (game, _) => boot(game),
      verify: (game, _) async {
        registerTestKinds(hoops: {HoopKindId.normal, HoopKindId.saw});
        game.runDebug.god = true;
        game.debugForceElement(ElementId.saw);
        expect(game.runDebug.force, [ElementId.saw]);
        await startRun(game, force: game.runDebug.force.toList());
        expect(hoopsOf(game).first.plan.kind, HoopKindId.saw);
        expect(game.runDebug.force, isEmpty, reason: 'consumed by the run');
      },
    );
  });

  group('§3.0 run plumbing', () {
    final opponent = OpponentRun(
      uid: 'u1',
      name: 'BrightOwl',
      score: 3,
      best: 9,
      level: 1,
      timeline: RunTimeline()
        ..addPoint(2)
        ..addPoint(4)
        ..addPoint(6)
        ..end(7),
    );
    final versus = FakeVersusService(pool: [opponent]);
    final spy = AnalyticsSpy();
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(versus: versus, services: spy),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );

    tester.testGameWidget(
      '§3.13 the setup takes the prefetched opponent; the run is submitted at '
      'the end; §3.7 a home-slot shield arms the run',
      setUp: (game, _) => boot(game),
      verify: (game, _) async {
        final run = await startRun(game, starter: Powerup.shield);
        expect(run.setup.opponent, same(opponent));
        expect(run.setup.starter, Powerup.shield);
        expect(run.state.shield, isTrue);
        // WP-2a: the armed shield absorbs a mistake (§3.7); drop it so the
        // kill ends the run.
        run.state.shield = false;
        killRun(game);
        await flushAndMount(game);
        expect(versus.submitted, hasLength(1));
      },
    );

    tester.testGameWidget(
      '§2.7 ctx.earn: the chick doubles, the wallet is credited at once, '
      'in-run coins_earned is aggregated per source at run end',
      setUp: (game, _) => boot(game),
      verify: (game, _) async {
        spy.events.clear();
        final run = await startRun(game);
        run.events.recordLog = true;
        final before = game.menu.wallet.balance;
        run.ctx.earn(1, CoinSource.hoop);
        run.ctx.earn(2, CoinSource.perfect);
        run.state.egg = EggState()..stage = EggStage.chick;
        run.ctx.earn(2, CoinSource.perfect);
        await flushAndMount(game);
        expect(game.menu.wallet.balance, before + 1 + 2 + 4);
        expect(run.state.coinsThisRun, 7);
        final earned = run.events.log.whereType<CoinsEarned>().toList();
        expect(earned.map((e) => e.amount), [1, 2, 4]);
        expect(earned.last.eggX2, isTrue);
        expect(analyticsLog(spy).where((e) => e.$1 == 'coins_earned'), isEmpty);

        killRun(game);
        await flushAndMount(game);
        final coins = analyticsLog(spy)
            .where((e) => e.$1 == 'coins_earned')
            .map((e) => e.$2!)
            .toList();
        expect(coins, contains(allOf(containsPair('source', 'hoop'), containsPair('amount', 1))));
        expect(coins, contains(allOf(containsPair('source', 'perfect'), containsPair('egg_x2', 0), containsPair('amount', 2))));
        expect(coins, contains(allOf(containsPair('source', 'perfect'), containsPair('egg_x2', 1), containsPair('amount', 4))));
        // PRD-2 §3.2: no 1.0 "1 coin per point" credit at game over.
        expect(coins.where((c) => c['source'] == 'play'), isEmpty);
      },
    );

    tester.testGameWidget(
      '§3.0.1 runClock follows the world time scale (Hourglass) and stops at '
      'death',
      setUp: (game, _) => boot(game),
      verify: (game, _) async {
        final run = await startRun(game);
        game.runDebug.god = true;
        stepGame(game, 1, flapBelow: 300);
        final t1 = run.clock.t;
        expect(t1, closeTo(1, 0.02));
        run.state.timeScale = 0.45;
        stepGame(game, 1, flapBelow: 300);
        expect(run.clock.t - t1, closeTo(0.45, 0.02));
        run.state.timeScale = 1;
        game.runDebug.god = false;
        game.onBirdHit();
        final t2 = run.clock.t;
        stepGame(game, 0.5);
        expect(run.clock.t, t2);
      },
    );
  });

  test('§2.4 a throwing event handler never breaks the others', () {
    final events = RunEvents();
    var got = 0;
    events.on<ScoreChanged>((_) => throw StateError('expected in this test'));
    events.on<ScoreChanged>((_) => got++);
    events.emit(const ScoreChanged(0, 1));
    expect(got, 1);
  });

  test('§3.6 Big Hoops: ×1.5, easing back over the last 8 s', () {
    final b = BigHoopsState(duration: 30, start: 10);
    expect(b.mult(10), 1.5);
    expect(b.mult(32), 1.5);
    expect(b.mult(36), closeTo(1.25, 1e-9));
    expect(b.mult(40), 1);
    expect(b.mult(41), 1);
  });

  test('§3.13 versus fake hands out its pool in order, then solo', () {
    final v = FakeVersusService(pool: []);
    expect(v.takeOpponent(), isNull);
    expect(NoopVersusService().takeOpponent(), isNull);
    expect(const Look().bird, 'classic');
  });
}
