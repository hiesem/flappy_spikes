import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flappy_spikes/versus/matcher.dart';
import 'package:flappy_spikes/versus/nickname.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fixture pool entry as a [Matchable].
class _E implements Matchable {
  _E(Map<String, Object?> m)
    : uid = m['uid']! as String,
      runId = m['runId']! as String,
      score = (m['score']! as num).toInt(),
      level = (m['level']! as num).toInt();
  @override
  final String uid;
  @override
  final String runId;
  @override
  final int score;
  @override
  final int level;
}

/// WP-5b PRD-2 §3.13 matching (shared fixture with `functions/src/
/// matching.ts`) and the generated nicknames.
void main() {
  group('§3.13 matching — test/fixtures/versus_matching.json', () {
    final fixture =
        jsonDecode(File('test/fixtures/versus_matching.json').readAsStringSync())
            as Map<String, Object?>;
    final cases = (fixture['cases']! as List).cast<Map<String, Object?>>();

    test('§3.13 the fixture has every rule case', () {
      expect(cases.length, greaterThanOrEqualTo(10));
    });

    for (final c in cases) {
      test('§3.13 ${c['name']}', () {
        final me = c['me']! as Map<String, Object?>;
        final pool = [
          for (final e in (c['pool']! as List).cast<Map<String, Object?>>())
            _E(e),
        ];
        final seen = {...(c['seen']! as List).cast<String>()};
        final expectMap = c['expect']! as Map<String, Object?>;
        final (tier, candidates) = matchCandidates(
          pool,
          myLevel: (me['level']! as num).toInt(),
          myBest: (me['best']! as num).toInt(),
          myUid: me['uid']! as String,
          seen: seen,
        );
        expect(tier.name, expectMap['tier']);
        expect(
          candidates.map((e) => e.runId).toSet(),
          {...(expectMap['runIds']! as List).cast<String>()},
        );
        // The random pick is always one of the candidates (or solo).
        for (var s = 0; s < 20; s++) {
          final pick = pickOpponent(
            pool,
            myLevel: (me['level']! as num).toInt(),
            myBest: (me['best']! as num).toInt(),
            myUid: me['uid']! as String,
            seen: seen,
            r: Random(s),
          );
          if (tier == MatchTier.solo) {
            expect(pick, isNull);
          } else {
            expect(candidates, contains(pick));
          }
        }
      });
    }

    // PRD-2.2 §3: the 2.1 read plan became a search order
    // (test/p22/s3_matcher_search_test.dart).
    test('§3.13 pool ids are level_shard', () {
      expect(poolId(3, 2), '3_2');
    });
  });

  group('§3.13 nicknames', () {
    test('§3.13 the word lists: 20 adjectives, 20 bird words (PRD)', () {
      expect(kNicknameAdjectives, hasLength(20));
      expect(kNicknameBirds, hasLength(20));
      expect(kNicknameAdjectives.first, 'Swift');
      expect(kNicknameAdjectives.last, 'Rapid');
      expect(kNicknameBirds.last, 'Flappy');
    });

    test('§3.13 Adjective + Bird + 3 digits (000–999), words ≤ 14 chars; '
        'longer pairs re-roll', () {
      final r = Random(42);
      final seen = <String>{};
      for (var i = 0; i < 2000; i++) {
        final n = generateNickname(r);
        expect(isGeneratedNickname(n), isTrue, reason: n);
        expect(n.length, lessThanOrEqualTo(14 + 3));
        expect(RegExp(r'\d{3}$').hasMatch(n), isTrue);
        seen.add(n.substring(0, n.length - 3));
      }
      for (final w in seen) {
        expect(w.length, lessThanOrEqualTo(14));
      }
      // With today's lists no pair is over 14 (the re-roll guards future
      // words).
      final tooLong = [
        for (final a in kNicknameAdjectives)
          for (final b in kNicknameBirds)
            if (a.length + b.length > 14) '$a$b',
      ];
      expect(tooLong, isEmpty, reason: 'longest pair is 7 + 6 = 13');
      expect(isGeneratedNickname('SwiftKiwi482'), isTrue);
      expect(isGeneratedNickname('SwiftKiwi48'), isFalse);
      expect(isGeneratedNickname('Nobody123'), isFalse);
    });

    test('§3.13 the same seed gives the same nickname (created once per '
        'install, stored in versusNickname)', () {
      expect(generateNickname(Random(7)), generateNickname(Random(7)));
    });
  });
}
