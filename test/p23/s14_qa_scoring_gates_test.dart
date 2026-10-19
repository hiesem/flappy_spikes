import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/gates_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/egg.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
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
    (ElementId.bullseye, HoopKindId.bullseye, 0.0, 1, 3), // PRD-2.3.1 §6
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
      setUp: (g, t) async {
        // The 2.3 rule this test pins: no perfect band (any rim-free pass is
        // perfect); the live default band (PRD-2.3.1 §0) is ±18 at hoop 15.
        TuningValues.current = TuningValues.resolve({
          'ui_unlock_best': '0',
          'point_perfect_band': '[[0,0]]',
        });
        addTearDown(() {
          TuningValues.current = TuningValues.resolve({'ui_unlock_best': '0'});
        });
        await boot(g, t);
      },
      verify: (g, _) async {
        final run = await startRun(g, startHoopIndex: 15, force: [element]);
        // PRD-2.3.1 §0: with the denser live spawn set the forced reward
        // ring waits longer for a free slot (§17.3 one big bonus).
        final hoop = await flyToHoop(g, kind, element, maxSeconds: 120);
        expect(hoop, isNotNull);
        // Pass every hoop before it first, so only [hoop] scores below.
        await flyUntil(
          g,
          (_) =>
              hoopsOf(g).every((h) => h.resolved || h.planeX >= hoop!.planeX),
        );
        run.state.streak = 0;
        run.state.egg = EggState()..stage = EggStage.chick;
        final score = run.state.score;
        final coins = run.state.coinsThisRun;
        final chick = run.features.whereType<EggFeature>().single;
        final added = chick.pointsAdded;
        expect(await passHoopAt(g, hoop!, dy: dy), isTrue);
        expect(hoop.touched, isFalse);
        expect(run.state.streak, streak);
        // PRD-2.3.1 §15.1 a FEVER pass scores with the streak before its
        // boost (0 + 1), not the boosted 5.
        final scored = kind == HoopKindId.fever ? 1 : streak;
        expect(run.state.score - score, (scored < 2 ? 2 : scored) + 1 + bonus);
        expect(run.state.coinsThisRun - coins, 2 + bonus);
        expect(chick.pointsAdded - added, 1);
      },
    );
  }
}
