import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/gates_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/egg.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
  }

  for (final games in [0, 3, 5, 8, 10, 15, 20]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(prefs: {'gamesPlayed': games}, worldHeight: 711),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      '§14.6 controller gates on at $games, no forced exemptions',
      setUp: boot,
      verify: (g, _) async {
        g.runDebug.ignoreGates = false;
        final run = await startRun(g);
        expect(run.setup.ignoreGates, isFalse);
        for (final e in GatesConfig.keys.keys) {
          // piggyCoins/fireflySwarm are activity internals, not spawn ids.
          if (e == ElementId.piggyCoins || e == ElementId.fireflySwarm) {
            continue;
          }
          expect(
            run.enabled.contains(e),
            GatesConfig.isOpen(e, games),
            reason: '$games: ${e.storageId}',
          );
        }
      },
    );
  }

  for (final (element, kind, dy, streak, bonus) in [
    (ElementId.fever, HoopKindId.fever, 20.0, 5, 0),
    (ElementId.bullseye, HoopKindId.bullseye, 0.0, 1, 1),
    (ElementId.bullseye, HoopKindId.bullseye, 20.0, 1, 0),
  ]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {'gamesPlayed': 20},
        worldHeight: 711,
        seed: 5,
      ),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      '§14.3 ${kind.name} offset $dy with chick: +1 point, coins never doubled',
      setUp: boot,
      verify: (g, _) async {
        final run = await startRun(g, startHoopIndex: 15, force: [element]);
        final hoop = await flyToHoop(g, kind, element);
        expect(hoop, isNotNull);
        run.state.streak = 0;
        run.state.egg = EggState()..stage = EggStage.chick;
        final score = run.state.score;
        final coins = run.state.coinsThisRun;
        final chick = run.features.whereType<EggFeature>().single;
        final added = chick.pointsAdded;
        expect(await passHoopAt(g, hoop!, dy: dy), isTrue);
        expect(hoop.touched, isFalse);
        expect(run.state.streak, streak);
        expect(run.state.score - score, (streak < 2 ? 2 : streak) + 1 + bonus);
        expect(run.state.coinsThisRun - coins, 2 + bonus);
        expect(chick.pointsAdded - added, 1);
      },
    );
  }
}
