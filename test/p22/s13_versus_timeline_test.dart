import 'dart:convert';
import 'dart:io';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/e2e.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §13.5 / §13.7 versus timeline format v2 against the fixture
/// shared with `functions/test/timeline.test.ts` (Dart record → TS validate
/// → Dart replay), no v1 replay, the duel on points.
void main() {
  final fx =
      jsonDecode(
            File('test/fixtures/versus_timeline_v2.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final run = fx['run'] as Map<String, dynamic>;

  group('§13.5 timeline v2', () {
    test('§13.7 the Dart recorder writes exactly the fixture run (the TS '
        'server validates it), and replays it', () {
      final t = RunTimeline();
      for (final e in (fx['record'] as List).cast<Map<String, dynamic>>()) {
        t.addEntry(
          (e['t'] as num).toDouble(),
          e['value'] as int,
          flag: e['flag'] as int,
        );
      }
      t.end((fx['endSeconds'] as num).toDouble());
      expect(t.encodeTl(), run['tl']);
      expect(t.encodeFlags(), run['fl']);
      expect(t.endCs, run['end']);
      expect(t.points, run['score']);
      final back = RunTimeline.tryDecode(run['tl'], run['fl'], run['end'])!;
      for (final c in (fx['replay'] as List).cast<List>()) {
        expect(
          back.scoreAt((c[0] as int) / 100),
          c[1],
          reason: 'at ${c[0]} cs',
        );
      }
      expect(back.points, run['score']);
    });

    test('§13.5 no v1 support: a v1 timeline does not decode, a v1 pool '
        'entry is skipped', () {
      final v1 = fx['v1'] as Map<String, dynamic>;
      expect(RunTimeline.tryDecode(v1['tl'], v1['fl'], v1['end']), isNull);
      final entry = {
        'runId': 'old',
        'score': v1['score'],
        'best': v1['score'],
        'ts': 0,
        'name': 'Old',
        'avatar': '',
        'look': const <String, String>{},
        'platform': 'android',
        'tl': v1['tl'],
        'end': v1['end'],
        'fl': v1['fl'],
        'uid': 'u-old',
        'level': 0,
      };
      expect(RunEntry.fromMap(entry), isNull);
      expect(PoolEntry.fromMap(entry), isNull);
      // The converted run (functions/scripts conversion) is read and
      // replays exactly as the v1 run did (one point per entry).
      final conv = fx['v1Converted'] as Map<String, dynamic>;
      final pool = PoolEntry.fromMap({...entry, 'fl': conv['fl']})!;
      final opp = pool.toOpponent();
      expect(opp.score, v1['score']);
      for (final c in (fx['v1Replay'] as List).cast<List>()) {
        expect(opp.scoreAt((c[0] as int) / 100), c[1], reason: 'at ${c[0]}');
      }
    });

    test('§13.5 the entry cap: values clamp to uint16, zero values are '
        'not recorded', () {
      final t = RunTimeline()
        ..addEntry(1, 0)
        ..addEntry(2, 70000);
      expect(t.entries, 1);
      expect(t.values.single, 0xFFFF);
    });
  });

  setUp(E2EHooks.reset);

  /// An opponent with one v2 entry of [points] at 1 s.
  OpponentRun opponent(int points) {
    final t = RunTimeline()
      ..addEntry(1, points)
      ..end(2);
    return OpponentRun(
      uid: 'u-molly',
      name: 'Molly',
      score: points,
      best: points,
      level: 1,
      timeline: t,
      runId: 'run-molly',
    );
  }

  late AnalyticsSpy spy;
  FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(
      worldHeight: 711,
      services: spy,
      versus: FakeVersusService(pool: [opponent(6)]),
    );
  }, gameSize: Vector2(320, 711)).testGameWidget(
    '§13.7 the compare uses points (3 perfect hoops = 7 points beat 6); '
    'the win bonus pays coins, not points; the bar replays their points',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      final run = await startRun(g);
      expect(run.setup.opponent, isNotNull);
      expect(run.setup.opponent!.scoreAt(1.0), 6);
      for (var i = 0; i < 3; i++) {
        run.debugPass(perfect: true);
      }
      expect(run.state.hoopsPassed, 3);
      expect(run.state.score, 7);
      final coins0 = run.state.coinsThisRun;
      final s = run.endRun();
      expect(s.duel, DuelResult.win);
      expect(s.score, 7, reason: 'the win bonus adds no points');
      expect(run.state.coinsThisRun - coins0, 10);
      expect(s.timeline.points, 7);
      final r = spy.events.where((e) => e.$1 == 'versus_result').single;
      expect(r.$2, {'result': 'win', 'score': 7, 'opp_score': 6});
    },
  );
}
