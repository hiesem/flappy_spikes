import '../../menu/wallet.dart';
// region P26-G1b
import '../../progression/missions.dart';
import '../director/plans.dart';
import '../run_state.dart';
import '../../versus/opponent.dart';
import '../../versus/diagnostics.dart';
// endregion
import '../elements.dart';
import '../run_controller.dart';
import '../run_events.dart';

/// Owner 2026-10-14 (2.3.0 (18)) gameplay tuning: what one run produced —
/// passes, coins (by source), points, special hoops, gap items and rides.
/// Shown live on the debug panel main page; the bot report
/// (`test/tools/fun_budget_test.dart`) uses the same counts.
class RunStats {
  RunStats(RunController run) {
    // region P26-G1b
    _run = run;
    missionBestAtStart = run.game.storage.bestHoops;
    missionRivalAtStart = run.game.storage.lastVersusHadRival;
    final versus = run.game.versus;
    missionOnlineAtStart = versus.ready &&
        (versus.holdsOpponent ||
         versus.lastSearch.state == VersusSearchState.found ||
         versus.lastSearch.reason == VersusSoloReason.noRival);
    // endregion
    run.events.onAny(_on);
  }

  // region P26-G1b
  late final RunController _run;
  late final int missionBestAtStart;
  late final bool missionRivalAtStart, missionOnlineAtStart;
  int missionChain = 0, missionMaxChain = 0;
  int missionPerfectChain = 0, missionMaxPerfect = 0;
  int missionPairGifts = 0, missionCometStars = 0;
  int missionCometRides = 0, missionPortalRides = 0;
  int missionFeathers = 0, missionPieces = 0, missionShield = 0;
  int missionBullseyes = 0, missionSwitches = 0, missionSqueezes = 0;
  int _squeezeIndex = 0;
  final Set<Object> _openedSwitches = {};
  void captureOpenedSwitches() {
    for (final hoop in _run.spawner.hoops) {
      if (hoop.plan.kind == HoopKindId.switchRing && hoop.open && _openedSwitches.add(hoop)) {
        missionSwitches++;
      }
    }
  }

  MissionRunCounts missionCounts(int gamesPlayedBefore) {
    int taken(ElementId id) => _run.state.taken[id.storageId] ?? 0;
    final inRunCoins = coinsBy.entries
        .where((e) => e.key.aggregatedInRun || e.key == CoinSource.puzzle)
        .fold<int>(0, (n, e) => n + e.value);
    return MissionRunCounts(
      gamesPlayedBefore: gamesPlayedBefore,
      hoops: _run.state.hoopsPassed,
      perfectPasses: _run.state.perfectPasses,
      inRunCoins: inRunCoins,
      hourglasses: taken(ElementId.hourglass),
      miniBirds: taken(ElementId.miniBird),
      coinFrenzies: taken(ElementId.coinFrenzy),
      shieldPickups: missionShield,
      cometStars: missionCometStars,
      pairGifts: missionPairGifts,
      cometRides: missionCometRides,
      portalRides: missionPortalRides,
      feathers: missionFeathers,
      pieces: missionPieces,
      bullseyes: missionBullseyes,
      openedSwitches: missionSwitches,
      versusWins: _run.setup.opponent != null && _run.state.duel == DuelResult.win ? 1 : 0,
      maxPerfectStreak: missionMaxPerfect,
      maxNoRimChain: missionMaxChain,
      squeezesSurvived: missionSqueezes,
    );
  }
  // endregion

  int passes = 0;
  int perfects = 0;
  int coins = 0;
  int points = 0;
  int specials = 0;
  int items = 0;
  int rides = 0;
  final Map<CoinSource, int> coinsBy = {};

  void _on(RunEvent e) {
    // region P26-G1b
    switch (e) {
      case RimTouched():
        missionChain = 0;
        missionPerfectChain = 0;
      case SavedHoopPassed():
        missionChain = 0;
        missionPerfectChain = 0;
      case RunDied():
        missionPerfectChain = 0;
      case HoopPassed(:final hoop, :final rimTouched, :final perfect):
        if (perfect) {
          missionPerfectChain++;
          if (missionPerfectChain > missionMaxPerfect) missionMaxPerfect = missionPerfectChain;
        } else {
          missionPerfectChain = 0;
        }
        if (rimTouched) {
          missionChain = 0;
        } else {
          missionChain++;
          if (missionChain > missionMaxChain) missionMaxChain = missionChain;
        }
        if (hoop != null && hoop.plan.kind == HoopKindId.pair && !hoop.rewardStripped) missionPairGifts++;
        if (hoop != null && hoop.plan.kind == HoopKindId.switchRing && hoop.open && _openedSwitches.add(hoop)) missionSwitches++;
      case CoinsEarned(:final source) when source == CoinSource.bullseye:
        missionBullseyes++;
      case PickupCollected(:final element, :final pickup):
        switch (element) {
          case ElementId.shield: missionShield++;
          case ElementId.comet: if (pickup != null) missionCometStars++;
          case ElementId.feather: missionFeathers++;
          case ElementId.puzzlePiece: missionPieces++;
          default: break;
        }
      case RideStarted(:final kind):
        if (kind == RideKind.comet) { missionCometRides++; } else { missionPortalRides++; }
      case SqueezePhaseChanged(:final phase, :final index):
        if (phase == SqueezePhase.idle && index > _squeezeIndex) missionSqueezes++;
        _squeezeIndex = index;
      default: break;
    }
    // endregion
    switch (e) {
      case HoopPassed(:final duringRide, :final perfect):
        if (!duringRide) {
          passes++;
          if (perfect) perfects++;
        }
      case CoinsEarned(:final amount, :final source):
        coins += amount;
        coinsBy[source] = (coinsBy[source] ?? 0) + amount;
      case ScoreChanged(:final oldScore, :final newScore):
        points += newScore - oldScore;
      case ElementSpawned(:final element, :final onScreen) when onScreen:
        if (element.kind == ElementKind.slot &&
            element != ElementId.normalHoop) {
          specials++;
        } else if (element.kind == ElementKind.gap &&
            element != ElementId.piggyCoins &&
            element != ElementId.fireflySwarm) {
          items++;
        }
      case RideStarted():
        rides++;
      default:
        break;
    }
  }

  double _per(int n) => n / (passes < 1 ? 1 : passes);

  /// One line: hoops, coins and points per hoop.
  String get economyLine =>
      'Run: $passes hoops · $coins c (${_per(coins).toStringAsFixed(2)}/h)'
      ' · $points pts (${_per(points).toStringAsFixed(2)}/h)';

  /// One line: specials, items and rides, per 10 hoops.
  String get funLine =>
      'Specials $specials · items $items · rides $rides'
      ' (${(_per(specials + items) * 10).toStringAsFixed(1)}/10h)';
}
