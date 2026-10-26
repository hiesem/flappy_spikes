import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/main.dart' show productionShowcaseFactory;
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flappy_spikes/services/e2e.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';
import 'package:flappy_spikes/services/soak.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  setUp(ShowcaseShow.resetProcessMemoryForTests);

  final now = DateTime.utc(2026, 10, 26, 12);
  for (final scenario in ['fresh', 'legacy', 'resumed']) {
    var factoryCalls = 0;
    FlameTester<FlappySpikesGame>(() {
      factoryCalls = 0;
      SharedPreferences.setMockInitialValues({
        Obf.prefGamesPlayed: scenario == 'legacy' ? 3 : 0,
        Obf.prefInstallAtMs: now
            .subtract(const Duration(seconds: 123))
            .millisecondsSinceEpoch,
        if (scenario == 'resumed') Obf.prefShowcaseSeen: 1,
        if (scenario == 'resumed') Obf.prefShowcaseAttempt: 2,
      });
      final services = GameServices();
      final factory = productionShowcaseFactory(services);
      final game = FlappySpikesGame(
        soundEnabled: false,
        services: services,
        clock: () => now,
        showcaseFactory: factory == null
            ? null
            : (storage) {
                factoryCalls++;
                // Constructor reads must see persisted state, not defaults.
                expect(storage.gamesPlayed, scenario == 'legacy' ? 3 : 0);
                expect(storage.showcaseSeen, scenario == 'resumed' ? 1 : 0);
                expect(storage.showcaseAttempt, scenario == 'resumed' ? 2 : 0);
                return factory(storage);
              },
      )..runSeed = 7;
      expect(factoryCalls, 0);
      return game;
    }, gameSize: Vector2(Config.worldWidth, Config.worldHeight)).testGameWidget(
      'production $scenario install wires loaded state at START '
      '(e2e=$kE2E soak=$kSoak)',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) => tester.runAsync(() async {
        if (kE2E || kSoak) {
          expect(factoryCalls, 0);
          expect(game.showcasePlan, isA<InertShowcasePlan>());
          expect(game.showcaseProgress, isA<InertShowcaseProgress>());
        } else {
          expect(factoryCalls, 1);
          expect(game.showcasePlan, isA<ShowcaseShow>());
          expect(game.showcaseProgress, same(game.showcasePlan));
          final show = game.showcasePlan as ShowcaseShow;
          expect(show.storage, same(game.storage));
          expect(show.secondsSinceInstall!(), 123);
          expect(show.tracker, isNotNull);
          if (scenario == 'legacy') {
            expect(game.storage.showcaseDoneAt, 3);
          }
        }
        final run = await startRun(game);
        if (kE2E || kSoak || scenario == 'legacy') {
          expect(run.setup.showcase, isNull);
          expect(game.storage.showcaseAttempt, scenario == 'resumed' ? 2 : 0);
        } else {
          final plan = run.setup.showcase!;
          expect(plan.step, scenario == 'resumed' ? 1 : 0);
          expect(plan.attempt, scenario == 'resumed' ? 3 : 1);
          expect(game.storage.showcaseAttempt, plan.attempt);
          expect(run.state.shield, isTrue);
          expect(run.state.bigHoops, isNotNull);
          if (scenario == 'fresh') {
            expect(plan.portalHoops, [7]);
            expect(run.state.bigHoops!.duration, 60);
          }
        }
        if (game.showcasePlan case final ShowcaseShow show) {
          await show.writesSettled;
          final prefs = await SharedPreferences.getInstance();
          if (scenario == 'legacy') {
            expect(prefs.getInt(Obf.prefShowcaseDoneAt), 3);
          } else {
            expect(
              prefs.getInt(Obf.prefShowcaseAttempt),
              run.setup.showcase!.attempt,
            );
          }
        }
      }),
    );
  }

  FlameTester<FlappySpikesGame>(
    createRunTestGame,
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  ).testGameWidget(
    'test harness keeps the inert default (PRD 8.3 decision 6)',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      expect(game.showcasePlan, isA<InertShowcasePlan>());
      expect(game.showcaseProgress, isA<InertShowcaseProgress>());
      final run = await startRun(game);
      expect(run.setup.showcase, isNull);
      expect(game.storage.showcaseAttempt, 0);
    },
  );
}
