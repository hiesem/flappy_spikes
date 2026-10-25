import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

final class _ShowcasePlan extends ShowcasePlan {
  const _ShowcasePlan(this.result);

  final ShowcaseRunPlan? result;

  @override
  ShowcaseRunPlan? atStart({
    required int gamesPlayed,
    required int seen,
    required int attempt,
    required bool forced,
  }) => result;
}

FlappySpikesGame _game(ShowcaseRunPlan plan) {
  SharedPreferences.setMockInitialValues({});
  return FlappySpikesGame(
    worldHeight: Config.worldHeight,
    soundEnabled: false,
    showcasePlan: _ShowcasePlan(plan),
  )..runSeed = 35;
}

List<Object> _nextTiming(RunDirector director) => [
  director.rollSqueezeHold(hoop: 7, index: 1),
  director.rollPuzzleBonus(),
  director.rollHourglassDuration(),
  director.rollBigHoopsDuration(),
  director.rollSqueezeAt(42, hoop: 12, index: 1),
];

void main() {
  for (final starter in [Powerup.none, Powerup.shield, Powerup.bigHoops]) {
    FlameTester<FlappySpikesGame>(
      () => _game(
        ShowcaseRunPlan(
          highlightId: 'portal',
          step: 0,
          attempt: 1,
          extraStarters: [Powerup.bigHoops, Powerup.shield],
        ),
      ),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    ).testGameWidget(
      'showcase step 1 arms Big Hoops for 60 s and shield with starter '
      '$starter',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        final run = await startRun(game, starter: starter);
        expect(run.setup.extraStarters, [Powerup.bigHoops, Powerup.shield]);
        expect(run.state.shield, isTrue);
        expect(run.state.bigHoops!.duration, 60);
        expect(run.state.bigHoops!.mult(52), 1.5);
        expect(run.countsForAchievements, isTrue);
        expect(RunHud.of(run), isNotNull);
        expect(game.menu.slot.armed, Powerup.none);
        expect(run.spawner.hoops, isNotEmpty);

        // The 60 s override still consumes the normal Big Hoops draw. Drive
        // the same startup draws on a normal Big Hoops director and compare
        // the next timing-stream values, so a missing draw cannot shift a
        // later squeeze, bonus or powerup.
        final baseline = RunDirector(
          seed: 35,
          enabled: const {},
          met: const {},
        );
        final rolled = baseline.rollBigHoopsDuration();
        expect(rolled, inInclusiveRange(30, 40));
        final firstSqueeze = baseline.rollSqueezeAt(
          0,
          hoop: 0,
          index: 0,
          first: true,
        );
        expect(
          run.state.squeeze.nextAt,
          firstSqueeze,
          reason: 'the showcase startup consumed a different timing draw',
        );
        expect(
          _nextTiming(run.director),
          _nextTiming(baseline),
          reason: 'the showcase timing stream drifted after Big Hoops',
        );
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => _game(
      ShowcaseRunPlan(
        highlightId: 'comet',
        step: 1,
        attempt: 1,
        extraStarters: [Powerup.bigHoops, Powerup.shield],
      ),
    ),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  ).testGameWidget(
    'later showcase steps keep the normal 30–40 s Big Hoops roll',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game, starter: Powerup.bigHoops);
      final baseline = RunDirector(seed: 35, enabled: const {}, met: const {});
      expect(run.state.bigHoops!.duration, baseline.rollBigHoopsDuration());
      expect(run.state.bigHoops!.duration, inInclusiveRange(30, 40));
    },
  );
}
