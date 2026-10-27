import 'package:flappy_spikes/progression/weekly_course.dart';
import 'package:flappy_spikes/run/run_setup.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUp(tzdata.initializeTimeZones);
  final monday = DateTime.utc(2026, 10, 26);
  final before = monday.subtract(const Duration(microseconds: 1));

  for (final zone in [
    'UTC',
    'Europe/Amsterdam',
    'America/Los_Angeles',
    'Asia/Kolkata',
    'Pacific/Auckland',
    'Pacific/Honolulu',
  ]) {
    test('Monday 00:00 UTC seed, countdown and reset in $zone (O30)', () {
      final location = tz.getLocation(zone);
      final localBefore = tz.TZDateTime.from(before, location);
      final localAfter = tz.TZDateTime.from(monday, location);
      final old = WeeklyWeek.at(localBefore);
      final next = WeeklyWeek.at(localAfter);
      expect(old.key, '2026-W43');
      expect(next.key, '2026-W44');
      expect(old.seed, isNot(next.seed));
      expect(next.seed, WeeklyWeek.at(monday).seed);
      expect(old.remaining(localBefore), const Duration(microseconds: 1));
      expect(old.countdown(localBefore), 'LAST DAY');
      expect(next.remaining(localAfter), const Duration(days: 7));
      expect(next.countdown(localAfter), '7 DAYS LEFT');
      final prior = WeeklyCourse(
        weeklyBest: {old.key: 120},
        weeklyRewards: {15, 30, 60, 120},
      );
      expect(prior.refresh(localBefore), same(prior));
      final reset = prior.refresh(localAfter);
      expect(reset.weeklyBest, {next.key: 0});
      expect(reset.weeklyRewards, isEmpty);
      expect(reset.refresh(localAfter), same(reset));
    });
  }

  test('ISO week-year changes at the right Monday, including week 53', () {
    expect(WeeklyWeek.at(DateTime.utc(2021, 1, 1)).key, '2020-W53');
    expect(WeeklyWeek.at(DateTime.utc(2021, 1, 4)).key, '2021-W01');
    expect(WeeklyWeek.at(DateTime.utc(2025, 12, 29)).key, '2026-W01');
    expect(WeeklyWeek.at(DateTime.utc(2027, 1, 3)).key, '2026-W53');
    expect(WeeklyWeek.at(DateTime.utc(2027, 1, 4)).key, '2027-W01');
  });

  test('all countdowns use actual time left, including the final 24h', () {
    final week = WeeklyWeek.at(monday);
    final sunday = monday.add(const Duration(days: 6));
    expect(week.daysLeft(sunday), 1);
    expect(week.lastDay(sunday), isFalse); // N6 is strictly <24h.
    expect(week.countdown(sunday), '1 DAY LEFT');
    expect(week.lastDay(sunday.add(const Duration(microseconds: 1))), isTrue);
    expect(week.daysLeft(monday.add(const Duration(hours: 97))), 3);
    expect(
      week.remaining(week.endsAt.add(const Duration(seconds: 1))),
      Duration.zero,
    );
    expect(
      WeeklyWeek.at(week.endsAt).remaining(week.endsAt),
      const Duration(days: 7),
    );
  });

  test('seed is fixed across clients, times of day and years', () {
    final week = WeeklyWeek.at(monday);
    expect(week.seed, 1230384827); // Stable compiled-salt hash fixture.
    expect(WeeklyWeek.at(monday.add(const Duration(days: 6))).seed, week.seed);
    expect(WeeklyWeek.at(DateTime.utc(2027, 11, 1)).seed, isNot(week.seed));
  });

  test('unlock requires both six completed games and 40 hoops in 2.6', () {
    expect(WeeklyCourse.unlocked(gamesPlayed: 5, bestHoops: 120), isFalse);
    expect(WeeklyCourse.unlocked(gamesPlayed: 6, bestHoops: 39), isFalse);
    expect(WeeklyCourse.unlocked(gamesPlayed: 6, bestHoops: 40), isTrue);
  });

  test('tiers pay once, cumulatively, survive hydration, max 570/week', () {
    final week = WeeklyWeek.at(monday);
    var course = WeeklyCourse();
    var total = 0;
    for (final (hoops, coins) in [
      (14, 0),
      (15, 40),
      (15, 0),
      (60, 230),
      (30, 0),
      (120, 300),
      (500, 0),
    ]) {
      final result = course.finishRun(
        now: monday,
        startedWeek: week,
        hoops: hoops,
      );
      expect(result.coins, coins);
      total += result.coins;
      course = WeeklyCourse(
        weeklyBest: result.course.weeklyBest,
        weeklyRewards: result.course.weeklyRewards,
      );
    }
    expect(total, 570);
    expect(course.bestHoops, 500);
    expect(course.weeklyRewards, {15, 30, 60, 120});
    final next = monday.add(const Duration(days: 7));
    final nextResult = course.finishRun(
      now: next,
      startedWeek: WeeklyWeek.at(next),
      hoops: 120,
    );
    expect(nextResult.coins, 570);
    expect(nextResult.course.bestHoops, 120);
  });

  test(
    'debug, negative, expired runs and clock rollback cannot earn tiers',
    () {
      final week = WeeklyWeek.at(monday);
      final result = WeeklyCourse().finishRun(
        now: monday,
        startedWeek: week,
        hoops: 120,
      );
      final course = result.course;
      for (final debug in [true, false]) {
        expect(
          course
              .finishRun(
                now: monday,
                startedWeek: week,
                hoops: debug ? 999 : -1,
                debug: debug,
              )
              .coins,
          0,
        );
      }
      final next = monday.add(const Duration(days: 7));
      final expired = course.finishRun(
        now: next,
        startedWeek: week,
        hoops: 999,
      );
      expect(expired.coins, 0);
      expect(expired.course.bestHoops, 0);
      final rolledBack = expired.course.finishRun(
        now: monday,
        startedWeek: week,
        hoops: 999,
      );
      expect(rolledBack.coins, 0);
      expect(rolledBack.course.weekKey, WeeklyWeek.at(next).key);
    },
  );

  test(
    'weekly setup excludes starters and allows every gate without debug',
    () {
      const setup = RunSetup(
        seed: 7,
        viewHeight: 711,
        weekly: true,
        starter: Powerup.shield,
        extraStarters: [Powerup.bigHoops],
      );
      expect(setup.starter, Powerup.none);
      expect(setup.extraStarters, isEmpty);
      expect(setup.gatesOpen, isTrue);
      expect(setup.ignoreGates, isFalse);
      expect(setup.allowsRevive, isFalse);
      expect(setup.submissionMode('versus'), 'weekly');
      final normal = const RunSetup(seed: 7, viewHeight: 711);
      expect(normal.gatesOpen, isFalse);
      expect(normal.allowsRevive, isTrue);
      expect(normal.submissionMode('free_fly'), 'free_fly');
      final week = WeeklyWeek.at(monday);
      expect(week.setup(viewHeight: 568).seed, week.seed);
    },
  );
}
