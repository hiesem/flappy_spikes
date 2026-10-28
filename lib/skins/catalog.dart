// region P26-F10a
import '../achievements/achievement_catalog.dart';
// endregion
import 'look.dart';

/// One purchasable/equippable wardrobe item (PRD-menu-v2 §5).
///
/// Ids, display names, rarities and `animated` flags mirror
/// `design/menu_v2/skin_art.js` (BIRDS / ACCS / HATS / HOOPS / FIRES) in grid
/// order; [price] follows §3.2 (common plain-colour birds cost 150) and the
/// free entries have price 0.
class SkinItem {
  const SkinItem({
    required this.layer,
    required this.id,
    required this.name,
    required this.rarity,
    required this.price,
    this.animated = false,
    // region P26-F10a
    this.unlock,
    // endregion
    // region P26-F9a
    this.cardKind,
    this.isSkillOnly = false,
    // endregion
  });

  final SkinLayer layer;
  final String id;
  final String name;

  /// null for the Gear and Hat "none" entries.
  final Rarity? rarity;
  final int price;
  final bool animated;
  // region P26-F10a
  final AchievementId? unlock;
  // endregion
  // region P26-F9a
  final CardKind? cardKind;
  /// Skill ownership will be derived from achievements by F10a. Never sold.
  final bool isSkillOnly;
  // endregion

  bool get isNone => id == kNoneId;
  bool get isFree => price == 0;

  /// Persisted / analytics key: `"<layer>:<id>"`.
  String get key => '${layer.key}:$id';
}

/// The 30 bird skins (§5.1), plus three PRD 2.6 F10 skill items.
const List<SkinItem> kBirds = [
  SkinItem(layer: SkinLayer.bird, id: 'classic', name: 'Classic', rarity: Rarity.common, price: 0),
  SkinItem(layer: SkinLayer.bird, id: 'sky', name: 'Sky', rarity: Rarity.common, price: 150),
  SkinItem(layer: SkinLayer.bird, id: 'lime', name: 'Lime', rarity: Rarity.common, price: 150),
  SkinItem(layer: SkinLayer.bird, id: 'grape', name: 'Grape', rarity: Rarity.common, price: 150),
  SkinItem(layer: SkinLayer.bird, id: 'tangerine', name: 'Tangerine', rarity: Rarity.common, price: 150),
  SkinItem(layer: SkinLayer.bird, id: 'mint', name: 'Mint', rarity: Rarity.common, price: 150),
  SkinItem(layer: SkinLayer.bird, id: 'lemon', name: 'Lemonade', rarity: Rarity.common, price: 150),
  SkinItem(layer: SkinLayer.bird, id: 'slate', name: 'Camo', rarity: Rarity.common, price: 150),
  SkinItem(layer: SkinLayer.bird, id: 'coral', name: 'Coral dots', rarity: Rarity.common, price: 150),
  SkinItem(layer: SkinLayer.bird, id: 'snow', name: 'Snow', rarity: Rarity.common, price: 150),
  SkinItem(layer: SkinLayer.bird, id: 'robin', name: 'Robin', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.bird, id: 'toucan', name: 'Toucan', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.bird, id: 'chick', name: 'Chick', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.bird, id: 'penguin', name: 'Penguin', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.bird, id: 'owl', name: 'Owl', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.bird, id: 'duck', name: 'Rubber duck', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.bird, id: 'flamingo', name: 'Flamingo', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.bird, id: 'puffer', name: 'Puffer', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.bird, id: 'zebra', name: 'Zebra', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.bird, id: 'buzz', name: 'Buzz', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.bird, id: 'robo', name: 'Robo', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.bird, id: 'zombie', name: 'Zombie', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.bird, id: 'ghost', name: 'Ghost', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.bird, id: 'pixel', name: '8-Bit', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.bird, id: 'frost', name: 'Frost', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.bird, id: 'magma', name: 'Magma', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.bird, id: 'galaxy', name: 'Galaxy', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.bird, id: 'golden', name: 'Golden', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.bird, id: 'rainbow', name: 'Rainbow', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.bird, id: 'phoenix', name: 'Phoenix', rarity: Rarity.legendary, price: 5000, animated: true),
  // region P26-F10a
  SkinItem(layer: SkinLayer.bird, id: 'magpie', name: 'Magpie', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.itemAll),
  SkinItem(layer: SkinLayer.bird, id: 'prism', name: 'Prism', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.hoops100),
  SkinItem(layer: SkinLayer.bird, id: 'daynight', name: 'Day & Night', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.daily30),
  // endregion
];

/// The 29 sold gear items, free "none", and three F10 skill items (§5.2;
/// PRD-2.3 §19.3: the
/// 15 new items mixed in by rarity, after the existing ones of each rarity).
const List<SkinItem> kGear = [
  SkinItem(layer: SkinLayer.gear, id: 'none', name: 'None', rarity: null, price: 0),
  SkinItem(layer: SkinLayer.gear, id: 'shades', name: 'Shades', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.gear, id: 'bowtie', name: 'Bow tie', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.gear, id: 'stache', name: 'Mustache', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.gear, id: 'scarf', name: 'Scarf', rarity: Rarity.common, price: 250, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'bandana', name: 'Bandana', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.gear, id: 'snorkel', name: 'Snorkel', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.gear, id: 'necktie', name: 'Necktie', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.gear, id: 'bandaid', name: 'Band-aid', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.gear, id: 'gum', name: 'Bubble gum', rarity: Rarity.common, price: 250, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'lei', name: 'Flower lei', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.gear, id: 'hearts', name: 'Heart shades', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.gear, id: 'monocle', name: 'Monocle', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.gear, id: 'sneakers', name: 'Sneakers', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'windup', name: 'Wind-up key', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'carpet', name: 'Magic carpet', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'balloon', name: 'Balloon', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'backpack', name: 'Backpack', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'skates', name: 'Roller skates', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'swimring', name: 'Swim ring', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'cape', name: 'Cape', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'chain', name: 'Gold chain', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'mask', name: 'Hero mask', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.gear, id: 'patch', name: 'Eye patch', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.gear, id: 'butterfly', name: 'Butterfly', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'drone', name: 'Drone buddy', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'jetpack', name: 'Jetpack', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'crystal', name: 'Crystal wings', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'atom', name: 'Atom', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'disco', name: 'Disco ball', rarity: Rarity.legendary, price: 5000, animated: true),
  // region P26-F10a
  SkinItem(layer: SkinLayer.gear, id: 'goggles', name: 'Flight Goggles', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.rideAll),
  SkinItem(layer: SkinLayer.gear, id: 'hoopchain', name: 'Hoop Necklace', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.hoops50),
  SkinItem(layer: SkinLayer.gear, id: 'peacock', name: 'Peacock Fan', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.skinAll),
  // endregion
];

/// The 29 sold hats, free "none", and three F10 skill items (§5.3).
const List<SkinItem> kHats = [
  SkinItem(layer: SkinLayer.hat, id: 'none', name: 'None', rarity: null, price: 0),
  SkinItem(layer: SkinLayer.hat, id: 'cap', name: 'Cap', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hat, id: 'beanie', name: 'Beanie', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hat, id: 'party', name: 'Party hat', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hat, id: 'band', name: 'Sweatband', rarity: Rarity.common, price: 250, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'bucket', name: 'Bucket hat', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hat, id: 'sprout', name: 'Sprout', rarity: Rarity.common, price: 250, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'cone', name: 'Traffic cone', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hat, id: 'egg', name: 'Fried egg', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hat, id: 'paperboat', name: 'Paper boat', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hat, id: 'phones', name: 'Headphones', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hat, id: 'tophat', name: 'Top hat', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hat, id: 'cowboy', name: 'Cowboy', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hat, id: 'prop', name: 'Propeller', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'chef', name: 'Chef', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hat, id: 'viking', name: 'Viking', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hat, id: 'fishbowl', name: 'Fishbowl', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'cupcake', name: 'Cupcake', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hat, id: 'raincloud', name: 'Rain cloud', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'antennae', name: 'Antennae', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'sharkfin', name: 'Shark fin', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'pirate', name: 'Pirate', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.hat, id: 'wizard', name: 'Wizard', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'volcano', name: 'Volcano', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'ufo', name: 'UFO', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'bdaycake', name: 'Birthday cake', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'crown', name: 'Crown', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'halo', name: 'Halo', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'planet', name: 'Ringed planet', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'sunburst', name: 'Sunburst', rarity: Rarity.legendary, price: 5000, animated: true),
  // region P26-F10a
  SkinItem(layer: SkinLayer.hat, id: 'skycrown', name: 'Sky Crown', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.skyHigh),
  SkinItem(layer: SkinLayer.hat, id: 'nest', name: 'Nest Hat', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.masterHatch),
  SkinItem(layer: SkinLayer.hat, id: 'jackpot', name: 'Jackpot', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.masterJackpot),
  // endregion
];

/// The 30 hoop skins and three F10 skill items (§5.4).
const List<SkinItem> kHoops = [
  SkinItem(layer: SkinLayer.hoop, id: 'pink', name: 'Classic', rarity: Rarity.common, price: 0),
  SkinItem(layer: SkinLayer.hoop, id: 'sky', name: 'Sky', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'lime', name: 'Lime', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'violet', name: 'Violet', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'night', name: 'Midnight', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'sunset', name: 'Sunset', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'lemon', name: 'Lemon slice', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'bamboo', name: 'Bamboo', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'rope', name: 'Rope', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'cloud', name: 'Cloud', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'candy', name: 'Candy cane', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hoop, id: 'polka', name: 'Polka', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hoop, id: 'checker', name: 'Finish line', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hoop, id: 'donut', name: 'Donut', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hoop, id: 'tire', name: 'Tire', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'melon', name: 'Watermelon', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hoop, id: 'zipper', name: 'Zipper', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'tape', name: 'Tape measure', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hoop, id: 'pearls', name: 'Pearls', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'vine', name: 'Vine', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'neon', name: 'Neon', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'lava', name: 'Lava', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'ice', name: 'Ice', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'electric', name: 'Electric', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'water', name: 'Water', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'cog', name: 'Cogwheel', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'rainbow', name: 'Rainbow', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'galaxy', name: 'Galaxy', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'blackhole', name: 'Black hole', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'aurora', name: 'Aurora', rarity: Rarity.legendary, price: 5000, animated: true),
  // region P26-F10a
  SkinItem(layer: SkinLayer.hoop, id: 'spikes', name: 'Steel Spikes', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.rankSpikeAce),
  SkinItem(layer: SkinLayer.hoop, id: 'phoenixring', name: 'Phoenix Ring', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.rankPhoenix),
  SkinItem(layer: SkinLayer.hoop, id: 'legend', name: 'Legend Ring', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.rankLegend),
  // endregion
];

/// The 30 trails and three F10 skill items (§5.5).
const List<SkinItem> kTrails = [
  SkinItem(layer: SkinLayer.trail, id: 'flame', name: 'Classic flame', rarity: Rarity.common, price: 0),
  SkinItem(layer: SkinLayer.trail, id: 'blue', name: 'Blue flame', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.trail, id: 'toxic', name: 'Toxic', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.trail, id: 'hot', name: 'Hot pink', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.trail, id: 'shadow', name: 'Shadow', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.trail, id: 'sunset', name: 'Sunset flame', rarity: Rarity.common, price: 250, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'leaves', name: 'Leaves', rarity: Rarity.common, price: 250, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'snow', name: 'Snowflakes', rarity: Rarity.common, price: 250, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'petals', name: 'Petals', rarity: Rarity.common, price: 250, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'ink', name: 'Ink drops', rarity: Rarity.common, price: 250, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'sparkle', name: 'Sparkles', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.trail, id: 'bubbles', name: 'Bubbles', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.trail, id: 'hearts', name: 'Hearts', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.trail, id: 'laser', name: 'Laser', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.trail, id: 'confetti', name: 'Confetti', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.trail, id: 'planes', name: 'Paper planes', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'popcorn', name: 'Popcorn', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'fireworks', name: 'Fireworks', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'steps', name: 'Footprints', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'fish', name: 'Fish', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'bolt', name: 'Lightning', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.trail, id: 'blocks', name: 'Pixel blocks', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.trail, id: 'notes', name: 'Music', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.trail, id: 'galaxy', name: 'Galaxy dust', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'prism', name: 'Prism', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'lavadrip', name: 'Lava drips', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'rainbow', name: 'Rainbow', rarity: Rarity.legendary, price: 5000),
  SkinItem(layer: SkinLayer.trail, id: 'echo', name: 'Afterimage', rarity: Rarity.legendary, price: 5000),
  SkinItem(layer: SkinLayer.trail, id: 'supernova', name: 'Supernova', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.trail, id: 'paint', name: 'Paint stroke', rarity: Rarity.legendary, price: 5000, animated: true),
  // region P26-F10a
  SkinItem(layer: SkinLayer.trail, id: 'thread', name: 'Golden Thread', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.bullseye),
  SkinItem(layer: SkinLayer.trail, id: 'constellation', name: 'Constellation', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.masterStars),
  SkinItem(layer: SkinLayer.trail, id: 'fireflies', name: 'Firefly Swarm', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true, unlock: AchievementId.masterJar),
  // endregion
];

// region P26-F9a
// PRD F9: server allow-list order, 17 sold + 3 skill items per kind.
const List<SkinItem> kCardFrames = [
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_bubblegum', name: 'Bubblegum', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_tape', name: 'Sky Tape', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_checker', name: 'Checkered', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_eggshell', name: 'Eggshell', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_stitch', name: 'Stitched', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_hazard', name: 'Caution', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_spikes', name: 'Spike Teeth', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_feathers', name: 'Feather Fan', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_hoops', name: 'Hoop Loop', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_pinball', name: 'Pinball', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_deepsea', name: 'Deep Sea', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_neon', name: 'Neon Sign', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_laurel', name: 'Gold Laurel', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_magma', name: 'Magma Crust', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_storm', name: 'Thunderhead', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_wings', name: 'Golden Wings', rarity: Rarity.legendary, price: 5000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'f_orbit', name: 'Cosmic Orbit', rarity: Rarity.legendary, price: 5000),
  // region P26-F10a
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'pecking', unlock: AchievementId.vs10, name: 'Pecking Order', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true),
  // endregion
  // region P26-F10a
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'roost', unlock: AchievementId.vs50, name: 'Roost Ruler', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true),
  // endregion
  // region P26-F10a
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.frame, id: 'prey', unlock: AchievementId.birdOfPrey, name: 'Bird of Prey', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true),
  // endregion
];

const List<SkinItem> kCardNames = [
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_tangerine', name: 'Tangerine', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_ocean', name: 'Ocean', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_grass', name: 'Grass', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_cherry', name: 'Cherry', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_grape', name: 'Grape', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_midnight', name: 'Midnight', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_bubble', name: 'Bubble Pop', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_candy', name: 'Candy Stripe', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_comic', name: 'Comic Ink', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_sunset', name: 'Sunset', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_spiky', name: 'Spike Line', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_rainbow', name: 'Rainbow', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_gold', name: 'Liquid Gold', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_flappy', name: 'Flappy', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_glitch', name: 'Glitch', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_fire', name: 'On Fire', rarity: Rarity.legendary, price: 5000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_stardust', name: 'Stardust', rarity: Rarity.legendary, price: 5000),
  // region P26-F10a
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_sky', unlock: AchievementId.secondWind, name: 'Skywriter', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true),
  // endregion
  // region P26-F10a
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_thunder', unlock: AchievementId.albatross, name: 'Thunderstruck', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true),
  // endregion
  // region P26-F10a
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.name, id: 'n_marquee', unlock: AchievementId.threeLittleBirds, name: 'Headliner', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true),
  // endregion
];

const List<SkinItem> kCardStickers = [
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_gg', name: 'GG!', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_thumbs', name: 'Thumbs Up', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_heart', name: 'Big Heart', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_wow', name: 'WOW', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_kaching', name: 'Ka-ching', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_spiked', name: 'Spiked!', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_pow', name: 'Pow!', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_nailed', name: 'Nailed It', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_bye', name: 'Bye Bye', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_hatch', name: 'Hatched', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_zoom', name: 'Zoom', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_hot', name: 'Hot Streak', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_medal', name: 'Gold Medal', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_piggy', name: 'Piggy Bank', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_disco', name: 'Disco', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_champ', name: 'Champion', rarity: Rarity.legendary, price: 5000),
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_fireworks', name: 'Fireworks', rarity: Rarity.legendary, price: 5000),
  // region P26-F10a
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_unstop', unlock: AchievementId.ironBeak, name: 'Unstoppable', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true),
  // endregion
  // region P26-F10a
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_flawless', unlock: AchievementId.flawless, name: 'Flawless', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true),
  // endregion
  // region P26-F10a
  SkinItem(layer: SkinLayer.card, cardKind: CardKind.sticker, id: 's_topflock', unlock: AchievementId.topBird, name: 'Top of the Flock', rarity: Rarity.legendary, price: 0, animated: true, isSkillOnly: true),
  // endregion
];

/// The 51 sold card cosmetics (skill entries remain separate).
final List<SkinItem> kCardItems = List.unmodifiable(
  kCards.where((item) => !item.isSkillOnly),
);

final List<SkinItem> kSkillCardItems = List.unmodifiable(
  kCards.where((item) => item.isSkillOnly),
);

const List<SkinItem> kCards = [...kCardFrames, ...kCardNames, ...kCardStickers];

/// Empty slots are free defaults, not collectible catalogue entries.
const SkinItem _emptyCardSlot = SkinItem(
  layer: SkinLayer.card, id: '', name: 'None', rarity: null, price: 0,
);

SkinItem? cardItemById(String id) {
  if (id.isEmpty) return _emptyCardSlot;
  for (final item in kCards) {
    if (item.id == id) return item;
  }
  return null;
}

List<SkinItem> cardItemsFor(CardKind kind) => switch (kind) {
  CardKind.frame => kCardFrames,
  CardKind.name => kCardNames,
  CardKind.sticker => kCardStickers,
};

/// Reject malformed shapes; unknown or misplaced ids leave only that slot empty.
String sanitiseCard(Object? value) {
  if (value is! String || value.length > 48) return '';
  final slots = value.split('|');
  if (slots.length != 3) return '';
  for (final kind in CardKind.values) {
    if (!cardItemsFor(kind).any((item) => item.id == slots[kind.index])) {
      slots[kind.index] = '';
    }
  }
  return slots.every((s) => s.isEmpty) ? '' : slots.join('|');
}
// endregion

/// Every layer's items in grid order (§5 has the same order as the mock).
const Map<SkinLayer, List<SkinItem>> kCatalog = {
  SkinLayer.bird: kBirds,
  SkinLayer.gear: kGear,
  SkinLayer.hat: kHats,
  SkinLayer.hoop: kHoops,
  SkinLayer.trail: kTrails,
  // region P26-F9a
  // region P26-F9e
  SkinLayer.card: kCards,
  // endregion
  // endregion
};

/// Collectible items in the whole catalogue (the two "none" entries do not
/// count): 223 (163 wardrobe collectibles and 60 card cosmetics; PRD F10).
// region P26-F9e
// PRD F10: 163 wardrobe collectibles + 60 cards. O81 / PRD:855
// separates PROUD PEACOCK's 199 sold collectibles from the UI total.
// region P26-F10a
const int kCollectibleTotal = 223;
const int kSoldCollectibleTotal = 199;
// TODO(F10c): register the skill item painters when both art packages merge.
// endregion
// endregion

/// Items added in the 2.3 update (PRD-2.3 §19.3): their NEW badge shows
/// until seen, regardless of the balance. Ordered: the four showpieces first
/// (the Shop's featured item is the first one not owned), then hats, gear,
/// hoops and trails in tag order.
const Set<String> kNewInUpdate = {
  'hat:sunburst', 'gear:disco', 'hoop:aurora', 'trail:supernova', //
  'hat:sprout', 'hat:cone', 'hat:egg', 'hat:paperboat', 'hat:phones',
  'hat:fishbowl', 'hat:cupcake', 'hat:raincloud', 'hat:antennae',
  'hat:sharkfin', 'hat:volcano', 'hat:ufo', 'hat:bdaycake', 'hat:planet',
  'gear:snorkel', 'gear:necktie', 'gear:bandaid', 'gear:gum', 'gear:lei',
  'gear:balloon', 'gear:backpack', 'gear:skates', 'gear:swimring',
  'gear:cape', 'gear:butterfly', 'gear:drone', 'gear:crystal', 'gear:atom',
  'hoop:sunset', 'hoop:lemon', 'hoop:bamboo', 'hoop:rope', 'hoop:cloud',
  'hoop:tire', 'hoop:melon', 'hoop:zipper', 'hoop:tape', 'hoop:pearls',
  'hoop:vine', 'hoop:electric', 'hoop:water', 'hoop:cog',
  'trail:sunset', 'trail:leaves', 'trail:snow', 'trail:petals', 'trail:ink',
  'trail:planes', 'trail:popcorn', 'trail:fireworks', 'trail:steps',
  'trail:fish', 'trail:galaxy', 'trail:prism', 'trail:lavadrip',
  'trail:paint',
};

/// Items of [layer] in grid order.
List<SkinItem> itemsFor(SkinLayer layer) => kCatalog[layer]!;

/// The item with [id] on [layer], or null when the id is unknown.
SkinItem? itemById(SkinLayer layer, String id) {
  // region P26-F9a
  if (layer == SkinLayer.card) return cardItemById(id);
  // endregion
  for (final item in itemsFor(layer)) {
    if (item.id == id) return item;
  }
  return null;
}

/// The free default id for [layer] (also the fallback for unknown / removed
/// ids): Classic bird, none gear, none hat, Classic hoop, Classic flame.
String defaultItemId(SkinLayer layer) => Look.defaults.idFor(layer);

/// Every catalogue item, all layers.
Iterable<SkinItem> get allItems =>
    // region P26-F9a
    kShopLayers.expand(itemsFor);
    // endregion
