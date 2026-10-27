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

/// WP-5b PRD-2 §3.13 matching (shared fixture with `functions/src/
/// matching.ts`) and the generated nicknames.
void main() {
  group('§3.13 matching — test/fixtures/versus_matching.json', () {
    final fixture =
        jsonDecode(
              File('test/fixtures/versus_matching.json').readAsStringSync(),
            )
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
        // PRD-2.3 §25.2 the ordered met list (oldest first).
        final seen = (c['seen']! as List).cast<String>();
        final myPg = (me['pg'] as String?) ?? '';
        final expectMap = c['expect']! as Map<String, Object?>;
        final (tier, candidates) = matchCandidates(
          pool,
          myBracket: (me['bracket']! as num).toInt(),
          myBest: (me['best']! as num).toInt(),
          myUid: me['uid']! as String,
          met: seen,
          myPg: myPg,
        );
        expect(tier.name, expectMap['tier']);
        expect(candidates.map((e) => e.runId).toSet(), {
          ...(expectMap['runIds']! as List).cast<String>(),
        });
        // The random pick is always one of the candidates (or solo).
        for (var s = 0; s < 20; s++) {
          final pick = pickOpponent(
            pool,
            myBracket: (me['bracket']! as num).toInt(),
            myBest: (me['best']! as num).toInt(),
            myUid: me['uid']! as String,
            met: seen,
            myPg: myPg,
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
    test('§3.13 pool ids are bracket_shard', () {
      expect(poolId(3, 2), '3_2');
    });
  });

  group('§3.13 nicknames', () {
    test('§3.13 the word lists: 40 adjectives, 40 bird words, the old 20 '
        'first in their old positions (nickname_words.md)', () {
      expect(kNicknameAdjectives, hasLength(40));
      expect(kNicknameBirds, hasLength(40));
      expect(kNicknameAdjectives.toSet(), hasLength(40), reason: 'no dupes');
      expect(kNicknameBirds.toSet(), hasLength(40), reason: 'no dupes');
      expect(kNicknameAdjectives.first, 'Swift');
      expect(kNicknameAdjectives[19], 'Rapid');
      expect(kNicknameAdjectives[20], 'Turbo');
      expect(kNicknameAdjectives.last, 'Zappy');
      expect(kNicknameBirds[19], 'Flappy');
      expect(kNicknameBirds[20], 'Duck');
      expect(kNicknameBirds.last, 'Pelican');
    });

    test('§3.13 both word orders are generated (about 50/50) and accepted; '
        'old names still match', () {
      final r = Random(3);
      var adjFirst = 0, birdFirst = 0;
      for (var i = 0; i < 2000; i++) {
        final n = generateNickname(r);
        expect(isGeneratedNickname(n), isTrue, reason: n);
        final m = RegExp(r'^([A-Z][a-z]+)([A-Z][a-z]+)\d{3}$').firstMatch(n)!;
        // 'Swift' is in both lists: SwiftSwift counts as adjective first.
        if (kNicknameAdjectives.contains(m[1]) &&
            kNicknameBirds.contains(m[2])) {
          adjFirst++;
        } else {
          expect(kNicknameBirds, contains(m[1]));
          expect(kNicknameAdjectives, contains(m[2]));
          birdFirst++;
        }
      }
      expect(adjFirst, inInclusiveRange(850, 1150));
      expect(birdFirst, inInclusiveRange(850, 1150));
      expect(isGeneratedNickname('TurboDuck111'), isTrue);
      expect(isGeneratedNickname('DuckTurbo111'), isTrue);
      expect(isGeneratedNickname('BraveParrot907'), isTrue, reason: 'old');
      expect(isGeneratedNickname('ParrotBrave907'), isTrue);
      expect(isGeneratedNickname('DuckGoose111'), isFalse, reason: '2 birds');
      expect(isGeneratedNickname('TurboMega111'), isFalse, reason: '2 adj');
      expect(isGeneratedNickname('DuckTurbo11'), isFalse);
    });

    test('§3.13 every pair (either order) is at most 14 letters', () {
      for (final a in kNicknameAdjectives) {
        for (final b in kNicknameBirds) {
          expect(a.length + b.length, lessThanOrEqualTo(kNicknameWordsMax));
          expect(isGeneratedNickname('$a${b}007'), isTrue);
          expect(isGeneratedNickname('$b${a}007'), isTrue);
        }
      }
    });

    test('§3.13 the server port functions/src/nickname.ts has the same lists '
        '(mirror, like brackets.test.ts)', () {
      final ts = File('functions/src/nickname.ts').readAsStringSync();
      List<String> tsList(String name) {
        final start = ts.indexOf('export const $name');
        expect(start, greaterThanOrEqualTo(0), reason: name);
        final body = ts.substring(
          ts.indexOf('[', start),
          ts.indexOf('];', start),
        );
        return [for (final m in RegExp(r"'([^']+)'").allMatches(body)) m[1]!];
      }

      expect(tsList('NICKNAME_ADJECTIVES'), kNicknameAdjectives);
      expect(tsList('NICKNAME_BIRDS'), kNicknameBirds);
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
      expect(tooLong, isEmpty, reason: 'longest pair is 7 + 7 = 14');
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
