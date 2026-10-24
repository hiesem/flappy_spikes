/// The C2 Home popup priority order.
enum HomeMoment {
  streakLost,
  levelUp,
  streakReward,
  leaderboardCollect,
  missionsChest,
  starRoad,
  noAds,
  rating,
}

/// Routes one eligible Home moment. The M1 policy is deliberately
/// pass-through: it invokes exactly the callback passed by the existing flow.
abstract class HomeMoments {
  const HomeMoments();

  void show(HomeMoment moment, void Function() open);
}

class PassthroughHomeMoments extends HomeMoments {
  const PassthroughHomeMoments();

  @override
  void show(HomeMoment moment, void Function() open) => open();
}
