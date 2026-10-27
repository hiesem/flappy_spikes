import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/versus/matcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fixture pool entry as a [Matchable].
class _E implements Matchable {
  _E(Map<String, Object?> m)
    : uid = m['uid']! as String,
      runId = m['runId']! as String,
      score = (m['score']! as num).toInt(),
      level = (m['bracket']! as num).toInt(),
      pg = (m['pg'] as String?) ?? '';
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

int _levelOf(String id) => int.parse(id.split('_').first);

/// PRD-2.2 §3 better matching when there are few players: the search order
/// (own level's shards first, then the nearest levels), stop at the first
/// hit, never the own uid, the 44-read cap and the time limit; the shared
/// fixture's `search` cases (also run by functions/test/matching.test.ts).
void main() {
  group('PRD-2.2 §3 search order', () {
    test('§3 own level first (all 4 shards), then nearest levels (lower '
        'before higher at a distance); each of the 44 pools once', () {
      expect(VersusConfig.maxSearchReads, 44);
      for (var level = 0; level <= VersusConfig.maxBracket; level++) {
        for (var seed = 0; seed < 8; seed++) {
          final order = poolSearchOrder(level, Random(seed * 31 + level));
          expect(order, hasLength(44));
          expect(order.toSet(), hasLength(44));
          expect(order.take(4).map(_levelOf), everyElement(level));
          expect(order.take(4).toSet(), {
            for (var s = 0; s < 4; s++) poolId(level, s),
          });
          final levels = [
            for (var i = 0; i < order.length; i += 4) _levelOf(order[i]),
          ];
          for (var i = 0; i < order.length; i++) {
            expect(_levelOf(order[i]), levels[i ~/ 4]);
          }
          for (var i = 1; i < levels.length; i++) {
            final a = (levels[i - 1] - level).abs();
            final b = (levels[i] - level).abs();
            expect(
              a < b || (a == b && levels[i - 1] < levels[i]),
              isTrue,
              reason: 'level $level order $levels',
            );
          }
        }
      }
    });

    test('§3 the shards of a level come in random order', () {
      final firsts = {
        for (var seed = 0; seed < 40; seed++)
          poolSearchOrder(3, Random(seed)).first,
      };
      expect(firsts.length, greaterThan(1));
    });
  });

  group('PRD-2.2 §3 search', () {
    Map<String, List<_E>> pools(Map<String, Object?> raw) => {
      for (final e in raw.entries)
        e.key: [
          for (final m in (e.value! as List).cast<Map<String, Object?>>())
            _E(m),
        ],
    };

    final fixture =
        jsonDecode(
              File('test/fixtures/versus_matching.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final cases = (fixture['search']! as List).cast<Map<String, Object?>>();

    test(
      '§3 the fixture has the sparse / own-uid-only / other-bracket cases',
      () {
        final names = cases.map((c) => c['name']! as String).join('\n');
        expect(names, contains('sparse pool'));
        expect(names, contains('own uid only'));
        expect(names, contains('other-bracket hit'));
      },
    );

    for (final c in cases) {
      test('§3 ${c['name']}', () async {
        final me = c['me']! as Map<String, Object?>;
        final myUid = me['uid']! as String;
        final bracket = (me['bracket']! as num).toInt();
        // PRD-2.3 §25.2 the ordered met list (oldest first).
        final seen = (c['seen']! as List).cast<String>();
        final myPg = (me['pg'] as String?) ?? '';
        final byId = pools(c['pools']! as Map<String, Object?>);
        final ex = c['expect']! as Map<String, Object?>;
        for (var seed = 0; seed < 12; seed++) {
          final reads = <String>[];
          final r = await searchPools<_E>(
            order: poolSearchOrder(bracket, Random(seed)),
            read: (id) async {
              reads.add(id);
              return byId[id] ?? const [];
            },
            myUid: myUid,
            met: seen,
            myPg: myPg,
          );
          expect(r.poolId, ex['pool']);
          expect(r.reads, reads.length);
          expect(
            r.reads,
            inInclusiveRange(ex['minReads']! as int, ex['maxReads']! as int),
          );
          // PRD-2.3 §25.2 reads go by rounds of 4 (one level's shards); a
          // fresh hit is in the last round read.
          if (r.found && ex['tier'] != 'rematch') {
            expect(reads.sublist(reads.length - 4), contains(r.poolId));
          }
          final (tier, cands) = matchCandidates(
            r.pool,
            myBracket: bracket,
            myBest: (me['best']! as num).toInt(),
            myUid: myUid,
            met: seen,
            myPg: myPg,
          );
          expect(tier.name, ex['tier']);
          expect(cands.map((e) => e.runId).toSet(), {
            ...(ex['runIds']! as List).cast<String>(),
          });
          expect(cands.every((e) => e.uid != myUid), isTrue);
        }
      });
    }

    test('§3 the read cap: never more than 44 reads, and a lower cap stops '
        'early', () async {
      var reads = 0;
      final all = await searchPools<_E>(
        order: [...poolSearchOrder(3, Random(1)), '99_0', '99_1'],
        read: (_) async {
          reads++;
          return const [];
        },
        myUid: 'me',
      );
      expect(all.reads, 44);
      expect(reads, 44);
      final capped = await searchPools<_E>(
        order: poolSearchOrder(3, Random(1)),
        read: (_) async => const [],
        myUid: 'me',
        maxReads: 5,
      );
      expect(capped.reads, 5);
      expect(capped.found, isFalse);
    });

    test(
      '§3 the time limit: an expired search stops before the next round',
      () async {
        var reads = 0;
        final r = await searchPools<_E>(
          order: poolSearchOrder(3, Random(1)),
          read: (_) async {
            reads++;
            return const [];
          },
          myUid: 'me',
          expired: () => reads >= 7,
        );
        // PRD-2.3 §25.2 checked between rounds of 4: 8 reads were issued.
        expect(r.timedOut, isTrue);
        expect(r.found, isFalse);
        expect(r.reads, 8);
      },
    );

    test('§3 a failing read ends the search with its error', () async {
      expect(
        searchPools<_E>(
          order: poolSearchOrder(3, Random(1)),
          read: (_) async => throw TimeoutException('slow'),
          myUid: 'me',
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
