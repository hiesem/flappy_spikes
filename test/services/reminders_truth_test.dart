import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/reminders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class _Analytics extends GameServices {
  Map<String, Object>? opened;
  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    if (name == 'notif_opened') opened = parameters;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late tz.Location zone;
  late tz.TZDateTime monday;
  late int day;

  setUp(() {
    tzdata.initializeTimeZones();
    zone = tz.getLocation('Europe/Amsterdam');
    monday = tz.TZDateTime(zone, 2026, 10, 19, 8);
    day = ReminderTruth.dayOf(monday);
  });

  ReminderPlan plan(ReminderTruth truth, {DateTime? now}) =>
      ReminderScheduler(location: zone, random: Random(7)).plan(
        now: now ?? monday,
        state: ReminderState.empty,
        best: 42,
        coins: 99,
        truth: truth,
      );

  test('calendar decay: 2/day days 1–3, 1/day days 4–7, none after', () {
    final reminders = plan(ReminderTruth(lastRunDay: day - 1)).reminders;
    final counts = <int, int>{};
    for (final r in reminders) {
      final age = ReminderTruth.dayOf(r.time) - (day - 1);
      counts.update(age, (n) => n + 1, ifAbsent: () => 1);
      expect(r.time.hour, inInclusiveRange(9, 21));
      if (age >= 4) expect(r.slot, ReminderSlot.evening);
    }
    expect(counts, {1: 2, 2: 2, 3: 2, 4: 1, 5: 1, 6: 1, 7: 1});
  });

  test('run-day slots remain available for missions; no eighth day', () {
    final reminders = plan(ReminderTruth(lastRunDay: day)).reminders;
    expect(reminders, hasLength(12));
    expect(
      reminders.where((r) => ReminderTruth.dayOf(r.time) == day),
      hasLength(2),
    );
    expect(ReminderTruth.dayOf(reminders.last.time), day + 7);
  });

  test('opening without a run never restarts decay', () {
    for (final age in [4, 7, 8, 30]) {
      final reminders = plan(ReminderTruth(lastRunDay: day - age)).reminders;
      expect(reminders.length, {4: 4, 7: 1, 8: 0, 30: 0}[age]);
    }
    expect(plan(ReminderTruth(lastRunDay: null)).reminders, isEmpty);
  });

  test('calendar decay survives DST fall-back and uses local dates', () {
    final now = tz.TZDateTime(zone, 2026, 10, 24, 8);
    final start = ReminderTruth.dayOf(now);
    final reminders = plan(
      ReminderTruth(lastRunDay: start - 1),
      now: now,
    ).reminders;
    expect(reminders, hasLength(10));
    expect(reminders.last.time.day, 30);
    for (final r in reminders) {
      expect(r.time.hour, inInclusiveRange(11, 20));
    }
  });

  test('N1a only next-day evening, streak >=2, ahead of missions', () {
    final reminders = plan(
      ReminderTruth(
        lastRunDay: day - 1,
        streakDays: 3,
        missionsUnlocked: true,
        missionDay: day,
        unfinishedMissionRewards: [20, 55],
      ),
    ).reminders;
    expect(reminders.first.type, 'N2');
    expect(reminders[1].type, 'N1a');
    expect(reminders[1].title, 'Your 3-day streak ends tonight 🔥');
    expect(reminders[1].body, 'One quick run before midnight keeps it alive.');
    expect(reminders.where((r) => r.type == 'N1a'), hasLength(1));
    for (final streak in [0, 1]) {
      expect(
        plan(
          ReminderTruth(lastRunDay: day - 1, streakDays: streak),
        ).reminders.where((r) => r.type == 'N1a'),
        isEmpty,
      );
    }
    expect(
      plan(
        ReminderTruth(lastRunDay: day, streakDays: 2),
      ).reminders.where((r) => r.type == 'N1a').single.time.day,
      monday.day + 1,
    );
  });

  test('N2 plural and singular count only unfinished rewards, same day', () {
    for (final rewards in [
      [55],
      [35, 55],
      [20, 35, 55],
    ]) {
      final reminders = plan(
        ReminderTruth(
          lastRunDay: day,
          missionsUnlocked: true,
          missionDay: day,
          unfinishedMissionRewards: rewards,
        ),
      ).reminders;
      final first = reminders.first;
      expect(first.type, rewards.length == 1 ? 'N2s' : 'N2');
      expect(
        first.title,
        rewards.length == 1
            ? '1 mission left today 🎯'
            : '${rewards.length} missions left today 🎯',
      );
      final coins = rewards.reduce((a, b) => a + b);
      expect(
        first.body,
        'Finish ${rewards.length == 1 ? 'it' : 'them'} for $coins coins and the bonus chest.',
      );
      for (final r in reminders.skip(2)) {
        expect(r.type, 'N3');
      }
    }
  });

  test('completed and locked missions never promise unfinished coins', () {
    expect(
      plan(
        ReminderTruth(lastRunDay: day, missionsUnlocked: true, missionDay: day),
      ).reminders.first.type,
      'generic',
    );
    expect(
      plan(
        ReminderTruth(
          lastRunDay: day,
          missionDay: day - 1,
          unfinishedMissionRewards: [55],
        ),
      ).reminders.first.type,
      'generic',
    );
    expect(
      plan(
        ReminderTruth(
          lastRunDay: day,
          missionsUnlocked: true,
          missionDay: day + 1,
          unfinishedMissionRewards: [55],
        ),
      ).reminders.first.type,
      'generic',
    );
  });

  test('N3 later mission day wins over feather and puzzle', () {
    final first = plan(
      ReminderTruth(
        lastRunDay: day,
        missionsUnlocked: true,
        missionDay: day - 1,
        feathers: 2,
        pieces: 3,
      ),
    ).reminders.first;
    expect(first.type, 'N3');
    expect(first.title, 'New daily missions are in! 🎯');
    expect(first.body, 'Three fresh missions and a chest are waiting for you.');
  });

  test('N4 then N5, exact held counts and approved copy', () {
    final feather = plan(
      ReminderTruth(lastRunDay: day, feathers: 2, pieces: 3),
    ).reminders.first;
    expect(feather.type, 'N4');
    expect(
      feather.body,
      'Catch one more golden feather to open the balloon bonus 🎈',
    );
    final piece = plan(
      ReminderTruth(lastRunDay: day, feathers: 3, pieces: 3),
    ).reminders.first;
    expect(piece.type, 'N5');
    expect(
      piece.body,
      'Find the last puzzle piece to finish your picture and win coins!',
    );
    expect(
      plan(
        ReminderTruth(lastRunDay: day, feathers: 1, pieces: 2),
      ).reminders.first.type,
      'generic',
    );
  });

  test(
    'N6a/b/c only current week and strictly less than 24h before UTC reset',
    () {
      final end = DateTime.utc(2026, 10, 26);
      for (final best in <int?>[null, 0, 14, 15, 30, 60, 119, 120, 999]) {
        final truth = ReminderTruth(
          lastRunDay: day,
          weeklyUnlocked: true,
          weeklyEndsAt: end,
          weeklyBest: best,
        );
        final text = truth.textAt(
          tz.TZDateTime.from(end.subtract(const Duration(hours: 1)), zone),
          ReminderSlot.evening,
        )!;
        expect(
          text.type,
          best == null
              ? 'N6c'
              : best >= 120
              ? 'N6b'
              : 'N6a',
        );
        if (best != null && best < 120) {
          final tier = best < 15
              ? (15, 40)
              : best < 30
              ? (30, 80)
              : best < 60
              ? (60, 150)
              : (120, 300);
          expect(
            text.text.body,
            'Your best: hoop $best. Reach hoop ${tier.$1} for +${tier.$2} coins before it resets!',
          );
        }
        for (final time in [
          end.subtract(const Duration(hours: 24)),
          end,
          end.add(const Duration(hours: 1)),
        ]) {
          expect(
            truth.textAt(tz.TZDateTime.from(time, zone), ReminderSlot.midday),
            isNull,
          );
        }
      }
    },
  );

  test('N6 uses absolute UTC boundary in positive and negative zones', () {
    final end = DateTime.utc(2026, 10, 26);
    final truth = ReminderTruth(
      lastRunDay: day,
      weeklyUnlocked: true,
      weeklyEndsAt: end,
    );
    for (final name in ['Asia/Tokyo', 'America/Los_Angeles']) {
      final local = tz.getLocation(name);
      expect(
        truth
            .textAt(
              tz.TZDateTime.from(
                end.subtract(const Duration(hours: 23)),
                local,
              ),
              ReminderSlot.midday,
            )
            ?.type,
        'N6c',
      );
      expect(
        truth.textAt(tz.TZDateTime.from(end, local), ReminderSlot.evening),
        isNull,
      );
    }
  });

  test('N6 wins before N7; locked weekly course never sends', () {
    final time = tz.TZDateTime(zone, 2026, 10, 25, 20);
    final end = DateTime.utc(2026, 10, 26);
    final truth = ReminderTruth(
      lastRunDay: day,
      weeklyUnlocked: true,
      weeklyEndsAt: end,
      nextLevelName: 'FLUFFBALL',
      pointsNeeded: 10,
      averageRunScore: 10,
    );
    expect(truth.textAt(time, ReminderSlot.evening)?.type, 'N6c');
    expect(
      ReminderTruth(
        lastRunDay: day,
        weeklyEndsAt: end,
      ).textAt(time, ReminderSlot.evening),
      isNull,
    );
  });

  test(
    'N7 needs a real next level, positive points and sufficient average',
    () {
      for (final average in [9.9, 10.0, 10.1, double.nan, double.infinity]) {
        final first = plan(
          ReminderTruth(
            lastRunDay: day,
            nextLevelName: 'FLUFFBALL',
            pointsNeeded: 10,
            averageRunScore: average,
          ),
        ).reminders.first;
        expect(
          first.type,
          average.isFinite && average >= 10 ? 'N7' : 'generic',
        );
        if (first.type == 'N7') {
          expect(first.title, 'So close to FLUFFBALL! ⭐');
          expect(
            first.body,
            'Just 10 more points to your next level and its reward.',
          );
        }
      }
      expect(
        plan(
          ReminderTruth(lastRunDay: day, pointsNeeded: 0, averageRunScore: 20),
        ).reminders.first.type,
        'generic',
      );
    },
  );

  test(
    'stateful reminders do not consume generic rotation; pending are reevaluated',
    () {
      final scheduler = ReminderScheduler(location: zone, random: Random(7));
      final first = plan(ReminderTruth(lastRunDay: day, feathers: 2));
      expect(first.state.position, 0);
      expect(first.state.lastSent, isEmpty);
      final second = scheduler.plan(
        now: monday,
        state: first.state,
        best: 42,
        coins: 99,
        truth: ReminderTruth(lastRunDay: day),
        pending: [
          for (final r in first.reminders)
            PendingReminder(messageNumber: r.messageNumber, time: r.time),
        ],
      );
      expect(second.reminders.first.type, 'generic');
      expect(second.state.order.toSet(), {for (var i = 1; i <= 20; i++) i});
      expect(second.state.lastSent.containsKey(0), isFalse);
    },
  );

  test('generic pending rotation survives a contextual replacement', () {
    final first = plan(ReminderTruth(lastRunDay: day));
    final scheduler = ReminderScheduler(location: zone, random: Random(8));
    final second = scheduler.plan(
      now: monday,
      state: first.state,
      best: 42,
      coins: 99,
      truth: ReminderTruth(lastRunDay: day, feathers: 2),
      pending: [
        for (final r in first.reminders)
          PendingReminder(
            messageNumber: r.messageNumber,
            time: r.time,
            previousLastSent: r.previousLastSent,
          ),
      ],
    );
    expect(second.reminders.every((r) => r.type == 'N4'), isTrue);
    expect(second.state.position, 0);
    expect(second.state.lastSent, isEmpty);
    final third = scheduler.plan(
      now: monday,
      state: second.state,
      best: 42,
      coins: 99,
      truth: ReminderTruth(lastRunDay: day),
    );
    expect(
      third.reminders.map((r) => r.messageNumber),
      first.reminders.map((r) => r.messageNumber),
    );
  });

  test('payload type round trip and old payload compatibility', () {
    final payload = plan(
      ReminderTruth(lastRunDay: day, feathers: 2),
    ).reminders.first.payload;
    expect(ReminderPayload.decode(payload.encode())!.type, 'N4');
    expect(
      ReminderPayload.decode('{"m":7,"s":"midday","t":123}')!.type,
      isNull,
    );
  });

  test(
    'storage snapshot counts puzzle bits and gates streak before game 4',
    () {
      final store = GameStorage()
        ..puzzlePieces = 13
        ..streakDays = 3
        ..gamesPlayed = 3;
      expect(ReminderTruth.fromStorage(store).pieces, 3);
      expect(ReminderTruth.fromStorage(store).streakDays, 0);
      store.gamesPlayed = 4;
      expect(ReminderTruth.fromStorage(store).streakDays, 3);
    },
  );

  test(
    'service refreshes truth, cancels stale promises and logs opened type',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = GameStorage(clock: () => monday);
      await store.load();
      final platform = FakeReminderPlatform();
      final analytics = _Analytics();
      var truth = ReminderTruth(lastRunDay: day, feathers: 2);
      final service = LocalReminders(
        storage: store,
        platform: platform,
        services: analytics,
        scheduler: ReminderScheduler(location: zone, random: Random(7)),
        truthSnapshot: () => truth,
      );
      await service.initialize();
      await service.reschedule();
      final payload = ReminderPayload.decode(platform.scheduled.first.payload)!;
      platform.onTap!(payload);
      expect(analytics.opened, {'message': 0, 'slot': 'midday', 'type': 'N4'});
      truth = ReminderTruth(lastRunDay: day, feathers: 3);
      await service.reschedule();
      expect(platform.cancelCalls, 2);
      expect(
        platform.scheduled.map((r) => ReminderPayload.decode(r.payload)!.type),
        everyElement('generic'),
      );
      truth = ReminderTruth(lastRunDay: day - 8);
      await service.reschedule();
      expect(platform.scheduled, isEmpty);
    },
  );
}
