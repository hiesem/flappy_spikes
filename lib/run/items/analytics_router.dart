import '../../menu/wallet.dart';
import '../config/run_config.dart';
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

  /// `gamesPlayed` when the run started (PRD-2.3 §14.8 `games_played`
  /// counts this run too).
  int _gamesAtStart = 0;

  /// PRD-2.3 §14.8 a ratio with 2 decimals.
  static double ratio2(num a, num b) =>
      ((b <= 0 ? 0 : a / b) * 100).roundToDouble() / 100;

  @override
  void attach(RunContext c) {
    _c = c;
    _gamesAtStart = c.game.storage.gamesPlayed;
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
      // PRD-2.2 §13.6 score = points; hoops = the hoop count.
      'score': s.score,
      'hoops': s.hoopsPassed,
      'max_streak': s.maxStreak,
      // PRD-2.2 §11.4
      'clean_passes': s.cleanPasses,
      'coins': s.coins,
      'saves': s.saves,
      // PRD-2.2 §19.3 the feather / piece came this run (0 / 1).
      'feather': c.s.featherSpawned ? 1 : 0,
      'piece': c.s.pieceSpawned ? 1 : 0,
      // PRD-2.3 §14.8 the budget and difficulty checks.
      'coins_per_hoop': ratio2(s.coins, s.hoopsPassed < 1 ? 1 : s.hoopsPassed),
      'perfect_rate': ratio2(s.perfectPasses, s.passes),
      'opening_end': RunConfig.openingFor(s.hoopIndex).round(),
      'speed_end': RunConfig.cruise(c.s.hoopIndex).round(),
      'games_played': _gamesAtStart + 1,
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
