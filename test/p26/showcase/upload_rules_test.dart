import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/menu/home_mode.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/upload_queue.dart';
import 'package:flappy_spikes/run/showcase/showcase_plan.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

// Records the production run-end call and offers it to the real persisted queue.
class QueueingVersus extends FakeVersusService {
  QueueingVersus({super.pool});
  late UploadQueue queue;

  @override
  Future<void> submitRun(RunSummary s, Look look) async {
    await super.submitRun(s, look);
    await queue.offer(
      RunEntry.fromSummary(
        s,
        runId: 'finished',
        name: 'Player',
        ts: DateTime.utc(2026),
      ),
      newBest: s.newBest,
    );
  }
}

void main() {
  for (final versus in [false, true]) {
    for (final revive in [null, ReviveKind.ad, ReviveKind.coins]) {
      final service = QueueingVersus(
        pool: [
          if (versus)
            OpponentRun(
              uid: 'rival',
              name: 'Rival',
              score: 3,
              best: 3,
              level: 0,
              timeline: RunTimeline()..end(10),
              runId: 'r',
            ),
        ],
      );
      FlameTester<FlappySpikesGame>(() {
        SharedPreferences.setMockInitialValues({});
        return FlappySpikesGame(
          worldHeight: 711,
          soundEnabled: false,
          versus: service,
          showcasePlan: FixedShowcase(ShowcaseScript.planFor(0, 1)),
        );
      }, gameSize: Vector2(320, 711)).testGameWidget(
        'B/E showcase uploads with versus=$versus revive=$revive',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
          service.queue = UploadQueue(game.storage);
        },
        verify: (game, _) async {
          if (!versus) await game.storage.saveHomeMode(HomeMode.freeFly);
          final run = await startRun(game);
          expect(game.homeMode, versus ? HomeMode.versus : HomeMode.freeFly);
          expect(run.setup.opponent != null, versus);
          expect(run.setup.forced, isEmpty);
          expect(run.countsForAchievements, isTrue);
          if (revive != null) run.revive(revive);
          // Real flight records a valid timeline; no debugPass or god mode.
          await flyRun(game, untilHoops: 3, maxSeconds: 10);
          expect(run.state.hoopsPassed, greaterThanOrEqualTo(3));
          expect(run.countsForAchievements, isTrue);
          final summary = run.endRun();
          game.endRun(summary);
          await flushAndMount(game);
          expect(service.submitted, contains(summary));
          expect(summary.revives, revive != null ? 1 : 0);
          // The same run-end call also reached the real persisted queue.
          expect(service.queue.pending, hasLength(1));
          expect(service.queue.pending.single.entry.score, summary.score);
        },
      );
    }
  }
  for (final assist in [
    'forced start',
    'forced mid-run',
    'god',
    'bot',
    'ignore gates',
  ]) {
    final service = QueueingVersus();
    FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({});
      return FlappySpikesGame(
        worldHeight: 711,
        soundEnabled: false,
        versus: service,
        showcasePlan: FixedShowcase(ShowcaseScript.planFor(0, 1)),
      );
    }, gameSize: Vector2(320, 711)).testGameWidget(
      'E1 finished $assist run never reaches submitRun or persisted queue',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        service.queue = UploadQueue(game.storage);
      },
      verify: (game, _) async {
        if (assist == 'ignore gates') game.runDebug.ignoreGates = true;
        final run = await startRun(
          game,
          force: assist == 'forced start' ? [ElementId.heart] : const [],
        );
        await flyRun(game, untilHoops: 3, maxSeconds: 10);
        expect(run.state.hoopsPassed, greaterThanOrEqualTo(3));
        switch (assist) {
          case 'forced mid-run':
            game.debugForceElement(ElementId.heart);
          case 'god':
            game.runDebug.god = true;
          case 'bot':
            game.runDebug.bot = true;
        }
        expect(run.countsForUpload, isFalse);
        // Turning assists off cannot restore eligibility.
        game.runDebug.god = false;
        game.runDebug.bot = false;
        final summary = run.endRun();
        expect(summary.score, greaterThanOrEqualTo(3));
        game.endRun(summary);
        await flushAndMount(game);
        expect(service.submitted, isEmpty);
        expect(service.queue.pending, isEmpty);
        expect(game.storage.uploadQueue, isEmpty);
      },
    );
  }
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({});
    return FlappySpikesGame(
      worldHeight: 711,
      soundEnabled: false,
      showcasePlan: FixedShowcase(ShowcaseScript.planFor(0, 1)),
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    'B showcase eligibility is permanently lost after debug assistance',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      expect(run.countsForAchievements, isTrue);
      run.markDebugAssist();
      expect(run.countsForAchievements, isFalse);
      expect(run.countsForUpload, isFalse);
    },
  );
}
