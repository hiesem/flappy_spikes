// PRD-2.3.1 §19.2 "earned for good" under app kills (QA P19-01..05,
// from Sol's probes): every achievement transition is ONE write of the
// whole state (`achState`), so a kill at any write boundary leaves the
// state before or after it. A write recorder snapshots the durable
// preferences after each individual write; each snapshot is relaunched
// (fresh storage + tracker + journal recovery, recovered twice) and must
// neither lose nor duplicate anything. Plus the FIFO / tie order (P19-04,
// P19-05), side effects only after the write, and the 2.3.1 (20)
// migration.
import 'dart:convert';

import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/achievements/achievements.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// The durable state after EACH individual preferences write.
class WriteTrace extends InMemorySharedPreferencesStore {
  WriteTrace(Map<String, Object> initial)
    : disk = copy(initial),
      super.withData({
        for (final e in initial.entries) 'flutter.${e.key}': e.value,
      });

  final Map<String, Object> disk;
  final List<(String, Map<String, Object>)> snapshots = [];

  static Map<String, Object> copy(Map<String, Object> src) => {
    for (final e in src.entries)
      e.key: e.value is List ? List<String>.from(e.value as List) : e.value,
  };

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final result = await super.setValue(type, key, value);
    final bare = key.substring('flutter.'.length);
    disk[bare] = value is List ? List<String>.from(value) : value;
    snapshots.add((bare, copy(disk)));
    return result;
  }

  @override
  Future<bool> remove(String key) async {
    final result = await super.remove(key);
    final bare = key.substring('flutter.'.length);
    disk.remove(bare);
    snapshots.add(('-$bare', copy(disk)));
    return result;
  }
}

Future<void> settle() async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.value();
  }
}

Future<(GameStorage, AchievementTracker)> boot(
  Map<String, Object> initial, {
  GameServices? services,
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final s = GameStorage();
  await s.load();
  return (
    s,
    AchievementTracker(storage: s, services: services ?? GameServices()),
  );
}

/// A launch from [initial] whose every write is recorded.
Future<(GameStorage, AchievementTracker, WriteTrace)> traced(
  Map<String, Object> initial, {
  GameServices? services,
}) async {
  final trace = WriteTrace(initial);
  SharedPreferencesStorePlatform.instance = trace;
  SharedPreferences.resetStatic();
  final s = GameStorage();
  await s.load();
  return (
    s,
    AchievementTracker(storage: s, services: services ?? GameServices()),
    trace,
  );
}

/// The durable prefs right now (for a trace's start).
Future<Map<String, Object>> disk() async {
  final prefs = await SharedPreferences.getInstance();
  return {for (final k in prefs.getKeys()) k: prefs.get(k)!};
}

/// Runs [action] from [initial] under a write recorder, then relaunches
/// from the start and from every write boundary: [check] sees the
/// recovered storage (after two launches' recoveries) and the boundary.
Future<int> killEverywhere(
  Map<String, Object> initial,
  void Function(AchievementTracker a) action,
  void Function(GameStorage s, String boundary) check,
) async {
  final (_, a, trace) = await traced(initial);
  action(a);
  await a.flush();
  await settle();
  final points = [('start', WriteTrace.copy(initial)), ...trace.snapshots];
  for (final (i, (key, state)) in points.indexed) {
    final (s, t) = await boot(state);
    await t.recoverJournal();
    await settle();
    // A second launch (a kill during the first recovery is either before
    // or after its one write): recovery is idempotent.
    final (s2, t2) = await boot(await disk());
    await t2.recoverJournal();
    await settle();
    expect(s2.achPending, s.achPending, reason: 'boundary $i ($key)');
    expect(s2.achItemCounts, s.achItemCounts, reason: 'boundary $i ($key)');
    check(s2, 'boundary $i after $key');
  }
  return trace.snapshots.where((w) => w.$1 == 'achState').length;
}

Map<String, Object?> stateOf(Map<String, Object> prefs) =>
    jsonDecode(prefs['achState']! as String) as Map<String, Object?>;

class _OrderSpy extends GameServices {
  _OrderSpy(this.trace);
  final WriteTrace trace;
  final List<String> seen = [];

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    if (name != 'achievement_unlocked') return;
    final key = parameters!['id']! as String;
    final unlocked = (stateOf(trace.disk)['unlocked']! as List).cast<String>();
    seen.add('$key durable=${unlocked.contains(key)}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // --- P19-01 recovery ---------------------------------------------------------

  test('P19-01 a kill at any write of the journal recovery keeps its '
      'earnings exactly once', () async {
    final writes = await killEverywhere(
      {
        'achJournal': ['u:first_revive', 'item:item_heart'],
        'achItemCounts': ['item_heart=9'],
      },
      (a) => a.recoverJournal(),
      (s, at) {
        expect(s.achPending, ['first_revive', 'item_heart'], reason: at);
        expect(s.achItemCounts['item_heart'], 10, reason: at);
        expect(s.achJournal, isEmpty, reason: at);
        expect(s.achUnlocked, isEmpty, reason: at);
      },
    );
    expect(writes, 1, reason: 'recovery is one write');
  });

  // --- P19-02 release ------------------------------------------------------------

  test('P19-02 a kill at any write of a run end never loses the released '
      'pending achievement', () async {
    final writes = await killEverywhere(
      {
        'achPending': ['master_hatch', 'master_jar'],
      },
      (a) {
        a.beginRun(counts: true);
        a.finishRun(counts: true);
      },
      (s, at) {
        final hatch =
            s.achUnlocked.contains('master_hatch') ^
            s.achPending.contains('master_hatch');
        expect(hatch, isTrue, reason: '$at: MOTHER HEN exactly once');
        expect(s.achPending.last, 'master_jar', reason: at);
      },
    );
    expect(writes, 2, reason: 'begin + finish, one write each');
  });

  // --- P19-03 run end + recovery -------------------------------------------------

  test('P19-03 a kill at any write of a run with a catch counts it at most '
      'once (8 + 1 = 9, no early TWEETHEART)', () async {
    await killEverywhere(
      {
        'achItemCounts': ['item_heart=8'],
      },
      (a) {
        a.beginRun(counts: true);
        a.runOp(AchOp.item(AchievementId.itemHeart));
        a.finishRun(counts: true);
      },
      (s, at) {
        final n = s.achItemCounts['item_heart'] ?? 0;
        expect(n, inInclusiveRange(8, 9), reason: at);
        expect(s.achJournal, isEmpty, reason: at);
        expect(s.achPending, isEmpty, reason: at);
        expect(s.achUnlocked, isEmpty, reason: at);
      },
    );
  });

  test('P19-03 the catch that reaches the goal survives every boundary: '
      'TWEETHEART is earned exactly once', () async {
    await killEverywhere(
      {
        'achItemCounts': ['item_heart=9'],
      },
      (a) {
        a.beginRun(counts: true);
        a.runOp(AchOp.item(AchievementId.itemHeart));
        a.runOp(AchOp.unlock(AchievementId.firstRevive));
        a.finishRun(counts: true);
      },
      (s, at) {
        final n = s.achItemCounts['item_heart'] ?? 0;
        expect(n, inInclusiveRange(9, 10), reason: at);
        final earned = {...s.achUnlocked, ...s.achPending};
        expect(earned.contains('item_heart'), n == 10, reason: at);
        expect(
          s.achPending.where((k) => k == 'item_heart'),
          hasLength(lessThanOrEqualTo(1)),
          reason: at,
        );
      },
    );
  });

  test('P19 a shop unlock is durable before its analytics / toast', () async {
    final (_, a, trace) = await traced({
      'achPending': ['master_hatch'],
    });
    final spy = _OrderSpy(trace);
    final b = AchievementTracker(storage: a.storage, services: spy);
    b.onShopPurchase(owned: 1, total: 148);
    expect(b.toastQueue, isEmpty, reason: 'queued only once durable');
    await b.flush();
    expect(spy.seen, ['skin_first durable=true']);
    expect(b.toastQueue, [AchievementId.skinFirst]);
    expect(trace.snapshots.where((w) => w.$1 == 'achState'), hasLength(1));
    expect(stateOf(trace.disk)['pending'], ['master_hatch']);
  });

  // --- P19-04 / P19-05 order ------------------------------------------------------

  test('P19-04 later hoop passes keep the first hoop goal ahead of revive '
      '(strict staging)', () async {
    final (s, a) = await boot({});
    a.beginRun(counts: true);
    a.runOp(AchOp.hoops(10));
    a.runOp(AchOp.unlock(AchievementId.firstRevive));
    a.runOp(AchOp.hoops(11));
    a.finishRun(counts: true);
    await a.flush();
    expect(s.achUnlocked, {'hoops_10'});
    expect(s.achPending, ['first_revive']);
  });

  test('P19-05 run-end ties (rank, versus, daily) go in catalog order '
      'behind the older pending', () async {
    final (s, a) = await boot({
      'achPending': ['master_hatch'],
      'achDayStreak': 6,
      'achLastPlayDay': 99,
    });
    a.beginRun(counts: true);
    a.runOp(AchOp.versusWin);
    a.finishRun(counts: true, score: 25, day: 100);
    await a.flush();
    expect(s.achUnlocked, {'master_hatch'});
    expect(s.achPending, ['rank_egg', 'vs_1', 'daily_7']);
  });

  test('P19-05 Sol: a first win and a run at EGG unlock EGG first', () async {
    final (s, a) = await boot({});
    a.beginRun(counts: true);
    a.runOp(AchOp.versusWin);
    a.finishRun(counts: true, score: 25, day: 100);
    await a.flush();
    expect(s.achUnlocked, {'rank_egg'});
    expect(s.achPending, ['vs_1']);
  });

  // --- migration ------------------------------------------------------------------

  test('P19 a 2.3.1 (20) install migrates once; the old keys are never '
      'written again', () async {
    final initial = <String, Object>{
      'achUnlocked': ['item_heart', 'rank_egg'],
      'achItems': ['item_heart'],
      'achReported': ['rank_egg'],
      'achReportedPlayer': 'p1',
      'achRides': ['cannon'],
      'achVersusWins': 2,
      'achDayStreak': 3,
      'achLastPlayDay': 50,
    };
    final (s, a, trace) = await traced(initial);
    expect(s.achUnlocked, {'item_heart', 'rank_egg'});
    expect(s.achVersusWins, 2);
    for (var i = 0; i < itemGoal(AchievementId.itemHeart) + 1; i++) {
      a.beginRun(counts: true);
      a.runOp(AchOp.item(AchievementId.itemHeart));
      a.finishRun(counts: true);
    }
    await a.flush();
    final written = trace.snapshots.map((w) => w.$1).toSet();
    expect(written, contains('achState'));
    expect(
      written.where((k) => k.startsWith('ach') && k != 'achState'),
      isEmpty,
    );
    final r = GameStorage();
    await r.load();
    expect(r.achUnlocked, {'item_heart', 'rank_egg'});
    expect(r.achPending, isEmpty);
    expect(a.toastQueue, isEmpty);
    expect(r.achItems, {'item_heart'});
    expect(r.achReported, {'rank_egg'});
    expect(r.achReportedPlayer, 'p1');
    expect(r.achRides, {'cannon'});
    expect(r.achDayStreak, 3);
    expect(r.achLastPlayDay, 50);
  });

  // --- every item's N−1 / N under strict staging -------------------------------------

  for (final id in kItemAchievements) {
    test('P19 strict lifetime boundary and restart ${id.key}', () async {
      var (s, a) = await boot({});
      for (var i = 0; i < itemGoal(id) - 1; i++) {
        a.beginRun(counts: true);
        a.runOp(AchOp.item(id));
        a.finishRun(counts: true);
      }
      await a.flush();
      expect(a.earned, isEmpty);
      (s, a) = await boot(await disk());
      a.beginRun(counts: true);
      a.runOp(AchOp.item(id));
      a.finishRun(counts: true);
      await a.flush();
      expect(s.achUnlocked, {id.key});
      expect(s.achPending, isEmpty);
      expect(s.achItemCounts[id.key], itemGoal(id));
      a.beginRun(counts: false);
      a.runOp(AchOp.item(id));
      a.finishRun(counts: false);
      await a.flush();
      expect(s.achItemCounts[id.key], itemGoal(id));
    });
  }
}
