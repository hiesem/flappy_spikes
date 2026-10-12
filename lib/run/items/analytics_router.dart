import '../../menu/wallet.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';

/// Run-level analytics (PRD-2 §6, ARCH §2.7): `run_end`,
/// `run_director_hoops`, `run_director_items` (≤ 25 int params each) at the
/// end of a run, plus the in-run `coins_earned` aggregated per (source,
/// egg_x2) into one event each (call: avoids ~100 events per run).
class AnalyticsRouter extends RunFeature {
  RunContext? _c;
  final Map<(CoinSource, bool), int> _coins = {};

  /// Hoop kinds and modifiers of `run_director_hoops` (+ rim_touches,
  /// perfect_pct).
  static const List<String> hoopKeys = [
    'normal_hoop',
    'bullseye',
    'train',
    'spring',
    'switch_ring',
    'pair',
    'fever',
    'lucky_spin',
    'saw',
    'portal',
    'comet',
    'tilted',
    'moving',
    // region anchors — append below
    // endregion anchors
  ];

  /// Gap item types of `run_director_items`.
  static const List<String> itemKeys = [
    'heart',
    'shield',
    'star_trail',
    'capsule',
    'egg',
    'piggy',
    'jar',
    'feather',
    'puzzle_piece',
    'piggy_coins',
    'firefly_swarm',
    // region anchors — append below
    // endregion anchors
  ];

  @override
  void attach(RunContext c) {
    _c = c;
    c.events.on<CoinsEarned>(_onCoins);
    c.events.on<RunEnded>(_onEnded);
  }

  void _onCoins(CoinsEarned e) {
    if (!e.source.aggregatedInRun) return;
    final key = (e.source, e.eggX2);
    _coins[key] = (_coins[key] ?? 0) + e.amount;
  }

  void _onEnded(RunEnded e) {
    final c = _c;
    if (c == null) return;
    final s = e.summary;
    c.track('run_end', {
      'cause': s.cause.analyticsName,
      'hoop_index': s.hoopIndex,
      'hoop_kind': s.hoopKind?.element.storageId ?? 'none',
      'run_s': s.runSeconds.round(),
      'hoops': s.hoopsPassed,
      'coins': s.coins,
      'saves': s.saves,
      // PRD-2.2 §19.3 the feather / piece came this run (0 / 1).
      'feather': c.s.featherSpawned ? 1 : 0,
      'piece': c.s.pieceSpawned ? 1 : 0,
    });
    c.track('run_director_hoops', {
      for (final k in hoopKeys) k: s.spawned[k] ?? 0,
      'rim_touches': s.rimTouches,
      'perfect_pct': s.passes == 0
          ? 0
          : (100 * s.perfectPasses / s.passes).round(),
    });
    c.track('run_director_items', {
      for (final k in itemKeys) k: s.spawned[k] ?? 0,
    });
    for (final entry in _coins.entries) {
      final (source, x2) = entry.key;
      c.track('coins_earned', {
        'amount': entry.value,
        'source': source.analyticsName,
        'egg_x2': x2 ? 1 : 0,
      });
    }
    _coins.clear();
  }

  @override
  void detach() {
    _c?.events.off<CoinsEarned>(_onCoins);
    _c?.events.off<RunEnded>(_onEnded);
    _c = null;
  }
}
