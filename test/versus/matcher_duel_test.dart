import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/items/versus_recorder.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/duel.dart';
import 'package:flappy_spikes/versus/matcher.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 's3_13_service_test.dart' as service;
import 's3_13_versus_run_test.dart' show vt;
import '../helpers.dart';
import 's3_13_upload_entry_test.dart' show entry;

class Candidate implements Matchable {
  Candidate(Map data)
    : uid = data['uid'] as String,
      runId = data['runId'] as String,
      score = data['score'] as int,
      level = data['bracket'] as int,
      pg = data['pg'] as String? ?? '';
  @override
  final String uid;
  @override
  final String runId;
  @override
  final int score;
  @override
  final int level;
  @override
  final String pg;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture =
      jsonDecode(File('test/fixtures/versus_duel.json').readAsStringSync())
          as Map;
  for (final c in fixture['stepCases'] as List) {
    test('E5 step: ${c['name']}', () {
      final result = switch (c['result']) {
        'win' => DuelResult.win,
        'loss' => DuelResult.lose,
        _ => DuelResult.draw,
      };
      expect(
        duelStepAfter(c['step'] as int? ?? duelStepStart, result),
        c['expect']['step'],
      );
    });
  }
  for (final c in fixture['targetCases'] as List) {
    test('E5 target: ${c['name']}', () {
      final step = c['step'] as int;
      final scores = (c['recentScores'] as List).cast<int>();
      expect(duelTarget(step, scores), c['expect']['target']);
      expect(duelTarget(step, [100]), 100 * (c['expect']['factor'] as num));
    });
  }
  for (final c in fixture['pickCases'] as List) {
    test('E5 pick: ${c['name']}', () {
      final pool = [for (final e in c['pool'] as List) Candidate(e as Map)];
      final expected = c['expect'] as Map;
      final ids = <String>{};
      for (var seed = 0; seed < 50; seed++) {
        final pick = pickDuelOpponent(
          pool,
          myUid: c['me']['uid'] as String,
          myPg: c['me']['pg'] as String? ?? '',
          step: c['step'] as int,
          recentScores: (c['recentScores'] as List).cast<int>(),
          met: (c['seen'] as List).cast<String>(),
          r: Random(seed),
        );
        expect(pick.target, expected['target']);
        expect(pick.tier.name, expected['tier']);
        if (expected['runIds'] != null) {
          expect(expected['runIds'], contains(pick.entry?.runId));
          ids.add(pick.entry!.runId);
        } else {
          expect(pick.entry?.runId, expected['pick']);
        }
      }
      if (expected['runIds'] != null) {
        expect(ids, unorderedEquals(expected['runIds'] as List));
      }
    });
  }

  for (final counting in [true, false]) {
    vt(
      'E5 run-end seam and analytics: counting=$counting',
      () {
        final opponent = OpponentRun(
          uid: 'rival',
          name: 'Rival',
          score: 4,
          best: 4,
          level: 0,
          timeline: RunTimeline.empty(),
        );
        setDuelMatchInfo(
          opponent,
          const DuelMatchInfo(tier: DuelTier.band, step: -2, target: 6),
        );
        return FakeVersusService(pool: [opponent]);
      },
      (game, spy) async {
        game.runDebug.ignoreGates = false;
        final run = await startRun(game);
        if (!counting) run.debugPass(perfect: false);
        run.state.score = 6;
        game.score = 6;
        final summary = run.endRun();
        game.endRun(summary);
        // Duplicate end notifications must not append another score or step.
        game.endRun(summary);
        await flushAndMount(game);
        expect(game.storage.recentScores, counting ? [6] : isEmpty);
        expect(game.storage.duelStep, counting ? -1 : -2);
        final result = analyticsLog(
          spy,
        ).where((e) => e.$1 == 'versus_result').single;
        expect(result.$2, {
          'result': 'win',
          'score': 6,
          'opp_score': 4,
          'tier': 'band',
          'duel_step': -2,
          'ratio_x100': 150,
          'first': 1,
        });
      },
    );
  }

  test('half-integer median preserves fractional target and band', () {
    expect(duelMedian([1, 2]), 1.5);
    expect(duelTarget(-1, [1, 2]), 1.05);
    final pick = pickDuelOpponent(
      [
        Candidate({'uid': 'u', 'runId': 'r', 'score': 1, 'bracket': 0}),
      ],
      myUid: 'me',
      step: -1,
      recentScores: [1, 2],
      r: Random(1),
    );
    expect(pick.tier, DuelTier.band);
  });

  for (final initialHistory in <List<int>>[
    [],
    [100],
  ]) {
    test(
      'service refreshes prefetched target (history=$initialHistory) and carries metadata',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = GameStorage();
        await storage.load();
        await storage.saveBestScore(80);
        await storage.saveRecentScores(initialHistory);
        final backend = service.FakeBackend();
        backend.pools['2_0'] = [
          for (final (id, score) in [('closest', 10), ('band', 60)])
            PoolEntry.fromMap({
              ...entry(score, id: id, bestBefore: 80).toMap(),
              'uid': 'other',
              'level': 2,
            })!,
        ];
        final versus = FirebaseVersusService(
          storageOf: () => storage,
          backend: backend,
          identity: service.FakeIdentity(),
          random: Random(7),
        );
        addTearDown(versus.dispose);
        await versus.initialize();
        await storage.saveRecentScores([100]);
        final opponent = versus.takeOpponent()!;
        expect(opponent.runId, 'band');
        expect(duelMatchInfo(opponent)?.tier, DuelTier.band);
        expect(duelMatchInfo(opponent)?.step, -2);
        expect(duelMatchInfo(opponent)?.first, isTrue);
        final second = versus.takeOpponent()!;
        expect(second.runId, 'closest');
        versus.onRunStart();
        await versus.searchForStart();
        final rematch = versus.takeOpponent()!;
        expect(rematch.runId, 'band');
        expect(duelMatchInfo(rematch)?.tier, DuelTier.rematch);
        expect(duelMatchInfo(rematch)?.first, isFalse);
      },
    );
  }

  test(
    'counting score history and rival results persist; solo and debug do not step',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      final rival = OpponentRun(
        uid: 'u',
        name: 'Rival',
        score: 20,
        best: 20,
        level: 0,
        timeline: RunTimeline.empty(),
      );
      RunSummary summary(int score, {bool versus = false}) => RunSummary(
        score: score,
        hoopsPassed: 0,
        coins: 0,
        bestBefore: 0,
        bestAfter: score,
        runSeconds: 1,
        cause: MistakeCause.missedHoop,
        hoopIndex: 0,
        timeline: RunTimeline.empty(),
        opponent: versus ? rival : null,
        duel: versus ? duelOf(score, rival.score) : null,
      );
      for (var score = 0; score < 12; score++) {
        await recordDuelRun(storage, summary(score), counts: true);
      }
      expect(storage.recentScores, List.generate(10, (i) => i + 2));
      expect(storage.duelStep, -2);
      await recordDuelRun(storage, summary(100, versus: true), counts: false);
      expect(storage.recentScores.last, 11);
      expect(storage.duelStep, -2);
      await recordDuelRun(storage, summary(30, versus: true), counts: true);
      expect(storage.duelStep, -1);
      await recordDuelRun(storage, summary(20, versus: true), counts: true);
      expect(storage.duelStep, -1);
      await recordDuelRun(storage, summary(10, versus: true), counts: true);
      expect(storage.duelStep, -3);
      final reloaded = GameStorage();
      await reloaded.load();
      expect(reloaded.recentScores, storage.recentScores);
      expect(reloaded.duelStep, -3);
    },
  );
}
