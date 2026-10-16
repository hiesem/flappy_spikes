import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:games_services/games_services.dart';

import '../achievements/achievement_catalog.dart';
import '../firebase_options.dart';
import '../game/diag.dart';
import '../skins/look.dart';
import 'redact.dart';

/// Outcome of a [GameServices.showLeaderboards] call, so the game can tell
/// "opened fine" apart from the different failure modes (and from "not a
/// failure at all" states where no user message should appear).
enum ShowLeaderboardResult {
  /// The native leaderboard UI was presented.
  opened,

  /// The interactive sign-in behind the leaderboard button failed or timed
  /// out.
  signInFailed,

  /// Sign-in was fine but the native leaderboard UI failed to open.
  leaderboardFailed,

  /// The service was never initialized (tests, unconfigured builds): the
  /// call was a no-op by design, not a failure.
  unavailable,

  /// A previous call is still in flight (double-tap guard).
  busy,
}

/// PRD-2.3.1 §12.4 outcome of [GameServices.showAchievements] (the Home
/// medal button), mirroring [ShowLeaderboardResult].
enum ShowAchievementsResult { opened, signInFailed, failed, unavailable, busy }

/// Firebase Analytics + platform leaderboards (Google Play Games on Android,
/// Game Center on iOS), wrapped so the rest of the game never touches plugin
/// APIs directly.
///
/// The default instance is a NO-OP: [initialize] is only called from main().
/// Unit tests and unconfigured builds therefore run the full game without any
/// plugin side effects — every plugin call is additionally gated on the
/// [_initialized] flag, so a never-initialized instance never even reaches
/// the method channel. Every plugin call is also individually guarded and
/// time-boxed: services must never take the game down.
/// 2.4.0 (26), Android: the launch dialogs (consent form, notification
/// question) come before anything listens to the games_services player
/// stream. Its first listen asks Play Games for the player, which signs a
/// returning player in and shows Play Games' "Welcome back" banner; at
/// launch that banner showed behind the dialogs and the player saw no
/// sign-in. main() sets [ready] to the dialogs (capped); it is complete
/// everywhere else (iOS, tests, Linux).
class PlayerStreamGate {
  PlayerStreamGate._();

  static Future<void> ready = Future<void>.value();
}

class GameServices {
  FirebaseAnalytics? _analytics;
  bool _signedIn = false;
  bool _initialized = false;
  bool _leaderboardBusy = false;

  /// Kept alive for the app's lifetime on purpose: the subscription keeps the
  /// plugin's native auth listener active so [_signedIn] tracks sign-ins.
  // ignore: unused_field
  StreamSubscription<PlayerData?>? _playerSub;

  /// Upper bound on any single plugin call. The plugin is documented to hang
  /// forever in some flows (games_services #197, #221: a second signIn()
  /// overwrites the first MethodChannel.Result, which then never completes);
  /// a timeout is the only way to turn a hang into a reportable event.
  /// Injectable in tests so they don't wait out the real 10 s.
  @visibleForTesting
  Duration pluginTimeout = const Duration(seconds: 10);

  /// Game Center leaderboard ID (App Store Connect, "Top Scores"; the new
  /// app record, not the 2014 original's `flappy_spikes_leaderboard`).
  static const String iosLeaderboardId = 'fs_top_scores';

  /// Google Play Games leaderboard ID (Play Console, "Top Scores").
  static const String androidLeaderboardId = 'CgkIsZz8pvUOEAIQAA';

  /// Initializes Firebase Analytics and starts tracking the game-service
  /// sign-in state. Any failure leaves the service a no-op.
  ///
  /// This NEVER requests sign-in: an explicit sign-in call at launch makes
  /// Play Games show its profile-picker popup when it cannot sign in
  /// silently (multiple profiles, no default picked). Play Games v2 signs
  /// returning players in automatically, and new players are only prompted
  /// when they tap a leaderboard button ([showLeaderboards]).
  ///
  /// Sign-in state comes from the plugin's player stream, kept alive for the
  /// app's lifetime: native code pushes auth changes there (after automatic
  /// and explicit sign-ins). `GameAuth.isSignedIn` is deliberately NOT used —
  /// in games_services 5.1.0 it completes with the STALE cached player before
  /// the real native check lands, i.e. false on every cold call.
  Future<void> initialize() async {
    await ensureFirebase();
    // 2.4.0 (26): the first listen is what makes Play Games sign in (and
    // show its "Welcome back" banner); it waits for the launch dialogs
    // ([PlayerStreamGate]), so the banner is not hidden behind them.
    unawaited(
      PlayerStreamGate.ready.then((_) {
        try {
          _playerSub = GameAuth.player.listen(_onPlayer);
        } catch (_) {
          _signedIn = false;
        }
      }),
    );
    // Set even when the plugin setup above failed: initialize() having RUN is
    // what distinguishes the real app from tests/unconfigured builds.
    _initialized = true;
    if (!_initDone.isCompleted) _initDone.complete();
  }

  final Completer<void> _initDone = Completer<void>();

  /// iOS round 2 §5 / §6: Game Center authentication at launch (iOS only).
  ///
  /// The Android rule "never `GameAuth.signIn()` at launch" (CLAUDE.md:
  /// Play Games shows a profile picker) stays Android-only. On iOS GameKit
  /// authenticates only once the app sets the local player's authenticate
  /// handler (games_services sets it in `signIn`); until then the player
  /// counts as signed out even when signed in to Game Center on the
  /// device: the in-game name stayed the generated one and no achievement
  /// was reported (no native banner) until the player tapped the
  /// leaderboard / achievements button. Setting the handler at launch is
  /// Apple's standard flow: an already signed-in player is authenticated
  /// silently (Apple's "Welcome back" banner), the player stream gets the
  /// player and everything follows at once. A signed-out player gets
  /// Game Center's own sign-in sheet once (GameKit stops asking after a
  /// cancel; Settings → Game Center signs in later, and the plugin's
  /// handler then reports the player at once).
  ///
  /// Runs after [initialize] and after [after] (the ads consent / ATT
  /// flow at launch, capped at [launchAuthWait]) so the Game Center sheet
  /// never collides with the UMP form or the ATT alert.
  Future<void> authenticateAtLaunch({Future<void>? after}) async {
    if (!isIOSPlatform()) return;
    try {
      await _initDone.future.timeout(launchAuthWait);
      if (after != null) {
        // 2.4.0 (26): the launch dialogs (consent form, ATT, notification
        // question) wait for the player, so the cap is generous.
        await after.timeout(launchGateWait, onTimeout: () {});
      }
    } catch (_) {}
    if (!_initialized || _signedIn) {
      diag(
        'FS-GC launch auth skipped (initialized=$_initialized '
        'signedIn=$_signedIn)',
      );
      return;
    }
    diag('FS-GC launch auth: GameAuth.signIn (sets the authenticate handler)');
    final watch = Stopwatch()..start();
    try {
      // Long: a signed-out player may take a while on Apple's sheet.
      await signInPlugin().timeout(const Duration(minutes: 3));
      diag('FS-GC launch auth ok in ${watch.elapsedMilliseconds} ms');
    } catch (e) {
      final code = e is PlatformException ? e.code : e.runtimeType.toString();
      diag(
        'FS-GC launch auth failed in ${watch.elapsedMilliseconds} ms: '
        '$code',
      );
      _reportPgsError('sign_in_launch', e);
    }
  }

  /// How long [authenticateAtLaunch] waits for [initialize] and for the
  /// launch consent flow.
  static const Duration launchAuthWait = Duration(seconds: 12);

  /// 2.4.0 (24), Android: the silent "signed in after all?" check.
  ///
  /// games_services 5.1.0 asks Play Games `isAuthenticated` only once, when
  /// Dart first listens to its player stream at launch. When the automatic
  /// sign-in of a returning player lands after that (a slow start, the
  /// consent form at launch), the game kept the player "signed out" for
  /// the session: the generated in-game name, the in-game achievement
  /// toast instead of Play Games' popup, until a leaderboard tap signed in.
  ///
  /// While the game counts the player as signed out, this asks Play Games
  /// again (`flappy_spikes/pgs` isAuthenticated, never any UI). Only when
  /// Play Games says the player IS signed in, the plugin's sign-in fetches
  /// the player: for an authenticated player that is silent (no profile
  /// picker, so the CLAUDE.md "never signIn at launch" rule holds) and it
  /// pushes the player into the stream, so name, achievements and the
  /// popup follow at once. Concurrent requests fold into one; no-op on iOS
  /// (Game Center: [authenticateAtLaunch]), in tests and when signed in.
  Future<void> recheckSignIn(String reason) async {
    if (!isAndroidPlatform() || _signedIn) return;
    final running = _recheck;
    if (running != null) return running;
    final run = _recheckSignIn(reason);
    _recheck = run;
    try {
      await run;
    } finally {
      _recheck = null;
    }
  }

  Future<void>? _recheck;

  Future<void> _recheckSignIn(String reason) async {
    try {
      await _initDone.future.timeout(launchAuthWait);
    } catch (_) {
      return;
    }
    final gate = launchGate;
    if (gate != null) {
      await gate.timeout(launchGateWait, onTimeout: () {});
      // Let the last dialog animate out, so the banner shows on the game.
      await Future<void>.delayed(launchGateSettle);
    }
    if (!_initialized || _signedIn) return;
    bool authenticated;
    try {
      authenticated = await isAuthenticatedPlugin().timeout(pluginTimeout);
    } catch (e) {
      diag('FS-GC recheck ($reason) failed: ${e.runtimeType}');
      return;
    }
    if (!authenticated) {
      diag('FS-GC recheck ($reason): not signed in to Play Games');
      return;
    }
    if (_signedIn) return;
    diag('FS-GC recheck ($reason): signed in to Play Games, fetching player');
    try {
      await signInPlugin().timeout(pluginTimeout);
    } catch (e) {
      diag('FS-GC recheck ($reason) sign-in failed: ${e.runtimeType}');
      _reportPgsError('sign_in_recheck', e);
    }
  }

  /// Android launch: [recheckSignIn] a few times over the first seconds
  /// (the automatic sign-in can take a while, and the consent form may be
  /// up); each one is a no-op once the player is signed in.
  void scheduleLaunchRechecks() {
    if (!isAndroidPlatform()) return;
    for (final s in launchRecheckSeconds) {
      Future<void>.delayed(
        Duration(seconds: s),
        () => recheckSignIn('launch +${s}s'),
      );
    }
  }

  static const List<int> launchRecheckSeconds = [2, 6, 15];

  /// 2.4.0 (26): the launch dialogs (consent form, notification question);
  /// set by main(). [recheckSignIn] signs in only after them, so Play
  /// Games' "Welcome back" banner is not hidden behind them.
  Future<void>? launchGate;
  static const Duration launchGateWait = Duration(minutes: 3);
  static const Duration launchGateSettle = Duration(milliseconds: 600);

  static const MethodChannel _pgsChannel = MethodChannel('flappy_spikes/pgs');

  /// The silent Play Games check (Android); a test seam.
  @visibleForTesting
  Future<bool> isAuthenticatedPlugin() async =>
      await _pgsChannel.invokeMethod<bool>('isAuthenticated') ?? false;

  /// The shared `Firebase.initializeApp` (S6-F01): every caller —
  /// [initialize] and the versus start-up (`main.dart`) — waits for the
  /// SAME attempt, so nothing that needs Firebase runs before it landed.
  /// Completes with whether Firebase is up; never throws. After a failure
  /// the next call tries again (a transient start-up failure recovers).
  /// Only `main.dart` paths call it: tests never touch the plugins.
  Future<bool> ensureFirebase() {
    if (_firebaseUp) return Future.value(true);
    return _firebaseInit ??= _initFirebase().whenComplete(
      () => _firebaseInit = null,
    );
  }

  bool _firebaseUp = false;
  Future<bool>? _firebaseInit;

  Future<bool> _initFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _analytics = FirebaseAnalytics.instance;
      _firebaseUp = true;
    } catch (e) {
      debugPrint(
        'GameServices: Firebase.initializeApp failed: ${redactSecrets(e)}',
      );
      _analytics = null;
    }
    return _firebaseUp;
  }

  // region P231-E — achievements (PRD-2.3.1 §12.4)
  String? _playerId;

  /// The signed-in platform player id (null = signed out / unknown).
  String? get playerId => _playerId;

  /// Called whenever a player appears or the player id changes (the
  /// tracker's `syncAll`, §12.4). Set by `AchievementTracker`.
  void Function()? onAchievementPlayer;

  /// Plugin calls for achievements may run: initialised and signed in.
  bool get achievementsReady => _initialized && _signedIn;

  void _onPlayer(PlayerData? player) {
    final before = _playerId;
    if ((player != null) != _signedIn || player?.playerID != before) {
      diag(
        'FS-GC player ${player == null ? 'signed out' : 'signed in "${player.displayName}"'}'
        ' (persistent id: ${player?.playerID != null})',
      );
    }
    _signedIn = player != null;
    _playerId = player?.playerID;
    if (player != null && (!_announcedPlayer || before != _playerId)) {
      _announcedPlayer = true;
      unawaited(_resetGameCenterIfAsked());
      _notifyAchievementPlayer();
    }
    if (player == null) _announcedPlayer = false;
  }

  bool _announcedPlayer = false;

  bool _resetChecked = false;

  /// Test only: a launch with the `-FSResetGameCenter` argument (only
  /// WebDriverAgent / Xcode can pass one; App Store launches can't) resets
  /// the signed-in player's Game Center achievements once, so the test
  /// iPhone can start as a new player. iOS only; never runs otherwise.
  Future<void> _resetGameCenterIfAsked() async {
    if (_resetChecked || !Platform.isIOS) return;
    _resetChecked = true;
    try {
      final args = await const MethodChannel(
        'flappy_spikes/device',
      ).invokeListMethod<String>('launchArgs');
      if (args == null || !args.contains('-FSResetGameCenter')) return;
      final r = await GamesServices.resetAchievements();
      diag('FS-GC reset achievements: ${r ?? 'ok'}');
    } catch (e) {
      diag('FS-GC reset achievements FAILED: $e');
    }
  }

  void _notifyAchievementPlayer() {
    try {
      onAchievementPlayer?.call();
    } catch (_) {}
  }

  /// Tests: what the plugin's player stream would push ([id] null = signed
  /// out).
  @visibleForTesting
  void debugSetPlayer(String? id) => _onPlayer(
    id == null ? null : PlayerData(playerID: id, displayName: 'test'),
  );

  /// Whether this is iOS (Game Center progress); a test seam.
  @visibleForTesting
  bool Function() isIOSPlatform = _isIOS;

  /// Whether this is Android (the Play Games re-check); a test seam.
  @visibleForTesting
  bool Function() isAndroidPlatform = _isAndroid;

  static bool _isAndroid() {
    try {
      return !kIsWeb && Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  static bool _isIOS() {
    try {
      return !kIsWeb && Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  final Set<String> _missingAndroidIdLogged = {};

  @visibleForTesting
  Future<void> unlockAchievementPlugin(AchievementId id) async {
    await Achievements.unlock(
      achievement: Achievement(
        androidID: id.androidId,
        iOSID: id.iosId,
        percentComplete: 100,
        showsCompletionBanner: true,
      ),
    );
  }

  @visibleForTesting
  Future<void> setAchievementProgressPlugin(
    AchievementId id,
    double percent,
  ) async {
    await Achievements.unlock(
      achievement: Achievement(
        androidID: id.androidId,
        iOSID: id.iosId,
        percentComplete: percent,
        showsCompletionBanner: false,
      ),
    );
  }

  @visibleForTesting
  Future<void> showAchievementsPlugin() async {
    await Achievements.showAchievements();
  }

  /// §12.4 reports one unlock. Only while signed in (never signs in);
  /// returns whether the platform confirmed it. A key without an Android
  /// id is skipped on Android (logged once).
  Future<bool> unlockAchievement(AchievementId id) async {
    if (!achievementsReady) return false;
    if (!isIOSPlatform() && id.androidId.isEmpty) {
      if (_missingAndroidIdLogged.add(id.key)) {
        debugPrint('GameServices: no Android id for achievement ${id.key}');
      }
      return false;
    }
    try {
      await unlockAchievementPlugin(id).timeout(pluginTimeout);
      diag(
        'FS-Ach report ${isIOSPlatform() ? id.iosId : id.androidId} '
        '100% banner=on: ok',
      );
      return true;
    } catch (e) {
      diag(
        'FS-Ach report ${isIOSPlatform() ? id.iosId : id.androidId} '
        'FAILED: ${e is PlatformException ? '${e.code} ${e.message}' : e}',
      );
      _reportPgsError('unlock_achievement', e);
      return false;
    }
  }

  /// §12.4 Game Center progress (iOS only; Android unlocks at once and has
  /// plain achievements). Game Center keeps the highest value.
  Future<void> reportAchievementProgress(
    AchievementId id,
    double percent,
  ) async {
    if (!achievementsReady || !isIOSPlatform()) return;
    try {
      await setAchievementProgressPlugin(id, percent).timeout(pluginTimeout);
      diag('FS-Ach progress ${id.iosId} ${percent.toStringAsFixed(1)}%: ok');
    } catch (e) {
      diag(
        'FS-Ach progress ${id.iosId} FAILED: '
        '${e is PlatformException ? e.code : e}',
      );
      _reportPgsError('achievement_progress', e);
    }
  }

  /// §12.4 opens the native achievements list, exactly like
  /// [showLeaderboards]: the same busy guard (one plugin UI call at a
  /// time), interactive sign-in on tap if needed, the timeout.
  Future<ShowAchievementsResult> showAchievements() async {
    if (!_initialized) return ShowAchievementsResult.unavailable;
    if (_leaderboardBusy) return ShowAchievementsResult.busy;
    _leaderboardBusy = true;
    try {
      if (!_signedIn) {
        try {
          await signInPlugin().timeout(pluginTimeout);
          _signedIn = true;
          _notifyAchievementPlayer();
        } catch (e) {
          _reportPgsError('sign_in', e);
          return ShowAchievementsResult.signInFailed;
        }
      }
      try {
        await showAchievementsPlugin().timeout(pluginTimeout);
        return ShowAchievementsResult.opened;
      } catch (e) {
        _reportPgsError('show_achievements', e);
        return ShowAchievementsResult.failed;
      }
    } finally {
      _leaderboardBusy = false;
    }
  }
  // endregion P231-E

  /// Test seam: simulates a main()-initialized service without touching
  /// plugins (the game-level spy overrides the public methods anyway).
  @visibleForTesting
  void markInitialized() {
    _initialized = true;
    if (!_initDone.isCompleted) _initDone.complete();
  }

  void logGameStart() => logEvent('game_start');

  void logGameOver({required int score, required int bestScore}) =>
      logEvent('game_over', {'score': score, 'best_score': bestScore});

  void logNewBest(int score) => logEvent('new_best', {'score': score});

  /// PRD-2.3 §2.1: [extra] = `text_id`, `banner_id` and `level`.
  void logShareScore(int score, [Map<String, Object> extra = const {}]) =>
      logEvent('share_score', {'score': score, ...extra});

  /// PRD-menu-v2 §7.3: layer-aware skin-shop events (they replaced the PRD-1
  /// `skin_*` ones).
  void logItemTryOn(SkinLayer layer, String id, Rarity? rarity) =>
      logEvent('item_try_on', _itemParams(layer, id, rarity: rarity));

  /// [source] = where the purchase was confirmed: `button` (the preview's
  /// BUY) or `tile` (the second tap on a tried-on grid tile, WP-J2).
  void logItemPurchase(
    SkinLayer layer,
    String id,
    Rarity? rarity,
    int price, {
    String? source,
  }) => logEvent('item_purchase', {
    ..._itemParams(layer, id, rarity: rarity, price: price),
    'source': ?source,
  });

  void logItemEquip(SkinLayer layer, String id) =>
      logEvent('item_equip', _itemParams(layer, id));

  void logItemNoCoins(SkinLayer layer, String id, int shortfall) =>
      logEvent('item_no_coins', _itemParams(layer, id, shortfall: shortfall));

  void logSkinShopTab(SkinLayer layer) =>
      logEvent('skin_shop_tab', {'layer': layer.key});

  // --- PRD-home-v3 §11 -----------------------------------------------------

  /// LEVELS screen opened; [source] e.g. `home_emblem`.
  void logLevelsOpen(String source) =>
      logEvent('levels_open', {'source': source});

  /// LEVEL UP popup shown for [level] at best score [best].
  void logLevelUp(int level, int best) =>
      logEvent('level_up', {'level': level, 'best': best});

  /// A LEVEL UP reward paid ([coins] = all rewards added together).
  void logLevelRewardClaimed(int level, int coins) =>
      logEvent('level_reward_claimed', {'level': level, 'coins': coins});

  /// Purchase cancelled / failed popup: [outcome] `cancelled` / `failed`,
  /// [code] the store error code (omitted when there is none).
  void logPurchaseResultPopup(String product, String outcome, String? code) =>
      logEvent('purchase_result_popup', {
        'product': product,
        'outcome': outcome,
        'code': ?code,
      });

  /// RUMBLE switched in Settings (`on` as 1 / 0: Firebase has no bool).
  ///
  /// region WP-2b — PRD-2 §6 `setting_changed` (setting: rumble, value).
  /// Call: both events are sent — `rumble_toggle` keeps the home-v3
  /// dashboards working, `setting_changed` is the PRD-2 name.
  void logRumbleToggle(bool on) {
    logEvent('rumble_toggle', {'on': on ? 1 : 0});
    logEvent('setting_changed', {'setting': 'rumble', 'value': on ? 1 : 0});
  }
  // endregion WP-2b

  /// No-ads celebration shown; [source] tile / shop_banner / popup.
  void logNoAdsCelebrationShown(String source) =>
      logEvent('noads_celebration_shown', {'source': source});

  /// The No-ads +1 000 bonus collected from the celebration.
  void logNoAdsBonusClaimed() => logEvent('noads_bonus_claimed');

  /// Shared parameter map. The Gear/Hat "none" entries have no rarity, so
  /// that key is omitted rather than sent as null.
  Map<String, Object> _itemParams(
    SkinLayer layer,
    String id, {
    Rarity? rarity,
    int? price,
    int? shortfall,
  }) => {
    'layer': layer.key,
    'id': id,
    'rarity': ?rarity?.label,
    'price': ?price,
    'shortfall': ?shortfall,
  };

  /// Menu / economy analytics (PRD-1 §6: coins_earned, shop_open,
  /// home_slot_shown, ...). Goes through [logEvent], so test spies that
  /// override it see these too.
  void track(String name, [Map<String, Object>? parameters]) =>
      // S7-18: no credential ever reaches an analytics parameter.
      logEvent(name, redactParams(parameters));

  /// Non-private so tests can record events instead of sending them;
  /// production behavior is unchanged (analytics, try/caught).
  @visibleForTesting
  void logEvent(String name, [Map<String, Object>? parameters]) {
    try {
      // Firebase Analytics takes only String / num values (a bool fails its
      // assertion asynchronously, outside this try — seen on the Pixel 8
      // for `notif_permission` {granted: true}): bools go as 1 / 0.
      // S7-18: credentials are stripped from every String value.
      final safe = redactParams(parameters);
      final params = safe == null
          ? null
          : {
              for (final e in safe.entries)
                e.key: switch (e.value) {
                  true => 1,
                  false => 0,
                  final v => v,
                },
            };
      _analytics
          ?.logEvent(name: name, parameters: params)
          .catchError((Object _) {});
    } catch (_) {
      // Analytics must never affect gameplay.
    }
  }

  // --- plugin seams (overridable in tests) --------------------------------

  @visibleForTesting
  Future<void> signInPlugin() async {
    await GameAuth.signIn();
  }

  @visibleForTesting
  Future<void> showLeaderboardsPlugin() async {
    await Leaderboards.showLeaderboards(
      androidLeaderboardID: androidLeaderboardId,
      iOSLeaderboardID: iosLeaderboardId,
    );
  }

  @visibleForTesting
  Future<void> submitScorePlugin(int value) async {
    await Leaderboards.submitScore(
      score: Score(
        androidLeaderboardID: androidLeaderboardId,
        iOSLeaderboardID: iosLeaderboardId,
        value: value,
      ),
    );
  }

  // --- error reporting -----------------------------------------------------

  /// Reports a plugin failure to Analytics (and logcat in debug builds).
  ///
  /// Plugin error codes to expect (see the plugin's PluginError.kt):
  /// `failed_to_authenticate`, `not_authenticated`, `leaderboard_not_found`,
  /// `failed_to_send_score`, `operation_canceled`.
  ///
  /// Diagnostic note: `failed_to_authenticate` with an EMPTY message means
  /// Google returned a well-formed *unauthenticated* result — in practice a
  /// configuration problem (unpublished PGS project / consent screen still in
  /// Testing / SHA-1 mismatch), not a transient error. That is the exact
  /// signature the 2026-07 production outage produced.
  void _reportPgsError(String op, Object error) {
    final String code;
    String message;
    if (error is PlatformException) {
      code = error.code;
      message = error.message ?? '';
    } else if (error is TimeoutException) {
      code = 'timeout';
      message = '';
    } else {
      code = 'unknown';
      message = error.toString();
    }
    // S7-18: strip credentials before truncating (a cut could leave half a
    // token that no longer matches the patterns).
    message = redactSecrets(message);
    // Analytics parameter values are capped at 100 chars — truncate at 90.
    message = message.substring(0, min(90, message.length));
    debugPrint('GameServices pgs_error: op=$op code=$code message=$message');
    logEvent('pgs_error', {'op': op, 'code': code, 'message': message});
  }

  // --- leaderboards ---------------------------------------------------------

  /// Submits [value] to the platform leaderboard (called with the local best
  /// after every game; the service keeps each player's single highest score).
  ///
  /// Attempted even when the local sign-in state is unknown: Play Games v2
  /// auto sign-in is not always visible to us, and submitting while signed
  /// out simply fails (reported as `pgs_error`). Never blocks gameplay, never
  /// requests interactive sign-in, and deliberately never gates on a
  /// `getPlayerScore()` read-back: brand-new Play Games players return null
  /// there while the backend provisions them, which would silently drop
  /// scores (games_services #202).
  Future<void> submitBestScore(int value) async {
    if (!_initialized) {
      return;
    }
    try {
      await submitScorePlugin(value).timeout(pluginTimeout);
    } catch (e) {
      _reportPgsError('submit_score', e);
    }
  }

  /// Opens the platform's native leaderboard UI, attempting sign-in first.
  ///
  /// Re-entrant-safe: the plugin keeps a SINGLE pendingOperation, so a second
  /// concurrent signIn() would overwrite the first MethodChannel.Result and
  /// hang it forever — a double-tap on the small leaderboard button would
  /// deadlock the call. The [_leaderboardBusy] guard returns
  /// [ShowLeaderboardResult.busy] instead, and every plugin call is
  /// time-boxed by [pluginTimeout].
  Future<ShowLeaderboardResult> showLeaderboards() async {
    if (!_initialized) {
      return ShowLeaderboardResult.unavailable;
    }
    if (_leaderboardBusy) {
      return ShowLeaderboardResult.busy;
    }
    _leaderboardBusy = true;
    try {
      if (!_signedIn) {
        try {
          await signInPlugin().timeout(pluginTimeout);
          // A completed signIn() means the player is authenticated — the
          // plugin only succeeds then (see its Auth.kt). Do NOT double-check
          // via GameAuth.isSignedIn (stale-cache race, see [initialize]).
          _signedIn = true;
          _notifyAchievementPlayer(); // PRD-2.3.1 §12.4
        } catch (e) {
          _reportPgsError('sign_in', e);
          return ShowLeaderboardResult.signInFailed;
        }
      }
      try {
        await showLeaderboardsPlugin().timeout(pluginTimeout);
        return ShowLeaderboardResult.opened;
      } catch (e) {
        _reportPgsError('show_leaderboards', e);
        return ShowLeaderboardResult.leaderboardFailed;
      }
    } finally {
      _leaderboardBusy = false;
    }
  }
}
