/// Every in-run element of the PRD-2 catalogue (§3.0.7) with a stable id.
///
/// Pure Dart (no Flame): the run director, storage (`metElements`) and the
/// debug force menu all key on [ElementId]. The [storageId] is persisted —
/// never rename one.
library;

/// How an element enters a run (§3.0.7 "Kind").
enum ElementKind {
  /// Occupies a hoop slot (normal and special hoops).
  slot,

  /// A modifier on a normal hoop (tilt, movement).
  modifier,

  /// Floats in a gap (optional or scheduled gap items).
  gap,

  /// A scheduled slot (portal, comet hoop).
  schedule,

  /// A timed run event (spike squeeze).
  event,

  /// Armed on the home screen before a run (Big Hoops).
  starter,

  /// Run-wide systems that are never spawned (streak, coins, rumble, …).
  meta,
}

/// Every catalogue element (§3.0.7) plus the two follow-up gap items the
/// director places for running collectables (piggy coins, firefly swarms).
///
/// [firstPossible] is the first hoop / gap index (§3.0.3) at which the
/// element may appear; `null` = never spawned by the director.
/// [firstMeet] = the director forces it once when never met (§3.0.8).
enum ElementId {
  normalHoop('normal_hoop', ElementKind.slot, 0, false),
  angledRing('angled_ring', ElementKind.modifier, 10, true),
  movingRing('moving_ring', ElementKind.modifier, 20, true),
  bullseye('bullseye', ElementKind.slot, 6, true),
  train('train', ElementKind.slot, 8, true),
  spring('spring', ElementKind.slot, 10, true),
  switchRing('switch_ring', ElementKind.slot, 12, true),
  pair('pair', ElementKind.slot, 12, true),
  fever('fever', ElementKind.slot, 15, true),
  luckySpin('lucky_spin', ElementKind.slot, 15, true),
  saw('saw', ElementKind.slot, 20, true),
  portal('portal', ElementKind.schedule, 25, true),
  comet('comet', ElementKind.schedule, 10, true),
  heart('heart', ElementKind.gap, 3, false),
  shield('shield', ElementKind.gap, 12, true),
  starTrail('star_trail', ElementKind.gap, 5, true),
  capsule('capsule', ElementKind.gap, 10, false),
  hourglass('hourglass', ElementKind.gap, 10, true),
  miniBird('mini_bird', ElementKind.gap, 10, true),
  coinFrenzy('coin_frenzy', ElementKind.gap, 10, true),
  egg('egg', ElementKind.gap, 10, true),
  piggy('piggy', ElementKind.gap, 12, true),
  jar('jar', ElementKind.gap, 15, true),
  feather('feather', ElementKind.gap, 3, false),
  puzzlePiece('puzzle_piece', ElementKind.gap, 14, false),
  squeeze('squeeze', ElementKind.event, null, false),
  bigHoops('big_hoops', ElementKind.starter, null, false),
  perfectStreak('perfect_streak', ElementKind.meta, null, false),
  coins('coins', ElementKind.meta, null, false),
  rumble('rumble', ElementKind.meta, null, false),
  revive('revive', ElementKind.meta, null, false),
  results('results', ElementKind.meta, null, false),
  versus('versus', ElementKind.meta, null, false),
  // Follow-up items of a running Piggy Bank / Firefly Jar (§3.0.3 gap order
  // 1). Not catalogue rows of their own.
  piggyCoins('piggy_coins', ElementKind.gap, null, false),
  fireflySwarm('firefly_swarm', ElementKind.gap, null, false),
  // region anchors — append below (one value per WP, with a `// WP-x` note)
  // endregion anchors
  ;

  const ElementId(this.storageId, this.kind, this.firstPossible, this.firstMeet);

  /// Stable snake_case id (storage `metElements`, analytics).
  final String storageId;
  final ElementKind kind;
  final int? firstPossible;

  /// Forced within 5 slots / gaps once [firstPossible] is reached and the
  /// player has never met it (§3.0.8).
  final bool firstMeet;

  /// Decided in a hoop slot (special hoops, portal, comet hoop, modifiers).
  bool get isSlotElement =>
      kind == ElementKind.slot ||
      kind == ElementKind.schedule ||
      kind == ElementKind.modifier;

  /// Decided in a gap.
  bool get isGapElement => kind == ElementKind.gap;

  /// The capsule powerups (§3.30–3.32).
  bool get isCapsuleType =>
      this == hourglass || this == miniBird || this == coinFrenzy;

  static ElementId? fromStorageId(String id) {
    for (final e in values) {
      if (e.storageId == id) return e;
    }
    return null;
  }
}
