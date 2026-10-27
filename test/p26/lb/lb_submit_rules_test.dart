import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/game_services.dart';
import '../../helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/leaderboard/lb_models.dart';
import 'package:flappy_spikes/leaderboard/lb_queue.dart';
import 'package:flappy_spikes/leaderboard/lb_service.dart';
import 'package:flappy_spikes/leaderboard/lb_submit_hook.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/services/integrity_guard.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/timeline.dart';

RunSummary summary({int score = 5, RunTimeline? timeline}) => RunSummary(
  score: score,
  hoopsPassed: 5,
  coins: 5,
  bestBefore: 0,
  bestAfter: score,
  runSeconds: 10,
  cause: MistakeCause.missedHoop,
  hoopIndex: 5,
  timeline:
      timeline ??
      (RunTimeline()
        ..addEntry(9, score)
        ..end(10)),
);

class _NativeSpy extends GameServices {
  final scores = <int>[];
  @override
  Future<void> submitBestScore(int value) async {
    scores.add(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameStorage storage;
  late LbSubmitHook hook;
  late List<Map<String, Object?>> calls;
  late IntegrityGuard original;
  setUp(() async {
    original = IntegrityGuard.instance;
    IntegrityGuard.instance = IntegrityGuard(enforce: true);
    SharedPreferences.setMockInitialValues({});
    storage = GameStorage();
    await storage.load();
    calls = [];
    hook = LbSubmitHook(
      LbQueue(
        storage: storage,
        service: FakeLeaderboardService(
          onCall: (_, request) async {
            calls.add(request);
            return {
              'accepted': [
                for (final r in request['runs'] as List) (r as Map)['id'],
              ],
              'dropped': [],
            };
          },
        ),
        request: (runs) =>
            LbSubmitRunRequest(runs: runs, t: LbSubmitHook.testerBuild ? 1 : 0),
      ),
      storage,
    );
  });
  tearDown(() {
    IntegrityGuard.instance = original;
  });
  final native = _NativeSpy();
  FlameTester<FlappySpikesGame>(
    () => createTestGame({}, null, native),
  ).testGameWidget(
    'native PG / GC submit still runs on every non-counting run end',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      final before = native.scores.length;
      game.state = GameState.playing;
      game.endRun(null);
      expect(native.scores.length, before + 1);
      expect(native.scores.last, game.storage.bestScore);
      expect(game.storage.lbQueue, isEmpty);
    },
  );
  for (final assist in ['debug', 'god', 'bot']) {
    final boardCalls = <Map<String, Object?>>[];
    FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({});
      return FlappySpikesGame(
        soundEnabled: false,
        leaderboard: FakeLeaderboardService(
          onCall: (_, request) async {
            boardCalls.add(request);
            return null;
          },
        ),
      );
    }).testGameWidget(
      '$assist run never submits even with achievement test override',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
        game.achievements.countDebugRuns = true;
      },
      verify: (game, _) async {
        game.runDebug.god = assist == 'god';
        game.runDebug.bot = assist == 'bot';
        final run = await startRun(
          game,
          startHoopIndex: assist == 'debug' ? 10 : 0,
        );
        expect(run.countsForAchievements, true);
        expect(run.countsForUpload, false);
        game.endRun(run.endRun());
        await flushAndMount(game);
        expect(boardCalls, isEmpty);
        expect(game.storage.lbQueue, isEmpty);
      },
    );
  }
  test('non-counting guard (including soak / e2e) never queues', () async {
    await hook.onRunEnd(
      summary(),
      countsForAchievements: true,
      countsForUpload: false,
      mode: 'free',
      look: Look.defaults,
    );
    expect(calls, isEmpty);
    expect(storage.lbQueue, isEmpty);
  });
  test('achievement guard and integrity guard both block submit', () async {
    await hook.onRunEnd(
      summary(),
      countsForAchievements: false,
      countsForUpload: true,
      mode: 'versus',
      look: Look.defaults,
    );
    IntegrityGuard.instance.markUntrusted('save');
    await hook.onRunEnd(
      summary(),
      countsForAchievements: true,
      countsForUpload: true,
      mode: 'versus',
      look: Look.defaults,
    );
    expect(calls, isEmpty);
  });
  for (final mode in ['free', 'versus', 'weekly']) {
    test(
      '$mode counting runs submit typed duration, proofs and tester marker',
      () async {
        await hook.onRunEnd(
          summary(),
          countsForAchievements: true,
          countsForUpload: true,
          mode: mode,
          look: Look.defaults,
        );
        expect(calls.single['t'], 1);
        final run = (calls.single['runs'] as List).single as Map;
        expect(run['mode'], mode);
        expect(run['cs'], 1000);
        expect(run['hoops'], 5);
        expect(run['tl'], summary().timeline.encodeTl());
        expect(run['fl'], summary().timeline.encodeFlags());
      },
    );
  }
  test('only notable, fitting timelines are included', () {
    LbSubmittedRun build(RunSummary s, {int? best, int? floor}) =>
        LbSubmitHook.fromSummary(
          s,
          id: 'r',
          end: DateTime.utc(2026),
          mode: 'free',
          verifiedBest: best,
          bestFloor: floor,
        );
    expect(build(summary(), best: 10).tl, isNull);
    expect(build(summary(), best: 1).tl, isNotNull);
    expect(build(summary(), best: 10, floor: 5).fl, isNotNull);
    expect(build(summary()).tl, isNotNull);
    final huge = RunTimeline(
      cs: List.filled(20000, 100),
      flags: List.filled(20000, 0),
    );
    expect(build(summary(score: 20000, timeline: huge)).tl, isNull);
    expect(build(summary(score: 20000, timeline: huge)).fl, isNull);
  });
}
