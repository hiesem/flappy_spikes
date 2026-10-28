// PRD:834 adds 60 card collectibles, including 51 sold for 69 750 coins.
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

int total(List<SkinItem> items) =>
    items.fold(0, (sum, item) => sum + item.price);

void main() {
  group('kCatalog shape', () {
    // PRD-2.3 §19.6: every layer has 30 entries (hats and gear: 29 + None).
    test('PRD F10: 33 per shop layer and 223 collectibles', () {
      expect(itemsFor(SkinLayer.bird).length, 33);
      expect(itemsFor(SkinLayer.gear).length, 33);
      expect(itemsFor(SkinLayer.hat).length, 33);
      expect(itemsFor(SkinLayer.hoop).length, 33);
      expect(itemsFor(SkinLayer.trail).length, 33);
      expect(allItems.length, 225);
      expect(kCollectibleTotal, 223);
      expect(allItems.where((item) => !item.isNone).length, kCollectibleTotal);
      expect(kCatalog.keys.toSet(), SkinLayer.values.toSet());
    });

    test('ids follow skin_art.js grid order per layer', () {
      expect(itemsFor(SkinLayer.bird).map((i) => i.id).toList(), [
        'classic', 'sky', 'lime', 'grape', 'tangerine', 'mint', 'lemon',
        'slate', 'coral', 'snow', 'robin', 'toucan', 'chick', 'penguin',
        'owl', 'duck', 'flamingo', 'puffer', 'zebra', 'buzz', 'robo',
        'zombie', 'ghost', 'pixel', 'frost', 'magma', 'galaxy', 'golden',
        'rainbow', 'phoenix', 'magpie', 'prism', 'daynight',
      ]);
      // PRD-2.3 §19.3: new items mixed in by rarity (existing first).
      expect(itemsFor(SkinLayer.gear).map((i) => i.id).toList(), [
        'none', 'shades', 'bowtie', 'stache', 'scarf', 'bandana', 'snorkel',
        'necktie', 'bandaid', 'gum', 'lei', 'hearts', 'monocle', 'sneakers',
        'windup', 'carpet', 'balloon', 'backpack', 'skates', 'swimring',
        'cape', 'chain', 'mask', 'patch', 'butterfly', 'drone', 'jetpack',
        'crystal', 'atom', 'disco', 'goggles', 'hoopchain', 'peacock',
      ]);
      expect(itemsFor(SkinLayer.hat).map((i) => i.id).toList(), [
        'none', 'cap', 'beanie', 'party', 'band', 'bucket', 'sprout', 'cone',
        'egg', 'paperboat', 'phones', 'tophat', 'cowboy', 'prop', 'chef',
        'viking', 'fishbowl', 'cupcake', 'raincloud', 'antennae', 'sharkfin',
        'pirate', 'wizard', 'volcano', 'ufo', 'bdaycake', 'crown', 'halo',
        'planet', 'sunburst', 'skycrown', 'nest', 'jackpot',
      ]);
      expect(itemsFor(SkinLayer.hoop).map((i) => i.id).toList(), [
        'pink', 'sky', 'lime', 'violet', 'night', 'sunset', 'lemon',
        'bamboo', 'rope', 'cloud', 'candy', 'polka', 'checker', 'donut',
        'tire', 'melon', 'zipper', 'tape', 'pearls', 'vine', 'neon', 'lava',
        'ice', 'electric', 'water', 'cog', 'rainbow', 'galaxy', 'blackhole',
        'aurora', 'spikes', 'phoenixring', 'legend',
      ]);
      expect(itemsFor(SkinLayer.trail).map((i) => i.id).toList(), [
        'flame', 'blue', 'toxic', 'hot', 'shadow', 'sunset', 'leaves', 'snow',
        'petals', 'ink', 'sparkle', 'bubbles', 'hearts', 'laser', 'confetti',
        'planes', 'popcorn', 'fireworks', 'steps', 'fish', 'bolt', 'blocks',
        'notes', 'galaxy', 'prism', 'lavadrip', 'rainbow', 'echo',
        'supernova', 'paint', 'thread', 'constellation', 'fireflies',
      ]);
    });

    test('display names match the mock', () {
      expect(itemById(SkinLayer.bird, 'lemon')!.name, 'Lemonade');
      expect(itemById(SkinLayer.bird, 'slate')!.name, 'Camo');
      expect(itemById(SkinLayer.bird, 'coral')!.name, 'Coral dots');
      expect(itemById(SkinLayer.bird, 'pixel')!.name, '8-Bit');
      expect(itemById(SkinLayer.gear, 'windup')!.name, 'Wind-up key');
      expect(itemById(SkinLayer.gear, 'carpet')!.name, 'Magic carpet');
      expect(itemById(SkinLayer.gear, 'stache')!.name, 'Mustache');
      expect(itemById(SkinLayer.hat, 'band')!.name, 'Sweatband');
      expect(itemById(SkinLayer.hat, 'prop')!.name, 'Propeller');
      expect(itemById(SkinLayer.hoop, 'night')!.name, 'Midnight');
      expect(itemById(SkinLayer.hoop, 'blackhole')!.name, 'Black hole');
      expect(itemById(SkinLayer.trail, 'hot')!.name, 'Hot pink');
      expect(itemById(SkinLayer.trail, 'blocks')!.name, 'Pixel blocks');
      expect(itemById(SkinLayer.trail, 'echo')!.name, 'Afterimage');
    });

    test('keys and ids are unique', () {
      final keys = allItems.map((item) => item.key).toList();
      expect(keys.toSet().length, keys.length);
      for (final layer in SkinLayer.values) {
        final ids = itemsFor(layer).map((item) => item.id).toList();
        expect(ids.toSet().length, ids.length, reason: layer.key);
        for (final item in itemsFor(layer)) {
          expect(item.layer, layer);
          expect(item.key, '${layer.key}:${item.id}');
        }
      }
    });

    test('the two none entries are free, rarity-less and only on gear/hat',
        () {
      final nones = allItems.where((item) => item.isNone).toList();
      expect(nones.map((item) => item.key).toSet(), {'gear:none', 'hat:none'});
      for (final item in nones) {
        expect(item.isFree, isTrue);
        expect(item.rarity, isNull);
        expect(item.price, 0);
        expect(item.animated, isFalse);
      }
      expect(itemById(SkinLayer.bird, 'none'), isNull);
      expect(itemById(SkinLayer.hoop, 'none'), isNull);
      expect(itemById(SkinLayer.trail, 'none'), isNull);
    });

    test('the five free items are exactly the defaults', () {
      expect(allItems.where((item) => item.isFree && !item.isSkillOnly).map((item) => item.key),
          {'bird:classic', 'gear:none', 'hat:none', 'hoop:pink', 'trail:flame'});
      for (final layer in SkinLayer.values) {
        expect(defaultItemId(layer), Look.defaults.idFor(layer));
        expect(itemById(layer, defaultItemId(layer))!.isFree, isTrue);
      }
    });
  });

  group('kCatalog prices', () {
    test('birds: Classic free, plain commons 150, rarity prices above', () {
      expect(itemsFor(SkinLayer.bird).where((i) => !i.isSkillOnly).map((i) => i.price).toList(), [
        0,
        150, 150, 150, 150, 150, 150, 150, 150, 150,
        750, 750, 750, 750, 750, 750, 750, 750, 750, 750,
        2000, 2000, 2000, 2000, 2000, 2000,
        5000, 5000, 5000, 5000,
      ]);
    });

    test('gear / hats / hoops / trails follow rarity prices', () {
      List<int> run(int f, int c, int r, int e, int l) => [
        for (var i = 0; i < f; i++) 0,
        for (var i = 0; i < c; i++) 250,
        for (var i = 0; i < r; i++) 750,
        for (var i = 0; i < e; i++) 2000,
        for (var i = 0; i < l; i++) 5000,
      ];
      // PRD-2.3 §19.1 layer totals (C / R / E / L).
      expect(itemsFor(SkinLayer.gear).where((i) => !i.isSkillOnly).map((i) => i.price).toList(),
          run(1, 10, 10, 5, 4));
      expect(itemsFor(SkinLayer.hat).where((i) => !i.isSkillOnly).map((i) => i.price).toList(),
          run(1, 10, 10, 5, 4));
      expect(itemsFor(SkinLayer.hoop).where((i) => !i.isSkillOnly).map((i) => i.price).toList(),
          run(1, 9, 10, 6, 4));
      expect(itemsFor(SkinLayer.trail).where((i) => !i.isSkillOnly).map((i) => i.price).toList(),
          run(1, 9, 10, 6, 4));
    });

    test('every price is 0 or matches its rarity', () {
      for (final item in allItems) {
        if (item.isFree) continue;
        if (item.layer == SkinLayer.bird && item.rarity == Rarity.common) {
          expect(item.price, 150, reason: item.key);
        } else {
          expect(item.price, item.rarity!.price, reason: item.key);
        }
      }
    });

    test('layer totals and the full-collection total (PRD-2.3: 204 350)', () {
      expect(total(itemsFor(SkinLayer.bird)), 40850);
      expect(total(itemsFor(SkinLayer.gear)), 16000 + 24000);
      expect(total(itemsFor(SkinLayer.hat)), 19000 + 21000);
      expect(total(itemsFor(SkinLayer.hoop)), 25000 + 16750);
      expect(total(itemsFor(SkinLayer.trail)), 20750 + 21000);
      expect(total(allItems.toList()), 274100);
    });
  });

  group('kCatalog flags', () {
    test('rarities per layer', () {
      expect(
        itemsFor(SkinLayer.bird)
            .where((i) => i.rarity == Rarity.legendary)
            .map((i) => i.id)
            .toSet(),
        {'galaxy', 'golden', 'rainbow', 'phoenix', 'magpie', 'prism', 'daynight'},
      );
      expect(itemById(SkinLayer.gear, 'windup')!.rarity, Rarity.rare);
      expect(itemById(SkinLayer.hat, 'crown')!.rarity, Rarity.legendary);
      expect(itemById(SkinLayer.hoop, 'neon')!.rarity, Rarity.epic);
      expect(itemById(SkinLayer.trail, 'echo')!.rarity, Rarity.legendary);
    });

    test('animated flags mirror skin_art.js', () {
      expect(
        allItems.where((item) => item.animated).map((item) => item.key).toSet(),
        {
          // PRD F10: all 24 skill items are animated.
          'bird:magpie', 'bird:prism', 'bird:daynight',
          'gear:goggles', 'gear:hoopchain', 'gear:peacock',
          'hat:skycrown', 'hat:nest', 'hat:jackpot',
          'hoop:spikes', 'hoop:phoenixring', 'hoop:legend',
          'trail:thread', 'trail:constellation', 'trail:fireflies',
          // PRD:834 adds the nine animated skill card entries.
          'card:pecking', 'card:roost', 'card:prey',
          'card:n_sky', 'card:n_thunder', 'card:n_marquee',
          'card:s_unstop', 'card:s_flawless', 'card:s_topflock',
          'bird:robo', 'bird:ghost', 'bird:frost', 'bird:magma', 'bird:galaxy',
          'bird:golden', 'bird:rainbow', 'bird:phoenix',
          'gear:scarf', 'gear:sneakers', 'gear:windup', 'gear:carpet',
          'gear:chain', 'gear:jetpack',
          'hat:band', 'hat:prop', 'hat:wizard', 'hat:crown', 'hat:halo',
          'hoop:neon', 'hoop:lava', 'hoop:ice', 'hoop:rainbow', 'hoop:galaxy',
          'hoop:blackhole',
          // PRD-2.3 §19.2 "Animated: yes"
          'hat:sprout', 'hat:fishbowl', 'hat:raincloud', 'hat:antennae',
          'hat:sharkfin', 'hat:volcano', 'hat:ufo', 'hat:bdaycake',
          'hat:planet', 'hat:sunburst',
          'gear:gum', 'gear:balloon', 'gear:backpack', 'gear:skates',
          'gear:swimring', 'gear:cape', 'gear:butterfly', 'gear:drone',
          'gear:crystal', 'gear:atom', 'gear:disco',
          'hoop:tire', 'hoop:zipper', 'hoop:pearls', 'hoop:vine',
          'hoop:electric', 'hoop:water', 'hoop:cog', 'hoop:aurora',
          for (final id in const [
            'sunset', 'leaves', 'snow', 'petals', 'ink', 'planes', 'popcorn',
            'fireworks', 'steps', 'fish', 'galaxy', 'prism', 'lavadrip',
            'supernova', 'paint',
          ])
            'trail:$id',
        },
      );
      expect(itemById(SkinLayer.gear, 'windup')!.animated, isTrue);
    });

    test('kNewInUpdate is the 2.3 list: 60 items, the showpieces first', () {
      expect(kNewInUpdate.length, 60);
      expect(kNewInUpdate.take(4).toList(), [
        'hat:sunburst', 'gear:disco', 'hoop:aurora', 'trail:supernova',
      ]);
      for (final key in kNewInUpdate) {
        final (layerKey, id) = (key.split(':')[0], key.split(':')[1]);
        final layer = SkinLayer.fromKey(layerKey)!;
        expect(itemById(layer, id), isNotNull, reason: key);
      }
      // The 2.0 entries left the list.
      expect(kNewInUpdate.contains('bird:lemon'), isFalse);
      expect(kNewInUpdate.contains('trail:echo'), isFalse);
    });
  });

  group('kCatalog helpers', () {
    test('itemById returns null for unknown ids', () {
      expect(itemById(SkinLayer.bird, 'nope'), isNull);
      expect(itemById(SkinLayer.gear, 'classic'), isNull);
      expect(itemById(SkinLayer.bird, 'classic')!.isNone, isFalse);
      expect(itemById(SkinLayer.gear, 'none')!.isNone, isTrue);
    });
  });
}
