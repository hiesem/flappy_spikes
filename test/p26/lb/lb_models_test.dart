import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/leaderboard/lb_config.dart';
import 'package:flappy_spikes/leaderboard/lb_models.dart';
import 'package:flappy_spikes/leaderboard/lb_service.dart';
import 'package:flappy_spikes/services/versus_service.dart';

// JSON output of functions/test/board.test.ts's O62 fixture:
// todayBoard(group({memberUids:['a'], members:{a:member(123,45,T0+1000)}}),
//            'a', T0+2000, {gid:'g'}). T0 = Date.UTC(2026,9,20).
const _todayJson = '''
{"tab":"today","rows":[{"rid":"fbe8f416f8b84b31","rank":1,
"name":"SwiftKiwi482","look":{"bird":"classic","gear":"none","hat":"none",
"hoop":"pink","trail":"flame"},"points":123,"lastAt":1792454401000,"playingNow":true}],
"me":{"rid":"fbe8f416f8b84b31","rank":1,"name":"SwiftKiwi482",
"look":{"bird":"classic","gear":"none","hat":"none","hoop":"pink","trail":"flame"},
"points":123,"lastAt":1792454401000,"playingNow":true},
"group":{"bracket":3,"start":{"_seconds":1792454400,"_nanoseconds":0},
"end":{"_seconds":1792540800,"_nanoseconds":0}},"gifts":[]}
''';
Map<String, Object?> _today() => jsonDecode(_todayJson) as Map<String, Object?>;
Map<String, Object?> _getBoard() => {
  'today': _today(),
  'best': {
    'tab': 'best',
    'rows': [],
    'me': null,
    'floor': null,
    'group': null,
    'gifts': [],
  },
  'bestAllTime': null,
};

class _StartupVersus extends NoopVersusService {
  final startup = Completer<void>();
  int starts = 0;
  bool _ready = false;
  @override
  bool get ready => _ready;
  @override
  Future<void> initialize() async {
    starts++;
    await startup.future;
    _ready = true;
  }
}

void main() {
  test('parses the functions O62 TODAY fixture with serialized timestamps', () {
    final result = LbGetBoardResult.fromJson(_getBoard());
    final today = result.today;
    expect(today.tab, LbBoardTab.today);
    expect(today.rows.single.rid, 'fbe8f416f8b84b31');
    expect(today.rows.single.rank, 1);
    expect(today.rows.single.name, 'SwiftKiwi482');
    expect(today.rows.single.look.bird, 'classic');
    expect(today.rows.single.look.hoop, 'pink');
    expect(today.rows.single.points, 123);
    expect(today.rows.single.best, isNull);
    expect(today.rows.single.lastAt, 1792454401000);
    expect(today.rows.single.playingNow, isTrue);
    expect(today.me!.rid, today.rows.single.rid);
    expect(today.group!.bracket, 3);
    expect(today.group!.start, DateTime.utc(2026, 10, 20));
    expect(today.group!.end, DateTime.utc(2026, 10, 21));
    expect(result.best.me, isNull);
    expect(result.bestAllTime, isNull);
  });

  test(
    'TODAY discards legacy best values for both list and pinned rows (O62)',
    () {
      final json = _today();
      ((json['rows'] as List).single as Map)['best'] = 45;
      (json['me'] as Map)['best'] = 45;
      final board = LbBoardPayload.fromJson(json);
      expect(board.rows.single.best, isNull);
      expect(board.me!.best, isNull);
    },
  );

  test(
    'BEST preserves rank 0, approximation, floor, card and private best',
    () {
      final json = _today();
      json['tab'] = 'best';
      json['group'] = null;
      json['approximate'] = true;
      json['floor'] = 100;
      (json['me'] as Map).addAll(<String, Object?>{
        'rank': 0,
        'best': 333,
        'card': 'gold|pink|star',
      });
      final board = LbBoardPayload.fromJson(json);
      expect(board.me!.rank, 0);
      expect(board.me!.best, 333);
      expect(board.me!.card, 'gold|pink|star');
      expect(board.approximate, isTrue);
      expect(board.floor, 100);
      expect(board.group, isNull);
    },
  );

  test('parses gift stubs and full submit response gifts', () {
    final result = LbSubmitRunResult.fromJson({
      'accepted': ['r1'],
      'dropped': [
        {'id': 'r0', 'reason': 'old'},
      ],
      'group': {'id': 'g', 'end': 1792540800000, 'bracket': 3},
      'rank': {'before': null, 'after': 1},
      'board': _today(),
      'gifts': [
        {
          'gid': 'g',
          'uid': 'a',
          'tier': 'gold',
          'boardRank': 1,
          'claimedAt': {'_seconds': 1792540800, '_nanoseconds': 123000000},
          'expireAt': {'_seconds': 1792540800, '_nanoseconds': 0},
          'rolled': {'kind': 'coins', 'coins': 150, 'seed': 'g:a'},
        },
      ],
    });
    expect(result.accepted, ['r1']);
    expect(result.dropped.single.id, 'r0');
    expect(result.dropped.single.reason, 'old');
    expect(result.group!.end, 1792540800000);
    expect(result.group!.id, 'g');
    expect(result.rank!.before, isNull);
    expect(result.rank!.after, 1);
    expect(result.board!.rows.single.points, 123);
    expect(result.gifts!.single.rolled!.coins, 150);
    expect(
      result.gifts!.single.claimedAt,
      DateTime.utc(2026, 10, 21, 0, 0, 0, 123),
    );
    final today = _today();
    today['gifts'] = [
      {'gid': 'g', 'tier': 'silver', 'boardRank': 2, 'claimedAt': null},
    ];
    final gift = LbBoardPayload.fromJson(today).gifts.single;
    expect(gift.tier, 'silver');
    expect(gift.boardRank, 2);
    expect(gift.claimedAt, isNull);
    expect(gift.rolled, isNull);
  });

  test('optional submit fields may be absent or explicitly null', () {
    for (final extra in <Map<String, Object?>>[
      {},
      {'group': null, 'rank': null, 'board': null, 'gifts': null},
    ]) {
      final result = LbSubmitRunResult.fromJson({
        'accepted': [],
        'dropped': [],
        ...extra,
      });
      expect(result.group, isNull);
      expect(result.rank, isNull);
      expect(result.board, isNull);
      expect(result.gifts, isNull);
    }
  });

  test('claim response follows functions claim fixture and decision 8.3-11', () {
    // board_store.test.ts: claims return {ok:true,id,tier,prize}; refused = {ok:false}.
    final result = LbClaimGiftResult.fromJson(
      jsonDecode('''
      {"ok":true,"id":"a_g","tier":"gold","prize":{"kind":"item","coins":150,
      "item":"bird:blue","rarity":"rare","seed":"a:g"}}
    ''')
          as Map<String, Object?>,
    );
    expect(result.ok, isTrue);
    expect(result.id, 'a_g');
    expect(result.tier, 'gold');
    expect(result.prize!.kind, 'item');
    expect(result.prize!.coins, 150);
    expect(result.prize!.item, 'bird:blue');
    expect(result.prize!.rarity, 'rare');
    expect(result.prize!.seed, 'a:g');
    final refused = LbClaimGiftResult.fromJson({'ok': false});
    expect(refused.ok, isFalse);
    expect(refused.prize, isNull);
    for (final kind in ['coins', 'feather', 'piece']) {
      final roll = LbGiftRoll.fromJson({'kind': kind, 'coins': 50});
      expect(roll.kind, kind);
      expect(roll.item, isNull);
      expect(roll.seed, isNull);
    }
  });

  test('claim owned request field is optional', () {
    expect(const LbClaimGiftRequest(id: 'g').toJson(), {'id': 'g'});
    expect(const LbClaimGiftRequest(id: 'g', owned: ['bird:blue']).toJson(), {
      'id': 'g',
      'owned': ['bird:blue'],
    });
  });

  test('timestamp parser handles public keys, milliseconds and null', () {
    expect(
      lbTimestamp({'seconds': 1, 'nanoseconds': 123456000}),
      DateTime.fromMicrosecondsSinceEpoch(1123456, isUtc: true),
    );
    expect(lbTimestamp(1000), DateTime.utc(1970, 1, 1, 0, 0, 1));
    expect(lbTimestamp(null), isNull);
  });

  test('Noop never invokes plugins or throws', () async {
    const service = NoopLeaderboardService();
    expect(await service.getBoard(), isNull);
    expect(await service.getBoard(tab: LbBoardTab.best), isNull);
    expect(await service.submitRun(const LbSubmitRunRequest(runs: [])), isNull);
    expect(await service.claimGift('g', owned: []), isNull);
  });

  test(
    'fake scripts all three callable payloads using production parsers',
    () async {
      final requests = <(String, Map<String, Object?>)>[];
      final service = FakeLeaderboardService(
        onCall: (name, request) async {
          requests.add((name, request));
          return switch (name) {
            'lbGetBoard' => _getBoard(),
            'lbSubmitRun' => {
              'accepted': ['r1'],
              'dropped': [],
            },
            'lbClaimGift' => {'ok': false},
            _ => throw StateError('unknown callable'),
          };
        },
      );
      expect(
        (await service.getBoard(
          tab: LbBoardTab.best,
        ))!.today.rows.single.points,
        123,
      );
      expect(
        (await service.submitRun(
          const LbSubmitRunRequest(
            runs: [
              LbSubmittedRun(
                id: 'r1',
                score: 1,
                hoops: 1,
                cs: 100,
                endTs: 1000,
                mode: 'free',
              ),
            ],
          ),
        ))!.accepted,
        ['r1'],
      );
      expect((await service.claimGift('g', owned: ['bird:blue']))!.ok, isFalse);
      expect(requests[0].$1, 'lbGetBoard');
      expect(requests[0].$2, {'tab': 'best'});
      expect(requests[1].$1, 'lbSubmitRun');
      expect(requests[1].$2, {
        'runs': [
          {
            'id': 'r1',
            'score': 1,
            'hoops': 1,
            'cs': 100,
            'endTs': 1000,
            'mode': 'free',
          },
        ],
      });
      expect(requests[2].$1, 'lbClaimGift');
      expect(requests[2].$2, {
        'id': 'g',
        'owned': ['bird:blue'],
      });
    },
  );

  test(
    'Firebase wrapper catches sync errors, async errors and malformed JSON for every method',
    () async {
      for (final script in <LbCallable>[
        (_, _) => throw StateError('sync plugin error'),
        (_, _) async => throw StateError('offline'),
        (_, _) async => <String, Object?>{'invalid': true},
        (_, _) async => null,
      ]) {
        final service = FakeLeaderboardService(onCall: script);
        expect(await service.getBoard(), isNull);
        expect(
          await service.submitRun(const LbSubmitRunRequest(runs: [])),
          isNull,
        );
        expect(await service.claimGift('g'), isNull);
      }
    },
  );

  test('failed versus startup does not invoke a callable', () async {
    var invoked = false;
    final service = FakeLeaderboardService(
      versus: NoopVersusService(),
      onCall: (_, _) async {
        invoked = true;
        return _getBoard();
      },
    );
    expect(await service.getBoard(), isNull);
    expect(invoked, isFalse);
  });

  testWidgets('all calls time out at six seconds with a fake clock', (
    tester,
  ) async {
    final service = FakeLeaderboardService(
      onCall: (_, _) => Completer<Object?>().future,
    );
    final results = <Object?>[];
    service.getBoard().then(results.add);
    service.submitRun(const LbSubmitRunRequest(runs: [])).then(results.add);
    service.claimGift('g').then(results.add);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5999));
    expect(results, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(results, [null, null, null]);
  });

  testWidgets('six-second budget includes waiting for shared versus startup', (
    tester,
  ) async {
    final versus = _StartupVersus();
    var invoked = false;
    var complete = false;
    LbGetBoardResult? board;
    final service = FakeLeaderboardService(
      versus: versus,
      onCall: (_, _) async {
        invoked = true;
        return _getBoard();
      },
    );
    service.getBoard().then((result) {
      board = result;
      complete = true;
    });
    await tester.pump();
    expect(versus.starts, 1);
    await tester.pump(const Duration(seconds: 6));
    expect(complete, isTrue);
    expect(board, isNull);
    versus.startup.complete();
    await tester.pump();
    expect(invoked, isFalse);
  });

  testWidgets(
    'a timed-out in-flight callable retains the lane; expired queued calls never run late',
    (tester) async {
      final lane = LbCallSerializer();
      final pending = Completer<Object?>();
      final invoked = <String>[];
      final service = FakeLeaderboardService(
        calls: lane,
        onCall: (name, _) {
          invoked.add(name);
          return pending.future;
        },
      );
      service.getBoard();
      await tester.pump();
      service.claimGift('g');
      await tester.pump(const Duration(seconds: 6));
      expect(invoked, ['lbGetBoard']);
      var authFinished = false;
      lane.run(() async {
        authFinished = true;
      });
      await tester.pump();
      expect(authFinished, isFalse);
      pending.complete(_getBoard());
      await tester.pump();
      expect(authFinished, isTrue);
      expect(invoked, ['lbGetBoard']);
    },
  );

  test(
    'leaderboard waits for versus auth lane, then retries after failure',
    () async {
      final lane = LbCallSerializer();
      final auth = Completer<void>();
      final events = <String>[];
      final authRun = lane.run(() async {
        events.add('auth');
        await auth.future;
      });
      var fail = true;
      final service = FakeLeaderboardService(
        calls: lane,
        onCall: (_, _) async {
          events.add('board');
          if (fail) throw StateError('offline');
          return _getBoard();
        },
      );
      final board = service.getBoard();
      await Future<void>.delayed(Duration.zero);
      expect(events, ['auth']);
      auth.complete();
      await authRun;
      expect(await board, isNull);
      fail = false;
      expect(await service.getBoard(), isNotNull);
      expect(events, ['auth', 'board', 'board']);
    },
  );

  test(
    'serializer supports nested guest cleanup without deadlocking',
    () async {
      final lane = LbCallSerializer();
      final events = <String>[];
      await lane.run(() async {
        events.add('link');
        await lane.run(() async {
          events.add('cleanup');
        });
        events.add('switch');
      });
      expect(events, ['link', 'cleanup', 'switch']);
    },
  );

  test('leaderboard config reads the existing baked tuning', () {
    expect(LbConfig.functionsRegion, 'europe-west1');
    expect(LbConfig.queueCap, 30);
    expect(LbConfig.batchSize, 10);
    expect(LbConfig.resultsMinGames, 3);
    expect(LbConfig.resultsWait, const Duration(seconds: 4));
  });
}
