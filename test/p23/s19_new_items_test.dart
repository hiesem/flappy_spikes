import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flappy_spikes/components/shop/shop_screen.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/skins/art/ctx2d.dart';
import 'package:flappy_spikes/skins/art/gear_art_v23.dart';
import 'package:flappy_spikes/skins/art/hat_art_v23.dart';
import 'package:flappy_spikes/skins/art/hoop_art_v23.dart';
import 'package:flappy_spikes/skins/art/hoop_painter.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/art/trail.dart';
import 'package:flappy_spikes/skins/art/trail_v23.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/item_store.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PRD-2.3 §19.2 table: tag, app id, name, rarity, animated.
const _table = <SkinLayer, List<(String, String, Rarity, bool)>>{
  SkinLayer.hat: [
    ('sprout', 'Sprout', Rarity.common, true),
    ('cone', 'Traffic cone', Rarity.common, false),
    ('egg', 'Fried egg', Rarity.common, false),
    ('paperboat', 'Paper boat', Rarity.common, false),
    ('phones', 'Headphones', Rarity.common, false),
    ('fishbowl', 'Fishbowl', Rarity.rare, true),
    ('cupcake', 'Cupcake', Rarity.rare, false),
    ('raincloud', 'Rain cloud', Rarity.rare, true),
    ('antennae', 'Antennae', Rarity.rare, true),
    ('sharkfin', 'Shark fin', Rarity.rare, true),
    ('volcano', 'Volcano', Rarity.epic, true),
    ('ufo', 'UFO', Rarity.epic, true),
    ('bdaycake', 'Birthday cake', Rarity.epic, true),
    ('planet', 'Ringed planet', Rarity.legendary, true),
    ('sunburst', 'Sunburst', Rarity.legendary, true),
  ],
  SkinLayer.gear: [
    ('snorkel', 'Snorkel', Rarity.common, false),
    ('necktie', 'Necktie', Rarity.common, false),
    ('bandaid', 'Band-aid', Rarity.common, false),
    ('gum', 'Bubble gum', Rarity.common, true),
    ('lei', 'Flower lei', Rarity.common, false),
    ('balloon', 'Balloon', Rarity.rare, true),
    ('backpack', 'Backpack', Rarity.rare, true),
    ('skates', 'Roller skates', Rarity.rare, true),
    ('swimring', 'Swim ring', Rarity.rare, true),
    ('cape', 'Cape', Rarity.rare, true),
    ('butterfly', 'Butterfly', Rarity.epic, true),
    ('drone', 'Drone buddy', Rarity.epic, true),
    ('crystal', 'Crystal wings', Rarity.legendary, true),
    ('atom', 'Atom', Rarity.legendary, true),
    ('disco', 'Disco ball', Rarity.legendary, true),
  ],
  SkinLayer.hoop: [
    ('sunset', 'Sunset', Rarity.common, false),
    ('lemon', 'Lemon slice', Rarity.common, false),
    ('bamboo', 'Bamboo', Rarity.common, false),
    ('rope', 'Rope', Rarity.common, false),
    ('cloud', 'Cloud', Rarity.common, false),
    ('tire', 'Tire', Rarity.rare, true),
    ('melon', 'Watermelon', Rarity.rare, false),
    ('zipper', 'Zipper', Rarity.rare, true),
    ('tape', 'Tape measure', Rarity.rare, false),
    ('pearls', 'Pearls', Rarity.rare, true),
    ('vine', 'Vine', Rarity.rare, true),
    ('electric', 'Electric', Rarity.epic, true),
    ('water', 'Water', Rarity.epic, true),
    ('cog', 'Cogwheel', Rarity.epic, true),
    ('aurora', 'Aurora', Rarity.legendary, true),
  ],
  SkinLayer.trail: [
    ('sunset', 'Sunset flame', Rarity.common, true),
    ('leaves', 'Leaves', Rarity.common, true),
    ('snow', 'Snowflakes', Rarity.common, true),
    ('petals', 'Petals', Rarity.common, true),
    ('ink', 'Ink drops', Rarity.common, true),
    ('planes', 'Paper planes', Rarity.rare, true),
    ('popcorn', 'Popcorn', Rarity.rare, true),
    ('fireworks', 'Fireworks', Rarity.rare, true),
    ('steps', 'Footprints', Rarity.rare, true),
    ('fish', 'Fish', Rarity.rare, true),
    ('galaxy', 'Galaxy dust', Rarity.epic, true),
    ('prism', 'Prism', Rarity.epic, true),
    ('lavadrip', 'Lava drips', Rarity.epic, true),
    ('supernova', 'Supernova', Rarity.legendary, true),
    ('paint', 'Paint stroke', Rarity.legendary, true),
  ],
};

/// §19.1 layer totals after 2.3 (C / R / E / L).
const _totals = <SkinLayer, List<int>>{
  SkinLayer.hat: [10, 10, 5, 4],
  SkinLayer.gear: [10, 10, 5, 4],
  SkinLayer.hoop: [10, 10, 6, 4],
  SkinLayer.trail: [10, 10, 6, 4],
};

const _prices = {
  Rarity.common: 250,
  Rarity.rare: 750,
  Rarity.epic: 2000,
  Rarity.legendary: 5000,
};

Set<String> get _newKeys => {
  for (final e in _table.entries)
    for (final r in e.value) '${e.key.key}:${r.$1}',
};

Future<(GameStorage, Wallet, ItemStore)> _store({
  int coins = 0,
  Set<String> owned = const {},
  Set<String> seen = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'coins': coins,
    'ownedItems': owned.toList(),
    'seenItems': seen.toList(),
  });
  final storage = GameStorage();
  await storage.load();
  final wallet = Wallet(storage);
  return (storage, wallet, ItemStore(storage, wallet));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('§19.6 catalogue', () {
    test('every layer has 30 entries (hats and gear: 29 + None)', () {
      for (final layer in SkinLayer.values) {
        expect(itemsFor(layer), hasLength(30), reason: layer.key);
      }
      expect(itemsFor(SkinLayer.hat).where((i) => !i.isNone), hasLength(29));
      expect(itemsFor(SkinLayer.gear).where((i) => !i.isNone), hasLength(29));
      expect(kCollectibleTotal, 148);
    });

    test('the 60 items of §19.2: names, rarities, prices, animated', () {
      for (final MapEntry(key: layer, value: rows) in _table.entries) {
        for (final (id, name, rarity, animated) in rows) {
          final item = itemById(layer, id);
          expect(item, isNotNull, reason: '${layer.key}:$id');
          expect(item!.name, name);
          expect(item.rarity, rarity);
          expect(item.price, _prices[rarity]);
          expect(item.animated, animated, reason: item.key);
        }
      }
      // The painters know exactly the same ids, in tag order.
      expect(HatArtV23.ids, [for (final r in _table[SkinLayer.hat]!) r.$1]);
      expect(GearArtV23.ids, [for (final r in _table[SkinLayer.gear]!) r.$1]);
      expect(HoopArtV23.ids, [for (final r in _table[SkinLayer.hoop]!) r.$1]);
      expect(TrailV23.ids, [for (final r in _table[SkinLayer.trail]!) r.$1]);
    });

    test('rarity counts of §19.1 per layer', () {
      for (final MapEntry(key: layer, value: want) in _totals.entries) {
        final got = [
          for (final r in Rarity.values)
            itemsFor(layer).where((i) => i.rarity == r).length,
        ];
        expect(got, want, reason: layer.key);
      }
    });

    test('ids unique within each layer; the hoop and trail sunset coexist',
        () {
      for (final layer in SkinLayer.values) {
        final ids = [for (final i in itemsFor(layer)) i.id];
        expect(ids.toSet(), hasLength(ids.length), reason: layer.key);
      }
      expect(itemById(SkinLayer.hoop, 'sunset')!.key, 'hoop:sunset');
      expect(itemById(SkinLayer.trail, 'sunset')!.key, 'trail:sunset');
    });

    test('grid order §19.3: free first, rarity groups common → legendary, '
        'existing items then new ones in tag order', () {
      for (final layer in _table.keys) {
        final items = itemsFor(layer);
        expect(items.first.isFree, isTrue, reason: layer.key);
        final rest = items.skip(1).toList();
        final newIds = [for (final r in _table[layer]!) r.$1];
        for (final rarity in Rarity.values) {
          final group = [
            for (final i in rest)
              if (i.rarity == rarity) i.id,
          ];
          // the group is contiguous
          final first = rest.indexWhere((i) => i.rarity == rarity);
          expect(rest.sublist(first, first + group.length).map((i) => i.id),
              group);
          final olds = group.where((id) => !newIds.contains(id)).toList();
          final news = group.where(newIds.contains).toList();
          expect(group, [...olds, ...news], reason: '${layer.key} $rarity');
          expect(news, [
            for (final id in newIds)
              if (itemById(layer, id)!.rarity == rarity) id,
          ]);
        }
        final order = [for (final i in rest) i.rarity!.index];
        expect(order, [...order]..sort(), reason: layer.key);
      }
    });

    test('kNewInUpdate: the 60 items, the four showpieces first', () {
      expect(kNewInUpdate, hasLength(60));
      expect(kNewInUpdate.toSet(), _newKeys);
      expect(kNewInUpdate.take(4), [
        'hat:sunburst', 'gear:disco', 'hoop:aurora', 'trail:supernova',
      ]);
      final rest = kNewInUpdate.skip(4).toList();
      final tagOrder = [
        for (final k in _newKeys)
          if (!{'hat:sunburst', 'gear:disco', 'hoop:aurora', 'trail:supernova'}
              .contains(k))
            k,
      ];
      expect(rest, tagOrder);
    });

    test('every trail has its tile head-dot colour', () {
      for (final id in TrailV23.ids) {
        expect(TrailV23.dots[id], isNotNull, reason: id);
        expect(TrailEmitter(id).orbColor, TrailV23.dots[id]);
      }
    });
  });

  group('§19.6 shop', () {
    test('NEW on all 60 for a 2.2 save (none seen), whatever the balance; '
        'cleared when seen', () async {
      final (_, _, items) = await _store(seen: {
        for (final i in allItems)
          if (!kNewInUpdate.contains(i.key)) i.key,
      });
      for (final key in kNewInUpdate) {
        final [l, id] = key.split(':');
        expect(items.isNew(SkinLayer.fromKey(l)!, id), isTrue, reason: key);
      }
      for (final key in kNewInUpdate) {
        final [l, id] = key.split(':');
        await items.markSeen(SkinLayer.fromKey(l)!, id);
        expect(items.isNew(SkinLayer.fromKey(l)!, id), isFalse, reason: key);
      }
      expect(items.hasNewBadge, isFalse);
    });

    test('the featured item is Sunburst until owned', () async {
      final (_, _, items) = await _store(coins: 99999);
      expect(featuredItemFor(items)!.key, 'hat:sunburst');
      await items.purchase(SkinLayer.hat, 'sunburst');
      expect(featuredItemFor(items)!.key, 'gear:disco');
    });

    test('buying and equipping a new item of each layer; x / 148', () async {
      final (_, wallet, items) = await _store(coins: 20000);
      expect(items.ownedCount, 3);
      for (final (layer, id) in [
        (SkinLayer.hat, 'ufo'),
        (SkinLayer.gear, 'cape'),
        (SkinLayer.hoop, 'aurora'),
        (SkinLayer.trail, 'fish'),
      ]) {
        final before = wallet.balance;
        expect(await items.purchase(layer, id), ItemPurchaseResult.purchased);
        expect(wallet.balance, before - itemById(layer, id)!.price);
        expect(items.isOwned(layer, id), isTrue);
        expect(items.look.idFor(layer), id);
      }
      expect(items.ownedCount, 7);
      expect(kCollectibleTotal, 148);
      expect('${items.ownedCount} / $kCollectibleTotal', '7 / 148');
    });
  });

  group('§19.6 versus', () {
    test('a Look with new ids round-trips through RunEntry JSON', () {
      const look = Look(
        bird: 'owl',
        gear: 'disco',
        hat: 'sunburst',
        hoop: 'aurora',
        trail: 'supernova',
      );
      final t = RunTimeline();
      for (var i = 1; i <= 5; i++) {
        t.addPoint(i.toDouble());
      }
      t.end(6);
      final e = RunEntry.fromSummary(
        RunSummary(
          score: 5,
          hoopsPassed: 5,
          coins: 0,
          bestBefore: 0,
          bestAfter: 5,
          runSeconds: 6,
          cause: MistakeCause.missedHoop,
          hoopIndex: 5,
          timeline: t,
        ),
        runId: 'r',
        name: 'SwiftKiwi482',
        look: look,
        ts: DateTime.utc(2026, 10, 13),
      );
      final back = RunEntry.fromMap(e.toMap());
      expect(back, isNotNull);
      expect(back!.look, look);
      expect(lookFromMap(lookToMap(look)), look);
    });

    test('an unknown id falls back to the layer default and paints without '
        'errors on every painter', () {
      final look = lookFromMap({
        'bird': 'classic',
        'gear': 'future_gear',
        'hat': 'future_hat',
        'hoop': 'future_hoop',
        'trail': 'future_trail',
      });
      expect(look, Look.defaults);
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      LookPainter.paint(
        c,
        const Look(bird: 'zz', gear: 'zz', hat: 'zz', hoop: 'zz', trail: 'zz'),
        t: 1,
      );
      HoopPainter.paintHalf(c, 'zz', ui.Offset.zero, 40, 1, front: true);
      final e = TrailEmitter('zz', random: math.Random(1));
      for (var i = 0; i < 30; i++) {
        e.emit(ui.Offset.zero, 1 / 60);
        e.step(1 / 60);
      }
      e.paint(c);
      expect(e.orbColor, TrailEmitter('flame').orbColor);
      rec.endRecording().dispose();
    });
  });

  group('§19.4 painters', () {
    test('every new item paints on every bird shape at many t without '
        'throwing; hoops and trails at several sizes', () {
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      for (final t in const [0.0, .37, 1.3, 2.81, 7.9, 61.2]) {
        for (final bird in BirdArt.ids) {
          for (final h in HatArtV23.ids) {
            LookPainter.paint(c, Look(bird: bird, hat: h), t: t);
          }
          for (final g in GearArtV23.ids) {
            LookPainter.paint(c, Look(bird: bird, gear: g), t: t, flap: true);
            LookPainter.paintOnMannequin(c, SkinLayer.gear, g, t: t);
          }
        }
        for (final id in HoopArtV23.ids) {
          for (final ry in const [20.0, 44.0, 59.0]) {
            HoopPainter.paintHalf(c, id, ui.Offset.zero, ry, t, front: false);
            HoopPainter.paintHalf(c, id, ui.Offset.zero, ry, t,
                front: true, lineWidth: 24, rx: 12);
          }
          HoopPainter.paintHoopTile(c, id, ui.Offset.zero, 30, t);
        }
      }
      rec.endRecording().dispose();
    });

    test('trails: seeded runs are deterministic, the pool stays bounded and '
        'the history trails keep their page lengths', () {
      for (final id in TrailV23.ids) {
        final a = TrailEmitter(id, random: math.Random(5));
        final b = TrailEmitter(id, random: math.Random(5));
        for (var i = 0; i < 600; i++) {
          a.emit(ui.Offset(100, 50 + math.sin(i / 9) * 20), 1 / 60, k: 2);
          a.step(1 / 60);
          b.emit(ui.Offset(100, 50 + math.sin(i / 9) * 20), 1 / 60, k: 2);
          b.step(1 / 60);
        }
        expect(a.particleCount, b.particleCount, reason: id);
        expect(a.particleCount, lessThanOrEqualTo(TrailV23.capacity));
        expect(a.particleCount, greaterThan(0), reason: id);
      }
      // The page's particle budget: Supernova (the heaviest) stays far
      // below the pool.
      final nova = TrailEmitter('supernova', random: math.Random(1));
      var peak = 0;
      for (var i = 0; i < 600; i++) {
        nova.emit(const ui.Offset(100, 50), 1 / 60, k: 2);
        nova.step(1 / 60);
        peak = math.max(peak, nova.particleCount);
      }
      expect(peak, lessThan(120));
    });

    test('gradients are built once and cached (the cache stays bounded)', () {
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      for (var i = 0; i < 600; i++) {
        final t = i / 60;
        LookPainter.paint(
          c,
          const Look(bird: 'classic', hat: 'ufo', gear: 'disco'),
          t: t,
        );
        LookPainter.paint(
          c,
          const Look(bird: 'classic', hat: 'planet', gear: 'butterfly'),
          t: t,
        );
        LookPainter.paint(c, const Look(bird: 'classic', hat: 'sunburst'),
            t: t);
        HoopPainter.paintHalf(c, 'cog', ui.Offset.zero, 44, t, front: true);
      }
      rec.endRecording().dispose();
      // ufo: at most 65 quantised beam alphas; planet, sunburst, disco,
      // butterfly: 1 each; cog: 1 for this ring size.
      expect(Ctx2D.cachedGradients, lessThanOrEqualTo(72));
    });
  });
}
