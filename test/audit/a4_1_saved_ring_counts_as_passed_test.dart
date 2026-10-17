// Audit A4-1 (2026-10-17): a saw ring or a closed switch ring whose mistake
// the shield / extra life saves "counts as passed with no score" (SPEC.md
// WP-3d). Before the fix the ring was resolved but never counted: passes,
// hoopsPassed (colour stage, hoop goals) and the taken tally lagged one
// hoop per save.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop_kind.dart';
import 'package:flappy_spikes/run/hoops/kinds/switch/switch_kind.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late AnalyticsSpy spy;
  FlameTester<FlappySpikesGame> tester({int seed = 9}) =>
      FlameTester<FlappySpikesGame>(() {
        spy = AnalyticsSpy();
        return createRunTestGame(worldHeight: 711, services: spy, seed: seed);
      }, gameSize: Vector2(320, 711));

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  tester().testGameWidget(
    'A4-1 a shield-saved saw touch counts the ring as passed with no score',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 20,
        force: [ElementId.saw],
        starter: Powerup.shield,
      );
      final h = await flyToHoop(game, HoopKindId.saw, ElementId.saw);
      expect(h, isNotNull);
      final h0 = h!;
      final events = <RunEvent>[];
      run.events.onAny(events.add);
      final hoops = run.state.hoopsPassed;
      final passes = run.state.passes;
      final taken = run.state.taken[h0.plan.element.storageId] ?? 0;
      final score = run.state.score;
      final coins = run.state.coinsThisRun;
      final ry = h0.opening / 2 + h.kind.rimRadius(h);
      await glideInto(
        game,
        h,
        h.position.y - ry,
        seconds: .3,
        until: (_) => h.resolved,
      );
      expect(run.dying, isFalse);
      expect(h.resolved, isTrue);
      expect(h.takenRing, isNull, reason: 'the look stays missed');
      expect(run.state.shield, isFalse);
      expect(run.state.hoopsPassed, hoops + 1);
      expect(run.state.passes, passes + 1);
      expect(run.state.taken[h.plan.element.storageId], taken + 1);
      expect(run.state.score, score, reason: 'no score');
      expect(run.state.coinsThisRun, coins, reason: 'no coins');
      expect(events.whereType<HoopPassed>(), isEmpty);
      expect(events.whereType<SavedHoopPassed>().single.hoop, same(h));
      expect(spy.events.map((e) => e.$1), contains('sawring_passed'));
    },
  );

  tester(seed: 11).testGameWidget(
    'A4-1 a shield-saved closed switch ring counts as passed with no score',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 12,
        force: [ElementId.switchRing],
        starter: Powerup.shield,
      );
      final h = await flyToHoop(
        game,
        HoopKindId.switchRing,
        ElementId.switchRing,
        maxSeconds: 150,
        where: (h) {
          final p = SwitchRingKind.stateOf(h)?.pickup;
          final b = run.birdTrackPosition();
          return p != null &&
              b != null &&
              p.position.x > b.x + 60 &&
              !run.spawner.hoops.any(
                (o) =>
                    !identical(o, h) &&
                    o.planeX > b.x &&
                    o.planeX < p.position.x,
              );
        },
      );
      expect(h, isNotNull);
      final p = SwitchRingKind.stateOf(h!)!.pickup!;
      p.position.y = h.position.y + 300; // out of reach
      await flyUntil(
        game,
        (r) {
          final b = r.birdTrackPosition();
          return b != null && h.planeX - b.x <= 12;
        },
        flap: (r) {
          final b = game.runBirdPosition!;
          return b.y > h.position.y + 6 && (game.runBirdVelocityY ?? 0) > -40;
        },
      );
      expect(run.state.shield, isTrue);
      final events = <RunEvent>[];
      run.events.onAny(events.add);
      final hoops = run.state.hoopsPassed;
      final passes = run.state.passes;
      final score = run.state.score;
      game.runBird!.setFlight(y: h.position.y, vy: 0);
      await flyUntil(game, (_) => h.resolved, maxSeconds: .4, autopilot: false);
      expect(run.dying, isFalse);
      expect(h.resolved, isTrue);
      expect(events.whereType<ClosedSwitchReached>().single.hoop, same(h));
      expect(run.state.hoopsPassed, hoops + 1);
      expect(run.state.passes, passes + 1);
      expect(run.state.score, score, reason: 'no score');
      expect(events.whereType<HoopPassed>(), isEmpty);
      expect(events.whereType<SavedHoopPassed>().single.hoop, same(h));
      expect(spy.events.map((e) => e.$1), contains('switchring_passed'));
    },
  );
}
