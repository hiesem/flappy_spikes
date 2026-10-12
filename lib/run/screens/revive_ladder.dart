import '../config/revive_config.dart';
import '../run_state.dart';

/// What one revive offer asks for (§3.14 "one option per death";
/// PRD-2.2 §7.7 adds [free]: a NO ADS owner's first revive of a game).
enum ReviveOfferKind { ad, coins, free }

/// One offer of the price ladder.
class ReviveOffer {
  const ReviveOffer.ad()
    : kind = ReviveOfferKind.ad,
      price = 0,
      noAdLabel = false;
  const ReviveOffer.coins(this.price, {this.noAdLabel = false})
    : kind = ReviveOfferKind.coins;

  /// PRD-2.2 §7.7 the NO ADS owner's ad step: revive at once, price 0.
  const ReviveOffer.free()
    : kind = ReviveOfferKind.free,
      price = 0,
      noAdLabel = false;

  final ReviveOfferKind kind;

  /// Coins (0 for the ad and free steps).
  final int price;

  /// §5.9 "NO AD AVAILABLE" above the heart: the ad step was skipped.
  final bool noAdLabel;

  bool get isAd => kind == ReviveOfferKind.ad;

  bool get isFree => kind == ReviveOfferKind.free;

  bool get isCoins => kind == ReviveOfferKind.coins;

  @override
  bool operator ==(Object other) =>
      other is ReviveOffer &&
      other.kind == kind &&
      other.price == price &&
      other.noAdLabel == noAdLabel;

  @override
  int get hashCode => Object.hash(kind, price, noAdLabel);

  @override
  String toString() => isAd
      ? 'ad'
      : isFree
      ? 'free'
      : '$price${noAdLabel ? ' (no ad)' : ''}';
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
/// No ad available (no fill, offline) on the 1st offer: the ad step is
/// skipped for the game — "NO AD AVAILABLE" over a 250 heart, then 500,
/// 1 000 … PRD-2.2 §7.7: a NO ADS owner's ad step is a FREE revive
/// (whatever the ad availability), then 250, 500 … A death with ≤ 5 hoops
/// never asks the ladder (no step used).
abstract final class ReviveLadder {
  /// The coin price after [coinRevives] coin revives this game.
  static int coinPrice(int coinRevives) {
    var p = ReviveConfig.firstCoinPrice;
    for (var i = 0; i < coinRevives; i++) {
      p *= ReviveConfig.priceFactor;
    }
    return p;
  }

  /// The offer for this death. [adReady] = a rewarded ad can be shown now.
  /// [noAds] = the player owns NO ADS (PRD-2.2 §7.7: the ad step is free).
  /// Skipping the ad step is written to [s] (it never comes back in this
  /// game).
  static ReviveOffer offer(
    RunState s, {
    required bool adReady,
    bool noAds = false,
  }) {
    if (s.adStepAvailableThisGame) {
      if (noAds) return const ReviveOffer.free();
      if (adReady) return const ReviveOffer.ad();
      s.adStepAvailableThisGame = false;
      return ReviveOffer.coins(coinPrice(s.coinRevives), noAdLabel: true);
    }
    return ReviveOffer.coins(coinPrice(s.coinRevives));
  }

  /// Records a revive paid with [offer] (one step up the ladder).
  static void record(RunState s, ReviveOffer offer) {
    if (offer.isAd || offer.isFree) {
      s.adStepAvailableThisGame = false;
    } else {
      s.coinRevives++;
    }
  }

  /// §3.14 the offer is only made from [ReviveConfig.minHoops] hoops passed.
  static bool eligible(RunState s) => s.hoopsPassed >= ReviveConfig.minHoops;
}
