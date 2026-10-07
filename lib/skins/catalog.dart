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

/// The 14 gear items plus the free "none" entry (§5.2).
const List<SkinItem> kGear = [
  SkinItem(layer: SkinLayer.gear, id: 'none', name: 'None', rarity: null, price: 0),
  SkinItem(layer: SkinLayer.gear, id: 'shades', name: 'Shades', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.gear, id: 'bowtie', name: 'Bow tie', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.gear, id: 'stache', name: 'Mustache', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.gear, id: 'scarf', name: 'Scarf', rarity: Rarity.common, price: 250, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'bandana', name: 'Bandana', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.gear, id: 'hearts', name: 'Heart shades', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.gear, id: 'monocle', name: 'Monocle', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.gear, id: 'sneakers', name: 'Sneakers', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'windup', name: 'Wind-up key', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'carpet', name: 'Magic carpet', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'chain', name: 'Gold chain', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.gear, id: 'mask', name: 'Hero mask', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.gear, id: 'patch', name: 'Eye patch', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.gear, id: 'jetpack', name: 'Jetpack', rarity: Rarity.legendary, price: 5000, animated: true),
];

/// The 14 hats plus the free "none" entry (§5.3).
const List<SkinItem> kHats = [
  SkinItem(layer: SkinLayer.hat, id: 'none', name: 'None', rarity: null, price: 0),
  SkinItem(layer: SkinLayer.hat, id: 'cap', name: 'Cap', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hat, id: 'beanie', name: 'Beanie', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hat, id: 'party', name: 'Party hat', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hat, id: 'band', name: 'Sweatband', rarity: Rarity.common, price: 250, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'bucket', name: 'Bucket hat', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hat, id: 'tophat', name: 'Top hat', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hat, id: 'cowboy', name: 'Cowboy', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hat, id: 'prop', name: 'Propeller', rarity: Rarity.rare, price: 750, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'chef', name: 'Chef', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hat, id: 'viking', name: 'Viking', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hat, id: 'pirate', name: 'Pirate', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.hat, id: 'wizard', name: 'Wizard', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'crown', name: 'Crown', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.hat, id: 'halo', name: 'Halo', rarity: Rarity.legendary, price: 5000, animated: true),
];

/// The 15 hoop skins (§5.4).
const List<SkinItem> kHoops = [
  SkinItem(layer: SkinLayer.hoop, id: 'pink', name: 'Classic', rarity: Rarity.common, price: 0),
  SkinItem(layer: SkinLayer.hoop, id: 'sky', name: 'Sky', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'lime', name: 'Lime', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'violet', name: 'Violet', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'night', name: 'Midnight', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.hoop, id: 'candy', name: 'Candy cane', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hoop, id: 'polka', name: 'Polka', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hoop, id: 'checker', name: 'Finish line', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hoop, id: 'donut', name: 'Donut', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.hoop, id: 'neon', name: 'Neon', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'lava', name: 'Lava', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'ice', name: 'Ice', rarity: Rarity.epic, price: 2000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'rainbow', name: 'Rainbow', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'galaxy', name: 'Galaxy', rarity: Rarity.legendary, price: 5000, animated: true),
  SkinItem(layer: SkinLayer.hoop, id: 'blackhole', name: 'Black hole', rarity: Rarity.legendary, price: 5000, animated: true),
];

/// The 15 trails (§5.5).
const List<SkinItem> kTrails = [
  SkinItem(layer: SkinLayer.trail, id: 'flame', name: 'Classic flame', rarity: Rarity.common, price: 0),
  SkinItem(layer: SkinLayer.trail, id: 'blue', name: 'Blue flame', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.trail, id: 'toxic', name: 'Toxic', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.trail, id: 'hot', name: 'Hot pink', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.trail, id: 'shadow', name: 'Shadow', rarity: Rarity.common, price: 250),
  SkinItem(layer: SkinLayer.trail, id: 'sparkle', name: 'Sparkles', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.trail, id: 'bubbles', name: 'Bubbles', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.trail, id: 'hearts', name: 'Hearts', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.trail, id: 'laser', name: 'Laser', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.trail, id: 'confetti', name: 'Confetti', rarity: Rarity.rare, price: 750),
  SkinItem(layer: SkinLayer.trail, id: 'bolt', name: 'Lightning', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.trail, id: 'blocks', name: 'Pixel blocks', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.trail, id: 'notes', name: 'Music', rarity: Rarity.epic, price: 2000),
  SkinItem(layer: SkinLayer.trail, id: 'rainbow', name: 'Rainbow', rarity: Rarity.legendary, price: 5000),
  SkinItem(layer: SkinLayer.trail, id: 'echo', name: 'Afterimage', rarity: Rarity.legendary, price: 5000),
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
/// count): 88.
const int kCollectibleTotal = 88;

/// Items added in the 2.0 update (the mock's `START_NEW`): their NEW badge
/// shows regardless of the balance.
const Set<String> kNewInUpdate = {
  'bird:lemon',
  'bird:toucan',
  'bird:ghost',
  'gear:carpet',
  'gear:windup',
  'hat:crown',
  'hat:wizard',
  'hoop:neon',
  'trail:hearts',
  'trail:echo',
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
