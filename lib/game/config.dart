import 'dart:math' as math;

import 'package:flame/extensions.dart';

import '../run/config/tuning_values.dart';

/// All gameplay constants from SPEC.md, in logical points on the original
/// 320x568 iPhone canvas (1 point = 1 Forge2D world unit).
class Config {
  Config._();

  // Virtual resolution. The playfield is always 320 pt wide; its height is
  // the screen aspect's height, clamped to [minViewHeight, maxViewHeight]
  // (568 = the original design height; 730 ~ a bit beyond 20:9 phones).
  static const double worldWidth = 320;
  static const double worldHeight = 568; // design/default height
  static const double minViewHeight = 568;
  static const double maxViewHeight = 730;

  // region WP-TAB — tablets (3:4) widen the world
  /// WP-TAB: the widest playfield (pt): 568 × 3 / 4, an iPad / Android
  /// tablet in portrait. Wider screens are capped here (side bars in the
  /// stage colour).
  static const double maxViewWidth = 426;

  /// WP-TAB: the playfield width for a screen whose height is
  /// [screenHeight] at 320 pt wide (`320 × h / w`). Phones (taller than
  /// 568/320) keep [worldWidth]; wider screens get height [minViewHeight]
  /// and width `568 × aspect`, capped at [maxViewWidth].
  static double viewWidthFor(double screenHeight) {
    if (screenHeight >= minViewHeight) return worldWidth;
    final w = minViewHeight * worldWidth / screenHeight;
    // Round off float noise (3:4 gives 426.0000000001).
    final r = (w * 1000).roundToDouble() / 1000;
    return r > maxViewWidth ? maxViewWidth : r;
  }
  // endregion WP-TAB

  // region PRD-2.2 §7.5 — gameplay banner
  /// §7.5.5: the smallest VISIBLE run playfield with a banner (a 16:9 phone
  /// with a 50 dp banner leaves ≈ 524 pt). Menus keep [minViewHeight].
  static const double minRunViewHeight = 500;

  /// §7.5.4: in a run with a banner the bottom spike strip moves this far
  /// down, under the bottom edge of the game view: 18 pt teeth + 6 pt base
  /// stay visible. Never below 20 → the 6 pt gap to the ad (§7.5.3).
  static const double bannerStripDrop = 20;

  /// §7.4: the banner fades in over this long when the bird starts flying.
  static const double bannerFadeIn = 0.25;
  // endregion PRD-2.2 §7.5

  // region PRD-2.2 §7.6 — interstitial after each run
  /// §7.6 guard 4 (PRD-2.3 §18.4 `ads_interstitial_min_gap_s`): no
  /// interstitial within this long after the previous full-screen ad
  /// (rewarded or interstitial) closed.
  static Duration get interstitialMinGap => Duration(
    seconds: TuningValues.current.i('ads_interstitial_min_gap_s'),
  );

  /// PRD-2.3 §18.2 (`ads_grace_runs`, replaces PRD-2.2's `interstitialFreeRuns`
  /// = 3): the new-player grace ends after this many finished runs …
  static int get adsGraceRuns => TuningValues.current.i('ads_grace_runs');

  /// … or after this much foreground playtime since install (s, §18.3;
  /// `ads_grace_seconds`), whichever comes first.
  static int get adsGraceSeconds => TuningValues.current.i('ads_grace_seconds');

  /// §7.8: how long the balloon bonus "▶ feather ×3" offer waits for a
  /// rewarded ad to load (WP-7b).
  static const Duration bonusAdWait = Duration(seconds: 5);

  /// §7.6 / §7.10: the Linux fake interstitial ("TEST AD") length (s).
  static const double fakeInterstitialSeconds = 3.0;
  // endregion PRD-2.2 §7.6

  // region PRD-2.2 §28 — audio around ads and other apps
  /// §28.3: for this long after a full-screen ad ended, the "other music
  /// playing" check is skipped (the ad's own player can still be listed).
  static const Duration adAudioSettle = Duration(seconds: 3);

  /// §28.3: at a scene change the "own music still playing?" re-check waits
  /// this long (s) so the scene's click / flap has rung out.
  static const double ownMusicRecheckDelay = .6;
  // endregion PRD-2.2 §28

  // region PRD-2.3 §13 — the music never stays silent without a reason
  /// §13.3 item 1: entries kept by the music diagnostic log.
  static const int musicLogSize = 50;

  /// §13.3 item 2: `music_held` is sent once per Home visit after the music
  /// has been held this long (s) with the music setting on.
  static const double musicHeldReportAfter = 10;

  /// §13.4: while the music is held for "own music" on a menu, the game
  /// re-checks this often (s).
  static const double musicOwnRecheckInterval = 2;

  /// §13.4: "own music" needs two "yes" answers at least this far apart (s).
  static const double musicOwnConfirmGap = 1;

  /// §13.4: the "own music" check on return to the foreground runs this long
  /// (s) after the return, so the previous app has finished pausing.
  static const double musicForegroundCheckDelay = 1;

  /// §13.4: while the music is held for an interruption or a notification,
  /// the game re-checks this often (s), not only on playback callbacks.
  static const double musicTransientPoll = .5;

  /// §13.4: a media sound that started while the game is in the foreground
  /// counts as the player's own music only once it has played this long (s):
  /// a notification ding of 1–2 s never does.
  static const double musicMediaSoundOwnAfter = 2;

  /// §13.4: a foreground media player must play this long (s) before it
  /// pauses the music (measured 2026-10-13 on the Pixel 6: a media player
  /// of another component opened and closed within 11 ms at launch).
  static const double musicMediaSoundDebounce = .3;

  /// §13.4: an ad suspend with no ad showing for longer than this (s) is
  /// cleared on any screen.
  static const double musicSuspendTimeout = 5;

  /// §13.4 music watchdog: how often (s) a menu checks the music player.
  static const double musicWatchdogInterval = 5;

  /// §13.4 watchdog: a player told to start / resume less than this long
  /// (s) ago is not judged yet (its state is still settling).
  static const double musicWatchdogGrace = 1;

  /// §13.4: where the platform cannot give a player's state, a listed
  /// notification player stops holding the music after this long (s): any
  /// ding has ended by then, so it can only be a finished, unreleased one.
  static const double musicUnknownNotificationMaxHold = 5;
  // endregion PRD-2.3 §13

  // Physics (Flappy Bird feel; an intentional, user-requested deviation from
  // the 2014 original's 1350/525 — see SPEC.md): a modest flap pop whose rise
  // is about half the final pipe gap, plus a terminal fall speed so dives
  // stay recoverable.
  static const double gravity = 1250; // pt/s^2 downward
  static const double flapVelocity = 370; // pt/s upward delta-v:
  // rise = v^2 / (2 * g) = 370^2 / 2500 ~= 55 pt (continuous, 60 fps alike)
  /// PRD-2 §3.0.1 max fall speed (pt/s, downward; was 500).
  static const double maxFallSpeed = 650;
  // PRD-2 §3.0.1: no fixed scroll speed any more — the world scrolls at the
  // bird's forward speed (`RunConfig.cruise`, 150 pt/s + 3.5 %/min).

  /// Longest simulation step in one frame. [FlappySpikesGame.update] clamps
  /// the frame's dt ONCE, so physics, the pipe spawner, fades, the colour
  /// crossfade and every component update share one clock: a stalled frame
  /// (app resumed from the background, debugger pause, the rewarded-ad
  /// wait) neither teleports the bird through pipes or into the spikes nor
  /// spawns overlapping pipe pairs — the whole game slows instead. 1/30 s
  /// still covers 30 fps devices without slowing them down.
  static const double maxFrameStep = 1 / 30;

  /// PRD-2.2 §33.4 item 5: frames per second of an idle menu (Home and
  /// Levels on top with nothing over it; owner 2026-10-17: never the Shop or
  /// Skins), settled and untouched for
  /// [idleMenuDelay]). Home's idle motion is slow (bob, pulse, streak), so
  /// half the display rate keeps its look and halves the CPU / GPU work.
  /// 0 = always the display rate.
  static const double idleMenuFps = 30;

  /// PRD-2.2 §33.4 item 5: seconds a menu must be settled (no touch, no
  /// fade, transition, count-up, coin flight or scroll glide) before
  /// [idleMenuFps] starts. Any touch returns to the display rate at once.
  static const double idleMenuDelay = 2;

  /// PRD-2.2 §33.4 item 5: the idle-frame timer fires this many seconds
  /// before the next idle frame is due, so the vsync after it is the right
  /// one (a late timer would skip a whole vsync).
  static const double idleMenuWakeLead = 0.006;

  // Collision categories (mirror the original bitmasks). PRD-2 §7: hoops,
  // rims and spikes are plain math, so nothing collides in Forge2D any more.
  static const int categoryBird = 0x1;
  static const int categoryWorld = 0x2;

  // Bird.
  /// PRD-2 §3.0.1 bird screen x in flight (was 80).
  static const double birdX = 70;
  static const double birdY = 284; // vertical center
  static final Vector2 birdSize = Vector2(46.5, 29.5);
  static const double birdRadius = 14.75; // sprite height / 2
  static const double idleFrameTime = 0.5;
  static const double flapFrameTime = 0.2;

  /// Points per art unit for the 2.0 look art ([LookPainter]'s 44 x 36 art
  /// box): the 30-unit art body square matches the 1.0 bird height
  /// (2 * [birdRadius] = 29.5), so the hitbox and physics stay untouched.
  static const double lookScale = 2 * birdRadius / 30; // 29.5 / 30
  // PRD-2 §3.0.5: the 1.0 death (impulse, restitution 0.1, spin 5π) is
  // replaced by the momentum tumble (`PhysicsConfig`).

  // Spike strips.
  /// PRD-2 §3.0.9 #1 spike strip height: band 26 + teeth 18 (was the 72 pt
  /// sprite strip).
  static const double spikeHeight = 44;
  static const double spikeTileWidth = 384;


  // UI sizes.
  static final Vector2 titleSize = Vector2(274.5, 147.5);
  static final Vector2 pointsfieldSize = Vector2(241.5, 82);
  static final Vector2 buttonSize = Vector2(241.5, 38.5);
  static final Vector2 settingsButtonSize = Vector2(30, 30);
  static final Vector2 gameCenterButtonSize = Vector2(30, 30);
  static final Vector2 gameCenterGameoverButtonSize = Vector2(60, 60);
  static final Vector2 scoreCircleSize = Vector2(183, 183);

  // PRD-2.3 §5.5: the privacy policy moved to flappyspikes.com (the GitHub
  // Pages copy only points here now). Linked from Settings.
  static const String privacyPolicyUrl = 'https://flappyspikes.com/privacy';

  // PRD-2.3 §5.6: the website, and the one share link of every share and
  // invite text (written without https://; /get redirects per device).
  static const String siteUrl = 'https://flappyspikes.com';
  static const String shareUrl = 'flappyspikes.com/get';

  // PRD-2.3 §20.3: the Settings links (no URL is written inline in a
  // component).
  static const String supportUrl = 'https://flappyspikes.com/support';
  static const String deleteDataUrl = 'https://flappyspikes.com/delete-data';

  // PRD-2.3 §22.2: Settings → Redeem code opens the Play Store's redeem
  // screen. Owner 2026-10-13: the bare `/redeem` link makes the Play app
  // hand it on to the browser (wrong account possible); with an empty
  // `code` it opens Play's own Redeem code screen for the Play account.
  static const String redeemCodeUrl = 'https://play.google.com/redeem?code=';

  // PRD-2.3 §22.2: the purchase sync (launch, every resume) runs at most
  // this often.
  static const Duration iapSyncInterval = Duration(seconds: 5);

  // PRD-2.3 §24.3 (QA S8-13): a restore / redeem at launch applies before
  // the first run. The session's first START waits at most this long (game
  // seconds) for the launch purchase sync still running, then starts anyway.
  static const double launchOwnershipStartWait = 1.5;

  // The Play listing. PRD-2.3 §5.6: no longer shared anywhere; kept for a
  // direct store link the app opens itself.
  static const String storeListingUrl =
      'https://play.google.com/store/apps/details?id=com.flappyspikes.flappy_spikes';

  // region PRD-2.3 §3 approved share texts (2026-10-12). The analytics ids
  // (§2.1 `text_id` / `banner_id`) are the 1-based positions in these lists.
  /// §3.1 share texts; `{score}` = the run's points on the card's sticker.
  static const List<String> shareTexts = [
    'I scored {score} points in Flappy Spikes 🐦 Think you can beat me? $shareUrl',
    '{score} points in Flappy Spikes. Beat that, I dare you 😏 $shareUrl',
    'Just hit {score} points in Flappy Spikes 🐦 Your move. $shareUrl',
    "{score} points in Flappy Spikes. Bet you can't top it 😎 $shareUrl",
    'I got {score} points in Flappy Spikes 🔥 Can you do better? $shareUrl',
  ];

  /// §3.2 banner texts on the share cards.
  static const List<String> shareBanners = [
    'BEAT MY SCORE!',
    'TRY TO BEAT ME!',
    'I DARE YOU!',
    'CAN YOU BEAT IT?',
    'THINK YOU CAN WIN?',
  ];

  /// §3.3 new-player invite texts (Invite tile, best = 0; no score).
  static const List<String> inviteTexts = [
    'Can you beat me at Flappy Spikes? $shareUrl',
    "Bet you can't beat me at Flappy Spikes! $shareUrl",
    'Come play Flappy Spikes with me, I dare you! $shareUrl',
  ];

  /// §12 the tagline (the home subtitle), in capitals.
  static const String tagline = 'FLAP FAST, FLY FAR';
  // endregion PRD-2.3 §3

  // UI positions. The helpers take the playfield center Y (viewHeight / 2)
  // and reproduce the original 320x568 layout exactly at centerY = 284
  // (SpriteKit y-up coordinates from SPEC converted to Flame's y-down).
  static Vector2 titlePositionFor(double centerY) =>
      Vector2(160, centerY - 147.5 / 2 - 35); // 175.25 at 284
  static Vector2 bestLabelPositionFor(double centerY) =>
      Vector2(160, centerY + 120); // 404 at 284
  static Vector2 gamesLabelPositionFor(double centerY) =>
      Vector2(160, centerY + 150); // 434 at 284
  static Vector2 settingsButtonPositionFor(double centerY) =>
      Vector2(160, centerY); // screen center
  static Vector2 scoreHudPositionFor(double centerY) =>
      Vector2(160, centerY + 35); // 319 at 284
  static Vector2 pointsfieldPositionFor(double centerY) =>
      Vector2(160, centerY - 41); // 243 at 284
  static Vector2 replayButtonPositionFor(double centerY) =>
      Vector2(160, centerY + 19.25 + 6); // 309.25 at 284
  static Vector2 shareButtonPositionFor(double centerY) =>
      Vector2(160, centerY + 3 * 19.25 + 12); // 353.75 at 284
  // Leaderboard buttons (positions from the 2014 original,
  // FlappySpikes/Flappy Spikes/GameScene.m): on the start scene at 3/4 width,
  // screen middle; on the game-over scene at the right side of the points
  // field, vertically centered on it.
  static Vector2 gameCenterButtonPositionFor(double centerY) =>
      Vector2(240, centerY); // (240, 284) at 284
  static Vector2 gameCenterGameoverButtonPositionFor(double centerY) =>
      Vector2(240.5, centerY - 41); // (240.5, 243) at 284
  // Privacy-policy link at the bottom of the start scene, just above the
  // ground spikes.
  static Vector2 privacyLinkPositionFor(double centerY) =>
      Vector2(160, 2 * centerY - 92); // 476 at 284 (above the 1.0 strip)
  // Transient service-failure message (ServiceMessage): bottom-center, the
  // same free band the privacy link used before it moved into settings —
  // visible on both the start and game-over scenes.
  static Vector2 serviceMessagePositionFor(double centerY) =>
      Vector2(160, 2 * centerY - 92); // 476 at 284 (above the 1.0 strip)

  // Game-over coin line ("+N" + coin, PRD-1 §4.2): below the games label,
  // in the free band above the ground spikes (466 at 284).
  static Vector2 coinsEarnedPositionFor(double centerY) =>
      Vector2(160, centerY + 182);
  static const double coinsEarnedFontSize = 22;
  static const double coinsEarnedIconSize = 18;

  // Fixed positions at the design height (kept for tests and defaults).
  static final Vector2 titlePosition = titlePositionFor(284);
  static final Vector2 bestLabelPosition = bestLabelPositionFor(284);
  static final Vector2 gamesLabelPosition = gamesLabelPositionFor(284);
  static final Vector2 settingsButtonPosition = settingsButtonPositionFor(284);
  static final Vector2 scoreHudPosition = scoreHudPositionFor(284);
  static final Vector2 pointsfieldPosition = pointsfieldPositionFor(284);
  static final Vector2 replayButtonPosition = replayButtonPositionFor(284);
  static final Vector2 shareButtonPosition = shareButtonPositionFor(284);
  static final Vector2 gameCenterButtonPosition = gameCenterButtonPositionFor(
    284,
  );
  static final Vector2 gameCenterGameoverButtonPosition =
      gameCenterGameoverButtonPositionFor(284);
  static final Vector2 privacyLinkPosition = privacyLinkPositionFor(284);
  static final Vector2 serviceMessagePosition = serviceMessagePositionFor(284);

  // --- Home screen v3 (PRD-home-v3 §3.1, design/menu_v2/
  // screen_home_final_v2.html = build78 / build77) ---------------------------
  //
  // Rects are in world points at a given playfield height. The §3.1 table is
  // measured at 711 pt and reproduced exactly there. Vertical rule: the top
  // part (top row, title, subtitle, emblem stage) is pinned to the top; the
  // tile row keeps its 711 distance to the bottom edge (compressing a little
  // toward 568); the START + slot block is centred in the band between the
  // emblem's ribbon and the tile row. When that band gets too small (short
  // screens) the emblem stage scales down about its top edge, to at least
  // emblem 0.78 / bird 1.1 (Q-H3), and then the gaps shrink evenly.

  /// Fixed menu chrome colours (not stage-tinted).
  static const Color menuPink = Color(0xFFEC008C);
  static const Color menuPinkDark = Color(0xFFC40073);
  static const Color menuSoft = Color(0xFFFCD9EE);
  static const Color menuGold = Color(0xFFFFB529);
  static const Color menuPlum = Color(0xFF7A0044);

  /// Height at which the PRD table was measured.
  static const double homeReferenceHeight = 711;
  // 2.0 DEVIATION (product owner, 2026-10-04): gear / back button top-left,
  // coin pill top-right. Gear = BEST = Shop tile left edge (14); pill right
  // edge = LAST = No-ads tile right edge (306).
  static const double homeMargin = 14; // gear / BEST / shop tile left edge
  static const double homeRightEdge = worldWidth - homeMargin; // 306 (pill)
  static const double homeTopRowY = 58; // gear + trophy + pill band 58..96
  static const double homeTopRowHeight = 38;

  /// The trophy box (moved from the bottom row into the top row; opens the
  /// Play Games leaderboard) and its 24 pt glyph.
  static const double homeTrophyLeft = 60;
  static const double homeTrophyIconSize = 24;

  /// Owner 2026-10-17 (design/logo_home, size S): the logo image replaces the
  /// "Flappy Spikes" title text: 150 pt wide, top at 100; the tagline moves
  /// under it to 183. (The title font size stays for the debug hotspot.)
  static const double homeTitleTop = 100;
  static const double homeLogoWidth = 150;
  static const double homeLogoAspect = 600 / 352; // assets/images/menu/logo.png
  static const double homeTitleFontSize = 34;
  static const double homeSubtitleTop = 183;
  static const double homeSubtitleFontSize = 13;
  static const double homeSubtitleLetterSpacing = 0.14; // em

  /// Emblem + bird stage: 264 x 204 at (28, 148), the plate centre at 52 %
  /// of its height (160, 254); emblem art scale 0.936, bird 1.32 (points
  /// per art unit). Scaled down to [homeStageMinScale] on short screens.
  static const double homeStageTop = 148;
  static const double homeStageWidth = 264;
  static const double homeStageHeight = 204;
  static const double homePlateYFraction = 0.52;
  static const double homeEmblemScale = 0.936;
  static const double homeBirdScale = 1.32;

  /// Smallest stage scale: emblem 0.78 / bird 1.1 (the build76 variation;
  /// below it only for [homeStartTightGap], PRD-2.2 §2.1).
  static const double homeStageMinScale = 0.78 / homeEmblemScale;

  /// How far the emblem's ribbon reaches below the plate centre (art units).
  static const double homeEmblemReach = 70;

  /// Smallest gap above / below the START + slot block before the emblem
  /// starts scaling down.
  static const double homeStartMinGap = 24;

  /// PRD-2.2 §2.1 with the mode button row in the START block, the block no
  /// longer fits the 568 pt band at the floor scale: there the stage shrinks
  /// past [homeStageMinScale] just enough to keep this gap above and below
  /// the block (clear of the slot's 3 pt outline and of the Skins NEW tag,
  /// which sticks 6 pt above its tile; emblem ≈ 0.71 / bird ≈ 1.0 at 568).
  static const double homeStartTightGap = 8;

  /// BEST / LAST flank columns: 70 wide, label 12 pt (0.18 em, 13 pt line
  /// + 2) over the number 30 pt (0.02 em, 33 pt line), centred on the
  /// plate; BEST gold, LAST stage fg.
  static const double homeFlankWidth = 70;
  static const double homeFlankLabelFontSize = 12;
  static const double homeFlankLabelLetterSpacing = 0.18;
  static const double homeFlankLabelLine = 13;
  static const double homeFlankLabelGap = 2;
  static const double homeFlankNumberFontSize = 30;
  static const double homeFlankNumberLetterSpacing = 0.02;
  static const double homeFlankNumberLine = 33;
  /// A 4+ digit number shrinks to this width: the 70 pt column less the
  /// tips of LEGEND's wings (they reach x 80 / 240).
  static const double homeFlankNumberMaxWidth = 62;
  static const double homeFlankHeight =
      homeFlankLabelLine + homeFlankLabelGap + homeFlankNumberLine; // 48

  /// START 216 x 67 (label 34 pt, play glyph 28, gap 10) and the powerup
  /// slot 216 x 31 4 pt below it (label 17 pt).
  static const double homeStartWidth = 216;
  static const double homeStartHeight = 67;
  static const double homeStartFontSize = 34;
  static const double homeStartIconSize = 28;
  static const double homeSlotHeight = 31;
  static const double homeSlotFontSize = 17;
  static const double homeSlotGap = 4; // START bottom -> slot top
  static const double homeSlotOutline = 3; // bg-coloured outline
  static const double homeStartBlockHeight =
      homeStartHeight + homeSlotGap + homeSlotHeight; // 102
  static const double homeStartLeft = (worldWidth - homeStartWidth) / 2; // 52

  // --- PRD-2.2 §2.1 mode button (VERSUS / FREE FLY) + VS tag on START,
  // approved design screen_mode_toggle3.html (drawn at 1.5x) ---------------

  /// PRD-2.2 §2.1 mode button: 147 x 21, right edge = START's right edge,
  /// 5 pt above START's top.
  static const double homeModeWidth = 147;
  static const double homeModeHeight = 21;
  static const double homeModeGap = 5;

  /// PRD-2.2 §2.1 the gold MODE part: 41 wide, "MODE" 8.7 pt / 0.14 em in
  /// plum #6A0040.
  static const double homeModePartWidth = 41;
  static const double homeModePartFontSize = 8.7;
  static const double homeModePartLetterSpacing = 0.14; // em
  static const Color homeModePlum = Color(0xFF6A0040);

  /// PRD-2.2 §2.1 the mode field (the rest): 12.7 pt / 0.16 em. VERSUS pink
  /// on pale pink; FREE FLY dark teal on pale sky-teal (teal is FREE FLY's
  /// own accent, used nowhere else).
  static const double homeModeFieldFontSize = 12.7;
  static const double homeModeFieldLetterSpacing = 0.16; // em
  static const Color homeModeVersusField = menuSoft; // #FCD9EE
  static const Color homeModeVersusText = menuPink; // #EC008C
  static const Color homeModeFreeFlyField = Color(0xFFD6F2F5);
  static const Color homeModeFreeFlyText = Color(0xFF0D8595);

  /// PRD-2.2 §2.1 the parts swap sides in 0.22 s with the mock's
  /// cubic-bezier(.3, 1.4, .5, 1) overshoot; the field colour cross-fades.
  static const double homeModeSwapDuration = 0.22;

  /// PRD-2.2 §2.1 press feedback: 96 % while pressed.
  static const double homeModePressedScale = 0.96;

  /// PRD-2.2 §2.2 the hit area is the whole button plus 6 pt.
  static const double homeModeHitPadding = 6;

  /// PRD-2.2 §2.1 VS tag (VERSUS only): gold, white "VS" 10.7 pt, 31 x 17,
  /// 9 pt in from START's left edge and 8 pt above START's top (half
  /// outside). Pops in 0.4 -> 1 over 0.22 s (mock cubic-bezier(.3, 1.6,
  /// .5, 1)); fades out in 0.18 s.
  static const double homeVsTagWidth = 31;
  static const double homeVsTagHeight = 17;
  static const double homeVsTagFontSize = 10.7;
  static const double homeVsTagLetterSpacing = 0.06; // em
  static const double homeVsTagInset = 9;
  static const double homeVsTagRise = 8;
  static const double homeVsTagPopDuration = 0.22;
  static const double homeVsTagFadeDuration = 0.18;
  static const double homeVsTagFromScale = 0.4;

  /// PRD-2.2 §2.1 the START block that is centred between the emblem and
  /// the tiles: the mode button row (21 + 5) above START + slot (102).
  static const double homeStartGroupHeight =
      homeModeHeight + homeModeGap + homeStartBlockHeight; // 128

  static const int homeTileCount = 4;
  static const double homeTileWidth = 70;
  static const double homeTileHeight = 92;
  static const double homeTileGap = 4;
  static const double homeTileIconSize = 38;
  // Owned No-ads tile: the check glyph (24-unit viewBox, ink ~16 x 12.5)
  // drawn in the icon slot in the same 38 pt box as the crossed-AD icon.
  static const double homeTileCheckSize = homeTileIconSize;

  /// 0 at 568, 1 at 711 (and above).
  static double _homeT(double viewHeight) =>
      ((viewHeight - minViewHeight) / (homeReferenceHeight - minViewHeight))
          .clamp(0.0, 1.0);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Top of the tile row: 149 pt above the bottom edge at 711 (y 562, 13 pt
  /// above the menu spike tips), 146 at 568 (10 pt above them).
  static double homeTileRowTopFor(double viewHeight) =>
      viewHeight - _lerp(146, 149, _homeT(viewHeight));

  /// Emblem stage scale (1 = the §3.1 size): shrinks when the START block
  /// would get less than [homeStartMinGap] above / below it, down to
  /// [homeStageMinScale].
  static double homeStageScaleFor(double viewHeight) {
    const reach =
        homeStageHeight * homePlateYFraction + homeEmblemReach * homeEmblemScale;
    final room =
        homeTileRowTopFor(viewHeight) -
        2 * homeStartMinGap -
        homeStartGroupHeight -
        homeStageTop;
    final k = (room / reach).clamp(homeStageMinScale, 1.0);
    final tight =
        (homeTileRowTopFor(viewHeight) -
            2 * homeStartTightGap -
            homeStartGroupHeight -
            homeStageTop) /
        reach;
    return tight < k ? tight : k;
  }

  /// The emblem + bird stage (tap area) at [viewHeight], centred on x 160.
  static Rect homeStageRectFor(double viewHeight) {
    final k = homeStageScaleFor(viewHeight);
    return Rect.fromLTWH(
      (worldWidth - homeStageWidth * k) / 2,
      homeStageTop,
      homeStageWidth * k,
      homeStageHeight * k,
    );
  }

  /// The emblem plate centre (160, 254 at 711).
  static Offset homePlateCentreFor(double viewHeight) {
    final stage = homeStageRectFor(viewHeight);
    return Offset(
      worldWidth / 2,
      stage.top + stage.height * homePlateYFraction,
    );
  }

  /// Emblem art scale (0.936 at full size, 0.78 at the minimum).
  static double homeEmblemScaleFor(double viewHeight) =>
      homeEmblemScale * homeStageScaleFor(viewHeight);

  /// Bird art scale (1.32 at full size, 1.1 at the minimum).
  static double homeBirdScaleFor(double viewHeight) =>
      homeBirdScale * homeStageScaleFor(viewHeight);

  /// Bottom of the emblem's ribbon (≈ 320 at 711).
  static double homeEmblemBottomFor(double viewHeight) =>
      homePlateCentreFor(viewHeight).dy +
      homeEmblemReach * homeEmblemScaleFor(viewHeight);

  /// Top of the START block (PRD-2.2 §2.1: the mode button's top), the
  /// mode button + START + slot block centred between the emblem bottom and
  /// the tile row, on whole points (377 at 711).
  static double homeStartGroupTopFor(double viewHeight) =>
      ((homeEmblemBottomFor(viewHeight) + homeTileRowTopFor(viewHeight)) / 2 -
              homeStartGroupHeight / 2)
          .roundToDouble();

  /// Top of the START button: below the mode button row (403 at 711; 390
  /// before PRD-2.2 §2.1 added the mode button to the block).
  static double homeStartTopFor(double viewHeight) =>
      homeStartGroupTopFor(viewHeight) + homeModeHeight + homeModeGap;

  /// PRD-2.2 §2.1 the mode button: right-aligned with START, 5 pt above it.
  static Rect homeModeRectFor(double viewHeight) => Rect.fromLTWH(
    homeStartLeft + homeStartWidth - homeModeWidth,
    homeStartTopFor(viewHeight) - homeModeGap - homeModeHeight,
    homeModeWidth,
    homeModeHeight,
  );

  /// PRD-2.2 §2.1 the VS tag on START's top-left corner.
  static Rect homeVsTagRectFor(double viewHeight) => Rect.fromLTWH(
    homeStartLeft + homeVsTagInset,
    homeStartTopFor(viewHeight) - homeVsTagRise,
    homeVsTagWidth,
    homeVsTagHeight,
  );

  /// TOP-RIGHT corner of the coin pill: the pill grows leftwards with the
  /// balance, its right edge pinned to [homeRightEdge].
  static Vector2 homeCoinPillPositionFor(double viewHeight) =>
      Vector2(homeRightEdge, homeTopRowY);
  static Rect homeGearRectFor(double viewHeight) => Rect.fromLTWH(
    homeMargin,
    homeTopRowY,
    homeTopRowHeight,
    homeTopRowHeight,
  );
  static Rect homeTrophyRectFor(double viewHeight) => Rect.fromLTWH(
    homeTrophyLeft,
    homeTopRowY,
    homeTopRowHeight,
    homeTopRowHeight,
  );
  // Title / subtitle positions are the TOP-CENTRE of their line boxes.
  static Vector2 homeTitlePositionFor(double viewHeight) =>
      Vector2(worldWidth / 2, homeTitleTop);
  static Vector2 homeSubtitlePositionFor(double viewHeight) =>
      Vector2(worldWidth / 2, homeSubtitleTopFor(viewHeight));

  /// Owner 2026-10-17 logo (size S): the tagline sits [homeSubtitleAboveFlank]
  /// above the BEST / LAST row (183 on 640 pt and taller screens); on shorter
  /// screens the row moves up, the tagline with it, and the logo shrinks to
  /// fit between the top row and the tagline ([homeLogoWidthFor]).
  static double homeSubtitleTopFor(double viewHeight) => math.min(
    homeSubtitleTop,
    homeFlankRectFor(viewHeight, right: false).top - homeSubtitleAboveFlank,
  );
  static const double homeSubtitleAboveFlank = 47;

  /// The logo's width: [homeLogoWidth] (150) where it fits, else as wide as
  /// the band from [homeTitleTop] to just under the tagline's top allows.
  static double homeLogoWidthFor(double viewHeight) => math.min(
    homeLogoWidth,
    (homeSubtitleTopFor(viewHeight) + homeLogoTaglineOverlap - homeTitleTop) *
        homeLogoAspect,
  );
  static const double homeLogoTaglineOverlap = 5; // the logo's soft shadow

  /// BEST (left, x 14) / LAST ([right], right edge 306) column, centred
  /// vertically on the plate.
  static Rect homeFlankRectFor(double viewHeight, {required bool right}) =>
      Rect.fromLTWH(
        right ? homeRightEdge - homeFlankWidth : homeMargin,
        homePlateCentreFor(viewHeight).dy - homeFlankHeight / 2,
        homeFlankWidth,
        homeFlankHeight,
      );

  static Rect homeStartRectFor(double viewHeight) => Rect.fromLTWH(
    homeStartLeft,
    homeStartTopFor(viewHeight),
    homeStartWidth,
    homeStartHeight,
  );
  static Rect homeSlotRectFor(double viewHeight) => Rect.fromLTWH(
    homeStartLeft,
    homeStartTopFor(viewHeight) + homeStartHeight + homeSlotGap,
    homeStartWidth,
    homeSlotHeight,
  );

  /// Tile [index] of the row: 0 Shop, 1 Skins, 2 Invite, 3 No ads.
  static Rect homeTileRectFor(double viewHeight, int index) => Rect.fromLTWH(
    homeMargin + index * (homeTileWidth + homeTileGap),
    homeTileRowTopFor(viewHeight),
    homeTileWidth,
    homeTileHeight,
  );

  /// Short-lived toasts on the home screen: centred in the gap between the
  /// powerup slot and the tile row.
  static Vector2 homeToastPositionFor(double viewHeight) {
    final slot = homeSlotRectFor(viewHeight);
    return Vector2(
      worldWidth / 2,
      (slot.bottom + homeTileRowTopFor(viewHeight)) / 2,
    );
  }

  /// Tap on the emblem stage -> LEVELS opens this much later (§3.3), with
  /// a fade + 14 pt rise over [levelsEnterDuration].
  static const double homeEmblemTapDelay = 0.17;
  static const double levelsEnterDuration = 0.22;
  static const double levelsEnterRise = 14;

  /// The home emblem's upgrade pop after a LEVEL UP claim (§4.3): 0.6 ->
  /// 1.15 -> 1 over 0.7 s.
  static const double homeEmblemPopDuration = 0.7;

  /// LEVEL UP trigger (Q-H1 interim): the popup opens once home has been
  /// up, with nothing over it, for this long.
  static const double levelUpSettleDelay = 0.35;

  // --- LEVELS screen (PRD-home-v3 §4.4, build74 `.lvh` / `.lvl`) -----------
  static const double levelsTitleTop = 106;
  static const Rect levelsHeaderRect = Rect.fromLTWH(14, 150, 292, 84);
  static const double levelsHeaderEmblemBox = 84;
  static const double levelsHeaderEmblemScale = 0.34;
  static const double levelsHeaderEmblemY = 44; // plate centre in the box
  static const double levelsHeaderNameFontSize = 20;
  static const double levelsHeaderStatsFontSize = 11;
  static const double levelsBarWidth = 186;
  static const double levelsBarHeight = 16;
  static const double levelsBarFontSize = 10;
  static const double levelsHeaderMix = 0.15; // card: fg 15 % over bg
  static const double levelsListTop = 242;
  static const double levelsListPadTop = 4;
  static const double levelsListPadBottom = 26;
  static const double levelsRowHeight = 72;
  static const double levelsRowGap = 6;
  static const double levelsRowMix = 0.09; // row: fg 9 % over bg
  static const double levelsRowEmblemWidth = 84;
  static const double levelsRowEmblemScale = 0.29;
  static const double levelsRowEmblemY = 37;
  static const double levelsRowNameFontSize = 17;
  static const double levelsRowReachFontSize = 11;
  static const double levelsChipHeight = 28;
  static const double levelsChipTop = 22;
  static const double levelsChipRight = 8;
  static const double levelsChipPad = 9;
  static const double levelsChipFontSize = 15;
  static const double levelsChipCoinSize = 15;
  static const double levelsCurrentOutline = 3;

  /// Bird on an emblem in the LEVELS header / rows / popup: 1.4 x the
  /// emblem's art scale (build74 `paintEmb`).
  static const double levelsBirdOnEmblem = 1.4;

  /// World y of row [index] (0 = EGG) at scroll 0.
  static double levelsRowTop(int index) =>
      levelsListTop + levelsListPadTop + index * (levelsRowHeight + levelsRowGap);

  // --- LEVEL UP popup (PRD-home-v3 §4.3, build74 `.pcard`) ------------------
  static const double levelUpCardWidth = 280;
  static const double levelUpHeaderHeight = 178;
  static const double levelUpTitleHeight = 45;
  static const double levelUpTitleFontSize = 22;
  static const double levelUpBodyPadTop = 14;
  static const double levelUpBodyPad = 16;
  static const double levelUpSmallFontSize = 12;
  static const double levelUpNameFontSize = 30;
  static const double levelUpButtonHeight = 50;
  static const double levelUpButtonGap = 14;
  static const double levelUpButtonFontSize = 22;
  static const double levelUpCoinSize = 22;
  static const double levelUpEmblemScale = 0.72;
  static const double levelUpEmblemY = 96; // in the header
  static const double levelUpPopDuration = 0.45;
  static const double levelUpCardPopDuration = 0.26;
  static const double levelUpConfettiDelay = 0.18;
  static const double levelUpCardHeight =
      levelUpHeaderHeight +
      levelUpTitleHeight +
      levelUpBodyPadTop +
      levelUpSmallFontSize * 1.284 +
      2 +
      levelUpNameFontSize * 1.284 +
      4 +
      levelUpSmallFontSize * 1.284 +
      levelUpButtonGap +
      levelUpButtonHeight +
      levelUpBodyPad; // ≈ 392

  /// The card, centred on the screen (x 20 -> 300).
  static Rect levelUpCardRectFor(double viewHeight) => Rect.fromLTWH(
    (worldWidth - levelUpCardWidth) / 2,
    (viewHeight - levelUpCardHeight) / 2,
    levelUpCardWidth,
    levelUpCardHeight,
  );

  /// Menus and runs show the same 44 pt strip since PRD-2 §3.0.9 #1 (it
  /// was 28 pt shorter than the 72 pt run strip in 1.0/2.0 menus).
  static const double menuSpikeInset = 0;

  // PRD-2.2 §20: the run bird keeps its own colours at every stage, so the
  // old stage blend (0.35 toward the stage foreground from stage 5) is gone.
  // Only the themed death tints (`Bird.deathTint`, PRD-2 §5.17) blend a look.

  /// Height of the menus' short spike strips (spike tips 44 pt from the
  /// edge).
  static const double menuSpikeHeight = spikeHeight - menuSpikeInset; // 44

  /// Depth of the spike teeth (tip to the solid band; PRD-2 §3.0.9 #1:
  /// 18 pt). Menu scroll lists show through the gaps between the bottom
  /// teeth down to this depth below the tips.
  static const double menuSpikeToothDepth = 18;

  // --- Shared menu-screen chrome (Shop, Skins; PRD-1 §5) --------------------
  //
  // Back button top-left in the gear's place, coin pill top-right (as on
  // home; [menuScreenPillPositionFor] is its top-right corner), title
  // centred at the top; the content scrolls in the band between the title
  // and the bottom spike tips. Everything is pinned to the top.

  static Vector2 menuScreenPillPositionFor(double viewHeight) =>
      homeCoinPillPositionFor(viewHeight);
  static Rect menuScreenBackRectFor(double viewHeight) =>
      homeGearRectFor(viewHeight);
  static const double menuScreenTitleTop = 104;
  static const double menuScreenTitleFontSize = 30;
  static const double menuScreenTitleLetterSpacing = 0.06; // em
  // Top-centre of the title's line box.
  static Vector2 menuScreenTitlePositionFor(double viewHeight) =>
      Vector2(worldWidth / 2, menuScreenTitleTop);

  /// Scrolling content viewport: from just below the title's line box
  /// (104 + 30 x 1.284) to the bottom spike tips.
  static double menuScreenContentTopFor(double viewHeight) => 143;
  static double menuScreenContentBottomFor(double viewHeight) =>
      viewHeight - menuSpikeHeight;

  /// Toasts over a menu screen (Shop, Skins, Settings): a chip centred in
  /// the band just above the bottom spike tips (643 at 711).
  static Vector2 menuScreenToastPositionFor(double viewHeight) =>
      Vector2(worldWidth / 2, viewHeight - menuSpikeHeight - 24);

  /// Card behind content blocks (packs, featured row): the stage foreground
  /// at this opacity over the background (mock `color-mix(fg 14%, bg)`).
  static const double menuCardMix = 0.14;

  // --- Shop and Skins lock (PRD-2.3 §26.2) ----------------------------------

  /// The lock overlay's text: 24 pt Opificio, .06 em, two centred lines
  /// [menuLockLineHeight] apart.
  static const double menuLockFontSize = 24;
  static const double menuLockLetterSpacing = 0.06; // em
  static const double menuLockLineHeight = 31;

  /// PRD-2.3 §26.2 the lock overlay's dim: #000000 at 90 % (owner
  /// 2026-10-13; was 72 %), over the whole playfield edge to edge,
  /// including both spike strips.
  static const Color menuLockDimColor = Color(0xE6000000);

  /// PRD-2.3 §26.2 (owner 2026-10-13) the lock overlay's world priority:
  /// above the menu screens (20) and the ground strip over them (21), below
  /// popups, toasts and flashes (25+).
  static const int menuLockOverlayPriority = 22;

  /// PRD-2.3 §26.2 (owner 2026-10-13) the coin pill's priority while a lock
  /// overlay is up: above it, so the pill stays bright and tappable.
  static const int menuLockPillPriority = 23;

  /// The gold lock badge on a Home tile (in the corner where the NEW tag sits)
  /// and the lock icon inside it (pt).
  static const double homeLockBadgeSize = 20;
  static const double homeLockIconSize = 12;

  // --- Menu list momentum scrolling (product decision 2026-10-07) ----------
  //
  // Every menu scroll list (skin shop grid, Shop, LEVELS, any
  // [MenuScrollArea]) flings after a release, rubber-bands past its edges and
  // springs back. Physics lives here so the feel is tunable in one place.

  /// Fraction of the release velocity kept per second while flinging
  /// (`v(t) = v0 * pow(menuScrollFlingDecay, t)`). A quick ~2000 pt/s flick
  /// travels ~1.3 viewports before it stops.
  static const double menuScrollFlingDecay = 0.07;

  /// A release slower than this (pt/s) does not fling.
  static const double menuScrollMinFlingVelocity = 40;

  /// Flings are capped at this initial speed (pt/s).
  static const double menuScrollMaxFlingVelocity = 4000;

  /// The glide stops below this speed (pt/s).
  static const double menuScrollRestVelocity = 6;

  /// Drag slop (world pt): a press that travels further than this is a
  /// scroll, never a tap: the drag wins the gesture arena, so every pressed
  /// tile / button cancels (QA S1-50). Flutter's default (18 logical px) is
  /// replaced by this, converted to logical px at the current camera scale,
  /// while a [MenuScrollArea] is mounted.
  static const double menuScrollSlop = 6;

  /// Release velocity = average of the drag samples of the last this many
  /// seconds (older samples are stale and ignored).
  static const double menuScrollVelocityWindow = 0.07;

  /// Rubber band: the displayed overshoot asymptotes at this share of the
  /// viewport height, so dragging further gets ever more resistance.
  static const double menuScrollRubber = 0.18;

  /// Critically damped spring back to an edge (~0.35 s to settle).
  static const double menuScrollSpringOmega = 19;
  static const double menuScrollSpringRestDistance = 1; // pt
  static const double menuScrollSpringRestVelocity = 20; // pt/s
  static const double menuScrollSpringMaxDuration = 1.0; // s

  // --- Shop (PRD-1 §5.2, design S1-B; content coordinates = world
  // coordinates before scrolling, measured at 711 and top-pinned) ---------

  static const double shopRowWidth = homeRightEdge - homeMargin; // 292
  static Rect shopBannerRectFor(double viewHeight) =>
      const Rect.fromLTWH(homeMargin, 146, shopRowWidth, 52);
  static Rect shopFreeCoinsRectFor(double viewHeight) =>
      const Rect.fromLTWH(homeMargin, 206, shopRowWidth, 44);

  static const double shopPackWidth = 142;
  static const double shopPackHeight = 150;
  static const double shopPackGap = 8; // 14 + 142 + 8 = 164
  static const double shopPackRowTop = 266;
  static const double shopPackRowStep = 160; // 266 -> 426

  /// Coin pack card [index] (0 = 500, 1 = 1,800, 2 = 5,000, 3 = 12,000), in
  /// a 2 x 2 grid.
  static Rect shopPackRectFor(double viewHeight, int index) => Rect.fromLTWH(
    homeMargin + (index % 2) * (shopPackWidth + shopPackGap),
    shopPackRowTop + (index ~/ 2) * shopPackRowStep,
    shopPackWidth,
    shopPackHeight,
  );

  /// Inside a pack card: the pack art box's top-left (PRD-menu-v4 §2.1,
  /// mock `.packart` 120 x 68 at 11 / 12), the amount's line box top and
  /// the price button height.
  static const double shopPackArtLeft = 11;
  static const double shopPackArtTop = 12;
  static const double shopPackAmountTop = 82.875;
  static const double shopPackPriceHeight = 38;
  // Gold flap tag centred on the card's top edge.
  static const double shopPackTagHeight = 24;
  static const double shopPackTagPadX = 10;

  static Rect shopFeaturedRectFor(double viewHeight) =>
      const Rect.fromLTWH(homeMargin, 588, shopRowWidth, 56);

  /// Bottom of the scrollable content (22 pt below the featured row, where
  /// the restore link ended before PRD-home-v3 §9 moved it to Settings):
  /// fits the 667 pt viewport at 711 without scrolling.
  static double shopContentBottomFor(double viewHeight) => 666;

  /// Content y the "+" of the coin pill scrolls to the top of the viewport:
  /// just above the first row of packs' flap tags.
  static double shopCoinsAnchorFor(double viewHeight) =>
      shopPackRowTop - shopPackTagHeight / 2 - 8;

  /// How long a restore may stay silent before "Nothing to restore".
  static const double restoreTimeout = 4;

  // --- Skin shop (PRD-menu-v2 §4.1, layout A; world coordinates measured at
  // 711 and top-pinned — only the grid's bottom follows the view height) ----

  /// Collection bar ("owned / 88") under the coin pill.
  static const Rect skinShopBarRect = Rect.fromLTWH(70, 100, 180, 18);
  static const double skinShopBarFontSize = 12;
  static const double skinShopBarLetterSpacing = 0.08; // em
  static const double skinShopBarPopScale = 1.12;
  static const double skinShopBarPopDelay = 0.5;
  static const double skinShopBarPopDuration = 0.4;
  static const double skinShopBarFillDelay = 0.4;
  static const double skinShopBarFillDuration = 0.6;

  /// Live preview stage: background = fg at [skinShopStageMix] over bg.
  static const Rect skinShopStageRect = Rect.fromLTWH(14, 126, 292, 138);
  static const double skinShopStageMix = 0.09;
  static const double skinShopBirdScale = 1.9;
  static const double skinShopBirdX = 0.42; // share of the stage width
  static const double skinShopBobAmplitude = 3;
  static const double skinShopBobSpeed = 3.2; // rad/s
  static const double skinShopHopKick = 150; // pt/s upwards
  static const double skinShopHopGravity = 900; // pt/s²
  static const double skinShopHoopInterval = 2.3;
  static const double skinShopHoopFirst = 0.8;
  static const double skinShopHoopSpeed = 120; // pt/s
  static const double skinShopHoopRy = 26; // art units (x bird scale)
  static const double skinShopTrailScroll = -150; // emitter vx
  /// Frames of 1/60 s the preview's trail runs before it is first drawn (on
  /// open, after an equip or a try-on): the rainbow ribbon's 120-point
  /// history is full at once.
  static const int skinShopTrailSeedFrames = 120;

  /// Name row (inside the stage, 8 / 7 from its top-left) and the action
  /// button (8 / 8 from its bottom-right).
  static const double skinShopNameLeft = 8;
  static const double skinShopNameTop = 7;
  static const double skinShopNameFontSize = 14;
  static const double skinShopChipFontSize = 9;
  static const double skinShopActionInset = 8;
  static const double skinShopActionHeight = 30;
  static const double skinShopActionFontSize = 13;
  static const double skinShopActionPulse = 1.06;
  static const Color skinShopPoorGrey = Color(0xFFA0A0A0);

  /// Tab bar: 5 equal tabs, 3 pt underline sliding 0.3 s with overshoot.
  static const Rect skinShopTabBarRect = Rect.fromLTWH(14, 270, 292, 52);
  static const double skinShopTabIconWidth = 30;
  static const double skinShopTabIconHeight = 24;
  static const double skinShopTabFontSize = 9;
  static const double skinShopTabUnderline = 3;
  static const double skinShopTabSlideDuration = 0.3;
  static const double skinShopTabIconActiveScale = 1.18;

  /// Item grid: 3 columns of 92 x 92 tiles, 8 pt gaps, 6 pt top / 30 pt
  /// bottom padding, from y 326 down to 44 pt above the bottom edge (667
  /// at 711).
  static const int skinShopColumns = 3;
  static const double skinShopGridLeft = homeMargin;
  static const double skinShopGridTop = 326;
  static const double skinShopGridWidth = 292;
  static const double skinShopTile = 92;
  static const double skinShopTileGap = 8;
  static const double skinShopGridPadTop = 6;
  static const double skinShopGridPadBottom = 30;
  static double skinShopGridBottomFor(double viewHeight) =>
      viewHeight - menuSpikeHeight;

  /// The scrolling grid viewport.
  static Rect skinShopGridRectFor(double viewHeight) => Rect.fromLTRB(
    skinShopGridLeft,
    skinShopGridTop,
    skinShopGridLeft + skinShopGridWidth,
    skinShopGridBottomFor(viewHeight),
  );

  /// Tile [index] of a tab's grid (content coordinates at scroll 0).
  static Rect skinShopTileRectFor(double viewHeight, int index) =>
      Rect.fromLTWH(
        skinShopGridLeft +
            (index % skinShopColumns) * (skinShopTile + skinShopTileGap),
        skinShopGridTop +
            skinShopGridPadTop +
            (index ~/ skinShopColumns) * (skinShopTile + skinShopTileGap),
        skinShopTile,
        skinShopTile,
      );

  /// Bottom of a grid of [count] tiles, including the bottom padding.
  static double skinShopContentBottomFor(double viewHeight, int count) =>
      skinShopTileRectFor(viewHeight, count - 1).bottom +
      skinShopGridPadBottom;

  // Inside a tile: art in an 84 x 68 box centred on the tile; card = fg at
  // [skinShopTileMix] over bg; locked art at 42 %; lock 13 pt at (6, 5);
  // price pill 8 pt above the bottom; 3 pt equipped / try-on outline; 22 pt
  // check badge; NEW tag 5 pt past the right edge, 6 pt above the top.
  static const double skinShopTileMix = 0.15;
  static const double skinShopArtWidth = 84;
  static const double skinShopArtHeight = 68;
  static const double skinShopLockedOpacity = 0.42;
  static const double skinShopLockSize = 13;
  static const double skinShopLockLeft = 6;
  static const double skinShopLockTop = 5;
  static const double skinShopPriceBottom = 8;
  static const double skinShopPriceFontSize = 12;
  static const double skinShopPriceCoin = 13;
  static const double skinShopOutline = 3;
  static const double skinShopCheckBadge = 22;
  static const double skinShopRarityBar = 4;
  static const double skinShopTagOverhangX = 5;
  static const double skinShopTagOverhangY = 6;
  static const double skinShopTagFontSize = 10;
  static const double skinShopPressScale = 0.93;
  static const double skinShopTryPulse = 0.9; // s per half cycle
  static const double skinShopNewWobble = 1.2;
  static const double skinShopShineLoop = 1.6;

  /// Tab-switch entrance: tiles rise 16 pt and fade in over 240 ms,
  /// staggered 30 ms per column and 40 ms per row.
  static const double skinShopEnterRise = 16;
  static const double skinShopEnterDuration = 0.24;
  static const double skinShopEnterColumnDelay = 0.03;
  static const double skinShopEnterRowDelay = 0.04;

  // --- Live home & Shop (PRD-menu-v2 §8) --------------------------------
  // Effect timings live in components/ui/live_effects.dart (LiveCurves).

  /// Free-coins reward: the pill counts up by the reward (75 by default,
  /// `shop_ad_coins`; PRD-2.3.1 §5) in 0.4 s once the coins have landed,
  /// then `sk_progress` 0.18 s later.
  static const double coinRewardCountDuration = 0.4;
  static const double coinRewardProgressDelay = 0.18;

  /// Coin pill coin pop on a reward (135 % and back in 0.3 s).
  static const double coinPopScale = 1.35;
  static const double coinPopDuration = 0.3;

  // --- Coin reward celebration (PRD-home-v3 §5, build73 / 74 / 79) -------
  /// Each landing pops the pill coin to 125 % (0.18 s).
  static const double coinRewardLandPopScale = 1.25;
  static const double coinRewardLandPopDuration = 0.18;

  /// End of the count: the pill pops 114 % (0.38 s, ease-out) and its coin
  /// spins and pops 150 % / -20° (0.42 s).
  static const double coinRewardPillPopScale = 1.14;
  static const double coinRewardPillPopDuration = 0.38;
  static const double coinRewardSpinPopScale = 1.5;
  static const double coinRewardSpinPopDuration = 0.42;
  static const double coinRewardSpinPopDegrees = -20;

  /// Pill gold glow fade (CSS `transition: box-shadow .25s`).
  static const double coinRewardGlowFade = 0.25;

  /// "+amount" under the pill: gold 26 pt, right edge 8 pt inside the
  /// pill's, top 8 pt below it (mock right 22 / top 104), 1.5 s.
  static const double coinRewardLabelFontSize = 26;
  static const double coinRewardLabelInset = 8;
  static const double coinRewardLabelGap = 8;
  static const double coinRewardLabelDuration = 1.5;

  /// The 100 000 pack's white flash: 75 % -> 0 in 0.5 s.
  static const double coinRewardFlashOpacity = 0.75;
  static const double coinRewardFlashDuration = 0.5;

  /// The Shop's GET button (was WATCH): 112 x 32, camera 20 + "GET" 20 pt
  /// bold (0.9 pt stroke), 0.12 em, gap 9; pulse 1 -> 1.05 with a pink glow
  /// (12 pt blur, #EC008C 45 %).
  static const double shopGetWidth = 112;
  static const double shopGetHeight = 32;
  static const double shopGetFontSize = 20;
  static const double shopGetLetterSpacing = 0.12;
  static const double shopGetStroke = 0.9;
  static const double shopGetIconSize = 20;
  static const double shopGetGap = 9;
  static const double shopGetPulse = 0.05;
  static const Color shopGetGlow = Color.fromRGBO(236, 0, 140, .45);
  static const double shopGetGlowBlur = 12;

  /// Home powerup slot pulse: 1 -> 1.035, gold glow (14 pt blur, #FFB529
  /// 55 %).
  static const double homeSlotPulse = 0.035;
  static const Color homeSlotGlow = Color.fromRGBO(255, 181, 41, .55);
  static const double homeSlotGlowBlur = 14;

  /// Shop price-button light-streak cascade (s): Remove ads, the four
  /// packs in reading order, the featured item.
  static const double shopStreakDelayNoAds = 0;
  static const List<double> shopStreakDelayPacks = [0.7, 1.14, 1.58, 2.02];
  static const double shopStreakDelayFeatured = 2.5;

  /// Purchase feedback: pill count-down, UNLOCKED! banner (top 150,
  /// centred), legendary flash + shake, NOT ENOUGH COINS toast (top 318).
  static const double skinShopCountDuration = 0.6;
  static const double skinShopBannerTop = 150;
  static const double skinShopBannerDuration = 1.9;
  static const double skinShopBannerDurationLegendary = 2.6;
  static const double skinShopFlashDuration = 0.6;
  static const double skinShopShakeDuration = 0.38;
  static const double skinShopToastTop = 318;
  static const double skinShopToastDuration = 1.5;
  static const double skinShopProgressSoundDelay = 0.52;
  static const double skinShopProgressSoundDelayLegendary = 1.3;

  // --- No-ads popup schedule (PRD-menu-v4 §8, plain constants) -------------

  /// A return from the background after at least this long starts a new
  /// session (the popup may show on that home arrival).
  static const Duration sessionGap = Duration(minutes: 30);

  /// PRD-2.3 §24.2 (`noads_gap_min`, was 4 h): minimum wall-clock gap since
  /// the popup was last SHOWN (closing no longer restarts it).
  static Duration get noAdsPopupMinGap => Duration(
    minutes: TuningValues.current.i('noads_gap_min'),
  );

  /// PRD-2.3 §24.2 (`noads_max_per_day`, was 2): shows per local calendar day.
  static int get noAdsPopupMaxPerDay =>
      TuningValues.current.i('noads_max_per_day');

  /// Eligible from install day 2 OR after this many finished runs.
  static const int noAdsPopupMinRuns = 10;

  /// Rewarded videos watched since the last show that trigger the popup.
  static const int noAdsPopupVideos = 3;

  /// PRD-2.3 §24.2 (`noads_fallback_h`, was 24 h): without a good-moment
  /// trigger, shown once this long has passed since the last show.
  static Duration get noAdsPopupFallback => Duration(
    milliseconds: (TuningValues.current.d('noads_fallback_h') * 3600000)
        .round(),
  );

  /// PRD-2.3 §23.2 (`rate_min_runs`): the run that reaches this many finished
  /// runs requests the store's rating sheet (any later run only on a new best).
  static int get ratingMinRuns => TuningValues.current.i('rate_min_runs');

  /// PRD-2.3 §23.2 (`rate_cooldown_days`): at most one request in this long.
  static Duration get ratingCooldown =>
      Duration(days: TuningValues.current.i('rate_cooldown_days'));

  /// PRD-2.3 §23.2 (`rate_delay_s`): seconds after the results page has
  /// settled (and no overlay is open) before the request.
  static double get ratingDelaySeconds =>
      TuningValues.current.d('rate_delay_s');

  /// PRD-2.3 §26.1 (`ui_unlock_best`): the Shop and Skins screens unlock at
  /// this best score (25). Shown in the lock text, so a tuned value reads true.
  static int get menuUnlockBest => TuningValues.current.i('ui_unlock_best');

  /// A previous run below this score suppresses the popup ("frustrating
  /// death").
  static const int noAdsPopupMinScore = 6;

  // --- No-ads popup (PRD-1 §5.1, design P1) --------------------------------

  /// Card x 20 -> 300, top 190 at 711; the card stays centred on the same
  /// band at other heights.
  static Rect noAdsCardRectFor(double viewHeight) => Rect.fromLTWH(
    20,
    190 + (viewHeight - homeReferenceHeight) / 2,
    worldWidth - 40,
    noAdsCardHeight,
  );
  static const double noAdsHeaderHeight = 120;
  static const double noAdsCloseSize = 38;
  static const double noAdsTitleFontSize = 22;
  static const double noAdsTitlePad = 8;
  // 22 pt line box + 2 x 8 pt padding; the browser's line box measures
  // 29 pt on popup_p1.png (22 x 1.284 = 28.25 rounded up).
  static const double noAdsTitleHeight = 29 + 2 * noAdsTitlePad; // 45
  static const double noAdsPad = 16;
  static const double noAdsBenefitSize = 44;
  static const double noAdsBenefitGap = 12;
  static const double noAdsPriceGap = 18;
  static const double noAdsPriceHeight = 54;
  static const double noAdsCardHeight =
      noAdsHeaderHeight +
      noAdsTitleHeight +
      noAdsPad +
      2 * noAdsBenefitSize +
      noAdsBenefitGap +
      noAdsPriceGap +
      noAdsPriceHeight +
      noAdsPad; // 369

  /// Toasts while the popup is up: centred below the card.
  static Vector2 noAdsToastPositionFor(double viewHeight) => Vector2(
    worldWidth / 2,
    noAdsCardRectFor(viewHeight).bottom + 32,
  );

  // --- Fake rewarded ad overlay (Linux / desktop debug only) ----------------

  /// Centred card, x 20 -> 300 like the popups.
  static Rect fakeAdCardRectFor(double viewHeight) => Rect.fromLTWH(
    20,
    (viewHeight - fakeAdCardHeight) / 2,
    worldWidth - 40,
    fakeAdCardHeight,
  );
  static const double fakeAdCardHeight = 260;
  static const double fakeAdHeaderHeight = 64;
  static const double fakeAdTitleFontSize = 30;
  static const double fakeAdPlacementFontSize = 13;
  static const double fakeAdCountFontSize = 64;
  static const double fakeAdMessageFontSize = 20;
  static const double fakeAdHintFontSize = 11;

  // Debug panel (debug builds / Linux): a column of text buttons centred on
  // the playfield.
  static const double debugRowHeight = 30;
  static Vector2 debugPanelTopFor(double viewHeight) =>
      Vector2(worldWidth / 2, Config.spikeHeight + 16);

  // UI accent: the native pink of the button/points-field artwork. Used for
  // the game-over title and labels so they never share the pipe tint (the
  // stage foreground made them unreadable behind frozen pipes).
  static const Color uiAccent = Color(0xFFFF4FB7);

  // Vertical offset of the score number inside the points field from the
  // field's center (the "POINTS" caption lives in the field's lower half).
  static const double scoreLabelNudgeY = -18;

  // Fonts.
  static const String scoreFont = 'LVDC Common2';
  static const String uiFont = 'Opificio Neue';

  // Durations.
  // Menu transitions (home <-> settings / Shop / Skins, the home UI fading
  // out on START, toasts): 3x+ faster than 1.0's 0.5 s after product-owner
  // feedback (2.0 menu deviation, SPEC.md).
  static const double uiFadeDuration = 0.15;
  static const double colorFadeDuration = 0.5;
  static const double replayFadeDuration = 0.3;
  // Popups and dialogs (No-ads popup, skin unlock dialog, fake-ad overlay)
  // fade in / out.
  static const double popupFadeDuration = 0.07;
  // PRD-2.2 §8.1 "one close per gesture": after a system back closes a menu
  // screen or popup, further system backs are ignored for its close fade
  // (uiFadeDuration), so the next back closes the screen below only once the
  // first close has finished.
  static const double systemBackDebounce = uiFadeDuration;
  // The run's bird fading in at its spawn point after START (the home
  // screen's bird fades out with the home screen).
  static const double runBirdFadeDuration = 0.25;
  // Stagger step for staggered menu elements.
  static const double staggerDuration = 0.07;
  // Gameplay fades keep the 1.0 timing: the score HUD in / out, the spike
  // strips sliding out on START, the bird fading on death, and the
  // game-over panel's staggered fade-in chain.
  static const double gameplayFadeDuration = 0.5;
  static const double gameOverStaggerDuration = 0.2;
  // How long a ServiceMessage stays fully visible between its fade-in and
  // fade-out (total lifetime: uiFadeDuration + this + uiFadeDuration).
  static const double serviceMessageHoldDuration = 2.0;
  // Fake rewarded ad overlay (Linux / desktop debug only): countdown
  // length, then how long "REWARD GRANTED" / "Ad failed to load" stay up.
  static const double fakeAdCountdown = 3.0;
  static const double fakeAdResultHold = 0.8;
  static const double fakeAdFailHold = 1.5;

  // Score HUD watermark: the circle is tinted this fraction of the way from
  // the foreground toward the background color, so pipes (full foreground
  // tint) stay visibly darker than the circle behind them.
  static const double hudCircleLighten = 0.45;

  // --- PRD-home-v3 §6 / §7: P1 popups after a purchase ----------------------

  /// The P1 popups' dim (`rgba(40,40,48,.72)`) and card width (x 20 -> 300).
  static const Color p1PopupDim = Color(0xB8282830);
  static const double p1PopupWidth = 280;
  static const double p1PopupCloseSize = 38;
  static const double p1PopupPad = 16;

  /// Grey body line (`#9a4d78`).
  static const Color p1PopupSmallText = Color(0xFF9A4D78);

  /// Purchase cancelled / failed (§6, build73 `.pcard`): 120 pt header,
  /// 45 pt title band (20 pt at 0.08 em), 20 pt body top padding, message
  /// 18 pt (line-height 1.3), small line 13 pt 8 pt below, OK 50 pt
  /// (24 pt at 0.12 em) 18 pt below.
  static const double purchasePopupHeaderHeight = 120;
  static const double purchasePopupTitleHeight = 45;
  static const double purchasePopupTitleFontSize = 20;
  static const double purchasePopupBodyTop = 20;
  static const double purchasePopupMessageFontSize = 18;
  static const double purchasePopupSmallFontSize = 13;
  static const double purchasePopupSmallGap = 8;
  static const double purchasePopupOkGap = 18;
  static const double purchasePopupOkHeight = 50;
  static const double purchasePopupOkFontSize = 24;

  /// §6 timings: dim in 0.15 s, card pop .82 -> 1.04 -> 1 in 0.24 s, the
  /// gold ✕ badge spins in over 0.38 s after 0.12 s, close fade 0.12 s.
  static const double purchasePopupFadeIn = 0.15;
  static const double purchasePopupPopDuration = 0.24;
  static const double purchasePopupBadgeDelay = 0.12;
  static const double purchasePopupBadgeDuration = 0.38;
  static const double purchasePopupFadeOut = 0.12;

  /// No-ads celebration (§7, build79): 170 pt header, 48 pt title band
  /// (22 pt at 0.1 em), body 16 pt padding, chip 15 pt, CLAIM 52 pt (22 pt
  /// at 0.1 em); 92 pt AD icon, 62 pt gold stamp at (154, 88) in the
  /// header with a 5 pt pink ring.
  static const double noAdsCelebrationHeaderHeight = 170;
  static const double noAdsCelebrationTitleHeight = 48;
  static const double noAdsCelebrationTitleFontSize = 22;
  static const double noAdsCelebrationIconSize = 92;
  static const double noAdsCelebrationStampSize = 62;
  static const Offset noAdsCelebrationStampTopLeft = Offset(154, 88);
  static const double noAdsCelebrationClaimHeight = 52;

  /// §7 timings (s).
  static const double noAdsCelebrationFlash = 0.6;
  static const double noAdsCelebrationShakeDelay = 0.2;
  static const double noAdsCelebrationShake = 0.38;
  static const double noAdsCelebrationSwing = 0.36;
  static const double noAdsCelebrationWobbleDelay = 0.12;
  static const double noAdsCelebrationWobble = 0.42;
  static const double noAdsCelebrationStampDelay = 0.33;
  static const double noAdsCelebrationStampDuration = 0.34;
  static const double noAdsCelebrationConfettiAt = 0.43;
  static const int noAdsCelebrationConfetti = 90;
  static const double noAdsCelebrationFadeOut = 0.15;

  /// Owned flips after the bonus count-up: 0.25 s after it, the Shop
  /// banner (rotateX); 0.7 s later the home tile (rotateY) and the video
  /// icons shrinking away. Flip: 0.18 s out + 0.28 s in.
  static const double noAdsFlipDelay = 0.25;
  static const double noAdsFlipHomeDelay = 0.7;
  static const double flipOutDuration = 0.18;
  static const double flipInDuration = 0.28;
  static const double videoIconShrinkDuration = 0.3;

  /// Owned No-ads tile / banner fill: pink 55 % over the menu background.
  static final Color noAdsOwnedFill = Color.lerp(
    const Color(0xFFF1F1F1),
    menuPink,
    .55,
  )!;

  // --- Settings v3 (PRD-home-v3 §8) -----------------------------------------

  // --- Music (PRD-2.2 §9) ---------------------------------------------------

  /// The music volume (0..1) until the player moves the Settings slider
  /// (PRD-2.2 §9.1): fresh installs, players who never moved it, and "Delete
  /// my data", which clears the stored key. A stored volume always wins.
  static const double defaultMusicVolume = 0.25;

  // --- Sound pools (PRD-2.2 §22, §33.4) -------------------------------------

  /// §22.1: a one-shot play is stopped (its voice returned) after the file's
  /// length from `kSoundDurations` plus this margin.
  static const int sfxStopMarginMs = 100;

  /// §22.2: release fallback length for a file missing from
  /// `kSoundDurations` (debug asserts instead) — never a silent 0.6 s cut.
  static const int sfxMissingLengthMs = 1000;

  /// §22.1: sounds longer than this get [sfxVoicesLong] players.
  static const int sfxLongSoundMs = 1000;

  /// §22.1 / §33.4 item 1: the fixed (hard-capped) number of players per
  /// sound, all created up front. Default 2, > 1 s 3, the 1.0 gameplay
  /// sounds 4, the burst cues (coin landings, ticks, piggy coins) 6. When
  /// every player is busy the oldest copy is stopped and reused.
  static const int sfxVoicesDefault = 2;
  static const int sfxVoicesLong = 3;
  static const int sfxVoicesLegacy = 4;
  static const int sfxVoicesBurst = 6;

  /// §33.4 item 3: a pool (not in `SoundService.prewarmed`) that has not
  /// played for this long is disposed (its players too) ...
  static const int sfxPoolIdleDisposeMs = 180000;

  /// iOS round 2 §2: a sound whose first voice failed to load tries again
  /// on a play this long after the failure (no retry storm).
  static const int sfxRetryFailedMs = 5000;

  /// iOS round 2 §2: back from at least this long in the background (iOS),
  /// the sound-effect voices are rebuilt ([SoundService.rebuildVoices]).
  static const Duration iosVoiceRebuildAfter = Duration(seconds: 20);

  /// ... and at most this many pools stay alive (least recently used idle
  /// pools go first). With ≤ 6 players each this bounds the native players.
  /// §33.6 (S7-19): 56 = the pinned session set (`SoundService.prewarmed` +
  /// `sessionWarm`, 33 pools) + 23 run-scoped pools (disposed at run end).
  static const int sfxMaxLivePools = 56;

  /// §33.4 item 3: the idle check runs at most this often (from `play`).
  static const int sfxTrimIntervalMs = 5000;

  /// The RUMBLE icon's buzz when switched on (s).
  static const double settingsRumbleBuzz = 0.32;

  // --- Settings 2.3 (PRD-2.3 §20.2, design/settings_v23/final_src.html) -----
  // The page's CSS at 711 pt; `SettingsLayout` stacks these top-down and,
  // when they don't fit (568 pt), shrinks them in the §20.2 order.

  /// §20.2 colours: ink (title, rows), caption grey, footer grey, the
  /// row dividers, the volume bars' off grey, the delete row's red and its
  /// pale chevron, the row chevron grey.
  static const Color settingsInk = Color(0xFF7A7A7A);
  static const Color settingsCaption = Color(0xFF9A9A9A);
  static const Color settingsFooter = Color(0xFFA0A0A0);
  static const Color settingsLine = Color(0xFFE2E2E2);
  static const Color settingsBarOff = Color(0xFFDADADA);
  static const Color settingsRed = Color(0xFFD32F2F);
  static const Color settingsRedChevron = Color(0xFFE5A3A3);
  static const Color settingsChevron = Color(0xFFB5B5B5);
  static const Color settingsRowPressed = Color(0xFFFAFAFA);

  /// §20.2 title `SETTINGS` (Opificio 30, .06 em), centred on the back
  /// box's row (page: top 62).
  static const double settingsTitleCenterY = 80;
  static const double settingsTitleFontSize = 30;

  /// §20.2 body: 14 pt side margins (292 pt wide), top 114, bottom inset 50.
  static const double settingsBodyLeft = 14;
  static const double settingsBodyWidth = 292;
  static const double settingsBodyTop = 114;
  static const double settingsBottomInset = 50;

  /// §20.2 captions: 10.5 pt, .22 em, a 15 pt line, 6 pt under it.
  static const double settingsCaptionFontSize = 10.5;
  static const double settingsCaptionHeight = 15;
  static const double settingsCaptionGap = 6;

  /// §20.2 tiles: 3 in a row, 8 pt gaps, 100 pt tall, 40 pt icon, label
  /// 11 pt (.14 em), ON / OFF tag 9 pt (.1 em) 6 pt from the top right.
  static const double settingsTileHeight = 100;
  static const double settingsTileGap = 8;
  static const double settingsTileIcon = 40;
  static const double settingsTileIconGap = 7;
  static const double settingsTileLabelFontSize = 11;
  static const double settingsTileTagFontSize = 9;

  /// §20.2 music volume card (8 pt under the tiles): padding 10 / 12 / 9,
  /// header line 17 + 6, 8 bars 30 pt tall with 5 pt gaps, rising from
  /// 32 % to 100 %.
  static const double settingsVolumeGap = 8;
  static const double settingsVolumePadTop = 10;
  static const double settingsVolumePadX = 12;
  static const double settingsVolumePadBottom = 9;
  static const double settingsVolumeHeadHeight = 17;
  static const double settingsVolumeHeadGap = 6;
  static const double settingsBarsHeight = 30;
  static const double settingsBarGap = 5;
  static const int settingsVolumeLevels = 8;
  static const double settingsBarMinHeight = 0.32;

  /// §20.2 a tap on the MUSIC tile at volume 0 with nothing remembered
  /// restores this level (5 of 8).
  static const int settingsMusicRestoreLevel = 5;

  /// §20.2 the bar pop on a new step: scaleY 1.12 over 0.15 s.
  static const double settingsBarPopScale = 1.12;
  static const double settingsBarPop = 0.15;

  /// §20.2 cards (GAME, PRIVACY & DATA): 10 pt apart, padding 2 / 12,
  /// caption 9 pt from the top, rows 37 pt (13 pt uppercase, .1 em, a
  /// 16 pt chevron).
  static const double settingsCardGap = 10;
  static const double settingsCardPadY = 2;
  static const double settingsCardPadX = 12;
  static const double settingsCardCaptionTop = 9;
  static const double settingsRowHeight = 37;
  static const double settingsRowFontSize = 13;
  static const double settingsChevronSize = 16;

  /// §20.2 footer: 10.5 pt (.08 em), two 16.8 pt lines, at least 8 pt
  /// under the last card.
  static const double settingsFooterFontSize = 10.5;
  static const double settingsFooterLine = 16.8;
  static const double settingsFooterGap = 8;

  // region PRD-2.3 §10 — the waiting start and the tap reminder
  /// §10.1 the waiting bird's hover: ±6 pt (the approved design's idle).
  static const double waitHoverAmp = 6;

  /// §10.1 hover speed (rad/s; 3 rad/s ≈ 0.5 Hz, `sin(t × 3)` in the design).
  static const double waitHoverOmega = 3;

  /// §10.1 a wing beat every this many seconds while hovering (the design's
  /// `(t × 2.5) % 1`).
  static const double waitWingBeatPeriod = 0.4;

  /// §10.3b the tap reminder shows after this long without a tap (s).
  /// Remote tuning key `ui_tap_reminder_s` (PRD-2.3 §0 item 5, §15); 4.0 by
  /// default.
  static double get tapReminderDelay =>
      TuningValues.current.d('ui_tap_reminder_s');

  /// §10.3 / PRD-2.3 §0 item 4 the first-run instructions fade out over
  /// this on the first tap (s; the design file's 0.35 s).
  static const double firstRunHintFadeOut = 0.35;

  /// §10.3b / §0 item 4 the tap reminder fades in (ease-out) over this (s).
  static const double tapReminderFadeIn = 0.3;

  /// §10.3b / §0 item 4 the tap reminder fades out (ease-in) on the tap (s).
  static const double tapReminderFadeOut = 0.2;
  // endregion PRD-2.3 §10

  // region P231-E — achievements (PRD-2.3.1 §12.5)
  /// PRD-2.3.1 §12.5 the Home medal box: right of the trophy with the same
  /// size and spacing as gear → trophy (14 → 60, so 60 → 106), y 58, 38×38.
  static const double homeMedalLeft =
      homeTrophyLeft + (homeTrophyLeft - homeMargin);

  /// PRD-2.3.1 §12.5 the medal glyph (the trophy's 24 pt).
  static const double homeMedalIconSize = homeTrophyIconSize;

  /// PRD-2.3.1 §12.5 the medal wiggles like the trophy, this many seconds
  /// after it (same 10 s period).
  static const double homeMedalWiggleDelay = 5;

  static Rect homeAchievementsRectFor(double viewHeight) => Rect.fromLTWH(
    homeMedalLeft,
    homeTopRowY,
    homeTopRowHeight,
    homeTopRowHeight,
  );

  /// PRD-2.3.1 §12.5 the coin pill (right edge 306) never reaches the medal:
  /// its widest is up to 8 pt (the top row's gap) right of the medal box;
  /// a longer balance shrinks its number to fit.
  static const double homeCoinPillMaxWidth =
      homeRightEdge - (homeMedalLeft + homeTopRowHeight + 8);

  /// PRD-2.3.1 §12.5 the unlock toast pill: width, height, top (below the
  /// top spike strip), corner radius.
  static const double achToastWidth = 280;
  static const double achToastHeight = 68;
  static const double achToastTop = spikeHeight + 10;
  static const double achToastRadius = 34;

  /// PRD-2.3.1 §12.5 the achievement icon in the pill (pt).
  static const double achToastIcon = 52;

  /// PRD-2.3.1 §12.5 "ACHIEVEMENT UNLOCKED" (Opificio 11 pt, uiAccent), the
  /// name (18 pt plum) and the "+N" points.
  static const double achToastLabelSize = 11;
  static const double achToastNameSize = 18;
  static const double achToastPointsSize = 16;
  static const Color achToastPlum = Color(0xFF6A0040);

  /// PRD-2.3.1 §12.5 one pill shows ≈ 2.4 s, with a 0.3 s slide in / out.
  static const double achToastDuration = 2.4;
  static const double achToastSlide = 0.3;

  /// PRD-2.3.1 §12.5 at most this many pills per batch; the last one of a
  /// longer queue reads "+N more".
  static const int achToastMaxPills = 5;
  // endregion P231-E
}
