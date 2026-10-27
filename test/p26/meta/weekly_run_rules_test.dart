import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/progression/weekly_course.dart';
import 'package:flappy_spikes/run/director/run_director.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/items/squeeze.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/run/run_setup.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  final monday = DateTime.utc(2026, 10, 26);
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({
      Obf.prefGamesPlayed: 6,
      Obf.prefBestHoops: 40,
    });
    return FlappySpikesGame(
      soundEnabled: false,
      worldHeight: 711,
      clock: () => monday,
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'weekly START preserves home slot, counts normally, and skips revive',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      await game.storage.saveArmedPowerup('shield');
      final homeMode = game.homeMode;
      await game.startWeeklyCourse();
      await flushAndMount(game);
      final run = game.run!;
      expect(run.setup.weekly, isTrue);
      expect(run.setup.seed, WeeklyWeek.at(monday).seed);
      expect(run.setup.opponent, isNull);
      expect(run.setup.showcase, isNull);
      expect(run.setup.starter, Powerup.none);
      expect(run.state.shield, isFalse);
      expect(game.storage.armedPowerup, 'shield');
      expect(game.homeMode, homeMode);
      expect(game.runSubmissionMode, 'weekly');
      expect(run.countsForUpload, isTrue);
      expect(run.countsForAchievements, isTrue);
      game.onPlayfieldTap();
      run.state.hoopsPassed = 30;
      killRunThroughSaves(game);
      await flushAndMount(game);
      expect(game.state, isNot(GameState.reviving));
      expect(game.reviveScreen, isNull);
      expect(run.state.revivesThisGame, 0);
      expect(game.storage.armedPowerup, 'shield');
    },
  );

  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({});
    return FlappySpikesGame(soundEnabled: false, worldHeight: 711);
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'weekly director opens every gate and ignores personal course history',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      await game.startWeeklyCourse(now: monday);
      expect(game.run, isNull); // Locked installs cannot enter through the API.
      final setup = WeeklyWeek.at(monday).setup(viewHeight: 711);
      final first = RunController(setup: setup, game: game);
      expect(first.enabled, contains(ElementId.saw));
      // Squeeze is a timed feature, not a hoop/pickup registry member. Exercise
      // its actual lifetime gate rather than testing registry membership.
      game.state = GameState.playing;
      first.start();
      first.state.runClock = 1000;
      first.state.hoopIndex = 10;
      first.state.squeeze.nextAt = 0;
      first.features.whereType<SqueezeFeature>().single.update(.01, .01);
      expect(first.state.squeeze.phase, SqueezePhase.warning);
      expect(first.countsForUpload, isTrue);
      final normal = RunController(
        setup: const RunSetup(seed: 7, viewHeight: 711),
        game: game,
      );
      normal.start();
      normal.state.runClock = 1000;
      normal.state.hoopIndex = 10;
      normal.state.squeeze.nextAt = 0;
      normal.features.whereType<SqueezeFeature>().single.update(.01, .01);
      expect(normal.state.squeeze.phase, SqueezePhase.idle);
      expect(normal.enabled, isNot(contains(ElementId.saw)));
      final replay = RunController(setup: setup, game: game);
      // Simulate another player, or another attempt after lifetime flags change.
      game.storage.metElements = ElementId.values
          .map((e) => e.storageId)
          .toSet();
      game.storage.lastPortalRide = RideId.values.last.storageId;
      game.storage.lastFeatherRun = 0;
      game.storage.lastPieceRun = 0;
      final second = RunController(setup: setup, game: game);
      final context = DirectorContext.open(711);
      for (var i = 0; i < 220; i++) {
        final a = replay.director.nextSlot(context);
        final b = second.director.nextSlot(context);
        expect(a, b, reason: 'slot $i');
        expect(
          replay.director.nextGap(context, a),
          second.director.nextGap(context, b),
          reason: 'gap $i',
        );
      }
    },
  );
}
