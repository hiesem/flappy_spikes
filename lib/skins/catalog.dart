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
  });

  final SkinLayer layer;
  final String id;
  final String name;

  /// null for the Gear and Hat "none" entries.
  final Rarity? rarity;
  final int price;
  final bool animated;

  bool get isNone => id == kNoneId;
  bool get isFree => price == 0;

  /// Persisted / analytics key: `"<layer>:<id>"`.
  String get key => '${layer.key}:$id';
}

/// The 30 bird skins (§5.1).
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
];

/// The 29 gear items plus the free "none" entry (§5.2; PRD-2.3 §19.3: the
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
];

/// The 29 hats plus the free "none" entry (§5.3; PRD-2.3 §19.3 grid order).
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
];

/// The 30 hoop skins (§5.4; PRD-2.3 §19.3 grid order).
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
];

/// The 30 trails (§5.5; PRD-2.3 §19.3 grid order).
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
];

/// Every layer's items in grid order (§5 has the same order as the mock).
const Map<SkinLayer, List<SkinItem>> kCatalog = {
  SkinLayer.bird: kBirds,
  SkinLayer.gear: kGear,
  SkinLayer.hat: kHats,
  SkinLayer.hoop: kHoops,
  SkinLayer.trail: kTrails,
};

/// Collectible items in the whole catalogue (the two "none" entries do not
/// count): 148 (PRD-2.3 §19.3: 88 + the 60 new items).
const int kCollectibleTotal = 148;

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
    SkinLayer.values.expand(itemsFor);
