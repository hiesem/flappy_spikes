import 'dart:math';

import '../run/elements.dart';

/// Daily missions, PRD G1 / O28 / O32 and texts.html §1.
/// No clock, storage, wallet, ad or UI side effects: callers persist the returned
/// state through missionDay / missionTier / missionRerollDay / missions.
enum MissionDifficulty { easy, medium, hard }

enum MissionTemplate {
  m01(MissionDifficulty.easy, [3, 3, 4, 5]),
  m02(MissionDifficulty.easy, [40, 80, 150, 300]),
  m03(MissionDifficulty.medium, [15, 30, 60, 120]),
  m04(MissionDifficulty.medium, [40, 80, 150, 300]),
  m05(MissionDifficulty.medium, [2, 3, 4, 6]),
  m06(MissionDifficulty.medium, [1, 1, 2, 3]),
  m07(MissionDifficulty.medium, [1, 1, 1, 2]),
  m08(MissionDifficulty.medium, [1, 2, 3, 5]),
  m09(MissionDifficulty.medium, [2, 3, 5, 8]),
  m10(MissionDifficulty.medium, [1, 1, 2, 3]),
  m11(MissionDifficulty.hard, [10, 20, 40, 80]),
  m12(MissionDifficulty.hard, [4, 6, 10, 15]),
  m13(MissionDifficulty.hard, [5, 10, 20, 35]),
  m14(MissionDifficulty.hard, [0, 1, 2, 3]),
  m15(MissionDifficulty.hard, [0, 20, 40, 80]);

  const MissionTemplate(this.difficulty, this.targets);
  final MissionDifficulty difficulty;
  final List<int> targets;
  String get id => name.toUpperCase();
  String textId(int tier) => '$id-T$tier';
  bool get modeOnly => this == m10;
  bool get oneRun => const {m11, m12, m13, m15}.contains(this);

  bool available(int tier, MissionEligibility eligibility) {
    if (targets[tier] == 0) return false;
    final met = eligibility.metElements;
    bool any(Set<ElementId> elements) => elements.any(met.contains);
    return switch (this) {
      m05 => any(const {
        ElementId.capsule,
        ElementId.hourglass,
        ElementId.miniBird,
        ElementId.coinFrenzy,
        ElementId.shield,
        ElementId.comet,
        ElementId.pair,
      }),
      m06 => any(const {ElementId.comet, ElementId.portal}),
      m07 => any(const {ElementId.feather, ElementId.puzzlePiece}),
      m08 => met.contains(ElementId.bullseye),
      m09 => met.contains(ElementId.switchRing),
      m10 => eligibility.online && eligibility.lastVersusHadRival,
      m14 => met.contains(ElementId.squeeze),
      // A world has no ElementId; reaching its boundary is evidence it was met.
      m15 => eligibility.bestHoops >= targets[tier],
      _ => true,
    };
  }
}

class MissionEligibility {
  MissionEligibility({
    required this.bestHoops,
    Set<ElementId> metElements = const {},
    this.online = false,
    this.lastVersusHadRival = false,
  }) : metElements = Set.unmodifiable(metElements);
  final int bestHoops;
  final Set<ElementId> metElements;
  final bool online;
  final bool lastVersusHadRival;
}

/// Totals for one finished run, including both sides of every revive. All modes
/// use the same counters; versusWins is 1 only for a win against a real rival.
/// inRunCoins excludes meta rewards, shop grants and post-run win bonuses.
/// maxNoRimChain includes perfect and non-perfect passes, resetting at a rim hit.
class MissionRunCounts {
  const MissionRunCounts({
    required this.gamesPlayedBefore,
    this.debug = false,
    this.hoops = 0,
    this.perfectPasses = 0,
    this.inRunCoins = 0,
    this.hourglasses = 0,
    this.miniBirds = 0,
    this.coinFrenzies = 0,
    this.shieldPickups = 0,
    this.cometStars = 0,
    this.pairGifts = 0,
    this.cometRides = 0,
    this.portalRides = 0,
    this.feathers = 0,
    this.pieces = 0,
    this.bullseyes = 0,
    this.openedSwitches = 0,
    this.versusWins = 0,
    this.maxPerfectStreak = 0,
    this.maxNoRimChain = 0,
    this.squeezesSurvived = 0,
  });
  final int gamesPlayedBefore;
  final bool debug;
  final int hoops, perfectPasses, inRunCoins;
  final int hourglasses, miniBirds, coinFrenzies, shieldPickups;
  final int cometStars, pairGifts, cometRides, portalRides;
  final int feathers, pieces, bullseyes, openedSwitches, versusWins;
  final int maxPerfectStreak, maxNoRimChain, squeezesSurvived;

  int count(MissionTemplate template) => max(0, switch (template) {
    MissionTemplate.m01 => 1,
    MissionTemplate.m02 || MissionTemplate.m11 || MissionTemplate.m15 => hoops,
    MissionTemplate.m03 => perfectPasses,
    MissionTemplate.m04 => inRunCoins,
    // O32: no hearts, armed Big Hoops, extra life or streak-gift starts.
    MissionTemplate.m05 =>
      hourglasses +
          miniBirds +
          coinFrenzies +
          shieldPickups +
          cometStars +
          pairGifts,
    MissionTemplate.m06 => cometRides + portalRides,
    MissionTemplate.m07 => feathers + pieces,
    MissionTemplate.m08 => bullseyes,
    MissionTemplate.m09 => openedSwitches,
    MissionTemplate.m10 => versusWins,
    MissionTemplate.m12 => maxPerfectStreak,
    MissionTemplate.m13 => maxNoRimChain,
    MissionTemplate.m14 => squeezesSurvived,
  });
}

class MissionProgress {
  const MissionProgress({
    required this.template,
    required this.target,
    this.progress = 0,
    this.paid = false,
  });
  final MissionTemplate template;
  final int target, progress;
  final bool paid;
  bool get complete => progress >= target;

  MissionProgress advance(MissionRunCounts run) => MissionProgress(
    template: template,
    target: target,
    paid: paid,
    progress: min(
      target,
      template.oneRun
          ? max(progress, run.count(template))
          : progress + run.count(template),
    ),
  );

  Map<String, Object?> toRecord() => {
    'id': template.id,
    'target': target,
    'progress': progress,
    'paid': paid,
  };

  factory MissionProgress.fromRecord(Map<String, Object?> record) =>
      MissionProgress(
        template: MissionTemplate.values.firstWhere(
          (t) => t.id == record['id'],
        ),
        target: record['target'] as int,
        progress: record['progress'] as int? ?? 0,
        paid: record['paid'] == true,
      );
}

enum MissionChestKind { feather, piece, coins }

class MissionChestReward {
  const MissionChestReward(this.kind, this.amount);
  final MissionChestKind kind;
  final int amount;
}

class Missions {
  Missions({
    this.day = -1,
    this.tier = 0,
    this.rerollDay = -1,
    List<MissionProgress> missions = const [],
    this.previousHard,
    Set<MissionTemplate> usedTemplates = const {},
    this.chestClaimed = false,
  }) : missions = List.unmodifiable(missions),
       usedTemplates = Set.unmodifiable({
         ...usedTemplates,
         for (final m in missions) m.template,
       });

  final int day, tier, rerollDay;
  final List<MissionProgress> missions;
  final MissionTemplate? previousHard;
  final Set<MissionTemplate> usedTemplates;
  final bool chestClaimed;
  bool get allDone => missions.length == 3 && missions.every((m) => m.complete);
  bool get chestPending => allDone && !chestClaimed;

  static int tierFor(int bestHoops) => bestHoops < 15
      ? 0
      : bestHoops < 40
      ? 1
      : bestHoops < 100
      ? 2
      : 3;

  /// Civil local-day ordinal, not elapsed 24-hour intervals (DST safe). Pass a
  /// local DateTime, or a civil date in the desired zone, not a UTC instant.
  static int localDay(DateTime local) =>
      DateTime.utc(local.year, local.month, local.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  Missions roll({
    required int today,
    required int gamesPlayed,
    required MissionEligibility eligibility,
  }) {
    if (gamesPlayed < 3 || today <= day) return this;
    final nextTier = tierFor(eligibility.bestHoops);
    final yesterdayHard = today == day + 1
        ? missions
              .where((m) => m.template.difficulty == MissionDifficulty.hard)
              .firstOrNull
              ?.template
        : null;
    final random = Random(today);
    final rolled = <MissionProgress>[];
    for (final difficulty in MissionDifficulty.values) {
      final candidates = MissionTemplate.values
          .where(
            (t) =>
                t.difficulty == difficulty &&
                t != yesterdayHard &&
                t.available(nextTier, eligibility),
          )
          .toList();
      final chosen = candidates[random.nextInt(candidates.length)];
      rolled.add(
        MissionProgress(template: chosen, target: chosen.targets[nextTier]),
      );
    }
    return Missions(
      day: today,
      tier: nextTier,
      rerollDay: rerollDay,
      missions: rolled,
      previousHard: yesterdayHard,
    );
  }

  Missions advance(MissionRunCounts run) {
    if (run.debug || run.gamesPlayedBefore < 3) return this;
    return _copy(missions: [for (final m in missions) m.advance(run)]);
  }

  /// Pure payout transition: persist this state together with the wallet credit
  /// in the run-end transaction. Replaying a persisted paid state pays nothing.
  /// This model performs no wallet writes (G1b owns durable application).
  ({Missions state, int coins, List<MissionTemplate> completed}) claimCoins({
    List<int> rewards = const [20, 35, 55],
  }) {
    final completed = <MissionTemplate>[];
    var coins = 0;
    final updated = <MissionProgress>[];
    for (final m in missions) {
      if (m.complete && !m.paid) {
        coins += rewards[m.template.difficulty.index];
        completed.add(m.template);
        updated.add(
          MissionProgress(
            template: m.template,
            target: m.target,
            progress: m.progress,
            paid: true,
          ),
        );
      } else {
        updated.add(m);
      }
    }
    return (
      state: _copy(missions: updated),
      coins: coins,
      completed: List.unmodifiable(completed),
    );
  }

  static MissionChestReward chestReward({
    required int feathers,
    required int pieces,
    int coins = 40,
  }) => feathers <= 1
      ? const MissionChestReward(MissionChestKind.feather, 1)
      : pieces <= 2
      ? const MissionChestReward(MissionChestKind.piece, 1)
      : MissionChestReward(MissionChestKind.coins, coins);

  ({Missions state, MissionChestReward? reward}) claimChest({
    required int feathers,
    required int pieces,
    int coins = 40,
  }) => chestPending
      ? (
          state: _copy(chestClaimed: true),
          reward: chestReward(feathers: feathers, pieces: pieces, coins: coins),
        )
      : (state: this, reward: null);

  bool canReroll(int index, int today) =>
      today == day &&
      rerollDay < today &&
      index >= 0 &&
      index < missions.length &&
      !missions[index].complete;

  /// Call only after a completed rewarded ad. A failed/no-fill ad never calls
  /// this transition. Keeps difficulty, tier and all other rows unchanged.
  Missions reroll({
    required int index,
    required int today,
    required MissionEligibility eligibility,
  }) {
    if (!canReroll(index, today)) return this;
    final candidates = rerollCandidates(index, today, eligibility);
    if (candidates.isEmpty) return this;
    final chosen =
        candidates[Random(day ^ 0x7265726f ^ index).nextInt(candidates.length)];
    final updated = [...missions];
    updated[index] = MissionProgress(
      template: chosen,
      target: chosen.targets[tier],
    );
    return _copy(
      missions: updated,
      rerollDay: today,
      usedTemplates: {...usedTemplates, chosen},
    );
  }

  /// Inspect before requesting an ad. The approved M12/M13 same-day exclusion
  /// can exhaust the hard pool when yesterday's hard was M11 (especially T0).
  /// That PRD conflict must be resolved by the orchestrator; never silently
  /// relax the pool rules or consume an ad allowance with no replacement.
  List<MissionTemplate> rerollCandidates(
    int index,
    int today,
    MissionEligibility eligibility,
  ) {
    if (!canReroll(index, today)) return const [];
    final old = missions[index];
    final others = [
      for (var i = 0; i < missions.length; i++)
        if (i != index) missions[i].template,
    ];
    return MissionTemplate.values
        .where(
          (t) =>
              t.difficulty == old.template.difficulty &&
              !usedTemplates.contains(t) &&
              t != previousHard &&
              t.available(tier, eligibility) &&
              !(t.modeOnly && others.any((o) => o.modeOnly)) &&
              !(t == MissionTemplate.m12 &&
                  usedTemplates.contains(MissionTemplate.m13)) &&
              !(t == MissionTemplate.m13 &&
                  usedTemplates.contains(MissionTemplate.m12)),
        )
        .toList();
  }

  Missions _copy({
    List<MissionProgress>? missions,
    int? rerollDay,
    Set<MissionTemplate>? usedTemplates,
    bool? chestClaimed,
  }) => Missions(
    day: day,
    tier: tier,
    rerollDay: rerollDay ?? this.rerollDay,
    missions: missions ?? this.missions,
    previousHard: previousHard,
    usedTemplates: usedTemplates ?? this.usedTemplates,
    chestClaimed: chestClaimed ?? this.chestClaimed,
  );

  /// Metadata lives inside the existing `missions` JSON; no extra storage key.
  List<Map<String, Object?>> toRecords() => [
    for (var i = 0; i < missions.length; i++)
      {
        ...missions[i].toRecord(),
        if (i == 0)
          'meta': {
            'previousHard': previousHard?.id,
            'used': [
              for (final t in MissionTemplate.values)
                if (usedTemplates.contains(t)) t.id,
            ],
            'chestClaimed': chestClaimed,
          },
      },
  ];

  factory Missions.fromRecords({
    required int day,
    required int tier,
    required int rerollDay,
    required List<Map<String, Object?>> records,
  }) {
    final meta = records.isEmpty
        ? const <String, Object?>{}
        : (records.first['meta'] as Map?) ?? const <String, Object?>{};
    return Missions(
      day: day,
      tier: tier,
      rerollDay: rerollDay,
      missions: records.map(MissionProgress.fromRecord).toList(),
      previousHard: MissionTemplate.values
          .where((t) => t.id == meta['previousHard'])
          .firstOrNull,
      usedTemplates: {
        for (final t in MissionTemplate.values)
          if ((meta['used'] as List? ?? const []).contains(t.id)) t,
      },
      chestClaimed: meta['chestClaimed'] == true,
    );
  }
}
