// Audit A2-31 (2026-10-17): the FEVER pass's screen flash and camera shake
// and the pair gift's rising word were added straight to the game world and
// survived the run (a replay / Home inside their life kept them on screen
// and the shake kept moving the camera). They are now owned by the run and
// removed with it.
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/effects/rising_word.dart';
import 'package:flappy_spikes/run/hoops/hoop_kind.dart';
import 'package:flappy_spikes/run/hoops/kinds/fever.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'A2-31 the FEVER flash, shake and a rising word go with the run',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      await flyUntil(game, (r) => r.state.hoopsPassed >= 1);
      final cam = game.camera.viewfinder.position.clone();
      final h = run.spawner.hoops.first;
      FeverHoopKind().onPass(
        h,
        const PassInfo(ring: 0, perfect: true),
        run.ctx,
      );
      run.addWorldFx(
        RisingWord(
          'FEVER!',
          at: Vector2(200, 300),
          fontSize: 30,
          fill: const Color(0xFFFFFFFF),
          outline: const Color(0xFF000000),
          outlineWidth: 7,
          life: 1.4,
        ),
      );
      await flushAndMount(game);
      expect(game.world.children.whereType<FeverFlash>(), hasLength(1));
      expect(game.world.children.whereType<FeverShake>(), hasLength(1));
      expect(game.world.children.whereType<RisingWord>(), hasLength(1));
      // Paused mid-effect (the world is frozen), then the run is left.
      game.pause();
      game.update(1 / 60);
      game.replay();
      await flushAndMount(game);
      expect(game.world.children.whereType<FeverFlash>(), isEmpty);
      expect(game.world.children.whereType<FeverShake>(), isEmpty);
      expect(game.world.children.whereType<RisingWord>(), isEmpty);
      void camBack() {
        final p = game.camera.viewfinder.position;
        expect(p.x, closeTo(cam.x, 1e-3), reason: 'shake undone');
        expect(p.y, closeTo(cam.y, 1e-3), reason: 'shake undone');
      }

      camBack();
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      camBack();
    },
  );
}
