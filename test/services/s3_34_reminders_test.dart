import 'dart:math';

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/reminders.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../helpers.dart';

/// [GameServices] that records the §6 events instead of sending them.
class RecordingGameServices extends GameServices {
  final List<({String name, Map<String, Object>? parameters})> events = [];

  /// Only the §3.34 events, in order.
  List<String> namesOf(String name) =>
      [for (final e in events) if (e.name == name) name];

  Map<String, Object>? last(String name) {
    for (final e in events.reversed) {
      if (e.name == name) return e.parameters;
    }
    return null;
  }

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) =>
      events.add((name: name, parameters: parameters));
}

/// Replays the app being opened once every morning: reminders that fired while
/// it was closed count as delivered, and everything still pending is handed
/// back to the next plan exactly as `LocalReminders` reads it back from the
/// plugin payloads (including each message's earlier `lastSent` day).
class MorningSim {
  MorningSim(this.scheduler);

  final ReminderScheduler scheduler;
  ReminderState state = ReminderState.empty;
  List<PendingReminder> pending = [];
  final List<({int message, DateTime time})> delivered = [];

  void open(DateTime now) {
    delivered.addAll(
      pending
          .where((p) => !p.time.isAfter(now))
          .map((p) => (message: p.messageNumber, time: p.time)),
    );
    pending = pending.where((p) => p.time.isAfter(now)).toList();
    final plan = scheduler.plan(
      now: now,
      state: state,
      best: 12,
      coins: 250,
      lastPlayedAt: now,
      pending: pending,
    );
    state = plan.state;
    pending = [
      for (final r in plan.reminders)
        PendingReminder(
          messageNumber: r.messageNumber,
          time: r.time,
          previousLastSent: r.previousLastSent,
        ),
    ];
  }
}

/// PRD-2 §3.34 Reminder notifications: the pure scheduler, driven with a fake
/// clock, the pending list the plugin would report and two real time zones
/// (so the DST / time-zone rules are exercised for real).
void main() {
  setUpAll(tzdata.initializeTimeZones);

  late final tz.Location amsterdam;
  late final tz.Location denver;
  setUpAll(() {
    amsterdam = tz.getLocation('Europe/Amsterdam');
    denver = tz.getLocation('America/Denver');
  });

  ReminderScheduler scheduler({tz.Location? zone, int seed = 7}) =>
      ReminderScheduler(random: Random(seed), location: zone ?? amsterdam);

  MorningSim morningSim(ReminderScheduler s) => MorningSim(s);

  ReminderPlan planAt(
    DateTime now, {
    ReminderScheduler? withScheduler,
    ReminderState state = ReminderState.empty,
    List<PendingReminder> pending = const [],
    int best = 12,
    int coins = 250,
    DateTime? lastPlayed,
  }) => (withScheduler ?? scheduler()).plan(
    now: now,
    state: state,
    best: best,
    coins: coins,
    lastPlayedAt: lastPlayed ?? now,
    pending: pending,
  );

  String dayKey(DateTime time) =>
      '${time.year}-${time.month}-${time.day}';

  List<PendingReminder> pendingOf(ReminderPlan plan) => [
    for (final r in plan.reminders)
      PendingReminder(
        messageNumber: r.messageNumber,
        time: r.time,
        previousLastSent: r.previousLastSent,
      ),
  ];

  void expectNoRepeatWithin10Days(
    List<({int message, DateTime time})> delivered, {
    String reason = '',
  }) {
    final lastSeen = <int, DateTime>{};
    for (final entry in delivered) {
      final previous = lastSeen[entry.message];
      if (previous != null) {
        final gap = DateTime.utc(
          entry.time.year,
          entry.time.month,
          entry.time.day,
        ).difference(DateTime.utc(previous.year, previous.month, previous.day));
        expect(
          gap.inDays,
          greaterThanOrEqualTo(ReminderScheduler.noRepeatDays),
          reason: '$reason message ${entry.message} repeated after '
              '${gap.inDays} days',
        );
      }
      lastSeen[entry.message] = entry.time;
    }
  }

  group('§3.34 messages', () {
    test('20 English messages, numbered 1-20', () {
      expect(ReminderMessages.count, 20);
      expect(ReminderMessages.all.length, 20);
      expect(
        ReminderMessages.all.map((m) => m.number),
        List<int>.generate(20, (i) => i + 1),
      );
      for (final message in ReminderMessages.all) {
        expect(message.title, isNotEmpty);
        expect(message.body, isNotEmpty);
      }
    });

    test('{best} and {coins} are filled in', () {
      final one = ReminderMessages.textFor(1, best: 42, coins: 250);
      expect(one.title, 'Can you beat 42? ⭐');
      expect(one.body, 'Your best is 42. Today could be the day you top it!');

      final ten = ReminderMessages.textFor(10, best: 42, coins: 1234);
      expect(ten.title, '1234 coins to spend 💰');
    });

    test('new-player fallback for #1 and #2 (best 0)', () {
      final one = ReminderMessages.textFor(1, best: 0, coins: 0);
      expect(one.title, ReminderMessages.newPlayerTitle1);
      expect(one.body, ReminderMessages.newPlayerBody1);

      final two = ReminderMessages.textFor(2, best: 0, coins: 0);
      expect(two.title, ReminderMessages.newPlayerTitle2);
      expect(two.body, ReminderMessages.newPlayerBody2);

      // Every other message is unchanged for a new player.
      final three = ReminderMessages.textFor(3, best: 0, coins: 0);
      expect(three.title, ReminderMessages.byNumber(3).title);
      expect(three.body, ReminderMessages.byNumber(3).body);
    });
  });

  group('§3.34 when', () {
    test('two slots a day inside their windows', () {
      final plan = planAt(tz.TZDateTime(amsterdam, 2026, 10, 8, 9));
      expect(plan.reminders.length, ReminderScheduler.windowSlots);

      final perDay = <String, int>{};
      for (final reminder in plan.reminders) {
        final minute = reminder.time.hour * 60 + reminder.time.minute;
        expect(
          minute,
          inInclusiveRange(
            reminder.slot.startMinute,
            reminder.slot.endMinute - 1,
          ),
          reason: '${reminder.time} is outside the ${reminder.slot.key} window',
        );
        perDay[dayKey(reminder.time)] = (perDay[dayKey(reminder.time)] ?? 0) + 1;
      }
      expect(perDay.values, everyElement(lessThanOrEqualTo(2)));
      expect(perDay.length, ReminderScheduler.windowDays);
    });

    test('the plan spans seven days with 14 slots', () {
      final plan = planAt(tz.TZDateTime(amsterdam, 2026, 10, 8, 9));
      expect(plan.reminders.length, 14);
      expect(plan.reminders.first.slot, ReminderSlot.midday);
      expect(plan.reminders.last.slot, ReminderSlot.evening);

      final days = plan.reminders.map((r) => dayKey(r.time)).toSet();
      expect(days.length, 7);
      // Chronological.
      final times = plan.reminders.map((r) => r.time).toList();
      for (var i = 1; i < times.length; i++) {
        expect(times[i].isAfter(times[i - 1]), isTrue);
      }
    });

    test('nothing between 22:00 and 09:00, across DST and time-zone changes',
        () {
      final cases = <({tz.Location zone, DateTime now})>[
        // Europe/Amsterdam ends DST on 2026-10-25 and starts it on 2027-03-28.
        (zone: amsterdam, now: tz.TZDateTime(amsterdam, 2026, 10, 24, 21, 30)),
        (zone: amsterdam, now: tz.TZDateTime(amsterdam, 2027, 3, 27, 21, 30)),
        // America/Denver ends DST on 2026-11-01 and starts it on 2027-03-14.
        (zone: denver, now: tz.TZDateTime(denver, 2026, 10, 31, 21, 30)),
        (zone: denver, now: tz.TZDateTime(denver, 2027, 3, 13, 21, 30)),
      ];
      for (final c in cases) {
        final plan = planAt(c.now, withScheduler: scheduler(zone: c.zone));
        expect(plan.reminders.length, 14, reason: '${c.zone.name} ${c.now}');
        for (final reminder in plan.reminders) {
          final hour = reminder.time.hour;
          expect(
            hour >= ReminderScheduler.awakeHourFrom &&
                hour < ReminderScheduler.awakeHourTo,
            isTrue,
            reason: '${reminder.time} (${c.zone.name}) is in quiet hours',
          );
          // The wall clock stays inside the slot's window on every day,
          // including the DST-change day.
          final minute = reminder.time.hour * 60 + reminder.time.minute;
          expect(minute, inInclusiveRange(
            reminder.slot.startMinute,
            reminder.slot.endMinute - 1,
          ));
          expect(reminder.time.isAfter(c.now), isTrue);
        }
        // A DST change never costs or duplicates a slot.
        final days = plan.reminders.map((r) => dayKey(r.time)).toSet();
        expect(days.length, 7);
      }
    });

    test('a slot within 2 h after play is skipped', () {
      // The player closes the app at 12:00, so today's midday slot is gone
      // but the evening one is still sent.
      final now = tz.TZDateTime(amsterdam, 2026, 10, 8, 12);
      final plan = planAt(now);
      expect(plan.reminders.length, 14);
      expect(plan.reminders.first.slot, ReminderSlot.evening);
      expect(plan.reminders.first.time.day, 8);
      for (final reminder in plan.reminders) {
        expect(
          reminder.time.difference(now),
          greaterThan(const Duration(hours: 2)),
          reason: '${reminder.time} is within 2 h of play',
        );
      }
      // Nothing was sent before the play time, either.
      for (final reminder in plan.reminders) {
        expect(reminder.time.isAfter(now), isTrue);
      }
      final midnights = plan.reminders
          .where((r) => r.slot == ReminderSlot.midday)
          .toList();
      expect(midnights.length, 7);
      expect(midnights.first.time.day, 9);
    });
  });

  group('§3.34 order', () {
    test('the order is a shuffled permutation of 1-20', () {
      final plan = planAt(tz.TZDateTime(amsterdam, 2026, 10, 8, 9));
      expect(plan.state.order.toSet().length, 20);
      expect(plan.state.order..sort(), List<int>.generate(20, (i) => i + 1));
      // Within one plan every message is used at most once.
      final numbers = plan.reminders.map((r) => r.messageNumber).toList();
      expect(numbers.toSet().length, numbers.length);
    });

    test('the rotation never repeats a message within 10 days', () {
      for (final seed in [1, 2, 3, 5, 7, 11, 13, 17, 23, 42]) {
        final sim = morningSim(scheduler(seed: seed));
        for (var day = 0; day < 45; day++) {
          sim.open(tz.TZDateTime(amsterdam, 2026, 10, 1 + day, 9));
        }
        expect(sim.delivered.length, 88,
            reason: 'seed $seed: 2 slots x 44 full days');
        // The first lap is a plain shuffle: 20 different messages.
        expect(
          sim.delivered.take(20).map((d) => d.message).toSet().length,
          20,
          reason: 'seed $seed',
        );
        expectNoRepeatWithin10Days(sim.delivered, reason: 'seed $seed');
      }
    });

    test('a long absence does not break the rotation', () {
      // 20 days in, then the app is closed for ~40 days (the notifications
      // fire unanswered and are reported as delivered on the next open),
      // then 25 days in again.
      final sim = morningSim(scheduler(seed: 9));
      for (var day = 0; day < 20; day++) {
        sim.open(tz.TZDateTime(amsterdam, 2026, 10, 1 + day, 9));
      }
      for (var day = 0; day < 25; day++) {
        sim.open(tz.TZDateTime(amsterdam, 2026, 12, 1 + day, 9));
      }
      expectNoRepeatWithin10Days(sim.delivered, reason: 'across the absence');
      // Every message still appears after the absence.
      expect(
        sim.delivered
            .where((d) => d.time.month == 12)
            .map((d) => d.message)
            .toSet()
            .length,
        greaterThan(10),
      );
    });

    test('re-scheduling without delivery keeps the same messages', () {
      final s = scheduler();
      final now = tz.TZDateTime(amsterdam, 2026, 10, 8, 9);
      final first = planAt(now, withScheduler: s);
      final second = s.plan(
        now: now.add(const Duration(minutes: 5)),
        state: first.state,
        best: 12,
        coins: 250,
        lastPlayedAt: now,
        pending: pendingOf(first),
      );
      expect(
        second.reminders.map((r) => r.messageNumber),
        first.reminders.map((r) => r.messageNumber),
      );
      expect(second.state.position, first.state.position);
    });

    test('delivered slots advance the rotation', () {
      final s = scheduler();
      final first = planAt(tz.TZDateTime(amsterdam, 2026, 10, 8, 9),
          withScheduler: s);
      // The two reminders of day 1 fired; the rest is still pending.
      final firedAt = tz.TZDateTime(amsterdam, 2026, 10, 8, 21);
      final pending = first.reminders
          .where((r) => r.time.isAfter(firedAt))
          .map((r) => PendingReminder(messageNumber: r.messageNumber, time: r.time))
          .toList();
      expect(pending.length, 12);

      final second = s.plan(
        now: tz.TZDateTime(amsterdam, 2026, 10, 9, 9),
        state: first.state,
        best: 12,
        coins: 250,
        lastPlayedAt: tz.TZDateTime(amsterdam, 2026, 10, 9, 9),
        pending: pending,
      );
      // Day 2 carries on where day 1 stopped: the third message of the plan.
      expect(second.reminders.first.messageNumber, first.reminders[2].messageNumber);
      expect(second.reminders.first.time.day, 9);
      // The two delivered messages are blocked for day 2 (1 day ago < 10).
      expect(
        second.reminders.map((r) => r.messageNumber).toSet(),
        isNot(contains(first.reminders[0].messageNumber)),
      );
    });
  });

  group('§3.34 service', () {
    late FakeReminderPlatform platform;
    late RecordingGameServices analytics;
    late GameStorage store;
    late DateTime now;
    late ReminderScheduler scheduler;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'bestScore': 12, 'coins': 250});
      platform = FakeReminderPlatform();
      analytics = RecordingGameServices();
      now = tz.TZDateTime(amsterdam, 2026, 10, 8, 22);
      store = GameStorage(clock: () => now);
      await store.load();
      scheduler = ReminderScheduler(random: Random(7), location: amsterdam);
    });

    LocalReminders service() => LocalReminders(
      storage: store,
      services: analytics,
      platform: platform,
      scheduler: scheduler,
    );

    test('reschedule lays out 14 filled reminders and persists the plan',
        () async {
      final reminders = service();
      await reminders.initialize();
      await reminders.reschedule();

      expect(platform.cancelCalls, 1);
      expect(platform.scheduled, hasLength(ReminderScheduler.windowSlots));
      expect(
        platform.scheduled.map((r) => r.id),
        List<int>.generate(ReminderScheduler.windowSlots, (i) => i + 1),
      );
      // Two slots a day inside their windows, from tomorrow on (22:00 start).
      final byDay = <int, List<({int id, String title, String body, DateTime time, String payload})>>{};
      for (final r in platform.scheduled) {
        byDay.putIfAbsent(r.time.day, () => []).add(r);
      }
      expect(byDay.length, ReminderScheduler.windowDays);
      for (final slot in byDay.values) {
        expect(slot, hasLength(ReminderScheduler.slotsPerDay));
        for (final r in slot) {
          final minutes = r.time.hour * 60 + r.time.minute;
          final insideMidday = minutes >= 11 * 60 + 30 && minutes <= 13 * 60 + 30;
          final insideEvening = minutes >= 18 * 60 + 30 && minutes <= 20 * 60 + 30;
          expect(insideMidday || insideEvening, isTrue,
              reason: '${r.time} is outside both windows');
        }
      }
      // {best} / {coins} filled in from storage, not left as placeholders.
      final joined = platform.scheduled.map((r) => '${r.title}\n${r.body}').join();
      expect(joined, isNot(contains('{')));
      // The persisted state is what the next plan continues from.
      expect(store.notifOrder, hasLength(ReminderMessages.count));
      expect(store.notifPosition, ReminderScheduler.windowSlots);
      expect(store.notifLastSent, hasLength(ReminderScheduler.windowSlots));
    });

    test('the new-player fallback is used when best is 0', () async {
      store.bestScore = 0;
      final reminders = service();
      await reminders.initialize();
      await reminders.reschedule();
      final joined = platform.scheduled.map((r) => '${r.title}\n${r.body}').join();
      expect(joined, contains(ReminderMessages.newPlayerTitle1));
      expect(joined, contains(ReminderMessages.newPlayerTitle2));
    });

    test('rescheduling twice without delivery keeps the same messages',
        () async {
      final reminders = service();
      await reminders.initialize();
      await reminders.reschedule();
      final first = [
        for (final raw in platform.pending) ReminderPayload.decode(raw)!,
      ];
      now = now.add(const Duration(minutes: 5));
      await reminders.reschedule();
      final second = [
        for (final raw in platform.pending) ReminderPayload.decode(raw)!,
      ];
      // The slot times are re-picked on every reschedule (§3.34 "pick each
      // slot's random time"), the messages must not move.
      expect(
        second.map((p) => p.messageNumber),
        first.map((p) => p.messageNumber),
      );
      expect(second.map((p) => p.slot), first.map((p) => p.slot));
    });

    test('permission is asked once and the result is logged', () async {
      final reminders = service();
      await reminders.initialize();
      await reminders.requestPermissionIfNeeded();
      expect(platform.permissionCalls, 1);
      expect(store.notifPermissionAsked, isTrue);
      expect(analytics.last('notif_permission'), {'granted': true});

      // Same service: the in-session flag stops a second prompt.
      await reminders.requestPermissionIfNeeded();
      expect(platform.permissionCalls, 1);

      // A later start reads the persisted flag and never asks again.
      final again = service();
      await again.initialize();
      await again.requestPermissionIfNeeded();
      expect(platform.permissionCalls, 1);
      expect(
        analytics.namesOf('notif_permission').length,
        1,
        reason: 'one notif_permission event, ever',
      );
    });

    test('a decline is final and logged', () async {
      platform.permissionResult = false;
      final reminders = service();
      await reminders.initialize();
      await reminders.requestPermissionIfNeeded();
      expect(platform.permissionCalls, 1);
      expect(analytics.last('notif_permission'), {'granted': false});
      expect(store.notifPermissionAsked, isTrue);
    });

    test('no prompt on an OS without one (Android <= 12)', () async {
      platform.permissionResult = null;
      final reminders = service();
      await reminders.initialize();
      await reminders.requestPermissionIfNeeded();
      expect(platform.permissionCalls, 1);
      // Nothing to report: no granted/denied event, but still asked-once.
      expect(analytics.last('notif_permission'), isNull);
      expect(store.notifPermissionAsked, isTrue);
    });

    test('permission is not asked before initialize', () async {
      final reminders = service();
      await reminders.requestPermissionIfNeeded();
      expect(platform.permissionCalls, 0);
      expect(store.notifPermissionAsked, isFalse);
    });

    test('tapping a reminder logs notif_opened', () async {
      final reminders = service();
      await reminders.initialize();
      expect(platform.onTap, isNotNull);
      platform.onTap!(
        const ReminderPayload(
          messageNumber: 7,
          slot: ReminderSlot.midday,
          epochMs: 0,
        ),
      );
      expect(analytics.last('notif_opened'), {'message': 7, 'slot': 'midday'});
    });

    test('payloads round-trip through the plugin string', () {
      const payload = ReminderPayload(
        messageNumber: 13,
        slot: ReminderSlot.evening,
        epochMs: 1760000000000,
        previousLastSent: '2026-10-01',
      );
      final decoded = ReminderPayload.decode(payload.encode());
      expect(decoded?.messageNumber, 13);
      expect(decoded?.slot, ReminderSlot.evening);
      expect(decoded?.epochMs, 1760000000000);
      expect(decoded?.previousLastSent, '2026-10-01');
      expect(ReminderPayload.decode('not json'), isNull);
      expect(ReminderPayload.decode(null), isNull);
    });

    test('a platform failure never throws and never blocks the game',
        () async {
      platform.throwOnInitialize = true;
      final reminders = service();
      await reminders.initialize(); // must not throw
      await reminders.requestPermissionIfNeeded();
      await reminders.reschedule();
      expect(platform.scheduled, isEmpty);

      platform.throwOnInitialize = false;
      platform.throwOnSchedule = true;
      final failing = service();
      await failing.initialize();
      await failing.reschedule(); // must not throw
      // The plan is still persisted, so the next pause/start retries.
      expect(store.notifOrder, hasLength(ReminderMessages.count));
    });

    test('a delivered slot advances the rotation, pending ones stay', () async {
      final reminders = service();
      await reminders.initialize();
      await reminders.reschedule();
      expect(platform.scheduled, hasLength(ReminderScheduler.windowSlots));

      // The two day-9 reminders fire; the app is opened again that evening.
      now = tz.TZDateTime(amsterdam, 2026, 10, 9, 21);
      platform.deliverDue(now);
      expect(
        platform.pending,
        hasLength(ReminderScheduler.windowSlots - 2),
        reason: 'the two day-9 slots fired',
      );
      final kept = {
        for (final raw in platform.pending)
          ReminderPayload.decode(raw)!.messageNumber,
      };

      await reminders.reschedule();
      final after = [
        for (final raw in platform.pending) ReminderPayload.decode(raw)!,
      ];
      expect(after, hasLength(ReminderScheduler.windowSlots));
      // Opening the app again does not burn the order: the 12 that had not
      // fired keep their message, only the two fired slots take the next two.
      expect(after.map((p) => p.messageNumber).toSet().containsAll(kept), isTrue);
    });
  });

  group('§3.34 lifecycle', () {
    late FakeReminders reminders;

    setUp(() => reminders = FakeReminders());

    final withGame = FlameTester<FlappySpikesGame>(
      () => createTestGame(const {}, null, null, null, reminders),
      gameSize: Vector2(Config.worldWidth, Config.worldHeight),
    );

    withGame.testGameWidget(
      'app start asks once and lays out the plan; leaving reschedules',
      setUp: (game, tester) async {
        await game.ready();
      },
      verify: (game, tester) async {
        // §3.34 "Permission"/"Scheduling": one initialize, one prompt, one
        // plan at the first app start.
        expect(reminders.initializeCalls, 1);
        expect(reminders.permissionCalls, 1);
        expect(reminders.rescheduleCalls, 1);

        // §3.34 "Every time the app goes to the background or is closed" —
        // driven through the real binding -> GameWidget -> GameRenderBox
        // path, not by calling the override directly.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        expect(reminders.rescheduleCalls, 2);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        expect(reminders.rescheduleCalls, 3);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.detached,
        );
        expect(reminders.rescheduleCalls, 4);
        // Coming back to the foreground is not a reschedule.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        expect(reminders.rescheduleCalls, 4);
      },
    );
  });
}
