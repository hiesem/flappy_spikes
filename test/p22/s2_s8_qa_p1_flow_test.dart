import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/upload_queue.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../versus/s3_13_service_test.dart' as fixture;

void main() {
  final spy = AnalyticsSpy();
  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, services: spy),
    gameSize: Vector2(320, 711),
  );
  Future<void> prepare(FlappySpikesGame g) async {
    spy.events.clear();
    await g.ready();
    await preloadImages(g);
  }

  tester.testGameWidget(
    '§8 nested debug panel closes before Settings and logs the right screens',
    setUp: (g, _) => prepare(g),
    verify: (g, _) async {
      g.openSettings();
      await flushAndMount(g);
      g.openDebugPanel();
      await flushAndMount(g);
      expect(g.debugPanel, isNotNull);
      expect(g.handleSystemBack(), isTrue);
      expect(g.debugPanel, isNull);
      expect(g.menuScene, MenuScene.settings);
      expect(g.handleSystemBack(), isFalse);
      stepGame(g, Config.systemBackDebounce + .01);
      expect(g.handleSystemBack(), isTrue);
      expect(g.menuScene, MenuScene.home);
      expect(
        spy.events
            .where((e) => e.$1 == 'back_gesture')
            .map((e) => e.$2!['screen']),
        ['debug', 'settings'],
      );
    },
  );

  tester.testGameWidget(
    '§2 × §8 mode switch and system back do nothing during awaited START',
    setUp: (g, _) => prepare(g),
    verify: (g, _) async {
      final gate = Completer<void>();
      g.beforeRunStart = () => gate.future;
      final mode = g.homeMode;
      final starting = g.startRun();
      final sounds = sfxLog(g);
      expect(g.state, GameState.start);
      g.toggleHomeMode();
      expect(g.homeMode, mode);
      expect(g.handleSystemBack(), isFalse);
      expect(sounds, isEmpty);
      gate.complete();
      await starting;
      await flushAndMount(g);
      expect(g.state, GameState.playing);
    },
  );

  late FlappySpikesGame game;
  late FirebaseVersusService versus;
  late fixture.FakeBackend backend;
  FlameTester<FlappySpikesGame>(() {
    backend = fixture.FakeBackend()..verdict = (_) => UploadWrite.retry;
    versus = FirebaseVersusService(
      storageOf: () => game.storage,
      backend: backend,
      identity: fixture.FakeIdentity(),
      random: Random(5),
    );
    game = createRunTestGame(
      worldHeight: 711,
      versus: versus,
      prefs: {
        'homeMode': 'freeFly',
        'bestScore': 900, 'playerLevel': 7,
        'claimedLevels': ['1', '2', '3', '4', '5', '6', '7', '8'],
      },
    );
    return game;
  }, gameSize: Vector2(320, 711)).testGameWidget(
    '§2.2 FREE FLY uses the real persisted queue: under 3 points is skipped, '
    'three non-bests queue, then daily cap, a new best still queues',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
      await versus.initialize();
    },
    verify: (g, _) async {
      addTearDown(versus.dispose);
      for (final (points, decision, count) in [
        (2, UploadDecision.lowScore, 0),
        (4, UploadDecision.queued, 1),
        (4, UploadDecision.queued, 2),
        (4, UploadDecision.queued, 3),
        (4, UploadDecision.dailyCap, 3),
        (901, UploadDecision.queuedBest, 4),
      ]) {
        final run = await startRun(g);
        expect(run.setup.opponent, isNull);
        expect(g.runHud!.versus, isNull);
        run.ctx.addScore(points);
        killRun(g);
        await declineRevive(g);
        await flushAndMount(g);
        expect(g.resultsScreen!.them, isNull);
        expect(versus.lastOffer, decision);
        expect(versus.queue.pending, hasLength(count));
        if (count > 0) {
          final queued = versus.queue.pending.last.entry;
          expect(queued.score, points);
          expect(queued.timeline.points, queued.score);
        }
        g.goHome();
        await flushAndMount(g);
        stepGame(g, 1);
        await flushAndMount(g);
      }
      expect(versus.queue.pending.last.newBest, isTrue);
      expect(versus.queue.uploadsToday, 3);
    },
  );
}
