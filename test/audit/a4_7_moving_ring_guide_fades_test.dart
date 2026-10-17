// Audit A4-7 / A2-30 (2026-10-17): on the portal clear-ahead a moving
// ring's dashed guide stayed at full alpha while its ring faded out, then
// popped away. The guide now fades with its ring's clear alpha.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/motion/motion_guide.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'A4-7 the moving-ring guide fades with its ring on the clear-ahead',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(
        game,
        startHoopIndex: 45,
        force: [ElementId.movingRing],
      );
      final h = hoopsOf(game).first;
      expect(h.plan.motion, isNotNull);
      await flushAndMount(game);
      final guide = run.layers.back.children.whereType<MotionGuide>().single;
      game.update(1 / 60);
      expect(guide.opacity, 1);

      run.spawner.clearAhead(fade: .2);
      final seen = <double>[];
      for (var i = 0; i < 30 && !h.isRemoved && !h.isRemoving; i++) {
        game.update(1 / 60);
        if (h.isRemoving || h.isRemoved) break;
        expect(guide.opacity, closeTo(h.clearAlpha, 1e-9));
        seen.add(guide.opacity);
      }
      expect(seen, isNotEmpty);
      expect(seen.last, lessThan(.5), reason: 'faded, not popped');
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], lessThanOrEqualTo(seen[i - 1]));
      }
      await flushAndMount(game);
      expect(run.layers.back.children.whereType<MotionGuide>(), isEmpty);
    },
  );
}
