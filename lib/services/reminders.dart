import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../game/storage.dart';
import '../run/elements.dart';
import 'game_services.dart';

/// Reminder notifications (PRD-2 §3.34).
///
/// Local only: the app schedules the next 7 days itself (no server, no FCM).
/// Two slots a day inside fixed windows, a shuffled 20-message rotation, and
/// nothing between 22:00 and 09:00 local time. The scheduling rules live in
/// the pure [ReminderScheduler] (fake clock in tests); the plugin sits behind
/// the narrow [ReminderPlatform] seam so nothing touches a channel in tests.
///
/// The default service is the no-op [NoopReminders]; `main.dart` swaps in
/// [LocalReminders] on mobile. Implementations never throw.
abstract class Reminders {
  /// Time zone + plugin + channel + tap handler. Safe to call once at app
  /// start; a failure leaves reminders off.
  Future<void> initialize();

  /// §3.34 permission: asks Android 13+ (and iOS) **once**, at the first app
  /// start. Never asks again after a decline.
  Future<void> requestPermissionIfNeeded();

  /// §3.34 scheduling: cancels the pending plan and schedules the next 7 days
  /// (14 slots) from now, with `{best}` / `{coins}` filled in.
  Future<void> reschedule();
}

/// Default: no notifications (tests, Linux, `FS_E2E`).
class NoopReminders implements Reminders {
  const NoopReminders();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermissionIfNeeded() async {}

  @override
  Future<void> reschedule() async {}
}

/// Recorder for tests / `FS_E2E`: counts the calls and scripts the permission
/// result.
class FakeReminders implements Reminders {
  FakeReminders({this.permissionGranted = true});

  final bool permissionGranted;
  int initializeCalls = 0;
  int permissionCalls = 0;
  int rescheduleCalls = 0;

  @override
  Future<void> initialize() async => initializeCalls++;

  @override
  Future<void> requestPermissionIfNeeded() async => permissionCalls++;

  @override
  Future<void> reschedule() async => rescheduleCalls++;
}

/// One of the 20 reminder messages (PRD-2 §3.34).
class ReminderMessage {
  const ReminderMessage(this.number, this.title, this.body);

  /// 1-20, the message's number in the PRD table.
  final int number;
  final String title;
  final String body;
}

/// A title/body pair after the `{best}` / `{coins}` fill-in (and the
/// new-player fallback).
class ReminderText {
  const ReminderText(this.title, this.body);

  final String title;
  final String body;
}

/// The 20 messages of PRD-2 §3.34, in table order.
class ReminderMessages {
  static const int count = 20;

  /// New player (best score 0): #1's text (§3.34 "Text fallback").
  static const String newPlayerTitle1 = 'Can you beat your best? ⭐';
  static const String newPlayerBody1 = 'Set your first record today!';

  /// New player: #2's text.
  static const String newPlayerTitle2 = 'Chase your record 🏅';
  static const String newPlayerBody2 = 'How far can you fly today?';

  static const List<ReminderMessage> all = [
    ReminderMessage(
      1,
      'Can you beat {best}? ⭐',
      'Your best is {best}. Today could be the day you top it!',
    ),
    ReminderMessage(
      2,
      'Chase your record 🏅',
      'Your best is {best} points. How close can you get today?',
    ),
    ReminderMessage(
      3,
      'Rematch? 🔥',
      'The spikes won last time. Think you can get them back?',
    ),
    ReminderMessage(
      4,
      'Daily flap time 🐤',
      'Fresh hoops, sharp spikes. Your daily run is waiting!',
    ),
    ReminderMessage(
      5,
      'New day, new record 🏆',
      "Today's a fresh start. Set a new best score!",
    ),
    ReminderMessage(
      6,
      'Go for gold ✨',
      'Fly through the hoops perfectly and watch every ring turn gold.',
    ),
    ReminderMessage(
      7,
      'Your bird is waiting 🐤',
      'Ready for a quick round? The hoops are lined up.',
    ),
    ReminderMessage(
      8,
      'Collect the puzzle 🧩',
      'Find puzzle pieces in your runs and finish a bird picture for coins!',
    ),
    ReminderMessage(
      9,
      'Golden feathers 🪶',
      'Collect 3 golden feathers to unlock the balloon bonus 🎈',
    ),
    ReminderMessage(
      10,
      '{coins} coins to spend 💰',
      'Check the shop for a new skin, or earn more in a run!',
    ),
    ReminderMessage(
      11,
      'Spike walls incoming 😬',
      'Can you survive the squeeze when the walls close in?',
    ),
    ReminderMessage(
      12,
      'Ride a comet ☄️',
      'Catch a comet and blast through the hoops on autopilot!',
    ),
    ReminderMessage(
      13,
      'Spin to win 🎡',
      'Fly through a Lucky Spin ring and see where the wheel stops!',
    ),
    ReminderMessage(
      14,
      'Dodge the spikes 🔺',
      'How far can you fly today? Every hoop counts.',
    ),
    ReminderMessage(
      15,
      'One more run? ⏱️',
      'Flap, dodge, beat your best. It only takes a minute!',
    ),
    ReminderMessage(
      16,
      'Hatch a lucky chick 🥚',
      'Carry an egg through 5 hoops to hatch a chick for bonus points!',
    ),
    ReminderMessage(
      17,
      'Fill the piggy bank 🐷',
      'Grab the piggy bank and catch the coins that follow!',
    ),
    ReminderMessage(
      18,
      'Bullseye! 🎯',
      'Hit the centre of a bullseye ring for bonus coins.',
    ),
    ReminderMessage(
      19,
      'Fever mode 🔥',
      'Fly through the glowing ring and set your bird on fire!',
    ),
    ReminderMessage(
      20,
      'Coffee break? ☕',
      "Perfect time for a few flaps. Let's go!",
    ),
  ];

  /// The message with [number] (1-20).
  static ReminderMessage byNumber(int number) => all[number - 1];

  /// Replaces `{best}` / `{coins}` (§3.34 "Messages").
  static String fill(String text, {required int best, required int coins}) =>
      text.replaceAll('{best}', '$best').replaceAll('{coins}', '$coins');

  /// Title + body for [number] with the current values, including the
  /// new-player fallback for #1 and #2 (best score 0).
  static ReminderText textFor(int number, {required int best, required int coins}) {
    if (best <= 0) {
      if (number == 1) {
        return const ReminderText(newPlayerTitle1, newPlayerBody1);
      }
      if (number == 2) {
        return const ReminderText(newPlayerTitle2, newPlayerBody2);
      }
    }
    final m = byNumber(number);
    return ReminderText(
      fill(m.title, best: best, coins: coins),
      fill(m.body, best: best, coins: coins),
    );
  }
}

// region P26-G3
/// Immutable facts at scheduling time. Dates are local calendar-day indexes
/// (UTC encoding of the local year/month/day), as in GameStorage.today.
/// A future slot must still satisfy its copy without assuming another run.
class ReminderTruth {
  ReminderTruth({
    required this.lastRunDay,
    this.streakDays = 0,
    this.missionsUnlocked = false,
    this.missionDay,
    List<int> unfinishedMissionRewards = const [],
    this.feathers = 0,
    this.pieces = 0,
    this.weeklyEndsAt,
    this.weeklyUnlocked = false,
    this.weeklyBest,
    this.nextLevelName,
    this.pointsNeeded,
    this.averageRunScore,
  }) : unfinishedMissionRewards = List.unmodifiable(unfinishedMissionRewards);

  final int? lastRunDay;
  final int streakDays;
  final bool missionsUnlocked;
  final int? missionDay;
  final List<int> unfinishedMissionRewards;
  final int feathers, pieces;

  /// The current course's Monday 00:00 UTC boundary, supplied by its clock.
  /// Null until the weekly-course model is available. Never extrapolate the
  /// current best into the following week.
  final DateTime? weeklyEndsAt;
  final bool weeklyUnlocked;

  /// Null means no run in this course; zero can be a played zero-hoop run.
  final int? weeklyBest;
  final String? nextLevelName;
  final int? pointsNeeded;
  final double? averageRunScore;

  static int dayOf(DateTime local) =>
      DateTime.utc(local.year, local.month, local.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// Safe persisted facts available even before the other meta models are
  /// wired. The injected LocalReminders.truthSnapshot supplies their richer
  /// state; absent inputs never make an unsupported promise.
  factory ReminderTruth.fromStorage(GameStorage store) => ReminderTruth(
    lastRunDay: store.achLastPlayDay < 0 ? null : store.achLastPlayDay,
    streakDays: store.gamesPlayed >= 4 ? store.streakDays : 0,
    missionsUnlocked: store.gamesPlayed >= 4 && store.missionDay >= 0,
    missionDay: store.missionDay < 0 ? null : store.missionDay,
    feathers: store.feathers,
    pieces: (store.puzzlePieces & 15).toRadixString(2).split('1').length - 1,
  );

  ({String type, ReminderText text})? textAt(
    tz.TZDateTime time,
    ReminderSlot slot,
  ) {
    final day = dayOf(time);
    if (lastRunDay != null &&
        day == lastRunDay! + 1 &&
        streakDays >= 2 &&
        slot == ReminderSlot.evening) {
      return (
        type: 'N1a',
        text: ReminderText(
          'Your $streakDays-day streak ends tonight 🔥',
          'One quick run before midnight keeps it alive.',
        ),
      );
    }
    if (missionsUnlocked && missionDay != null) {
      final count = unfinishedMissionRewards.length;
      if (day == missionDay && count >= 1 && count <= 3) {
        final coins = unfinishedMissionRewards.fold<int>(0, (a, b) => a + b);
        return (
          type: count == 1 ? 'N2s' : 'N2',
          text: ReminderText(
            count == 1
                ? '1 mission left today 🎯'
                : '$count missions left today 🎯',
            'Finish ${count == 1 ? 'it' : 'them'} for $coins coins and the bonus chest.',
          ),
        );
      }
      if (day > missionDay!) {
        return (
          type: 'N3',
          text: const ReminderText(
            'New daily missions are in! 🎯',
            'Three fresh missions and a chest are waiting for you.',
          ),
        );
      }
    }
    if (feathers == 2) {
      return (
        type: 'N4',
        text: const ReminderText(
          'One feather to go 🪶',
          'Catch one more golden feather to open the balloon bonus 🎈',
        ),
      );
    }
    if (pieces == 3) {
      return (
        type: 'N5',
        text: const ReminderText(
          'One piece to go 🧩',
          'Find the last puzzle piece to finish your picture and win coins!',
        ),
      );
    }
    final end = weeklyEndsAt;
    if (weeklyUnlocked &&
        end != null &&
        time.isBefore(end) &&
        end.difference(time) < const Duration(hours: 24)) {
      const title = "Last day for this week's course ⏳";
      final best = weeklyBest;
      if (best == null) {
        return (
          type: 'N6c',
          text: const ReminderText(
            title,
            'Same course for everyone, coins at hoops 15, 30, 60 and 120. Give it a go!',
          ),
        );
      }
      for (final tier in [(15, 40), (30, 80), (60, 150), (120, 300)]) {
        if (best < tier.$1) {
          return (
            type: 'N6a',
            text: ReminderText(
              title,
              'Your best: hoop $best. Reach hoop ${tier.$1} for +${tier.$2} coins before it resets!',
            ),
          );
        }
      }
      return (
        type: 'N6b',
        text: ReminderText(
          title,
          'Your best: hoop $best. Can you go even further?',
        ),
      );
    }
    final needed = pointsNeeded;
    final average = averageRunScore;
    if (nextLevelName != null &&
        nextLevelName!.isNotEmpty &&
        needed != null &&
        needed > 0 &&
        average != null &&
        average.isFinite &&
        needed <= average) {
      return (
        type: 'N7',
        text: ReminderText(
          'So close to $nextLevelName! ⭐',
          'Just $needed more points to your next level and its reward.',
        ),
      );
    }
    return null;
  }
}
// endregion

/// The two daily windows of §3.34, in the phone's local time.
enum ReminderSlot {
  /// A random moment between 11:30 and 13:30.
  midday('midday', 11 * 60 + 30, 120),

  /// A random moment between 18:30 and 20:30.
  evening('evening', 18 * 60 + 30, 120);

  const ReminderSlot(this.key, this.startMinute, this.windowMinutes);

  final String key;

  /// Minutes after local midnight when the window opens.
  final int startMinute;

  /// Width of the window in minutes.
  final int windowMinutes;

  int get endMinute => startMinute + windowMinutes;
}

/// What the plugin stores as a notification's payload so the app can tell
/// which message a fired (or still pending) reminder carries.
class ReminderPayload {
  const ReminderPayload({
    required this.messageNumber,
    required this.slot,
    required this.epochMs,
    this.previousLastSent,
    // region P26-G3
    this.type,
    // endregion
  });

  final int messageNumber;
  final ReminderSlot slot;

  /// The scheduled instant, epoch milliseconds.
  final int epochMs;

  /// The message's `lastSent` day *before* this plan (null = it had never
  /// been used). Carried so a still-pending reminder can be given back to the
  /// rotation without losing its earlier use.
  final String? previousLastSent;
  // region P26-G3
  final String? type;
  // endregion

  String encode() => jsonEncode({
    'm': messageNumber,
    's': slot.key,
    't': epochMs,
    // region P26-G3
    if (type != null) 'type': type,
    // endregion
    if (previousLastSent != null) 'p': previousLastSent,
  });

  static ReminderPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final number = json['m'];
      final slot = json['s'];
      final epochMs = json['t'];
      if (number is! int || epochMs is! int || slot is! String) return null;
      final parsed = ReminderSlot.values.firstWhere((s) => s.key == slot);
      return ReminderPayload(
        messageNumber: number,
        slot: parsed,
        epochMs: epochMs,
        previousLastSent: json['p'] is String ? json['p'] as String : null,
        // region P26-G3
        type: json['type'] is String ? json['type'] as String : null,
        // endregion
      );
    } catch (_) {
      return null;
    }
  }
}

/// One planned reminder, ready for [ReminderPlatform.schedule].
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.slot,
    required this.messageNumber,
    required this.time,
    required this.title,
    required this.body,
    this.previousLastSent,
    // region P26-G3
    this.type,
    // endregion
  });

  /// Platform notification id (1..14 for the 7-day window).
  final int id;
  final ReminderSlot slot;
  final int messageNumber;

  /// Absolute local instant the reminder fires at.
  final tz.TZDateTime time;
  final String title;
  final String body;

  /// See [ReminderPayload.previousLastSent].
  final String? previousLastSent;
  // region P26-G3
  final String? type;
  // endregion

  ReminderPayload get payload =>
      ReminderPayload(
        messageNumber: messageNumber,
        slot: slot,
        epochMs: time.millisecondsSinceEpoch,
        previousLastSent: previousLastSent,
        // region P26-G3
        type: type,
        // endregion
      );
}

/// What the scheduler needs to keep between calls (the §3.34 persistence
/// keys: `notifOrder`, `notifPosition`, `notifLastSent`).
class ReminderState {
  const ReminderState({
    required this.order,
    required this.position,
    required this.lastSent,
  });

  /// The shuffled message numbers (a permutation of 1..20).
  final List<int> order;

  /// Index in [order] of the next message to schedule.
  final int position;

  /// Message number -> `yyyy-MM-dd` of the day it was (scheduled to be) sent.
  final Map<int, String> lastSent;

  static const ReminderState empty = ReminderState(
    order: [],
    position: 0,
    lastSent: {},
  );
}

/// A reminder the plugin still has pending from the last plan (read back from
/// the payload at the next reschedule).
class PendingReminder {
  const PendingReminder({
    required this.messageNumber,
    required this.time,
    this.previousLastSent,
  });

  final int messageNumber;
  final DateTime time;

  /// See [ReminderPayload.previousLastSent].
  final String? previousLastSent;
}

/// The result of one scheduling pass.
class ReminderPlan {
  const ReminderPlan({
    required this.reminders,
    required this.state,
    ReminderState? unscheduledState,
  }) : unscheduledState = unscheduledState ?? state;

  final List<ScheduledReminder> reminders;
  final ReminderState state;

  /// §3.34 The state to persist when [reminders] could not be scheduled:
  /// fired messages stay consumed, none of this plan's are (S6-07), so the
  /// next pause / start retries them.
  final ReminderState unscheduledState;
}

/// Pure §3.34 scheduler.
///
/// Given the wall clock, the persisted rotation state, the wallet/best values
/// and what the plugin still has pending, it returns the next 7 days of
/// reminders plus the state to persist. No plugin, no I/O — tests drive it
/// with a fake clock and [PendingReminder]s.
// region P26-G3
class ReminderScheduler {
  ReminderScheduler({Random? random, tz.Location? location})
    : _random = random ?? Random(),
      _zone = location;

  final Random _random;
  final tz.Location? _zone;

  /// The local zone the slots are built in (the device's, once
  /// [Reminders.initialize] resolved it).
  tz.Location get location => _zone ?? tz.local;

  /// §3.34 "When": two slots a day.
  static const int slotsPerDay = 2;

  /// §3.34 "Scheduling": schedule the next 7 days.
  static const int windowDays = 7;

  /// 7 days x 2 slots.
  static const int windowSlots = windowDays * slotsPerDay;

  /// §3.34 "Skip after play": skip a slot in the 2 h after the player played.
  static const Duration skipAfterPlay = Duration(hours: 2);

  /// §3.34 "Order": the same message never comes twice within 10 days.
  static const int noRepeatDays = 10;

  /// §3.34 "When": never between 22:00 and 09:00.
  static const int awakeHourFrom = 9;
  static const int awakeHourTo = 22;

  static const Map<int, ElementId> _elementByMessage = {
    11: ElementId.squeeze,
    13: ElementId.luckySpin,
    16: ElementId.egg,
    19: ElementId.fever,
  };

  /// Builds the next 7 days of reminders (§3.34 "Scheduling").
  ///
  /// [now] is the moment the app is left (+ the app-start pass): it is both
  /// the start of the window and the play time used by the skip-after-play
  /// rule ("the player just played"). [pending] is what the plugin still has
  /// scheduled from the previous pass; its still-future messages are carried
  /// into this plan so that opening the app twice does not burn the order.
  ReminderPlan plan({
    required DateTime now,
    required ReminderState state,
    required int best,
    required int coins,
    Set<ElementId>? metElements,
    // region P26-G3
    ReminderTruth? truth,
    // endregion
    DateTime? lastPlayedAt,
    List<PendingReminder> pending = const [],
  }) {
    final tzNow = tz.TZDateTime.from(now, location);
    final lastSent = Map<int, String>.of(state.lastSent);
    final carried = <PendingReminder>[];
    final carriedNumbers = <int>{};
    for (final p in pending) {
      final at = tz.TZDateTime.from(p.time, location);
      // Still to fire: put its earlier use back (this plan's future date is
      // not a use yet) and carry the message itself into this plan below.
      // region P26-G3
      if (p.messageNumber < 1 || p.messageNumber > ReminderMessages.count) {
        continue;
      }
      // endregion
      if (at.isAfter(tzNow)) {
        if (carriedNumbers.add(p.messageNumber)) carried.add(p);
        final previous = p.previousLastSent;
        if (previous == null) {
          lastSent.remove(p.messageNumber);
        } else {
          lastSent[p.messageNumber] = previous;
        }
      }
    }
    carried.sort((a, b) => a.time.compareTo(b.time));

    final slots = _slots(
      tzNow,
      lastPlayedAt == null ? null : tz.TZDateTime.from(lastPlayedAt, location),
      // region P26-G3
      truth: truth,
      // endregion
    );
    // region P26-G3
    final contextual = {
      for (final slot in slots)
        slot.time.millisecondsSinceEpoch: truth?.textAt(slot.time, slot.slot),
    };
    final genericCount = slots
        .where((s) => contextual[s.time.millisecondsSinceEpoch] == null)
        .length;
    // endregion
    final priorOrder = state.order.isEmpty ? _freshOrder() : state.order;
    final priorPosition = state.position.clamp(0, priorOrder.length);
    // Recover the actual pending sequence from the payloads: after a shuffle
    // it may no longer match the order before the cursor. Move it immediately
    // before the remaining rotation, keeping a permutation of all messages.
    // This also puts any tail that won't fit the new window back at the cursor
    // rather than consuming it without scheduling it.
    final consumed = priorOrder
        .take(priorPosition)
        .where((number) => !carriedNumbers.contains(number))
        .toList();
    final order = [
      ...consumed,
      for (final p in carried) p.messageNumber,
      ...priorOrder
          .skip(priorPosition)
          .where((number) => !carriedNumbers.contains(number)),
    ];
    final unscheduled = ReminderState(
      order: order,
      // cancelAll() removes the previous plan too. Retry its recovered
      // sequence, with the delivered history intact, if replacement fails.
      position: consumed.length,
      lastSent: Map<int, String>.of(lastSent),
    );
    final rotation = _Rotation(
      random: _random,
      order: order,
      position: consumed.length + min(carried.length, genericCount),
      unavailableMessages: _unavailableMessages(metElements),
    );
    final toCarry = carried.take(genericCount).toList();
    for (final p in toCarry) {
      // Carried messages are still in this plan, so a reshuffle while taking
      // a new message must not hand one of them out a second time.
      rotation.reserve(p.messageNumber);
    }

    final reminders = <ScheduledReminder>[];
    // region P26-G3
    var genericIndex = 0;
    // endregion
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      // region P26-G3
      final context = contextual[slot.time.millisecondsSinceEpoch];
      final int number;
      final ReminderText text;
      if (context != null) {
        number = 0; // Contextual copy never consumes the generic rotation.
        text = context.text;
      } else {
        number = genericIndex < toCarry.length
            ? toCarry[genericIndex].messageNumber
            : rotation.take(_dayOf(slot.time), lastSent);
        genericIndex++;
        text = ReminderMessages.textFor(number, best: best, coins: coins);
      }
      // endregion
      final previous = lastSent[number];
      reminders.add(
        ScheduledReminder(
          id: i + 1,
          slot: slot.slot,
          messageNumber: number,
          time: slot.time,
          title: text.title,
          body: text.body,
          previousLastSent: previous,
          // region P26-G3
          type: context?.type ?? 'generic',
          // endregion
        ),
      );
      // region P26-G3
      if (context == null) lastSent[number] = _dayKey(slot.time);
      // endregion
    }

    return ReminderPlan(
      reminders: reminders,
      state: ReminderState(
        order: rotation.order,
        position: rotation.position,
        lastSent: lastSent,
      ),
      unscheduledState: unscheduled,
    );
  }

  List<int> _freshOrder() {
    final order = List<int>.generate(ReminderMessages.count, (i) => i + 1);
    order.shuffle(_random);
    return order;
  }

  static Set<int> _unavailableMessages(Set<ElementId>? metElements) {
    if (metElements == null) return const {};
    return {
      for (final entry in _elementByMessage.entries)
        if (!metElements.contains(entry.value)) entry.key,
    };
  }

  /// The window's slot times: today's remaining slots plus the next days up
  /// to the same wall-clock time 7 days on, skipping (not refilling, S6-06)
  /// anything inside 2 h after play and anything outside 09:00-22:00.
  List<({ReminderSlot slot, tz.TZDateTime time})> _slots(
    tz.TZDateTime now,
    tz.TZDateTime? playedAt, {
    // region P26-G3
    ReminderTruth? truth,
    // endregion
  }) {
    final out = <({ReminderSlot slot, tz.TZDateTime time})>[];
    // §3.34 "schedule the next 7 days": a fixed horizon, so a player who
    // never returns gets seven days and then nothing.
    // region P26-G3
    final horizon = truth == null
        ? tz.TZDateTime(
            location,
            now.year,
            now.month,
            now.day + windowDays,
            now.hour,
            now.minute,
            now.second,
            now.millisecond,
          )
        : tz.TZDateTime(
            location,
            now.year,
            now.month,
            now.day + windowDays + 1,
          );
    // endregion
    for (
      var offset = 0;
      out.length < windowSlots && offset <= windowDays;
      offset++
    ) {
      // Calendar arithmetic on the plain (normalised) date, then the wall
      // clock time in the current zone: a DST change never shifts the window.
      final day = DateTime(now.year, now.month, now.day + offset);
      // region P26-G3
      final lastDay = truth?.lastRunDay;
      final daysAway = lastDay == null
          ? null
          : ReminderTruth.dayOf(day) - lastDay;
      if (truth != null && (daysAway == null || daysAway < 0 || daysAway > 7)) {
        continue;
      }
      // endregion
      for (final slot in ReminderSlot.values) {
        // region P26-G3
        // Keep the evening slot on days 4–7; never refill a skipped slot.
        if (daysAway != null && daysAway >= 4 && slot == ReminderSlot.midday) {
          continue;
        }
        // endregion
        final time = tz.TZDateTime(
          location,
          day.year,
          day.month,
          day.day,
          slot.startMinute ~/ 60,
          slot.startMinute % 60,
        ).add(Duration(minutes: _random.nextInt(slot.windowMinutes)));
        if (!time.isAfter(now)) continue;
        if (time.isAfter(horizon)) continue;
        if (playedAt != null &&
            !time.isBefore(playedAt) &&
            time.difference(playedAt) <= skipAfterPlay) {
          continue;
        }
        if (time.hour < awakeHourFrom || time.hour >= awakeHourTo) continue;
        out.add((slot: slot, time: time));
        if (out.length >= windowSlots) break;
      }
    }
    return out;
  }
}

// endregion

/// The shuffled-order cursor of one plan: hands out the next message that is
/// at least [ReminderScheduler.noRepeatDays] days away from its last use,
/// reshuffling (least recently used first) when the order runs out.
class _Rotation {
  _Rotation({
    required this.random,
    required List<int> order,
    required int position,
    required this.unavailableMessages,
  })
    : order = List<int>.of(order),
      position = position.clamp(0, order.length);

  final Random random;
  List<int> order;
  int position;
  final Set<int> unavailableMessages;
  final Set<int> _used = {};

  /// Keeps a message from an earlier plan out of the fresh part of this one.
  void reserve(int number) => _used.add(number);

  int take(DateTime slotDay, Map<int, String> lastSent) {
    var passes = 0;
    while (passes < 4) {
      if (position >= order.length) {
        order = _reshuffle(lastSent);
        position = 0;
        passes++;
        continue;
      }
      final number = order[position++];
      if (_used.contains(number)) continue;
      if (unavailableMessages.contains(number)) continue;
      if (_blocked(number, slotDay, lastSent)) continue;
      _used.add(number);
      return number;
    }
    // Everything left is within 10 days (only possible when the player has
    // been away long enough that 2 a day beats the 20-message rotation):
    // take the least recently used one.
    final number = _oldest(lastSent);
    _used.add(number);
    return number;
  }

  /// §3.34 "Order": reshuffle, keeping the least recently used messages in
  /// front so a blocked message "moves further back".
  List<int> _reshuffle(Map<int, String> lastSent) {
    final shuffled = List<int>.of(order)..shuffle(random);
    final tieBreak = <int, int>{};
    for (var i = 0; i < shuffled.length; i++) {
      tieBreak[shuffled[i]] = i;
    }
    final out = List<int>.of(shuffled);
    out.sort((a, b) {
      final byAge = (lastSent[a] ?? '').compareTo(lastSent[b] ?? '');
      if (byAge != 0) return byAge;
      return tieBreak[a]!.compareTo(tieBreak[b]!);
    });
    return out;
  }

  int _oldest(Map<int, String> lastSent) {
    final candidates = order
        .where((m) => !_used.contains(m) && !unavailableMessages.contains(m))
        .toList();
    if (candidates.isEmpty) {
      return order.firstWhere((m) => !_used.contains(m), orElse: () => order.first);
    }
    candidates.sort((a, b) {
      final byAge = (lastSent[a] ?? '').compareTo(lastSent[b] ?? '');
      if (byAge != 0) return byAge;
      return a.compareTo(b);
    });
    return candidates.first;
  }

  bool _blocked(int number, DateTime slotDay, Map<int, String> lastSent) {
    final last = lastSent[number];
    if (last == null) return false;
    return _daysBetween(DateTime.parse(last), slotDay) < ReminderScheduler.noRepeatDays;
  }
}

/// Whole days between two calendar dates (UTC arithmetic, so DST never
/// changes the count).
int _daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

DateTime _dayOf(DateTime time) => DateTime(time.year, time.month, time.day);

String _dayKey(DateTime time) =>
    '${time.year.toString().padLeft(4, '0')}-'
    '${time.month.toString().padLeft(2, '0')}-'
    '${time.day.toString().padLeft(2, '0')}';

/// Narrow platform seam over `flutter_local_notifications` (PRD-2 §3.34,
/// ARCH §8: platform code lives behind a small interface so tests never touch
/// a plugin channel).
abstract class ReminderPlatform {
  /// Time zone + plugin + channel + tap handler.
  Future<void> initialize({required void Function(ReminderPayload) onTap});

  /// Asks for the notification permission; null when the OS has no prompt
  /// (Android 12 and lower).
  Future<bool?> requestPermission();

  /// Raw payloads of the reminders the plugin still has scheduled.
  Future<List<String>> pendingPayloads();

  Future<void> cancelAll();

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime time,
    required String payload,
  });
}

/// The real plugin: channel "Reminders" (default importance, the custom
/// "B · Perfect chime" from `res/raw/notif_chime.ogg`), the white bird small
/// icon `ic_notif_bird`, inexact alarms only.
class LocalNotificationsPlatform implements ReminderPlatform {
  LocalNotificationsPlatform({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// §3.34: one channel. A channel's sound is fixed when it is created, so
  /// changing it later needs a new id (e.g. `reminders_v2`).
  static const String channelId = 'reminders';
  static const String channelName = 'Reminders';
  static const String channelDescription = 'Two gentle reminders a day';

  /// `RawResourceAndroidNotificationSound('notif_chime')` (§3.34).
  static const String sound = 'notif_chime';

  /// `res/drawable-*/ic_notif_bird.png`, the white bird silhouette. It is the
  /// only icon on the reminder: there is no large icon beside the text.
  static const String icon = 'ic_notif_bird';

  static const AndroidNotificationDetails _details =
      AndroidNotificationDetails(
        channelId,
        channelName,
        icon: icon,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        sound: RawResourceAndroidNotificationSound(sound),
        playSound: true,
        channelDescription: channelDescription,
      );

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize({
    required void Function(ReminderPayload) onTap,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(icon),
        // iOS is paused (no `ios/` edits and no `notif_chime.caf` yet), so
        // this only registers the tap handler for later.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = ReminderPayload.decode(response.payload);
        if (payload != null) onTap(payload);
      },
    );
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              channelId,
              channelName,
              description: channelDescription,
              importance: Importance.defaultImportance,
              playSound: true,
              sound: RawResourceAndroidNotificationSound(sound),
            ),
          );
    } catch (_) {
      // No Android side (test host, desktop): the channel is a no-op.
    }
    // §3.34 tapping: a cold start from a reminder is reported too.
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        final payload = ReminderPayload.decode(
          details?.notificationResponse?.payload,
        );
        if (payload != null) onTap(payload);
      }
    } catch (_) {
      // Ignore: analytics only.
    }
  }

  @override
  Future<bool?> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    return _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  @override
  Future<List<String>> pendingPayloads() async {
    final pending = await _plugin.pendingNotificationRequests();
    return [
      for (final request in pending)
        if (request.payload != null) request.payload!,
    ];
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime time,
    required String payload,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: time,
      notificationDetails: const NotificationDetails(
        android: _details,
        // iOS is paused: the file comes with the iOS work (ARCH §8).
        iOS: DarwinNotificationDetails(sound: 'notif_chime.caf'),
      ),
      // §3.34: inexact — no exact-alarm permission, a few minutes late is
      // fine inside the two-hour windows.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }
}

/// Records what a [LocalReminders] would hand to the plugin, so the service
/// and permission logic can be tested without touching a channel.
class FakeReminderPlatform implements ReminderPlatform {
  final List<({int id, String title, String body, DateTime time, String payload})>
      scheduled = [];
  final List<String> pending = [];
  int initializeCalls = 0;
  int permissionCalls = 0;
  int cancelCalls = 0;
  bool? permissionResult = true;
  bool throwOnInitialize = false;
  bool throwOnSchedule = false;
  void Function(ReminderPayload onTap)? onTap;

  @override
  Future<void> initialize({
    required void Function(ReminderPayload) onTap,
  }) async {
    initializeCalls++;
    if (throwOnInitialize) throw StateError('no channel');
    this.onTap = onTap;
  }

  @override
  Future<bool?> requestPermission() async {
    permissionCalls++;
    return permissionResult;
  }

  @override
  Future<List<String>> pendingPayloads() async => List.of(pending);

  @override
  Future<void> cancelAll() async {
    cancelCalls++;
    // §3.34: every reschedule cancels the whole plan before laying out the
    // new one, so the fake drops both the records and the pending payloads.
    scheduled.clear();
    pending.clear();
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime time,
    required String payload,
  }) async {
    if (throwOnSchedule) throw StateError('no alarm');
    scheduled.add((
      id: id,
      title: title,
      body: body,
      time: time,
      payload: payload,
    ));
    // A scheduled alarm is a pending one (what `pendingNotificationRequests`
    // reports back on the next reschedule).
    pending.add(payload);
  }

  /// Simulates the OS firing every reminder that is due at [now].
  void deliverDue(DateTime now) =>
      pending.removeWhere((p) => (ReminderPayload.decode(p)?.epochMs ?? 0) <= now.millisecondsSinceEpoch);
}

/// The real service (§3.34): [ReminderScheduler] + [ReminderPlatform] + the
/// persistence keys. Never throws — a failure leaves reminders off.
class LocalReminders implements Reminders {
  LocalReminders({
    required GameStorage storage,
    GameServices? services,
    ReminderPlatform? platform,
    ReminderScheduler? scheduler,
    // region P26-G3
    this.truthSnapshot,
    // endregion
  }) : _store = storage,
       _analytics = services,
       _platform = platform ?? LocalNotificationsPlatform(),
       _scheduler = scheduler ?? ReminderScheduler();

  final GameStorage _store;
  final GameServices? _analytics;
  final ReminderPlatform _platform;
  final ReminderScheduler _scheduler;
  // region P26-G3
  /// Called on every replan, so runs, claims and midnight refreshes replace
  /// all pending promises. Null uses the persisted facts available locally.
  final ReminderTruth Function()? truthSnapshot;
  // endregion

  bool _initializing = false;
  bool _ready = false;
  bool _busy = false;
  bool _askedThisSession = false;

  @override
  Future<void> initialize() async {
    if (_ready || _initializing) return;
    _initializing = true;
    try {
      // The zone is resolved *before* the first [reschedule], so the very
      // first plan is already built in the phone's local time (§3.34 "the
      // slots are recalculated in the current local time zone"), not in the
      // tz package default.
      tzdata.initializeTimeZones();
      await _resolveLocalZone();
      await _platform.initialize(onTap: _logOpened);
      _ready = true;
    } catch (_) {
      // Reminders are optional; never take the game down.
    } finally {
      _initializing = false;
    }
  }

  /// Resolves the device's zone so the slot times are local ones. A failure
  /// keeps whatever zone the package already had (UTC on a bare install).
  Future<void> _resolveLocalZone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Keep the default zone.
    }
  }

  @override
  Future<void> requestPermissionIfNeeded() async {
    if (_askedThisSession || _store.notifPermissionAsked) return;
    _askedThisSession = true;
    if (!_ready) return;
    bool? granted;
    try {
      granted = await _platform.requestPermission();
    } catch (_) {
      granted = null;
    }
    // §3.34: asked once — a decline is final (the player can still enable
    // reminders in the system settings).
    try {
      await _store.saveNotifPermissionAsked(true);
    } catch (_) {
      // Ignore: the in-session flag still stops a second prompt.
    }
    if (granted != null) {
      _analytics?.track('notif_permission', {'granted': granted});
    }
  }

  @override
  Future<void> reschedule() async {
    if (!_ready || _busy) return;
    _busy = true;
    try {
      // §3.34 recalculated in the *current* local zone: the device may have
      // changed zone since [initialize] (S6-05).
      await _resolveLocalZone();
      final now = _store.now();
      var pending = const <PendingReminder>[];
      try {
        pending = [
          for (final raw in await _platform.pendingPayloads())
            if (ReminderPayload.decode(raw) case final payload?)
              PendingReminder(
                messageNumber: payload.messageNumber,
                time: DateTime.fromMillisecondsSinceEpoch(
                  payload.epochMs,
                  isUtc: true,
                ),
                // Give the message back to the rotation with the use it had
                // before this plan, so a still-pending slot never counts as
                // "sent" and never blocks the no-repeat rule.
                previousLastSent: payload.previousLastSent,
              ),
        ];
      } catch (_) {
        // Without the pending list the rotation still advances for the slots
        // that already fired (the order only ever moves forward).
        pending = const [];
      }
      final metElements = <ElementId>{};
      for (final storageId in _store.metElements) {
        final element = ElementId.fromStorageId(storageId);
        if (element != null) metElements.add(element);
      }
      final plan = _scheduler.plan(
        now: now,
        state: ReminderState(
          order: _store.notifOrder,
          position: _store.notifPosition,
          lastSent: _store.notifLastSent,
        ),
        best: _store.bestScore,
        coins: _store.coins,
        metElements: metElements,
        // region P26-G3
        // Legacy installs without any recorded run retain generic slots.
        truth:
            truthSnapshot?.call() ??
            (_store.achLastPlayDay >= 0
                ? ReminderTruth.fromStorage(_store)
                : null),
        // endregion
        // §3.34: a reminder within 2 h of now is skipped — the player just
        // played (this runs when the app is left and at app start).
        lastPlayedAt: now,
        pending: pending,
      );
      try {
        await _platform.cancelAll();
      } catch (_) {
        // Nothing changed on the platform: the persisted state still matches
        // what is pending. The next pause/start retries.
        return;
      }
      var state = plan.state;
      try {
        for (final reminder in plan.reminders) {
          await _platform.schedule(
            id: reminder.id,
            title: reminder.title,
            body: reminder.body,
            time: reminder.time,
            payload: reminder.payload.encode(),
          );
        }
      } catch (_) {
        // S6-07: a failed plan consumes no message. Drop any partial plan
        // and persist the state without it; the next pause/start retries.
        state = plan.unscheduledState;
        try {
          await _platform.cancelAll();
        } catch (_) {
          // Best effort.
        }
      }
      await _store.saveNotifOrder(state.order);
      await _store.saveNotifPosition(state.position);
      await _store.saveNotifLastSent(state.lastSent);
    } finally {
      _busy = false;
    }
  }

  /// §3.34 `notif_opened` (message 1-20, slot midday / evening).
  void _logOpened(ReminderPayload payload) {
    _analytics?.track('notif_opened', {
      'message': payload.messageNumber,
      'slot': payload.slot.key,
      // region P26-G3
      if (payload.type != null) 'type': payload.type!,
      // endregion
    });
  }
}
