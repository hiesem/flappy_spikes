import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

RunDirector _director(int seed) => RunDirector(
  seed: seed,
  enabled: ElementId.values.toSet(),
  met: ElementId.values.toSet(),
);

void main() {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'controller looks one slot ahead of the current squeeze window',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      final state = run.state;
      final cruise = RunConfig.cruise(state.hoopIndex);
      final birdX = run.birdTrackPosition()!.x;
      final lead = (run.director.nextTrackX - birdX) / cruise;
      final slotSeconds = RunConfig.spacing / cruise;
      final currentWindowAt =
          state.runClock + RunConfig.squeezeWindowLead + lead;
      state.squeeze
        ..phase = SqueezePhase.idle
        ..nextAt = currentWindowAt + slotSeconds + .01;
      expect(run.directorContext().squeezeWindow, isFalse);
      expect(run.directorContext().squeezeNextSlot, isFalse);

      state.squeeze.nextAt = currentWindowAt + slotSeconds - .01;
      expect(run.directorContext().squeezeWindow, isFalse);
      expect(run.directorContext().squeezeNextSlot, isTrue);

      state.squeeze.nextAt = currentWindowAt - .01;
      expect(run.directorContext().squeezeWindow, isTrue);
      expect(run.directorContext().squeezeNextSlot, isTrue);

      state.squeeze
        ..nextAt = double.infinity
        ..phase = SqueezePhase.hold;
      expect(run.directorContext().squeezeWindow, isTrue);
      expect(run.directorContext().squeezeNextSlot, isTrue);
    },
  );

  // PRD §3.23 and D3 × O18 (§8.3 decision 2): protect squeezed landings
  // without globally suppressing ordinary springs below hazard budget 4.
  test('spring landing look-ahead defaults to false', () {
    expect(DirectorContext.open(711).squeezeNextSlot, isFalse);
    expect(
      const DirectorContext(
        viewHeight: 711,
        topTooth: 44,
        floorTooth: 667,
      ).squeezeNextSlot,
      isFalse,
    );
    expect(
      DirectorContext.open(711, squeezeNextSlot: true).squeezeNextSlot,
      isTrue,
    );
  });

  test(
    'an upcoming squeeze downgrades an otherwise affordable early spring',
    () {
      var checked = 0;
      var earliest = 50;
      for (var seed = 0; seed < 200; seed++) {
        final ordinary = _director(seed);
        final guarded = _director(seed);
        for (var i = 0; i < 49; i++) {
          final ctx = DirectorContext.open(711);
          final spring = ordinary.nextSlot(ctx);
          final hasSpring = spring.kind == HoopKindId.spring && !spring.forced;
          final next = guarded.nextSlot(
            DirectorContext.open(711, squeezeNextSlot: hasSpring),
          );
          if (hasSpring) {
            expect(guarded.hazardBudgetAt(i + 1), lessThan(4));
            expect(next.kind, HoopKindId.normal, reason: 'seed=$seed slot=$i');
            expect(next.extra, isNull);
            expect(next.forced, isFalse);
            expect(i, greaterThanOrEqualTo(10));
            if (i < earliest) earliest = i;
            checked++;
            // The spring changes subsequent geometry. Only compare identical
            // histories up to the first natural spring in each seed.
            break;
          }
          expect(next, spring);
          expect(guarded.nextGap(ctx, next), ordinary.nextGap(ctx, spring));
        }
      }
      expect(checked, greaterThan(20));
      expect(earliest, 10);
    },
  );

  for (final (height, baseline25) in [(568.0, 167), (711.0, 329)]) {
    test('springs before hoop 50 retain half the 2.5 rate at $height', () {
      var springs = 0;
      for (var seed = 0; seed < 200; seed++) {
        final director = _director(seed);
        for (var i = 0; i < 50; i++) {
          final ctx = DirectorContext.open(height);
          final plan = director.nextSlot(ctx);
          director.nextGap(ctx, plan);
          if (plan.kind == HoopKindId.spring) springs++;
        }
      }
      // 200-seed 2.5 measurements (d0a72c2), a3 audit WP-a3-1.
      expect(springs, greaterThanOrEqualTo(baseline25 * .5));
    });
  }
}
