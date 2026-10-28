@Tags(['slow'])
library;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/human_bot.dart';
import 'package:flappy_spikes/run/director/formations.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

// PRD D7: report the calibrated bot's actual exposure, not unvisited spawn
// previews. Each next unresolved plane counts once, including the fatal plane.
// Non-formation slots and deaths stay in both denominators. Spikes without a
// named hoop are attributed to the next plane being approached.
// Use 100 seeds per start: at 30 seeds one extra switch death changes this
// soft balance estimate by about 0.3x (the pilot measured 2.12x / 1.80x).
// The threshold stays exactly 2x at each height; no sampling allowance.
// Recorded 2026-10-27, seeds 0..99 at each start (150/200/250), 120 s cap:
//                       568 pt                 711 pt
// shape              slots deaths ratio     slots deaths ratio
// stairs               260   23   1.402       256   21   1.346
// slalom               288    4   0.220       302    5   0.272
// tiltWave             411    6   0.231       421    8   0.312
// syncRails            190   11   0.917       202   13   1.056
// sawGate              161   17   1.673       144   13   1.482
// switchChain          168   19   1.792       167   17   1.671
// Denominators include ordinary slots: 4753 / 4874 slots, 300 / 297 deaths
// (three 711 pt flights reached the cap). The test prints counts by start too.
// Initial 30-seed pilot: switch-chain deaths 9 / 8; tuned pilot: 7 / 6.
// Rails and saw gates needed no change. Only the switch-chain route was tuned.
void main() {
  for (final height in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: height, prefs: {'gamesPlayed': 10}),
      gameSize: Vector2(Config.worldWidth, height),
    ).testGameWidget(
      'D7 calibrated formation death share <=2x slot share h=$height',
      timeout: const Timeout(Duration(minutes: 15)),
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        final slots = <FormationId?, int>{};
        final deaths = <FormationId?, int>{};
        final report = <String>[];
        game.runDebug.ignoreGates = false;
        for (final start in [150, 200, 250]) {
          final startSlots = <FormationId?, int>{};
          final startDeaths = <FormationId?, int>{};
          for (var seed = 0; seed < 100; seed++) {
            game.runSeed = seed;
            game.storage.gamesPlayed = 10;
            final run = await startRun(game, startHoopIndex: start);
            expect(run.setup.showcase, isNull);
            expect(run.setup.ignoreGates, isFalse);
            final seen = <int>{};
            SlotPlan? target;
            var unattributedDeath = false;
            void encounter(SlotPlan plan) {
              if (!seen.add(plan.index)) return;
              startSlots.update(
                plan.formation,
                (n) => n + 1,
                ifAbsent: () => 1,
              );
            }

            void listen(RunEvent event) {
              if (event is HoopPassed && event.hoop != null) {
                encounter(event.hoop!.plan);
              }
              if (event is RunDied) {
                final plan = event.mistake.hoop?.plan ?? target;
                unattributedDeath = plan == null;
                if (plan?.formation == FormationId.switchChain) {
                  report.add(
                    'switch death start=$start seed=$seed '
                    'slot=${plan?.index} cause=${event.mistake.cause}',
                  );
                }
                if (plan != null) encounter(plan);
                startDeaths.update(
                  plan?.formation,
                  (n) => n + 1,
                  ifAbsent: () => 1,
                );
              }
            }

            run.events.onAny(listen);
            try {
              await flyHumanNoiseBotToDeath(
                game,
                seed: seed,
                jitterSigma: .05, // D-CAL / SPEC §0.3.4, 2.5 calibration.
                extraFlapChance: .1,
                maxSeconds: 120,
                onFrame: (_) {
                  if (run.lastDeath != null) return;
                  final x = run.birdTrackPosition()!.x;
                  final ahead =
                      run.spawner.hoops
                          .where((h) => !h.resolved && h.planeX >= x - 30)
                          .toList()
                        ..sort((a, b) => a.planeX.compareTo(b.planeX));
                  if (ahead.isNotEmpty) {
                    target = ahead.first.plan;
                    encounter(target!);
                  }
                },
              );
            } finally {
              run.events.offAny(listen);
            }
            expect(
              unattributedDeath,
              isFalse,
              reason: 'fatal plane start=$start seed=$seed',
            );
            game.replay();
            await flushAndMount(game);
            stepGame(game, .4);
            await flushAndMount(game);
          }
          report.add('start=$start slots=$startSlots deaths=$startDeaths');
          for (final entry in startSlots.entries) {
            slots.update(
              entry.key,
              (n) => n + entry.value,
              ifAbsent: () => entry.value,
            );
          }
          for (final entry in startDeaths.entries) {
            deaths.update(
              entry.key,
              (n) => n + entry.value,
              ifAbsent: () => entry.value,
            );
          }
        }
        final totalSlots = slots.values.fold(0, (a, b) => a + b);
        final totalDeaths = deaths.values.fold(0, (a, b) => a + b);
        expect(totalDeaths, greaterThan(0));
        for (final id in FormationId.values) {
          expect(slots[id] ?? 0, greaterThan(0), reason: '$id exposure');
          final slotShare = (slots[id] ?? 0) / totalSlots;
          final deathShare = (deaths[id] ?? 0) / totalDeaths;
          report.add(
            '${id.name}: slots=${slots[id] ?? 0}/$totalSlots '
            'deaths=${deaths[id] ?? 0}/$totalDeaths '
            'ratio=${(deathShare / slotShare).toStringAsFixed(3)}',
          );
        }
        // ignore: avoid_print
        print(
          'D-SHAPES h=$height sigma=.05 extra=.1 seeds=0..99\n${report.join('\n')}',
        );
        for (final id in FormationId.values) {
          expect(
            (deaths[id] ?? 0) / totalDeaths,
            lessThanOrEqualTo(2 * (slots[id] ?? 0) / totalSlots),
            reason: 'D7 soft balance signal: $id\n${report.join('\n')}',
          );
        }
      },
    );
  }
}
