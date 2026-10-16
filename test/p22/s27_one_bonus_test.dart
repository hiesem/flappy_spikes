import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/pair/pair_kind.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §27 one bonus at a time — in the run: forced activities, the
/// reward items ahead fading out, the 2-hoop cool-down, owed feathers and a
/// pair losing its gifts.
Future<void> _boot(FlappySpikesGame game) async {
  await game.ready();
  game.sound.enabled = false;
  await preloadImages(game);
}

/// Every element met: no first-meet forcing gets in the way.
final Map<String, Object> _allMet = {
  'metElements': [for (final e in ElementId.values) e.storageId],
};

FlameTester<FlappySpikesGame> _tester({double h = 711, int seed = 5}) =>
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, seed: seed, prefs: _allMet),
      gameSize: Vector2(320, h),
    );

/// Watches activities and reward spawns; checks §27.2 / §27.5.
class _Watch {
  _Watch(this.run) {
    run.events
      ..on<ActivityStarted>((e) {
        started.add(e.activity);
        active = true;
      })
      ..on<ActivityEnded>((e) {
        ended.add(e.activity);
        active = false;
        endX = run.birdTrackPosition()?.x ?? run.state.camX + RunConfig.birdX;
      })
      ..on<PickupSpawned>((e) {
        if (!RunDirector.isRewardItem(e.pickup.id)) return;
        _reward(e.pickup.id.storageId, e.pickup.position.x);
      })
      ..on<HoopSpawned>((e) {
        if (RunDirector.isRewardSlot(e.plan)) {
          _reward('${e.plan.kind.name} hoop', e.plan.trackX);
        }
        if (active && e.plan.kind != HoopKindId.normal) obstacles++;
        if (!active && ended.isNotEmpty && e.plan.kind != HoopKindId.normal) {
          obstaclesAfter++;
        }
      });
  }

  final RunController run;
  final List<RunActivity> started = [], ended = [];
  final List<String> bad = [];
  bool active = false;
  double? endX;
  int obstacles = 0;

  /// Obstacle hoops after the activity ended (PRD-2.4 §1: a short jar run,
  /// whose three escapes come early on the wider openings, can end before a
  /// planned obstacle; obstacles still come after it).
  int obstaclesAfter = 0;

  void _reward(String what, double x) {
    if (active) {
      bad.add('$what during ${started.last}');
      return;
    }
    final e = endX;
    if (e == null) return;
    // ≥ 2 hoops between where the bird was when it ended and the item.
    final between = run.spawner.slotLog
        .where((s) => s.trackX > e && s.trackX < x)
        .length;
    if (between < RunConfig.activityCooldownHoops) {
      bad.add('$what with $between hoops after the end');
    }
  }
}

void main() {
  for (final (label, force, collect) in <(String, List<ElementId>, ElementId?)>[
    ('comet ride', [ElementId.comet], null),
    ('piggy run', [ElementId.piggy], ElementId.piggy),
    ('jar run', [ElementId.jar], ElementId.jar),
    ('capsule power-up', [ElementId.hourglass], ElementId.capsule),
  ]) {
    _tester().testGameWidget(
      '§27.5 a forced $label: no reward item from its start to its end + 2 '
      'hoops; obstacle rings still come',
      setUp: (g, _) => _boot(g),
      verify: (game, _) async {
        game.runDebug.god = true;
        final run = await startRun(game, startHoopIndex: 20, force: force);
        final watch = _Watch(run);
        if (collect != null) {
          final got = await collectPickup(game, collect, reforce: false);
          expect(got, isNotNull, reason: 'the bot takes the $collect');
        }
        final ride = force.first == ElementId.comet;
        await flyUntil(
          game,
          (r) {
            // Rewards are forced all along (they must wait); obstacles
            // too (rides keep "no specials" — §3.0.3). PRD-2.3 §17.3 rule 4
            // a blocked ring drawn now waits and the slot is drawn again,
            // so the saw goes first in the queue (the head slot element).
            for (final e in [ElementId.saw, ElementId.heart, ElementId.pair]) {
              if (!r.director.forcedQueue.contains(e)) r.debugForce(e);
            }
            return watch.ended.isNotEmpty;
          },
          maxSeconds: 60,
        );
        expect(watch.started, isNotEmpty);
        expect(watch.ended, isNotEmpty, reason: 'the activity ended');
        // After the end the forced rewards come — but only after 2 hoops.
        await flyRun(game, maxSeconds: 8);
        expect(watch.bad, isEmpty);
        if (!ride) {
          expect(
            watch.obstacles + watch.obstaclesAfter,
            greaterThan(0),
            reason: 'obstacle rings come during or after the activity',
          );
        }
        // Never two at once.
        expect(watch.started.length - watch.ended.length, lessThanOrEqualTo(1));
      },
    );
  }

  _tester().testGameWidget(
    '§27.5 a forced portal ride: nothing rewarding during it or within 2 '
    'hoops of its end',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(
        game,
        startHoopIndex: 25,
        ride: RideId.space,
      );
      final watch = _Watch(run);
      await flyUntil(
        game,
        (r) {
          if (watch.started.isNotEmpty &&
              !r.director.forcedQueue.contains(ElementId.heart)) {
            r.debugForce(ElementId.heart);
          }
          return watch.ended.isNotEmpty;
        },
        maxSeconds: 60,
      );
      expect(watch.started, contains(RunActivity.portal));
      expect(watch.ended, contains(RunActivity.portal));
      await flyRun(game, maxSeconds: 8);
      expect(watch.bad, isEmpty);
    },
  );

  /// Forces [first] (the comet), then [ahead] into the gap after it.
  Future<(RunController, Pickup)> cometWith(
    FlappySpikesGame game,
    ElementId ahead,
  ) async {
    game.runDebug.god = true;
    final run = await startRun(
      game,
      startHoopIndex: 20,
      force: [ElementId.comet, ahead],
    );
    Pickup? item = pickupsOf(game).where((p) => p.id == ahead).firstOrNull;
    run.events.on<PickupSpawned>((e) {
      if (e.pickup.id == ahead) item ??= e.pickup;
    });
    await flyUntil(game, (_) => item != null, maxSeconds: 10);
    return (run, item!);
  }

  /// PRD-2.3.1 §16.1 A (supersedes PRD-2.3 §17.5 for a comet): [p] lay in
  /// the gap of a hoop the comet moved (past the last hoop that stays), so
  /// it was dropped unjudged, visible or not. Returns whether it was.
  bool droppedByCometLayout(RunController run, Pickup p) {
    final anchor = run.spawner.cometAnchorX;
    expect(anchor, isNotNull);
    if (p.position.x <= anchor!) return false;
    expect(p.escaped, isTrue);
    expect(run.spawner.pickups, isNot(contains(p)));
    return true;
  }

  // PRD-2.3 §17.5 (changes PRD-2.2 §27.3): an item already visible when an
  // activity starts is never cleared; only what is not visible yet goes
  // (that part: test/p23/s17_one_big_bonus_test.dart).
  _tester().testGameWidget(
    '§27.5 / PRD-2.3 §17.5 a feather on screen when a comet starts stays '
    '(it is not cleared, owed or faded), unless it lies in a moved hoop\'s '
    'gap (PRD-2.3.1 §16.1 A: dropped)',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      final (run, feather) = await cometWith(game, ElementId.feather);
      final watch = _Watch(run);
      final cleared = <Pickup>[];
      run.events.on<PickupCleared>((e) => cleared.add(e.pickup));
      await flyUntil(game, (_) => watch.started.isNotEmpty, maxSeconds: 20);
      expect(watch.started.single, RunActivity.comet);
      expect(run.spawner.isVisible(feather), isTrue);
      if (droppedByCometLayout(run, feather)) {
        expect(cleared, contains(feather));
        return;
      }
      expect(cleared, isNot(contains(feather)));
      expect(run.spawner.pickups, contains(feather));
      expect(run.state.featherSpawned, isTrue);
      for (var i = 0; i < 16; i++) {
        game.update(1 / 60);
      }
      expect(feather.clearAlpha, 1);
    },
  );

  _tester().testGameWidget(
    '§27.5 / PRD-2.3 §17.5 a heart on screen when a comet starts stays; the '
    'heart schedule is kept (PRD-2.3.1 §16.1 A: dropped in a moved gap)',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      final (run, heart) = await cometWith(game, ElementId.heart);
      final watch = _Watch(run);
      final heartAt = run.director.heartAt;
      await flyUntil(game, (_) => watch.started.isNotEmpty, maxSeconds: 20);
      if (droppedByCometLayout(run, heart)) return;
      expect(run.spawner.pickups, contains(heart));
      expect(heart.clearAlpha, 1);
      expect(run.director.heartAt, heartAt, reason: 'the schedule is kept');
    },
  );

  _tester().testGameWidget(
    '§27.5 / PRD-2.3 §17.5 a shield on screen when a comet starts stays '
    '(PRD-2.3.1 §16.1 A: dropped in a moved gap)',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      final (run, shield) = await cometWith(game, ElementId.shield);
      final watch = _Watch(run);
      await flyUntil(game, (_) => watch.started.isNotEmpty, maxSeconds: 20);
      if (droppedByCometLayout(run, shield)) return;
      expect(run.spawner.pickups, contains(shield));
      expect(shield.clearAlpha, 1);
      expect(run.director.forcedQueue, isNot(contains(ElementId.shield)));
    },
  );

  _tester().testGameWidget(
    '§27.5 / PRD-2.3 §17.5 a pair already on screen when a jar run starts '
    'keeps its gift boxes and passes as a pair',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(
        game,
        startHoopIndex: 20,
        force: [ElementId.pair],
      );
      // A pair on screen ahead, then a jar between the bird and it.
      Hoop? pair;
      await flyUntil(game, (r) {
        final b = r.birdTrackPosition()!;
        for (final h in r.spawner.hoops) {
          if (h.plan.kind == HoopKindId.pair &&
              h.planeX - b.x > 200 &&
              h.planeX - r.state.camX < RunConfig.worldWidth) {
            pair = h;
          }
        }
        if (pair == null && !r.director.forcedQueue.contains(ElementId.pair)) {
          r.debugForce(ElementId.pair);
        }
        return pair != null;
      }, maxSeconds: 20);
      final bird = run.birdTrackPosition()!;
      run.spawner.spawnItem(
        GapItemPlan(kind: ElementId.jar, trackX: bird.x + 70, y: bird.y),
      );
      final p = pair!;
      final picked = <String>[];
      run.events.on<HoopPassed>((e) {
        if (identical(e.hoop, p)) picked.add(e.hoop!.plan.kind.name);
      });
      final got = await collectPickup(game, ElementId.jar, reforce: false);
      expect(got, isNotNull);
      game.update(1 / 60); // the activity is seen
      expect(run.state.activity, RunActivity.jar);
      expect(p.rewardStripped, isFalse);
      expect(p.plan.kind, HoopKindId.pair);
      for (var i = 0; i < 15; i++) {
        game.update(1 / 60);
      }
      expect(p.rewardAlpha, 1);
      expect(PairHoopKind.stateOf(p), isNotNull);
      await flyUntil(game, (_) => p.resolved, maxSeconds: 6);
      expect(picked, ['pair']);
    },
  );

  _tester().testGameWidget(
    '§27.4 the activity state follows the features: start clears, end '
    'starts the cool-down',
    setUp: (g, _) => _boot(g),
    verify: (game, _) async {
      game.runDebug.god = true;
      final run = await startRun(game, startHoopIndex: 20);
      expect(run.state.activity, isNull);
      run.state.jar = JarState();
      game.update(1 / 60);
      expect(run.state.activity, RunActivity.jar);
      expect(run.directorContext().activity, isTrue);
      run.state.jar = null;
      game.update(1 / 60);
      expect(run.state.activity, isNull);
      expect(run.state.activityEndedAtSlot, run.director.hoopIndex);
      expect(run.directorContext().activity, isFalse);
      expect(run.directorContext().activityEndedAtSlot, run.director.hoopIndex);
      // Passive states are no activity.
      run.state
        ..egg = EggState()
        ..shield = true
        ..onFire = true;
      game.update(1 / 60);
      expect(run.state.activity, isNull);
    },
  );
}
