import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flappy_spikes/run/backdrop/run_backdrop.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// A2-32: the run backdrop's cached strip pictures (`Ctx.strip`, PRD-2.4
/// §3.4) were never released: `clearStrips` had no caller, so every run's
/// strip pictures stayed alive after the backdrop left the world. The
/// backdrop now clears them when it is removed with its run.
void main() {
  const prefs = {'firstRunHintSeen': true};

  FlameTester<FlappySpikesGame> tester() => FlameTester(
    () => createRunTestGame(
      prefs: prefs,
      worldHeight: 568,
    ),
    gameSize: Vector2(320, 568),
  );

  tester().testGameWidget(
    'A2-32 the run backdrop releases its strip pictures when it leaves the world',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, tester) async {
      await startRun(game);
      final backdrop = RunBackdrop.of(game)!;
      final painter = backdrop.painter;
      final pal = kPalettes[0]!;
      // Paint a few scenes so static bands (strip keys 101, 201, 301, …)
      // are recorded into the cache.
      final rec = PictureRecorder();
      final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, 320, 568));
      for (var s = 0; s < 4; s++) {
        painter.paint(
          canvas,
          cam: (s + .5) * kE, // mid-scene
          t: 2,
          viewHeight: 568,
          bg: pal.background,
          fg: pal.foreground,
        );
      }
      rec.endRecording().dispose();
      expect(
        painter.ctx.stripCount,
        greaterThan(0),
        reason: 'the scenes must have cached at least one strip',
      );

      backdrop.removeFromParent();
      await flushAndMount(game);

      expect(backdrop.isRemoved, isTrue);
      expect(
        painter.ctx.stripCount,
        0,
        reason: 'a removed backdrop must not keep its strip pictures',
      );
    },
  );
}
