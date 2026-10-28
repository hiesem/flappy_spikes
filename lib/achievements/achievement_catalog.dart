/// PRD-2.3.1 §12.1 the 48 achievements (Play Games + Game Center), in the
/// approved order. The single source for the tracker, the store kits and the
/// tests: the names, the descriptions (Play's description = Apple's
/// pre-earned text), Apple's earned text, the points (Game Center points =
/// Play XP), hidden (the rides; PRD-2.3.1 §19.3 adds the masteries,
/// MAGPIE, vs_10, vs_50, skin_all and daily_30) and both platform ids.
library;

/// §12.1 the groups (their point sums are tested: 220 / 90 / 80 / 60 / 75 /
/// 75 / 155).
enum AchievementGroup { rank, ride, item, mastery, hoops, versus, more }

enum AchievementId {
  // region P26-J9
  // Single-run score achievements (10, 220 pts).
  // endregion
  rankEgg(
    'rank_egg',
    'EGG',
    'Score 25 points in one run.',
    "Cracked it! You're an EGG.",
    5,
    AchievementGroup.rank,
    androidId: 'CgkIsZz8pvUOEAIQBA',
  ),
  rankChick(
    'rank_chick',
    'CHICK',
    'Score 50 points in one run.',
    "Peep peep! You're a CHICK.",
    5,
    AchievementGroup.rank,
    androidId: 'CgkIsZz8pvUOEAIQBQ',
  ),
  rankFledgling(
    'rank_fledgling',
    'FLEDGLING',
    'Score 100 points in one run.',
    'Your first feathers are in.',
    10,
    AchievementGroup.rank,
    androidId: 'CgkIsZz8pvUOEAIQBg',
  ),
  rankFlapper(
    'rank_flapper',
    'FLAPPER',
    'Score 200 points in one run.',
    'Flap, flap, flap!',
    10,
    AchievementGroup.rank,
    androidId: 'CgkIsZz8pvUOEAIQBw',
  ),
  rankGlider(
    'rank_glider',
    'GLIDER',
    'Score 400 points in one run.',
    'Smooth sailing.',
    15,
    AchievementGroup.rank,
    androidId: 'CgkIsZz8pvUOEAIQCA',
  ),
  rankFalcon(
    'rank_falcon',
    'FALCON',
    'Score 600 points in one run.',
    'Sharp eyes, fast wings.',
    20,
    AchievementGroup.rank,
    androidId: 'CgkIsZz8pvUOEAIQCQ',
  ),
  rankHawk(
    'rank_hawk',
    'HAWK',
    'Score 800 points in one run.',
    'One fierce flyer.',
    25,
    AchievementGroup.rank,
    androidId: 'CgkIsZz8pvUOEAIQCg',
  ),
  rankSpikeAce(
    'rank_spike_ace',
    'SPIKE ACE',
    'Score 1,000 points in one run.',
    'The spikes fear you.',
    30,
    AchievementGroup.rank,
    androidId: 'CgkIsZz8pvUOEAIQCw',
  ),
  rankPhoenix(
    'rank_phoenix',
    'PHOENIX',
    'Score 2,000 points in one run.',
    'Rising from the ashes.',
    40,
    AchievementGroup.rank,
    androidId: 'CgkIsZz8pvUOEAIQDA',
  ),
  rankLegend(
    'rank_legend',
    'LEGEND',
    'Score 5,000 points in one run.',
    'Legendary. Truly.',
    60,
    AchievementGroup.rank,
    androidId: 'CgkIsZz8pvUOEAIQDQ',
  ),

  // --- Rides (7, 90 pts, all hidden) ------------------------------------------
  rideCannon(
    'ride_cannon',
    'BEAK FIRST',
    'Finish the Cannon ride.',
    'Fired out beak first!',
    10,
    AchievementGroup.ride,
    hidden: true,
    androidId: 'CgkIsZz8pvUOEAIQDg',
  ),
  rideSpace(
    'ride_space',
    'SPACE TWEET',
    'Finish the Space ride.',
    'Houston, we have a tweet.',
    10,
    AchievementGroup.ride,
    hidden: true,
    androidId: 'CgkIsZz8pvUOEAIQDw',
  ),
  rideVolcano(
    'ride_volcano',
    'FLAME-INGO',
    'Finish the Volcano ride.',
    'Hot stuff!',
    10,
    AchievementGroup.ride,
    hidden: true,
    androidId: 'CgkIsZz8pvUOEAIQEA',
  ),
  rideSea(
    'ride_sea',
    'PENGUIN MODE',
    'Finish the Sea ride.',
    'Waddle you know, you made it!',
    10,
    AchievementGroup.ride,
    hidden: true,
    androidId: 'CgkIsZz8pvUOEAIQEQ',
  ),
  ridePinball(
    'ride_pinball',
    'BUMPER BIRD',
    'Finish the Pinball ride.',
    'Boing, boing, boing!',
    10,
    AchievementGroup.ride,
    hidden: true,
    androidId: 'CgkIsZz8pvUOEAIQEg',
  ),
  rideStorm(
    'ride_storm',
    'RUFFLED FEATHERS',
    'Finish the Storm ride.',
    'You weathered the storm.',
    10,
    AchievementGroup.ride,
    hidden: true,
    androidId: 'CgkIsZz8pvUOEAIQEw',
  ),
  rideAll(
    'ride_all',
    'FREQUENT FLYER',
    'Finish all six rides.',
    'Every ride, done!',
    30,
    AchievementGroup.ride,
    hidden: true,
    androidId: 'CgkIsZz8pvUOEAIQFA',
  ),

  // --- Item catch goals (12, 80 pts; PRD-2.3.1 §19.1 lifetime counts) ---------------------------------
  itemHeart(
    'item_heart',
    'TWEETHEART',
    'Catch 10 Hearts.',
    'Love is in the air.',
    5,
    AchievementGroup.item,
    androidId: 'CgkIsZz8pvUOEAIQFQ',
  ),
  itemShield(
    'item_shield',
    'TOUGH EGG',
    'Catch 10 Shields.',
    'Hard to crack.',
    5,
    AchievementGroup.item,
    androidId: 'CgkIsZz8pvUOEAIQFg',
  ),
  itemStarTrail(
    'item_star_trail',
    'STARLING',
    'Catch stars from 50 Star Trails.',
    'Star catcher!',
    5,
    AchievementGroup.item,
    androidId: 'CgkIsZz8pvUOEAIQFw',
  ),
  itemHourglass(
    'item_hourglass',
    'TIME FLIES',
    'Catch 3 Hourglasses.',
    "Time flies when you're flapping.",
    5,
    AchievementGroup.item,
    androidId: 'CgkIsZz8pvUOEAIQGA',
  ),
  itemMiniBird(
    'item_mini_bird',
    'LITTLE BIRDIE',
    'Catch 3 Mini Birds.',
    'Small but mighty.',
    5,
    AchievementGroup.item,
    androidId: 'CgkIsZz8pvUOEAIQGQ',
  ),
  itemCoinFrenzy(
    'item_coin_frenzy',
    'GOLDFINCH',
    'Catch 3 Coin Frenzies.',
    'Coins, coins, coins!',
    5,
    AchievementGroup.item,
    androidId: 'CgkIsZz8pvUOEAIQGg',
  ),
  itemEgg(
    'item_egg',
    'EGGCELLENT!',
    'Catch 5 Eggs.',
    'Simply eggcellent!',
    5,
    AchievementGroup.item,
    androidId: 'CgkIsZz8pvUOEAIQGw',
  ),
  itemPiggy(
    'item_piggy',
    'NEST EGG',
    'Catch 3 Piggy Banks.',
    'Saving for a rainy day.',
    5,
    AchievementGroup.item,
    androidId: 'CgkIsZz8pvUOEAIQHA',
  ),
  itemJar(
    'item_jar',
    'BUG BUFFET',
    'Catch 3 Firefly Jars.',
    'Crunchy snacks ahead.',
    5,
    AchievementGroup.item,
    androidId: 'CgkIsZz8pvUOEAIQHQ',
  ),
  itemFeather(
    'item_feather',
    'LIGHT AS A FEATHER',
    'Catch 3 Feathers.',
    'Floating on air.',
    5,
    AchievementGroup.item,
    androidId: 'CgkIsZz8pvUOEAIQHg',
  ),
  itemPuzzle(
    'item_puzzle',
    'PUZZLED PIGEON',
    'Catch 3 Puzzle Pieces.',
    'Hmm… where does this go?',
    5,
    AchievementGroup.item,
    androidId: 'CgkIsZz8pvUOEAIQHw',
  ),
  itemAll(
    'item_all',
    'MAGPIE',
    'Reach every item goal.',
    'Every shiny thing is yours.',
    25,
    AchievementGroup.item,
    hidden: true, // PRD-2.3.1 §19.3
    androidId: 'CgkIsZz8pvUOEAIQIA',
  ),

  // --- Mastery (5, 60 pts) ---------------------------------------------------
  masterHatch(
    'master_hatch',
    'MOTHER HEN',
    'Hatch an egg into a chick.',
    'Proud parent!',
    10,
    AchievementGroup.mastery,
    hidden: true, // PRD-2.3.1 §19.3
    androidId: 'CgkIsZz8pvUOEAIQIQ',
  ),
  masterJar(
    'master_jar',
    'NIGHT OWL',
    'Fill a Firefly Jar.',
    'What a glow!',
    10,
    AchievementGroup.mastery,
    hidden: true, // PRD-2.3.1 §19.3
    androidId: 'CgkIsZz8pvUOEAIQIg',
  ),
  masterStars(
    'master_stars',
    'SEEING STARS',
    'Catch all 8 stars of a Star Trail.',
    'Twinkle, twinkle!',
    10,
    AchievementGroup.mastery,
    hidden: true, // PRD-2.3.1 §19.3
    androidId: 'CgkIsZz8pvUOEAIQIw',
  ),
  masterPicture(
    'master_picture',
    "BIRD'S-EYE VIEW",
    'Complete a puzzle picture.',
    'What a view!',
    15,
    AchievementGroup.mastery,
    hidden: true, // PRD-2.3.1 §19.3
    androidId: 'CgkIsZz8pvUOEAIQJA',
  ),
  masterJackpot(
    'master_jackpot',
    'GOLDEN EGG',
    'Pop the jackpot balloon on the bonus screen.',
    'Jackpot!',
    15,
    AchievementGroup.mastery,
    hidden: true, // PRD-2.3.1 §19.3
    androidId: 'CgkIsZz8pvUOEAIQJQ',
  ),

  // --- Hoops in one run (4, 75 pts) ------------------------------------------
  hoops10(
    'hoops_10',
    'FIRST FLIGHT',
    'Pass 10 hoops in one run.',
    'Wheels up!',
    5,
    AchievementGroup.hoops,
    androidId: 'CgkIsZz8pvUOEAIQJg',
  ),
  hoops25(
    'hoops_25',
    'HOOPOE',
    'Pass 25 hoops in one run.',
    'Hoop, hoop, hooray!',
    10,
    AchievementGroup.hoops,
    androidId: 'CgkIsZz8pvUOEAIQJw',
  ),
  hoops50(
    'hoops_50',
    'RING-NECKED',
    'Pass 50 hoops in one run.',
    'Ring after ring after ring.',
    20,
    AchievementGroup.hoops,
    androidId: 'CgkIsZz8pvUOEAIQKA',
  ),
  hoops100(
    'hoops_100',
    'FLYING COLORS',
    'Pass 100 hoops in one run.',
    'Passed with flying colors!',
    40,
    AchievementGroup.hoops,
    androidId: 'CgkIsZz8pvUOEAIQKQ',
  ),

  // --- Versus (3, 75 pts) ----------------------------------------------------
  vs1(
    'vs_1',
    'BEAK TO BEAK',
    'Win a versus match.',
    'Beak to beak, and you won!',
    10,
    AchievementGroup.versus,
    androidId: 'CgkIsZz8pvUOEAIQKg',
  ),
  vs10(
    'vs_10',
    'PECKING ORDER',
    'Win 10 versus matches.',
    'Top of the pecking order.',
    25,
    AchievementGroup.versus,
    hidden: true, // PRD-2.3.1 §19.3
    androidId: 'CgkIsZz8pvUOEAIQKw',
  ),
  vs50(
    'vs_50',
    'RULES THE ROOST',
    'Win 50 versus matches.',
    'The roost is yours.',
    40,
    AchievementGroup.versus,
    hidden: true, // PRD-2.3.1 §19.3
    androidId: 'CgkIsZz8pvUOEAIQLA',
  ),

  // --- Firsts, skins and daily play (7, 155 pts) -----------------------------
  firstRevive(
    'first_revive',
    'STILL TWEETING',
    'Revive during a run.',
    'Still tweeting!',
    5,
    AchievementGroup.more,
    androidId: 'CgkIsZz8pvUOEAIQLQ',
  ),
  firstBigHoops(
    'first_big_hoops',
    'BIG BIRD',
    'Play a run with Big Hoops.',
    'Go big or go home.',
    5,
    AchievementGroup.more,
    androidId: 'CgkIsZz8pvUOEAIQLg',
  ),
  firstFever(
    'first_fever',
    'HOT WINGS',
    'Trigger FEVER.',
    'Hot, hot, hot!',
    10,
    AchievementGroup.more,
    androidId: 'CgkIsZz8pvUOEAIQLw',
  ),
  skinFirst(
    'skin_first',
    'FRESH FEATHERS',
    'Buy your first item in the shop.',
    'Looking sharp!',
    10,
    AchievementGroup.more,
    androidId: 'CgkIsZz8pvUOEAIQMA',
  ),
  skinAll(
    'skin_all',
    'PROUD PEACOCK',
    'Own every item in the shop.',
    'The proudest bird in the sky.',
    50,
    AchievementGroup.more,
    hidden: true, // PRD-2.3.1 §19.3
    androidId: 'CgkIsZz8pvUOEAIQMQ',
  ),
  daily7(
    'daily_7',
    'EARLY BIRD',
    'Play on 7 days in a row.',
    'Rise and shine!',
    25,
    AchievementGroup.more,
    androidId: 'CgkIsZz8pvUOEAIQMg',
  ),
  daily30(
    'daily_30',
    'HOMING PIGEON',
    'Play on 30 days in a row.',
    'Always finds its way home.',
    50,
    AchievementGroup.more,
    hidden: true, // PRD-2.3.1 §19.3
    androidId: 'CgkIsZz8pvUOEAIQMw',
  );

  const AchievementId(
    this.key,
    this.title,
    this.description,
    this.earned,
    this.points,
    this.group, {
    this.hidden = false,
    this.androidId = '',
  });

  /// Stable internal id: storage, analytics, asset and kit file names.
  final String key;

  /// The store name (Play name, Apple reference name and title).
  final String title;

  /// Play description / Apple pre-earned description.
  final String description;

  /// Apple's earned description (Play has no such field).
  final String earned;

  /// Game Center points = Play XP (multiples of 5, ≤ 100).
  final int points;

  final AchievementGroup group;

  /// Shown as "Hidden" until unlocked: the 7 rides, plus the 10 of
  /// PRD-2.3.1 §19.3 (Game Center kit). Play Console locks the initial
  /// state of a published achievement, so on Play only the 7 rides are
  /// hidden; the §19.3 ten stay Revealed there (2026-10-14).
  final bool hidden;

  /// Play Console's generated id (§12.6, created 2026-10-14). Empty = not
  /// created: `unlock` skips the key on Android (logged once).
  final String androidId;

  /// Game Center id (App Store Connect, §12.6 iOS kit).
  String get iosId => 'fs_ach_$key';

  /// The 160 pt toast icon (§12.5).
  String get asset => 'achievements/ach_$key.png';

  static AchievementId? fromKey(String key) {
    for (final a in values) {
      if (a.key == key) return a;
    }
    return null;
  }
}

// region P26-J9
/// PRD-2.6 R5: single-run score achievements in ascending threshold order.
const List<AchievementId> kRankAchievements = [
  AchievementId.rankEgg,
  AchievementId.rankChick,
  AchievementId.rankFledgling,
  AchievementId.rankFlapper,
  AchievementId.rankGlider,
  AchievementId.rankFalcon,
  AchievementId.rankHawk,
  AchievementId.rankSpikeAce,
  AchievementId.rankPhoenix,
  AchievementId.rankLegend,
];

/// Single-run scores for [kRankAchievements], independent of player level.
const List<int> kRankScoreThresholds = [
  25,
  50,
  100,
  200,
  400,
  600,
  800,
  1000,
  2000,
  5000,
];
// endregion

/// §12.1 hoops in one run: threshold → achievement.
const List<(int, AchievementId)> kHoopAchievements = [
  (10, AchievementId.hoops10),
  (25, AchievementId.hoops25),
  (50, AchievementId.hoops50),
  (100, AchievementId.hoops100),
];

/// §12.1 versus wins: threshold → achievement.
const List<(int, AchievementId)> kVersusAchievements = [
  (1, AchievementId.vs1),
  (10, AchievementId.vs10),
  (50, AchievementId.vs50),
];

/// §12.1 days in a row: threshold → achievement.
const List<(int, AchievementId)> kDailyAchievements = [
  (7, AchievementId.daily7),
  (30, AchievementId.daily30),
];

/// §12.1 the 11 item achievements (PRD-2.3.1 §19.1: lifetime catch goals;
/// MAGPIE needs all of them unlocked).
const List<AchievementId> kItemAchievements = [
  AchievementId.itemHeart,
  AchievementId.itemShield,
  AchievementId.itemStarTrail,
  AchievementId.itemHourglass,
  AchievementId.itemMiniBird,
  AchievementId.itemCoinFrenzy,
  AchievementId.itemEgg,
  AchievementId.itemPiggy,
  AchievementId.itemJar,
  AchievementId.itemFeather,
  AchievementId.itemPuzzle,
];

/// PRD-2.3.1 §19.1 the lifetime catches each item achievement needs, set by
/// how often the bot catches the item in a 20-hoop run on the live defaults
/// (the rarest items get the smallest N; never below 3), so the 11 goals
/// land after about 25–40 such runs (puzzle, the rarest, later). Bot
/// catches per 20-hoop run of a simulated new player (2026-10-14, 8 × 40
/// runs, first-meet and lifetime gates, `test/tools/ach_pacing_test.dart`):
/// heart 0.27, shield 0.37, star trails 1.80 (a trail counts once),
/// hourglass 0.07, mini bird 0.08, coin frenzy 0.09, egg 0.15, piggy 0.11,
/// jar 0.11, feather 0.08, puzzle 0.05. The descriptions above say the same
/// count (a test checks it).
const Map<AchievementId, int> kItemGoals = {
  AchievementId.itemHeart: 10,
  AchievementId.itemShield: 10,
  AchievementId.itemStarTrail: 50,
  AchievementId.itemHourglass: 3,
  AchievementId.itemMiniBird: 3,
  AchievementId.itemCoinFrenzy: 3,
  AchievementId.itemEgg: 5,
  AchievementId.itemPiggy: 3,
  AchievementId.itemJar: 3,
  AchievementId.itemFeather: 3,
  AchievementId.itemPuzzle: 3,
};

/// The goal of an item achievement (1 for any other id).
int itemGoal(AchievementId id) => kItemGoals[id] ?? 1;
