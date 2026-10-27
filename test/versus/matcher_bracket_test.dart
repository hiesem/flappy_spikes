import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flappy_spikes/versus/brackets.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flappy_spikes/versus/matcher.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import 's3_13_upload_entry_test.dart' show entry;
import 's3_13_service_test.dart' as service;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'E4 service searches best bracket while profile and emblem use progression',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      await storage.saveBestScore(80);
      await storage.savePlayerLevel(25);
      final backend = service.FakeBackend();
      backend.pools['2_0'] = [
        PoolEntry.fromMap({
          ...entry(60, bestBefore: 80).toMap(),
          'uid': 'other',
          'level': 2,
          'plv': 32,
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
      expect(versus.me.level, 25);
      expect(versus.lastSearch.bracket, 2);
      expect(backend.poolReads.toSet(), {'2_0', '2_1', '2_2', '2_3'});
      final opponent = versus.takeOpponent()!;
      expect(opponent.level, 32);
      expect(opponent.score, 60);
    },
  );

  final fixture =
      jsonDecode(File('test/fixtures/versus_matching.json').readAsStringSync())
          as Map;
  for (final c in fixture['cases'] as List) {
    test('E4 best-score bracket ignores progression: ${c['name']}', () {
      final me = c['me'] as Map;
      final best = me['best'] as int;
      expect(bracketFor(best), me['bracket']);
      // Repeat with very different progression levels on every opponent.
      for (final plv in [0, 25, 9999]) {
        final pool = [
          for (final e in c['pool'] as List)
            PoolCandidate(
              PoolEntry.fromMap({
                ...entry(
                  e['score'] as int,
                  bestBefore: 5000,
                  id: e['runId'] as String,
                ).toMap(),
                'uid': e['uid'],
                'pg': e['pg'] ?? '',
                'level': e['bracket'], // Stored name remains `level`.
                'plv': plv,
              })!,
            ),
        ];
        final (tier, candidates) = matchCandidates(
          pool,
          myBracket: bracketFor(best),
          myBest: best,
          myUid: me['uid'] as String,
          myPg: me['pg'] as String? ?? '',
          met: (c['seen'] as List).cast<String>(),
        );
        expect(tier.name, c['expect']['tier']);
        expect(
          candidates.map((e) => e.runId),
          unorderedEquals(c['expect']['runIds'] as List),
        );
      }
    });
  }

  test(
    'E4 level 25 / best 80 searches bracket 2; 44 bracket_shard ids',
    () async {
      final order = poolSearchOrder(bracketFor(80), Random(7));
      expect(order.take(4).toSet(), {'2_0', '2_1', '2_2', '2_3'});
      expect(order.toSet(), {
        for (var b = 0; b <= 10; b++)
          for (var s = 0; s < 4; s++) '${b}_$s',
      });
      final result = await searchPools<PoolCandidate>(
        order: order,
        read: (_) async => [],
        myUid: 'me',
      );
      expect(result.reads, 44);
      expect(result.found, isFalse);
    },
  );

  for (final (raw, expected) in <(Object?, int)>[
    (null, 0),
    (-12, 0),
    (25, 25),
    (10000, 9999),
    (12.9, 12),
    ('25', 0),
    (double.nan, 0),
    (double.infinity, 0),
  ]) {
    test('R4 opponent emblem plv $raw becomes $expected', () {
      final pool = PoolEntry.fromMap({
        ...entry(60, bestBefore: 5000).toMap(),
        'uid': 'other',
        'level': 10,
        'plv': ?raw,
      })!;
      expect(pool.plv, expected);
      expect(pool.toOpponent().level, expected);
    });
  }
}
