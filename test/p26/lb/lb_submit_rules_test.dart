import 'dart:convert';
import 'dart:io';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/home_mode.dart';
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

RunSummary summary({
  int score = 5,
  int bestBefore = 0,
  RunTimeline? timeline,
}) => RunSummary(
  score: score,
  hoopsPassed: 5,
  coins: 5,
  bestBefore: bestBefore,
  bestAfter: score > bestBefore ? score : bestBefore,
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
  for (final cardCase in <(String, String?)>[
    ('', null),
    ('f_bubblegum|n_ocean|s_gg', 'f_bubblegum|n_ocean|s_gg'),
    ('unknown|unknown|unknown', null),
    ('unknown|n_ocean|unknown', '|n_ocean|'),
  ]) {
    FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({});
      return FlappySpikesGame(soundEnabled: false);
    }).testGameWidget(
      'real queue request passes server card/look validation: ${cardCase.$1}',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, _) async {
        game.storage.ownedItems = {
          ...game.storage.ownedItems,
          'card:f_bubblegum',
          'card:n_ocean',
          'card:s_gg',
        };
        game.storage.equippedItems = {
          ...game.storage.equippedItems,
          SkinLayer.card: cardCase.$1,
        };
        final request = game.leaderboardQueue.request([]).toJson();
        if (cardCase.$2 == null) {
          expect(request.containsKey('card'), false);
          expect((request['look'] as Map).containsKey('card'), false);
        } else {
          expect(request['card'], cardCase.$2);
          expect((request['look'] as Map)['card'], cardCase.$2);
        }
        // Use the actual server validators, not a Dart reimplementation.
        // functions/lib is built by verify.sh before the Dart checks.
        final checked = Process.runSync('node', [
          '--input-type=module',
          '-e',
          r'''
          import {validCard} from './functions/lib/card.js';
          import {validLook} from './functions/lib/schema.js';
          const request = JSON.parse(process.argv[1]);
          console.log(JSON.stringify({card: validCard(request.card), look: validLook(request.look)}));
        ''',
          jsonEncode(request),
        ]);
        expect(
          checked.exitCode,
          0,
          reason: '${checked.stdout}\n${checked.stderr}',
        );
        expect(jsonDecode(checked.stdout as String), {
          'card': true,
          'look': true,
        });
      },
    );
  }
  for (final mode in [HomeMode.freeFly, HomeMode.versus]) {
    final submitted = <Map<String, Object?>>[];
    FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({});
      return FlappySpikesGame(
        soundEnabled: false,
        leaderboard: FakeLeaderboardService(
          onCall: (_, request) async {
            submitted.add(request);
            return {
              'accepted': [
                for (final r in request['runs'] as List) (r as Map)['id'],
              ],
              'dropped': [],
            };
          },
        ),
      );
    }).testGameWidget(
      'counting game run end sends look, platform and ${mode.name} mode',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
        await game.storage.saveHomeMode(mode);
      },
      verify: (game, _) async {
        final run = await startRun(game);
        expect(run.countsForAchievements, true);
        expect(run.countsForUpload, true);
        await flyRun(game, untilHoops: 1, maxSeconds: 10);
        final ended = run.endRun();
        game.endRun(ended);
        await game.leaderboardQueue.flush();
        expect(submitted, hasLength(1));
        final payload = submitted.single;
        expect(payload['look'], {
          'bird': 'classic',
          'gear': 'none',
          'hat': 'none',
          'hoop': 'pink',
          'trail': 'flame',
        });
        expect(payload['platform'], 'android');
        final sent = (payload['runs'] as List).single as Map;
        expect(sent['score'], ended.score);
        expect(sent['mode'], mode == HomeMode.freeFly ? 'free' : 'versus');
        expect(game.storage.lbQueue, isEmpty);
      },
    );
  }
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
    // PRD WP-LB/O55: an offline local PB is not a verified server PB.
    final belowLocalBest = build(summary(score: 5, bestBefore: 1000));
    expect(belowLocalBest.tl, summary().timeline.encodeTl());
    expect(belowLocalBest.fl, summary().timeline.encodeFlags());
    final huge = RunTimeline(
      cs: List.filled(20000, 100),
      flags: List.filled(20000, 0),
    );
    expect(build(summary(score: 20000, timeline: huge)).tl, isNull);
    expect(build(summary(score: 20000, timeline: huge)).fl, isNull);
  });
}
