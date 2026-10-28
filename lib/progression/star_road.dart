import 'dart:math' as math;

import 'missions.dart';

/// Star Road's calendar uses local civil-day ordinals (see [Missions.localDay]).
/// The caller supplies the shared season epoch; season 1 starts on that day.
const starRoadSeasonDays = 28;
const starRoadStarsPerTier = 8;
const starRoadTierCount = 25;
const starRoadMaxStars = starRoadStarsPerTier * starRoadTierCount;

const starRoadSeasonNames = <String>[
  'SPIKE SPRING',
  'HILLTOP HOP',
  'SUGAR SPIKES',
  'ROOFTOP RUSH',
  'TICK TOCK',
  'PAPER PLANES',
  'BUBBLE BAY',
  'HOOP DREAMS',
  'PENCIL PASS',
  'SLEEPY SKIES',
  'FEATHER STORM',
  'ZERO GRAVITY',
  'SPIKE NIGHT',
];

int starRoadSeasonForDay(int day, {required int epochDay}) {
  if (day < epochDay) throw ArgumentError.value(day, 'day');
  return (day - epochDay) ~/ starRoadSeasonDays + 1;
}

int starRoadDaysLeft(int day, {required int epochDay}) {
  if (day < epochDay) throw ArgumentError.value(day, 'day');
  return starRoadSeasonDays - (day - epochDay) % starRoadSeasonDays;
}

String starRoadSeasonName(int season) {
  if (season < 1) throw ArgumentError.value(season, 'season');
  return starRoadSeasonNames[(season - 1) % starRoadSeasonNames.length];
}

enum StarRoadRewardKind { coins, feather, piece, rare, epic, legendary }

class StarRoadReward {
  const StarRoadReward(this.tier, this.kind, {this.coins = 0});
  final int tier;
  final StarRoadRewardKind kind;

  /// For item tiers, the fallback if no eligible item remains.
  final int coins;
}

StarRoadReward starRoadReward(int tier) {
  const coins = <int, int>{
    1: 25,
    2: 25,
    3: 30,
    4: 30,
    6: 35,
    7: 35,
    8: 40,
    9: 40,
    11: 45,
    12: 45,
    13: 50,
    14: 50,
    16: 55,
    17: 55,
    18: 60,
    19: 60,
    21: 65,
    22: 70,
    23: 70,
    24: 75,
  };
  if (tier < 1 || tier > starRoadTierCount) {
    throw ArgumentError.value(tier, 'tier');
  }
  if (coins.containsKey(tier)) {
    return StarRoadReward(tier, StarRoadRewardKind.coins, coins: coins[tier]!);
  }
  return switch (tier) {
    5 => const StarRoadReward(5, StarRoadRewardKind.feather, coins: 50),
    10 => const StarRoadReward(10, StarRoadRewardKind.rare, coins: 250),
    15 => const StarRoadReward(15, StarRoadRewardKind.piece, coins: 50),
    20 => const StarRoadReward(20, StarRoadRewardKind.epic, coins: 500),
    25 => const StarRoadReward(25, StarRoadRewardKind.legendary, coins: 1000),
    _ => throw StateError('Missing Star Road tier $tier'),
  };
}

/// Immutable state mirroring the four starRoad storage fields. Reward effects
/// are instructions: persist the returned state and apply them together. The
/// caller also persists the rollover summary until it has been shown once.
class StarRoad {
  StarRoad({
    this.season = 0,
    this.xp = 0,
    Set<int> claimed = const {},
    this.popupDay = -1,
  }) : assert(season >= 0),
       assert(xp >= 0 && xp <= starRoadMaxStars),
       claimed = Set.unmodifiable(claimed);

  final int season, xp, popupDay;
  final Set<int> claimed;
  int get tier => math.min(starRoadTierCount, xp ~/ starRoadStarsPerTier);
  int get starsIntoTier =>
      tier == starRoadTierCount ? 0 : xp % starRoadStarsPerTier;
  List<int> get claimable => [
    for (var i = 1; i <= tier; i++)
      if (!claimed.contains(i)) i,
  ];

  /// Rolls forward only. On first join there is no old road to pay; missing
  /// whole seasons never create rewards. Persist effects before discarding them.
  ({StarRoad state, int endedSeason, List<StarRoadReward> rewards}) rollover(
    int currentSeason,
  ) {
    if (currentSeason < 1) {
      throw ArgumentError.value(currentSeason, 'currentSeason');
    }
    if (currentSeason <= season) {
      return (state: this, endedSeason: 0, rewards: const []);
    }
    final rewards = season == 0
        ? <StarRoadReward>[]
        : [for (final t in claimable) starRoadReward(t)];
    return (
      state: StarRoad(season: currentSeason, popupDay: popupDay),
      endedSeason: season,
      rewards: List.unmodifiable(rewards),
    );
  }

  /// Call once with the persisted before/after board for a finished run.
  /// [firstFinishedRun] must come from the persisted local-day run watermark.
  /// The board transition ensures each mission and the all-done bonus pay once.
  StarRoad finishRun({
    required Missions before,
    required Missions after,
    required bool firstFinishedRun,
    bool debug = false,
  }) {
    if (debug || season == 0 || before.day != after.day) return this;
    final prior = {
      for (final m in before.missions) m.template.difficulty: m.complete,
    };
    final next = {
      for (final m in after.missions) m.template.difficulty: m.complete,
    };
    var earned = firstFinishedRun ? 2 : 0;
    for (final difficulty in MissionDifficulty.values) {
      if (next[difficulty] == true && prior[difficulty] == false) {
        earned += difficulty.index + 1;
      }
    }
    if (!before.allDone && after.allDone) earned += 3;
    return StarRoad(
      season: season,
      xp: math.min(starRoadMaxStars, xp + earned),
      claimed: claimed,
      popupDay: popupDay,
    );
  }

  ({StarRoad state, StarRoadReward? reward}) claim(int tierNumber) {
    if (!claimable.contains(tierNumber)) return (state: this, reward: null);
    return (
      state: StarRoad(
        season: season,
        xp: xp,
        claimed: {...claimed, tierNumber},
        popupDay: popupDay,
      ),
      reward: starRoadReward(tierNumber),
    );
  }

  bool shouldShowPopup({required int today, required int runNumber}) =>
      runNumber >= 4 && claimable.isNotEmpty && today > popupDay;

  StarRoad markPopupShown({required int today, required int runNumber}) =>
      shouldShowPopup(today: today, runNumber: runNumber)
      ? StarRoad(season: season, xp: xp, claimed: claimed, popupDay: today)
      : this;
}
