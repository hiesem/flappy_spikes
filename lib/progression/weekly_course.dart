import '../run/config/tuning_values.dart';
import '../run/run_setup.dart';

/// One worldwide ISO week. All G5 consumers (including reminders) use this
/// clock, rather than local calendar dates. The seed salt is compiled in.
class WeeklyWeek {
  WeeklyWeek.at(DateTime instant) {
    final utc = instant.toUtc();
    final date = DateTime.utc(utc.year, utc.month, utc.day);
    startsAt = date.subtract(Duration(days: date.weekday - DateTime.monday));
    endsAt = startsAt.add(const Duration(days: 7));
    final thursday = startsAt.add(const Duration(days: 3));
    year = thursday.year;
    final jan4 = DateTime.utc(year, 1, 4);
    final firstMonday = jan4.subtract(Duration(days: jan4.weekday - 1));
    week = startsAt.difference(firstMonday).inDays ~/ 7 + 1;
  }

  late final DateTime startsAt;
  late final DateTime endsAt;
  late final int year;
  late final int week;
  String get key => '$year-W${week.toString().padLeft(2, '0')}';

  /// FNV-1a over a fixed ASCII encoding; no platform-dependent hashCode.
  int get seed {
    var hash = 0x811c9dc5;
    for (final byte in 'flappy-spikes-weekly-v1:$key'.codeUnits) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  Duration remaining(DateTime instant) {
    final left = endsAt.difference(instant.toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  bool lastDay(DateTime instant) =>
      remaining(instant) > Duration.zero &&
      remaining(instant) < const Duration(days: 1);

  int daysLeft(DateTime instant) =>
      (remaining(instant).inMicroseconds / Duration.microsecondsPerDay).ceil();

  String countdown(DateTime instant) => lastDay(instant)
      ? 'LAST DAY'
      : '${daysLeft(instant)} DAY${daysLeft(instant) == 1 ? '' : 'S'} LEFT';

  RunSetup setup({required double viewHeight}) => RunSetup(
    seed: seed,
    viewHeight: viewHeight,
    weekly: true,
    weeklyStartedAt: startsAt,
  );
}

/// G5's immutable model. [weeklyBest] uses the S0 storage map as a single
/// {ISO-week-key: best-hoops} entry; retaining that key also anchors the rewards
/// set. Persist refreshes before displaying a new week. Older clock readings
/// never reset the state or reopen paid tiers.
class WeeklyCourse {
  WeeklyCourse({
    Map<String, int> weeklyBest = const {},
    Set<int> weeklyRewards = const {},
  }) : weeklyBest = Map.unmodifiable(weeklyBest),
       weeklyRewards = Set.unmodifiable(weeklyRewards);

  final Map<String, int> weeklyBest;
  final Set<int> weeklyRewards;

  static bool unlocked({required int gamesPlayed, required int bestHoops}) =>
      gamesPlayed >= 6 && bestHoops >= 40;

  String? get weekKey =>
      weeklyBest.isEmpty ? null : (weeklyBest.keys.toList()..sort()).last;
  int get bestHoops => weeklyBest[weekKey] ?? 0;

  WeeklyCourse refresh(DateTime now) {
    final key = WeeklyWeek.at(now).key;
    final stored = weekKey;
    if (stored != null && key.compareTo(stored) <= 0) return this;
    return WeeklyCourse(weeklyBest: {key: 0});
  }

  /// Finish against the week frozen at START. A run crossing Monday belongs
  /// to the old course and cannot set the new week's best or earn its tiers.
  /// Returned rewards are instructions for the payout caller: persist the
  /// returned state with its payout before applying/presenting coins.
  WeeklyCourseResult finishRun({
    required DateTime now,
    required WeeklyWeek startedWeek,
    required int hoops,
    bool debug = false,
    TuningValues? tuning,
  }) {
    final current = refresh(now);
    if (debug ||
        hoops < 0 ||
        startedWeek.key != WeeklyWeek.at(now).key ||
        startedWeek.key != current.weekKey) {
      return WeeklyCourseResult(current, const {});
    }
    final best = hoops > current.bestHoops ? hoops : current.bestHoops;
    final rewards =
        (tuning ?? TuningValues.current).raw('weekly_rewards') as Map;
    final earned = <int, int>{};
    for (final entry in rewards.entries) {
      final tier = int.parse(entry.key as String);
      if (best >= tier && !current.weeklyRewards.contains(tier)) {
        earned[tier] = (entry.value as num).toInt();
      }
    }
    return WeeklyCourseResult(
      WeeklyCourse(
        weeklyBest: {startedWeek.key: best},
        weeklyRewards: {...current.weeklyRewards, ...earned.keys},
      ),
      earned,
    );
  }
}

class WeeklyCourseResult {
  WeeklyCourseResult(this.course, Map<int, int> rewards)
    : rewards = Map.unmodifiable(rewards);

  final WeeklyCourse course;
  final Map<int, int> rewards;
  int get coins => rewards.values.fold(0, (sum, coins) => sum + coins);
}
