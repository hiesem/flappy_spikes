import '../config/revive_config.dart';
import '../run_state.dart';

/// What one revive offer asks for (§3.14 "one option per death").
enum ReviveOfferKind { ad, coins }

/// One offer of the price ladder.
class ReviveOffer {
  const ReviveOffer.ad()
    : kind = ReviveOfferKind.ad,
      price = 0,
      noAdLabel = false;
  const ReviveOffer.coins(this.price, {this.noAdLabel = false})
    : kind = ReviveOfferKind.coins;

  final ReviveOfferKind kind;

  /// Coins (0 for the ad step).
  final int price;

  /// §5.9 "NO AD AVAILABLE" above the heart: the ad step was skipped.
  final bool noAdLabel;

  bool get isAd => kind == ReviveOfferKind.ad;

  @override
  bool operator ==(Object other) =>
      other is ReviveOffer &&
      other.kind == kind &&
      other.price == price &&
      other.noAdLabel == noAdLabel;

  @override
  int get hashCode => Object.hash(kind, price, noAdLabel);

  @override
  String toString() => isAd ? 'ad' : '$price${noAdLabel ? ' (no ad)' : ''}';
}

/// The §3.14 price ladder (pure; the state lives in [RunState], so it
/// resets with every new game and a revive in the same game moves it one
/// step up):
///
/// | revive | price |
/// |---|---|
/// | 1st | rewarded ad |
/// | 2nd | 250 |
/// | 3rd | 500 |
/// | 4th | 1 000 |
/// | next | doubles again, no cap |
///
/// No ad available (no fill, offline) or a no-ads owner on the 1st offer:
/// the ad step is skipped for the game — "NO AD AVAILABLE" over a 250
/// heart, then 500, 1 000 … A death with ≤ 5 hoops never asks the ladder
/// (no step used).
abstract final class ReviveLadder {
  /// The coin price after [coinRevives] coin revives this game.
  static int coinPrice(int coinRevives) {
    var p = ReviveConfig.firstCoinPrice;
    for (var i = 0; i < coinRevives; i++) {
      p *= ReviveConfig.priceFactor;
    }
    return p;
  }

  /// The offer for this death. [adReady] = a rewarded ad can be shown now
  /// and the player is not a no-ads owner. Skipping the ad step is written
  /// to [s] (it never comes back in this game).
  static ReviveOffer offer(RunState s, {required bool adReady}) {
    if (s.adStepAvailableThisGame) {
      if (adReady) return const ReviveOffer.ad();
      s.adStepAvailableThisGame = false;
      return ReviveOffer.coins(coinPrice(s.coinRevives), noAdLabel: true);
    }
    return ReviveOffer.coins(coinPrice(s.coinRevives));
  }

  /// Records a revive paid with [offer] (one step up the ladder).
  static void record(RunState s, ReviveOffer offer) {
    if (offer.isAd) {
      s.adStepAvailableThisGame = false;
    } else {
      s.coinRevives++;
    }
  }

  /// §3.14 the offer is only made from [ReviveConfig.minHoops] hoops passed.
  static bool eligible(RunState s) => s.hoopsPassed >= ReviveConfig.minHoops;
}
