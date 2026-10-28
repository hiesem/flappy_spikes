import 'dart:async';

import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/leaderboard/results_climb.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/leaderboard/lb_models.dart';
import 'package:flappy_spikes/leaderboard/lb_service.dart';
import 'package:flappy_spikes/run/screens/post_run_flow.dart';
import 'package:flappy_spikes/services/integrity_guard.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

class _Service extends NoopLeaderboardService {
  _Service(this.response, this.requested);
  final Completer<LbSubmitRunResult?> response;
  final Completer<void> requested;
  String? runId;
  @override
  Future<LbSubmitRunResult?> submitRun(LbSubmitRunRequest request) {
    runId = request.runs.first.id;
    if (!requested.isCompleted) requested.complete();
    return response.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final me = LbBoardRow(
    rid: 'me',
    rank: 4,
    name: 'Me',
    look: Look.defaults,
    points: 42,
    best: 900,
  );
  final board = LbBoardPayload(tab: LbBoardTab.today, rows: [me], me: me);
  LbSubmitRunResult result(int before, int after) => LbSubmitRunResult(
    accepted: const ['run'],
    dropped: const [],
    rank: LbRankChange(before: before, after: after),
    board: board,
  );

  test('run 4 and a positive climb show approved sticker and timings', () {
    for (final entry in [(5, 4, .55), (7, 4, 1.1), (12, 4, 2.3)]) {
      final climb = ResultsClimb.fromSubmit(
        result(entry.$1, entry.$2),
        gamesPlayed: 4,
      )!;
      expect(climb.climbDuration, entry.$3);
      expect(
        climb.stickerText,
        entry.$1 == 5
            ? 'YOU CLIMBED 1 SPOT!'
            : 'YOU CLIMBED ${entry.$1 - 4} SPOTS!',
      );
    }
    expect(ResultsClimb.fromSubmit(result(5, 4), gamesPlayed: 3), isNull);
    expect(ResultsClimb.fromSubmit(result(4, 4), gamesPlayed: 4), isNull);
    expect(ResultsClimb.fromSubmit(result(4, 5), gamesPlayed: 4), isNull);
    expect(ResultsClimb.fromSubmit(null, gamesPlayed: 4), isNull);
  });

  testWidgets('deadline returns without waiting and ignores a late submit', (
    tester,
  ) async {
    final submit = Completer<LbSubmitRunResult?>();
    var completed = false;
    LbSubmitRunResult? received;
    timelyClimbSubmit(submit.future).then((r) {
      completed = true;
      received = r;
    });
    await tester.pump(const Duration(milliseconds: 3999));
    expect(completed, false);
    await tester.pump(const Duration(milliseconds: 1));
    expect(completed, true);
    expect(received, isNull);
    submit.complete(result(5, 4));
    await tester.pump();
    expect(received, isNull);
  });

  final response = Completer<LbSubmitRunResult?>();
  final requested = Completer<void>();
  late IntegrityGuard original;
  setUp(() {
    original = IntegrityGuard.instance;
    IntegrityGuard.instance = IntegrityGuard(enforce: true);
  });
  tearDown(() {
    IntegrityGuard.instance = original;
  });
  final service = _Service(response, requested);
  FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({});
    return FlappySpikesGame(soundEnabled: false, leaderboard: service);
  }).testGameWidget(
    'run-end submit reaches the results climb without holding the page',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
      await game.storage.saveGamesPlayed(3);
    },
    verify: (game, tester) async {
      final run = await startRun(game);
      await flyRun(game, untilHoops: 1, maxSeconds: 10);
      game.endRun(run.endRun());
      await tester.pump();
      await flushAndMount(game);
      expect(game.resultsScreen, isNotNull);
      expect(game.resultsScreen!.children.whereType<ResultsClimb>(), isEmpty);
      for (var i = 0; i < 30 && !requested.isCompleted; i++) {
        await tester.pump();
        await flushAndMount(game);
      }
      expect(requested.isCompleted, isTrue);
      expect(game.storage.gamesPlayed, 4);
      await tester.runAsync(() async {
        response.complete(
          LbSubmitRunResult(
            accepted: [service.runId!],
            dropped: const [],
            rank: const LbRankChange(before: 5, after: 4),
            board: board,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 1));
        await flushAndMount(game);
      }
      expect(
        game.resultsScreen!.children.whereType<ResultsClimb>(),
        hasLength(1),
      );
      final page = game.resultsScreen!;
      page.next();
      expect(page.leaving, false);
      for (var i = 0; i < 200; i++) {
        game.update(.1);
      }
      await flushAndMount(game);
      page.next();
      for (var i = 0; i < 30; i++) {
        game.update(.1);
      }
      await flushAndMount(game);
      expect(page.children.whereType<ResultsClimb>(), isEmpty);
    },
  );
}
