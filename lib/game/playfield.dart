import '../services/obf_strings.g.dart';

/// PRD-2.2 §7.5.2: a persistent component that survives scene changes and
/// caches positions derived from `game.viewHeight`. It registers with
/// `game.registerResizable(this)` (like `Tintable`) and re-lays itself out
/// when `game.setPlayfieldHeight` changes the playfield (START with a
/// banner, the Home arrival).
abstract interface class PlayfieldResizable {
  /// [viewHeight] is the new playfield layout height (`game.viewHeight`).
  void onPlayfieldResize(double viewHeight);
}

/// A [PlayfieldResizable] around a callback (game-owned chrome: backdrop,
/// score HUD position, ...).
class PlayfieldResizeCallback implements PlayfieldResizable {
  PlayfieldResizeCallback(this._onResize);

  final void Function(double viewHeight) _onResize;

  @override
  void onPlayfieldResize(double viewHeight) => _onResize(viewHeight);
}

/// PRD-2.2 §7.10: what the app shell's banner slot under the game shows.
enum BannerState {
  /// No strip (menus, NO ADS owners, no consent): the slot has height 0.
  off,

  /// The strip is reserved (START fade, VS intro, no fill yet) and painted
  /// in the spike grey; no ad on it.
  reservedEmpty,

  /// The bird flies: the banner shows on the strip once it is loaded (the
  /// strip stays grey while it is not).
  showing,
}

/// PRD-2.2 §7.6: why the video ad after a run was skipped
/// (`ad_interstitial_skipped.reason`). PRD-2.3 §18.4 / §23.2: `new_player`
/// replaces `first_runs` (the new-player grace), `rating` is a run that
/// asked for the store's rating sheet.
enum InterstitialSkip {
  noAds,
  newPlayer,
  rating,
  rewardedThisRun,
  cooldown,
  notLoaded,
  background;

  /// A getter, not a const field: `no_ads` is also the No-Ads product id,
  /// whose literal must not be in the binary (PRD-2.5 §3.5).
  String get analyticsName => switch (this) {
    InterstitialSkip.noAds => Obf.productNoAds,
    InterstitialSkip.newPlayer => 'new_player',
    InterstitialSkip.rating => 'rating',
    InterstitialSkip.rewardedThisRun => 'rewarded_this_run',
    InterstitialSkip.cooldown => 'cooldown',
    InterstitialSkip.notLoaded => 'not_loaded',
    InterstitialSkip.background => 'background',
  };
}
