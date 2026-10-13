import 'dart:ui';

import 'tuning_values.dart';

/// Versus tuning (PRD-2 §3.13 rules + backend, §5.7 HUD out state, §5.8 VS
/// intro, §5.10 results). WP-5b. Every member's doc starts with its PRD
/// section. The backend limits mirror `functions/src/schema.ts` (WP-5a).
abstract final class VersusConfig {
  // ------------------------------------------------------------ rules
  /// §3.13 Win bonus (coins, source `win_bonus`; PRD-2.3 §14.2 unchanged,
  /// tunable `coin_versus_win`).
  static int get winBonus => TuningValues.current.i('coin_versus_win');

  /// §3.13 A draw pays half (coins, source `win_bonus`; tunable
  /// `coin_versus_draw`).
  static int get drawBonus => TuningValues.current.i('coin_versus_draw');

  /// §3.13 Runs under this score are never uploaded (schema.ts MIN_SCORE).
  static const int minUploadScore = 3;

  /// §3.13 Non-best uploads per player per UTC day (schema.ts
  /// DAILY_UPLOADS; the server counts per UTC day, so the client does too).
  static const int dailyUploads = 3;

  /// PRD-2.2 §13.5 the 0.9 s gap rule between two plain entries,
  /// centiseconds (schema.ts MIN_GAP_CS).
  static const int minGapCs = 90;

  /// PRD-2.2 §13.5 a pass entry is worth at most passCapMult × (pass
  /// entries so far + passCapExtra) points (schema.ts PASS_CAP_*).
  static const int passCapMult = 2;
  static const int passCapExtra = 5;

  /// PRD-2.2 §13.5 cap of a generic bonus entry: 2 × the 40-coin piggy
  /// (schema.ts BONUS_CAP).
  static const int bonusCap = 80;

  /// PRD-2.2 §13.1 / §13.5 (fix S7-05) cap of a puzzle completion entry:
  /// 2 × the largest 250 roll (schema.ts PUZZLE_BONUS_CAP).
  static const int puzzleBonusCap = 500;

  /// PRD-2.2 §13.5 cap of a pair gift entry: 2 × +5 (schema.ts GIFT_CAP).
  static const int giftCap = 10;

  /// §3.13 / ARCH §6.1 `expireAt` = now + 60 days (TTL; rules accept ±1 d).
  static const Duration expireAfter = Duration(days: 60);

  /// §3.13 Pool shards per level (schema.ts SHARDS).
  static const int shards = 4;

  /// §3.13 Highest level (schema.ts MAX_LEVEL; levels 0–10).
  static const int maxLevel = 10;

  /// §3.13 Kept runs per player: `recent` ≤ 5 (ARCH §6.1).
  static const int recentRuns = 5;

  /// §3.13 (call) Upload queue cap: the oldest non-best entries are dropped
  /// beyond it (a long offline stretch never grows the prefs unbounded).
  static const int queueCap = 12;

  /// §3.13 ARCH §6.1 field limits: name 1–32, avatar ≤ 512, runId ≤ 64,
  /// look ids ≤ 40, `tl` ≤ 16 384, `fl` ≤ 8 192 chars.
  static const int nameMax = 32;
  static const int avatarMax = 512;
  static const int lookIdMax = 40;
  static const int tlMax = 16384;
  static const int flMax = 8192;

  /// §3.13 Every Firebase call is time-boxed (a failure = solo).
  static const Duration callTimeout = Duration(seconds: 10);

  /// PRD-2.2 §3 The opponent search's own time limit (it runs during the
  /// Home prefetch); after it the run starts solo (`versus_solo` reason
  /// `timeout`).
  static const Duration searchLimit = Duration(seconds: 6);

  /// PRD-2.3 §25.2 each pool read of the search is time-boxed to 4 s (was
  /// the 10 s [callTimeout]).
  static const Duration readTimeout = Duration(seconds: 4);

  /// PRD-2.3 §25.2 the "met at" list keeps the last 100 run ids met
  /// (oldest dropped first).
  static const int metCap = 100;

  /// PRD-2.3 §25.3 a VERSUS START without a held opponent: the VS intro
  /// waits up to 3 s (after START) for the running search, then lands on
  /// "NO RIVAL FOUND".
  static const double introWait = 3;

  /// PRD-2.3 §25.3 (call) after landing on NO RIVAL FOUND the FLY SOLO
  /// banner shows this long after the plate flash, then the white fade.
  static const double soloBannerAt = .3;
  static const double soloBanner = 1.3;

  /// PRD-2.3 §21.3 the uploaded picture: 96 × 96 JPEG ≤ 30 KB (the
  /// `storage.rules` cap), the qualities tried from best down.
  static const int avatarSide = 96;
  static const int avatarMaxBytes = 30 * 1024;
  static const List<int> avatarQualities = [88, 80, 70, 60, 50, 40, 30];

  /// PRD-2.3 §21.3 the Storage path of a player's picture.
  static String avatarPath(String uid) => 'avatars/$uid.jpg';

  /// PRD-2.3 §5.5 / §21.3 (S8-06): the server deletes the picture with the
  /// player doc (≈ 60 days after the last run), so an unchanged picture is
  /// uploaded again when its last upload is older than this.
  static const Duration avatarRefresh = Duration(days: 30);

  /// PRD-2.3 §21.4 / §0 item 7 the Remote Config parameter holding the
  /// salt of the hashed Play Games id (generated at deploy, never in git).
  static const String pgSaltKey = 'versus_pg_salt';

  /// PRD-2.3 §21.4 / §25.3 (call) a search waits at most this long for the
  /// pg salt before it goes on with the pg known so far.
  static const Duration pgWait = Duration(milliseconds: 500);

  /// PRD-2.2 §3 At most this many pool documents per search: every shard of
  /// every level ((maxLevel + 1) × shards = 44).
  static const int maxSearchReads = (maxLevel + 1) * shards;

  /// §3.13 offline rules (S6-66) A failed start-up auth is retried in the
  /// background with doubling waits from [authRetryBase] up to
  /// [authRetryMax] (also at once on app resume, Home prefetch, a run
  /// submit and before every flush).
  static const Duration authRetryBase = Duration(seconds: 5);
  static const Duration authRetryMax = Duration(minutes: 2);

  /// §3.13 Firebase project and Functions region (ARCH §6.3).
  static const String functionsRegion = 'europe-west1';

  /// §3.13 The callable that deletes everything online (ARCH §6.3).
  static const String deleteFunction = 'deleteMyData';

  /// §3.13 Play Games → Firebase link: the OAuth **web** client id the Play
  /// Games server auth code is requested for (public config, not a secret).
  static const String playGamesWebClientId =
      '512525012529-ts8djs53vnjrsjl52l3o55n8sul6cua1.apps.googleusercontent.com';

  // ------------------------------------------------------------ HUD (§5.7)
  /// §3.13 / §5.7 (call) The opponent box once their timeline has ended
  /// ("their box shows they are out (dimmed)"): drawn at this opacity.
  static const double outOpacity = .4;

  // ------------------------------------------------------------ VS intro (§5.8)
  /// §5.8 START squash (s).
  static const double startSquash = .14;

  /// §5.8 Panels slide in at 0.12 s for 0.42 s with a 6 pt overshoot.
  static const double panelsAt = .12;
  static const double panelsSlide = .42;
  static const double panelOvershoot = 6;

  /// §5.8 Seam: the top panel ends at y 340 + teeth (22 pt, period 32).
  static const double seamY = 340;
  static const double seamTooth = 22;
  static const double seamPeriod = 32;

  /// §5.8 Top panel `fg` 26 % over bg; bottom pink 16 % over bg.
  static const double topTint = .26;
  static const double bottomTint = .16;

  /// §5.8 Stripes: 14 pt band / 14 pt clear, top 45° `fg` 9 %, bottom −45°
  /// pink 7 %, drifting one period (39.6 pt) every 3.2 s in opposite ways.
  static const double stripeBand = 14;
  static const double stripeTopAlpha = .09;
  static const double stripeBottomAlpha = .07;
  static const double stripeDrift = 39.598;
  static const double stripePeriod = 3.2;

  /// §5.8 Floating squares 8–14 pt (`fg` 30 % rising / pink 22 % sinking,
  /// 260 pt over 6–9 s, rotating 180°).
  static const double floatTravel = 260;
  static const double floatTopAlpha = .3;
  static const double floatBottomAlpha = .22;

  /// §5.8 Plates (232 × 52): opponent at (44, 80), you at (44, 584); a
  /// 52 pt avatar square, name 22 pt, the 52 pt emblem slot on the right.
  static const Rect oppPlate = Rect.fromLTWH(44, 80, 232, 52);
  static const Rect youPlate = Rect.fromLTWH(44, 584, 232, 52);
  static const double plateSlot = 52;

  /// §5.8 the plate name size; PRD-2.3 §21.2 (S8-08 call): 18 pt in the
  /// name font (Fredoka SemiBold, like every other name tag) instead of
  /// 22 pt Opificio, so every generated nickname (the longest: 14 letters
  /// + 3 digits) fits the room before the emblem at 70 % with its digits.
  static const double plateNameSize = 18;
  static const double plateNameLeft = 12;

  /// PRD-2.3 §21.2 the emblem's half width on the plate (the widest emblem,
  /// levels 9–10, is 98 art units each side × [emblemScale] ≈ 31.4 pt), and
  /// the gap kept between the name and the emblem.
  static const double plateEmblemHalf = 32;
  static const double plateNameGap = 4;

  /// PRD-2.3 §25.3 / §0 item 11 the texts of the no-rival landing (written
  /// in the game's tone; listed in the report for the owner's review).
  static const String noRivalText = 'NO RIVAL FOUND';
  static const String flySoloText = 'FLY SOLO';

  /// §5.8 Level emblem on the plate: 0.32 × art scale, centred on the slot.
  static const double emblemScale = .32;

  /// §5.8 Emblem pop: 0.15 → 1.3 → 0.92 → 1 with −25° → 0°, 0.42 s.
  static const double emblemPop = .42;

  /// §5.8 Birds at 2.2 × (boxes at y ≈ 170–260 / 432–520): body centres
  /// (160, 209) (opponent, mirrored) and (160, 471) (you).
  static const double birdScale = 2.2;
  static const Offset oppBird = Offset(160, 209);
  static const Offset youBird = Offset(160, 471);

  /// §5.8 Your bird flies in at 0.54 s (0.62 s arc from (−280, +70)).
  static const double youFlyAt = .54;
  static const double youFly = .62;

  /// §5.8 Opponent plate drop (0.32 s), "FINDING RIVAL…" 14 pt 0.18 em.
  static const double plateDrop = .32;
  static const double findingTop = 142;
  static const double findingSize = 14;

  /// §5.8 Name reel: 20 names, interval 40 + 330 · p^2.4 ms; the last one
  /// lands with a 0.42 s overshoot.
  static const int reelNames = 20;
  static const double reelBaseMs = 40;
  static const double reelSlowMs = 330;
  static const double reelPow = 2.4;
  static const double reelLand = .42;

  /// §5.8 Lock: plate flash (0.38 s) + punch to 110 %, MATCH FOUND! tag
  /// (gold, 11 pt, −6°) at (36, 68), 80 confetti at (160, 106), three
  /// fireworks from the seam.
  static const double lockFlash = .38;
  static const Offset foundTag = Offset(36, 68);
  static const int lockConfetti = 80;

  /// §5.8 Fireworks at lock: (x, burst y, colour, delay s).
  static const List<(double, double, Color, double)> rockets = [
    (64, 170, Color(0xFFFFB529), 0),
    (258, 150, Color(0xFF29B6F6), .22),
    (170, 210, Color(0xFFFF4FB7), .44),
  ];

  /// §5.8 Opponent bird flies in 0.25 s after the lock (0.65 s arc).
  static const double oppFlyDelay = .25;
  static const double oppFly = .65;

  /// §5.8 VS square 100 × 56 at (110, 316), soft-pink 42 pt; punches in
  /// 0.15 s after the opponent lands (0.32 s from 3 × / −14°).
  static const Rect vsBox = Rect.fromLTWH(110, 316, 100, 56);
  static const double vsSize = 42;
  static const double vsDelay = .15;
  static const double vsPunch = .32;

  /// §5.8 Screen shake 0.3 s (±6 / ±5 pt) 0.19 s into the punch.
  static const double shakeAt = .19;
  static const double shake = .3;

  /// §5.8 Hold with taunts (s after the VS punch): flip at 0.69, hops at
  /// 1.24 and 1.47, white fade at 2.02 (0.3 s).
  static const double flipAt = .69;
  static const double hop1At = 1.24;
  static const double hop2At = 1.47;
  static const double fadeAt = 2.02;
  static const double whiteFade = .3;

  /// §5.8 Birds always alive: bob ±7 pt / ±5°, periods 1.0 / 1.15 s; wing
  /// flaps 0.22 s idle, 0.1 / 0.09 s while flying.
  static const double bob = 7;
  static const double bobTilt = 5;
  static const double youBobPeriod = 1;
  static const double oppBobPeriod = 1.15;
  static const double idleFlap = .22;
  static const double flyFlap = .1;
}
