import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

import '../../game/flappy_game.dart';
import '../../menu/wallet.dart';
import '../../progression/missions.dart';
import '../../run/config/results_config.dart';
import '../../run/items/versus_recorder.dart' show duelOf;
import '../../run/run_summary.dart';
import '../../services/redact.dart';
import '../../versus/opponent.dart';
import '../home/menu_primitives.dart';
import '../ui/coin_fly.dart';

/// PRD 2.6 G6: style A. Payment is independent of the presentation, so NEXT
/// before the moment finishes cannot discard the daily reward.
class FirstWinReward extends PositionComponent
    with HasGameReference<FlappySpikesGame>, GroupOpacity {
  FirstWinReward({
    required this.coin,
    required this.onCount,
    this.missionsStrip = false,
  }) : super(
         position: Vector2(160, missionsStrip ? 595 : 572),
         anchor: Anchor.center,
         size: Vector2(292, 18),
       );

  final Sprite coin;
  final void Function() onCount;
  bool missionsStrip;
  int shownCoins = 0;
  double? _time;
  bool _flew = false;
  CoinFly? flight;

  /// Reserve synchronously through saveFirstWinDay's in-memory write before
  /// awaiting persistence, also protecting concurrent results loads.
  static Future<int> pay(FlappySpikesGame game, RunSummary summary) async {
    final opponent = summary.opponent;
    if (opponent == null ||
        (summary.duel ?? duelOf(summary.score, opponent.score)) !=
            DuelResult.win) {
      return 0;
    }
    final day = Missions.localDay(game.storage.now().toLocal());
    if (game.storage.firstWinDay >= day) return 0;
    try {
      // Deliberately reserve the day first: an interrupted payout cannot pay
      // twice. A process kill between the writes can lose this day's award.
      await game.storage.saveFirstWinDay(day);
      await game.menu.wallet.add(20, CoinSource.firstWinDay);
      return 20;
    } catch (error) {
      debugPrint('first_win_day payout failed: ${errorKind(error)}');
      return 0;
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final row = PositionComponent(size: size.clone());
    await add(row);
    layoutRow(row, [
      MenuText(
        '+20',
        fontSize: 11.5,
        color: ResultsConfig.plum,
        letterSpacingEm: .14,
      ),
      MenuIcon(coin, size: Vector2.all(13)),
      MenuText(
        'FIRST WIN TODAY',
        fontSize: 11.5,
        color: ResultsConfig.goldDark,
        letterSpacingEm: .14,
      ),
    ], gap: 5);
    opacity = 0;
  }

  bool get running => _time != null && _time! < 1.5;
  double get remaining => (1.5 - (_time ?? 0)).clamp(0.0, 1.5);

  void start() => _time ??= 0;

  void showImmediately() {
    _time = 1.5;
    _flew = true;
    shownCoins = 20;
    opacity = 1;
    scale.setAll(1);
    onCount();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final previous = _time;
    if (previous == null) return;
    final t = previous + dt;
    _time = t;
    position.y = missionsStrip ? 595 : 572;
    final still = game.reduceMotion;
    opacity = still ? 1 : ((t - .6) / .1).clamp(0.0, 1.0);
    final u = ((t - .6) / .3).clamp(0.0, 1.0);
    scale.setAll(
      still
          ? 1
          : 1 + 2.70158 * math.pow(u - 1, 3) + 1.70158 * math.pow(u - 1, 2),
    );
    if (!_flew && t >= .85) {
      _flew = true;
      if (!still) {
        flight = CoinFly.burst(
          coin: coin,
          origin: Offset(152, position.y - 8),
          to: Offset(180, ResultsConfig.rewardPill.center.dy - 8),
          count: 5,
          duration: .42,
          stagger: .05,
          spreadX: 0,
          midSpreadX: 24,
          rise: (min: 60, range: 0),
          coinSize: 16,
        );
        parent?.add(flight!);
      }
    }
    final count = still
        ? 20
        : (20 * ((t - 1.05) / .45).clamp(0.0, 1.0)).round();
    if (count != shownCoins) {
      shownCoins = count;
      onCount();
    }
  }
}
