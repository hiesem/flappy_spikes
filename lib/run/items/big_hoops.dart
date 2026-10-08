import '../../menu/powerup_slot.dart';
import '../director/plans.dart';
import '../hoops/hoop.dart';
import '../hoops/ring_painter.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_state.dart';

/// Big Hoops, run side (PRD-2 §3.0.1, §3.6, §5.1).
///
/// Armed from the home slot (`RunSetup.starter == Powerup.bigHoops`; the
/// game consumed it and sent `big_hoops_used`). At attach — before the
/// first hoop is planned — the run rolls D = 30–40 s on the director's
/// `timing` stream and sets `RunState.bigHoops`. The director scales every
/// slot's opening by `BigHoopsState.mult(runClock)` at spawn time (1.5
/// until D − 8 s, easing 1.5 → 1.0 over the last 8 s, 1 after D), capped so
/// the hoop still fits the band — a hoop never changes size on screen.
/// Every hoop kind grows; this feature paints the normal hoops spawned with
/// a multiplier > 1 gold (`#FFB529` / `#D48A00`); special kinds keep their
/// own look. No in-game indicator; boosted runs count for everything.
class BigHoopsFeature extends RunFeature {
  RunContext? _c;

  /// Hoops this run painted gold (the streak tier look, WP-2b, may layer on
  /// top and should fall back to gold for these).
  static final Expando<bool> _gold = Expando('bigHoopsGold');

  /// True when [h] was spawned gold by Big Hoops.
  static bool isGold(Hoop h) => _gold[h] ?? false;

  @override
  void attach(RunContext c) {
    _c = c;
    if (c.run.setup.starter == Powerup.bigHoops) {
      c.s.bigHoops = BigHoopsState(
        duration: c.director.rollBigHoopsDuration(),
        start: c.s.runClock,
      );
    }
    c.events.on<HoopSpawned>(_onSpawn);
  }

  void _onSpawn(HoopSpawned e) {
    final c = _c;
    if (c == null) return;
    final b = c.s.bigHoops;
    if (b == null) return;
    if (b.mult(c.s.runClock) <= 1) return;
    if (e.plan.kind != HoopKindId.normal) return;
    e.hoop.look.colors = RingColors.gold;
    _gold[e.hoop] = true;
  }

  @override
  void update(double gameDt, double realDt) {
    final c = _c;
    if (c == null) return;
    // WP-2d fix: the Big Hoops gold re-applies every frame while its hoops
    // are on screen (gold and tier-2 gold share a colour, so a broken
    // streak could otherwise drop them back to the skin); only the miss
    // flash's ghost wins over it.
    for (final h in c.run.spawner.hoops) {
      if (!isGold(h) || h.look.missed) continue;
      if (h.look.colors != RingColors.gold) h.look.colors = RingColors.gold;
    }
    final b = c.s.bigHoops;
    // Over: back to normal hoops (the state is cleared, mult = 1).
    if (b != null && c.s.runClock - b.start >= b.duration) c.s.bigHoops = null;
  }

  @override
  void detach() {
    _c?.events.off<HoopSpawned>(_onSpawn);
    _c = null;
  }
}
