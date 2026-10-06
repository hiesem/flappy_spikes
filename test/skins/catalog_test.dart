import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

int total(List<SkinItem> items) =>
    items.fold(0, (sum, item) => sum + item.price);

void main() {
  group('kCatalog shape', () {
    test('layer sizes: 30 / 15 / 15 / 15 / 15 and 88 collectible', () {
      expect(itemsFor(SkinLayer.bird).length, 30);
      expect(itemsFor(SkinLayer.gear).length, 15);
      expect(itemsFor(SkinLayer.hat).length, 15);
      expect(itemsFor(SkinLayer.hoop).length, 15);
      expect(itemsFor(SkinLayer.trail).length, 15);
      expect(allItems.length, 90);
      expect(kCollectibleTotal, 88);
      expect(allItems.where((item) => !item.isNone).length, kCollectibleTotal);
      expect(kCatalog.keys.toSet(), SkinLayer.values.toSet());
    });

    test('ids follow skin_art.js grid order per layer', () {
      expect(itemsFor(SkinLayer.bird).map((i) => i.id).toList(), [
        'classic', 'sky', 'lime', 'grape', 'tangerine', 'mint', 'lemon',
        'slate', 'coral', 'snow', 'robin', 'toucan', 'chick', 'penguin',
        'owl', 'duck', 'flamingo', 'puffer', 'zebra', 'buzz', 'robo',
        'zombie', 'ghost', 'pixel', 'frost', 'magma', 'galaxy', 'golden',
        'rainbow', 'phoenix',
      ]);
      expect(itemsFor(SkinLayer.gear).map((i) => i.id).toList(), [
        'none', 'shades', 'bowtie', 'stache', 'scarf', 'bandana', 'hearts',
        'monocle', 'sneakers', 'windup', 'carpet', 'chain', 'mask', 'patch',
        'jetpack',
      ]);
      expect(itemsFor(SkinLayer.hat).map((i) => i.id).toList(), [
        'none', 'cap', 'beanie', 'party', 'band', 'bucket', 'tophat',
        'cowboy', 'prop', 'chef', 'viking', 'pirate', 'wizard', 'crown',
        'halo',
      ]);
      expect(itemsFor(SkinLayer.hoop).map((i) => i.id).toList(), [
        'pink', 'sky', 'lime', 'violet', 'night', 'candy', 'polka', 'checker',
        'donut', 'neon', 'lava', 'ice', 'rainbow', 'galaxy', 'blackhole',
      ]);
      expect(itemsFor(SkinLayer.trail).map((i) => i.id).toList(), [
        'flame', 'blue', 'toxic', 'hot', 'shadow', 'sparkle', 'bubbles',
        'hearts', 'laser', 'confetti', 'bolt', 'blocks', 'notes', 'rainbow',
        'echo',
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
      expect(allItems.where((item) => item.isFree).map((item) => item.key),
          {'bird:classic', 'gear:none', 'hat:none', 'hoop:pink', 'trail:flame'});
      for (final layer in SkinLayer.values) {
        expect(defaultItemId(layer), Look.defaults.idFor(layer));
        expect(itemById(layer, defaultItemId(layer))!.isFree, isTrue);
      }
    });
  });

  group('kCatalog prices', () {
    test('birds: Classic free, plain commons 150, rarity prices above', () {
      expect(itemsFor(SkinLayer.bird).map((i) => i.price).toList(), [
        0,
        150, 150, 150, 150, 150, 150, 150, 150, 150,
        750, 750, 750, 750, 750, 750, 750, 750, 750, 750,
        2000, 2000, 2000, 2000, 2000, 2000,
        5000, 5000, 5000, 5000,
      ]);
    });

    test('gear / hats / hoops / trails follow rarity prices', () {
      expect(itemsFor(SkinLayer.gear).map((i) => i.price).toList(), [
        0, 250, 250, 250, 250, 250, 750, 750, 750, 750, 750, 2000, 2000,
        2000, 5000,
      ]);
      expect(itemsFor(SkinLayer.hat).map((i) => i.price).toList(), [
        0, 250, 250, 250, 250, 250, 750, 750, 750, 750, 750, 2000, 2000,
        5000, 5000,
      ]);
      expect(itemsFor(SkinLayer.hoop).map((i) => i.price).toList(), [
        0, 250, 250, 250, 250, 750, 750, 750, 750, 2000, 2000, 2000, 5000,
        5000, 5000,
      ]);
      expect(itemsFor(SkinLayer.trail).map((i) => i.price).toList(), [
        0, 250, 250, 250, 250, 750, 750, 750, 750, 750, 2000, 2000, 2000,
        5000, 5000,
      ]);
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

    test('layer totals and the full-collection total (121 600)', () {
      expect(total(itemsFor(SkinLayer.bird)), 40850);
      expect(total(itemsFor(SkinLayer.gear)), 16000);
      expect(total(itemsFor(SkinLayer.hat)), 19000);
      expect(total(itemsFor(SkinLayer.hoop)), 25000);
      expect(total(itemsFor(SkinLayer.trail)), 20750);
      expect(total(allItems.toList()), 121600);
    });
  });

  group('kCatalog flags', () {
    test('rarities per layer', () {
      expect(
        itemsFor(SkinLayer.bird)
            .where((i) => i.rarity == Rarity.legendary)
            .map((i) => i.id)
            .toSet(),
        {'galaxy', 'golden', 'rainbow', 'phoenix'},
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
          'bird:robo', 'bird:ghost', 'bird:frost', 'bird:magma', 'bird:galaxy',
          'bird:golden', 'bird:rainbow', 'bird:phoenix',
          'gear:scarf', 'gear:sneakers', 'gear:windup', 'gear:carpet',
          'gear:chain', 'gear:jetpack',
          'hat:band', 'hat:prop', 'hat:wizard', 'hat:crown', 'hat:halo',
          'hoop:neon', 'hoop:lava', 'hoop:ice', 'hoop:rainbow', 'hoop:galaxy',
          'hoop:blackhole',
        },
      );
      expect(itemById(SkinLayer.gear, 'windup')!.animated, isTrue);
    });

    test('kNewInUpdate is the mock START_NEW set', () {
      expect(kNewInUpdate, {
        'bird:lemon', 'bird:toucan', 'bird:ghost',
        'gear:carpet', 'gear:windup',
        'hat:crown', 'hat:wizard',
        'hoop:neon',
        'trail:hearts', 'trail:echo',
      });
      for (final key in kNewInUpdate) {
        final (layerKey, id) = (key.split(':')[0], key.split(':')[1]);
        final layer = SkinLayer.fromKey(layerKey)!;
        expect(itemById(layer, id), isNotNull, reason: key);
      }
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
