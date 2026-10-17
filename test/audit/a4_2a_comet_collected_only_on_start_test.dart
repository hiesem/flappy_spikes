// Audit A4-2a (2026-10-17): `comet_collected` was tracked for every comet
// star / COMET gift collected, also when the boost refused to start
// (another timed powerup running). It is now tracked only for a boost that
// really starts. (The refused star itself, A4-2b, is for the owner.)
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/items/timed_powerup.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late AnalyticsSpy spy;
  FlameTester<FlappySpikesGame> tester() => FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: 711, seed: 5, services: spy);
  }, gameSize: Vector2(320, 711));

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  int sent() => spy.events.where((e) => e.$1 == 'comet_collected').length;

  tester().testGameWidget(
    'A4-2a a comet refused while an Hourglass runs sends no comet_collected; '
    'a comet that starts sends one',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await startRun(game);
      await flyUntil(game, (r) => r.state.hoopsPassed >= 1);
      final slot = run.features.whereType<TimedPowerupSlot>().single;
      final comet = run.features.whereType<CometFeature>().single;
      expect(slot.start(CapsuleType.hourglass), isTrue);
      run.events.emit(const PickupCollected(ElementId.comet, null));
      expect(comet.started, 0, reason: 'refused: the Hourglass runs');
      expect(sent(), 0);

      run.state.timed!.remaining = 0;
      for (var i = 0; i < 20 && run.state.timed != null; i++) {
        game.update(1 / 60);
      }
      expect(run.state.timed, isNull);
      run.events.emit(const PickupCollected(ElementId.comet, null));
      expect(comet.started, 1);
      expect(sent(), 1);
      expect(
        spy.events.lastWhere((e) => e.$1 == 'comet_collected').$2,
        {'source': 'pair'},
      );
    },
  );
}
