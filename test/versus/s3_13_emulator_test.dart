
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flappy_spikes/levels/levels.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/matcher.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP-5b opt-in live check (ARCH §7.2): the Dart client's data contract
/// against the **Firebase Emulator Suite** (auth + firestore + functions)
/// on the `demo-flappy-spikes` project — the real `firestore.rules` and
/// `onPlayerRunWrite`. Nothing touches `flappy-spikes-a2b55`.
///
/// The FlutterFire plugins need a device, so this drives the emulators over
/// their REST APIs with exactly the documents the client builds
/// ([RunEntry], [nextPlayerDoc], `updatedAt` = request time, `expireAt` =
/// now + 60 d), then reads the pool back and matches / replays it with the
/// Dart matcher and timeline. Run it with
/// `tool/versus_emulator_test.sh` (sets `FS_EMULATOR_TESTS=1` inside
/// `firebase emulators:exec`); without the variable it is skipped.
const String project = 'demo-flappy-spikes';
final bool enabled = Platform.environment['FS_EMULATOR_TESTS'] == '1';

final String fsHost =
    Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '127.0.0.1:8080';
final String authHost =
    Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'] ?? '127.0.0.1:9099';
const String functionsHost = '127.0.0.1:5001';

String get docs =>
    'http://$fsHost/v1/projects/$project/databases/(default)/documents';

Future<(int, Object?)> http(
  String method,
  String url, {
  Object? body,
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse(url));
    req.headers.contentType = ContentType.json;
    headers.forEach(req.headers.set);
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
  } finally {
    client.close();
  }
}

/// An unsigned JWT (the emulators accept them).
String fakeJwt(Map<String, Object?> payload) {
  String b(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b({'alg': 'none', 'typ': 'JWT'})}.${b(payload)}.';
}

/// A Firestore REST timestamp kept verbatim (so stored runs round-trip
/// exactly — the rules compare `recent[i] in old`).
class RestTs {
  const RestTs(this.raw);
  final String raw;
  DateTime get date => DateTime.parse(raw);
}

Map<String, Object?> toValue(Object? v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': '$v'};
  if (v is double) return {'doubleValue': v};
  if (v is String) return {'stringValue': v};
  if (v is RestTs) return {'timestampValue': v.raw};
  if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
  if (v is List) {
    return {
      'arrayValue': {'values': [for (final e in v) toValue(e)]},
    };
  }
  if (v is Map) {
    return {
      'mapValue': {
        'fields': {for (final e in v.entries) '${e.key}': toValue(e.value)},
      },
    };
  }
  throw ArgumentError('unsupported $v');
}

Object? fromValue(Map<String, Object?> v) {
  if (v.containsKey('nullValue')) return null;
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('integerValue')) return int.parse('${v['integerValue']}');
  if (v.containsKey('doubleValue')) return (v['doubleValue']! as num).toDouble();
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('timestampValue')) return RestTs('${v['timestampValue']}');
  if (v.containsKey('arrayValue')) {
    final a = (v['arrayValue']! as Map)['values'] as List? ?? const [];
    return [for (final e in a) fromValue((e as Map).cast())];
  }
  if (v.containsKey('mapValue')) {
    final f = (v['mapValue']! as Map)['fields'] as Map? ?? const {};
    return {for (final e in f.entries) e.key: fromValue((e.value as Map).cast())};
  }
  throw ArgumentError('unsupported $v');
}

/// Plain values for [RunEntry.fromMap] (timestamps → DateTime).
Object? plain(Object? v) => switch (v) {
  RestTs t => t.date,
  Map m => {for (final e in m.entries) e.key: plain(e.value)},
  List l => [for (final e in l) plain(e)],
  _ => v,
};

Future<(String uid, String token)> signUp() async {
  final (code, body) = await http(
    'POST',
    'http://$authHost/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake',
    body: {'returnSecureToken': true},
  );
  expect(code, 200, reason: '$body');
  final m = body! as Map;
  return (m['localId'] as String, m['idToken'] as String);
}

Future<Map<String, Object?>?> getDoc(String path, String token) async {
  final (code, body) = await http(
    'GET',
    '$docs/$path',
    headers: {'Authorization': 'Bearer $token'},
  );
  // 404: no doc yet; 403: not mine (the rules refuse the read too).
  if (code == 404 || code == 403) return null;
  expect(code, 200, reason: '$body');
  final fields = (body! as Map)['fields'] as Map? ?? const {};
  return {
    for (final e in fields.entries)
      e.key as String: fromValue((e.value as Map).cast()),
  };
}

/// The client's write: the next player doc for one new run, with
/// `updatedAt` = request time and `expireAt` = now + 60 d.
Future<int> writeRun(
  String uid,
  String token,
  RunEntry entry, {
  required bool newBest,
}) async {
  final old = await getDoc('players/$uid', token);
  final doc = nextPlayerDoc(
    old: old,
    run: entry.toMap(ts: RestTs(entry.ts.toUtc().toIso8601String())),
    newBest: newBest,
    name: entry.name,
    avatar: '',
    platform: 'android',
    look: entry.look,
    uploadsDay: '2026-10-08',
    uploadsCount: newBest ? 0 : 1,
  );
  doc['expireAt'] = DateTime.now().toUtc().add(VersusConfig.expireAfter);
  final name = 'projects/$project/databases/(default)/documents/players/$uid';
  final (code, body) = await http(
    'POST',
    'http://$fsHost/v1/projects/$project/databases/(default)/documents:commit',
    headers: {'Authorization': 'Bearer $token'},
    body: {
      'writes': [
        {
          'update': {
            'name': name,
            'fields': {for (final e in doc.entries) e.key: toValue(e.value)},
          },
          'updateTransforms': [
            {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
          ],
        },
      ],
    },
  );
  if (code != 200) {
    // ignore: avoid_print
    print('write refused: $code $body');
  }
  return code;
}

/// A real-shaped run of [score] points 1.2 s apart (a +5 gift at the end
/// when [gift]).
RunEntry clientRun(int score, int bestBefore, {bool gift = false, String? id}) {
  final t = RunTimeline();
  final plain = gift ? score - 4 : score;
  for (var i = 1; i <= plain; i++) {
    t.addPoint(i * 1.2);
  }
  if (gift) {
    for (var i = 0; i < 4; i++) {
      t.addPoint(plain * 1.2, flag: PointFlags.gift);
    }
  }
  t.end(plain * 1.2 + .8);
  final s = RunSummary(
    score: score,
    hoopsPassed: score,
    coins: 0,
    bestBefore: bestBefore,
    bestAfter: max(score, bestBefore),
    runSeconds: plain * 1.2 + .8,
    cause: MistakeCause.missedHoop,
    hoopIndex: score,
    timeline: t,
  );
  return RunEntry.fromSummary(
    s,
    runId: id ?? 'r${DateTime.now().microsecondsSinceEpoch}',
    name: 'SwiftKiwi482',
    look: const Look(bird: 'sky'),
    ts: DateTime.now().toUtc(),
  );
}

Future<List<PoolEntry>> poolOf(int level, String token) async {
  final out = <PoolEntry>[];
  for (var shard = 0; shard < VersusConfig.shards; shard++) {
    final d = await getDoc('pools/${poolId(level, shard)}', token);
    final entries = d?['entries'];
    if (entries is! List) continue;
    for (final e in entries) {
      final p = PoolEntry.fromMap((plain(e)! as Map).cast());
      if (p != null) out.add(p);
    }
  }
  return out;
}

Future<PoolEntry?> waitForEntry(int level, String uid, String runId, String token) async {
  for (var i = 0; i < 60; i++) {
    final pool = await poolOf(level, token);
    for (final e in pool) {
      if (e.uid == uid && e.runId == runId) return e;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return null;
}

void main() {
  test(
    '§3.13 emulator: a client-built best run passes the rules, the function '
    'pools it (cheat filter: count == score with a +5 gift), another player '
    'matches it and replays its timeline',
    () async {
      final (uid, token) = await signUp();
      final run = clientRun(64, 40, gift: true);
      expect(await writeRun(uid, token, run, newBest: true), 200);
      final level = levelFor(64);
      final pooled = await waitForEntry(level, uid, run.runId, token);
      expect(pooled, isNotNull, reason: 'onPlayerRunWrite accepted the run');
      expect(pooled!.level, level);
      expect(pooled.run.name, 'SwiftKiwi482');
      expect(pooled.run.look.bird, 'sky');

      // A second player at that level with a higher best gets it.
      final (other, otherToken) = await signUp();
      final pool = await poolOf(level, otherToken);
      final pick = pickOpponent(
        pool.map(PoolCandidate.new),
        myLevel: level,
        myBest: 99,
        myUid: other,
        r: Random(1),
      );
      expect(pick, isNotNull);
      final opp = pool
          .firstWhere((e) => e.runId == run.runId)
          .toOpponent();
      expect(opp.scoreAt(1.2 * 10 + .01), 10);
      expect(opp.scoreAt(60 * 1.2 + .01), 64, reason: 'the +5 lands at once');
      expect(opp.outAt(60 * 1.2 + 1), isTrue);
    },
    skip: enabled ? false : 'opt-in: FS_EMULATOR_TESTS=1 (tool/versus_emulator_test.sh)',
  );

  test(
    '§3.13 emulator: one new run per write — a second (non-best) run is '
    'recent[0] with the first shifted down; best never decreases; another '
    "player cannot write my doc; deleteMyData needs App Check",
    () async {
      final (uid, token) = await signUp();
      final first = clientRun(30, 0, id: 'a1-$uid');
      expect(await writeRun(uid, token, first, newBest: true), 200);
      final second = clientRun(12, 30, id: 'a2-$uid');
      expect(await writeRun(uid, token, second, newBest: false), 200);
      final doc = await getDoc('players/$uid', token);
      final recent = (doc!['recent']! as List).cast<Map>();
      expect(recent.map((r) => r['runId']), ['a2-$uid', 'a1-$uid']);
      expect((doc['bestRun']! as Map)['runId'], 'a1-$uid');
      expect(doc['best'], 30);

      // Someone else's token is refused by the rules.
      final (_, intruder) = await signUp();
      expect(
        await writeRun(uid, intruder, clientRun(5, 0), newBest: false),
        isNot(200),
      );

      // The callable is App Check enforced (the client's release build
      // sends a Play Integrity token).
      final (code, _) = await http(
        'POST',
        'http://$functionsHost/$project/${VersusConfig.functionsRegion}/'
        '${VersusConfig.deleteFunction}',
        headers: {'Authorization': 'Bearer $token'},
        body: {'data': {}},
      );
      expect(code, 401);
      final appCheck = fakeJwt({
        'sub': '1:512525012529:android:8bb85c213b543c6487cf10',
        'aud': ['projects/$project'],
      });
      final (ok, body) = await http(
        'POST',
        'http://$functionsHost/$project/${VersusConfig.functionsRegion}/'
        '${VersusConfig.deleteFunction}',
        headers: {
          'Authorization': 'Bearer $token',
          'X-Firebase-AppCheck': appCheck,
        },
        body: {'data': {}},
      );
      expect(ok, 200, reason: '$body');
      expect(((body! as Map)['result'] as Map)['ok'], isTrue);
    },
    skip: enabled ? false : 'opt-in: FS_EMULATOR_TESTS=1 (tool/versus_emulator_test.sh)',
  );
}
