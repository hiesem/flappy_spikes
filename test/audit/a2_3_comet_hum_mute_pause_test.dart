// Audit A2-3 (2026-10-17): the comet hum came back at full volume on resume
// even when SFX were muted during the pause, and its 0.3 s fade-out played
// through a pause. Both now stay silent.
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/run/config/comet_config.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  FlameTester<FlappySpikesGame> tester() => FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: Vector2(320, 711),
  );

  Future<void> boot(FlappySpikesGame game) async {
    await game.ready();
    await preloadImages(game);
  }

  void step(FlappySpikesGame g, double seconds) {
    for (var t = 0.0; t < seconds; t += 1 / 60) {
      g.update(1 / 60);
    }
  }

  tester().testGameWidget(
    'A2-3 SFX muted during the pause: the comet hum stays silent on resume',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      game.update(1 / 60);
      run.events.emit(const PickupCollected(ElementId.comet, null));
      step(game, 1.5);
      final loop = game.sound.activeLoops.single;
      expect(loop.loop, SfxLoop.cometLoop);
      expect(loop.volume, CometConfig.loopVolume);
      game.pause();
      game.update(1 / 60);
      expect(loop.volume, 0);
      game.sound.muted = true; // the pause screen's settings
      game.resume();
      game.update(1 / 60);
      expect(loop.volume, 0, reason: 'muted: the hum stays silent');
      game.sound.muted = false;
      game.update(1 / 60);
      expect(loop.volume, CometConfig.loopVolume);
    },
  );

  tester().testGameWidget(
    'A2-3 the comet hum is silent during a pause in its fade-out',
    setUp: (g, _) => boot(g),
    verify: (game, _) async {
      final run = await startRun(game);
      final comet = run.features.whereType<CometFeature>().single;
      game.update(1 / 60);
      run.events.emit(const PickupCollected(ElementId.comet, null));
      step(game, 1.5);
      final loop = game.sound.activeLoops.single;
      for (var i = 0; i < 900 && comet.active; i++) {
        game.update(1 / 60);
      }
      expect(comet.active, isFalse);
      game.update(1 / 60);
      expect(loop.stopped, isFalse, reason: 'fading out');
      expect(loop.volume, greaterThan(0));
      game.pause();
      game.update(1 / 60);
      expect(loop.stopped || loop.volume == 0, isTrue);
    },
  );
}
