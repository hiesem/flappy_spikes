import 'dart:io';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/item_store.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'F9 card ids mirror the server allow-lists in exactly the same order',
    () {
      final source = File('functions/src/card.ts').readAsStringSync();
      for (final (kind, constant) in [
        (CardKind.frame, 'CARD_FRAME_IDS'),
        (CardKind.name, 'CARD_NAME_IDS'),
        (CardKind.sticker, 'CARD_STICKER_IDS'),
      ]) {
        final body = RegExp(
          '$constant = \\[(.*?)\\] as const',
          dotAll: true,
        ).firstMatch(source)!.group(1)!;
        final ids = RegExp(
          "'([^']+)'",
        ).allMatches(body).map((m) => m.group(1)!);
        expect(cardItemsFor(kind).map((item) => item.id), orderedEquals(ids));
      }
    },
  );

  test('F9 has 17 sold + 3 skill items per kind, standard rarity prices', () {
    for (final kind in CardKind.values) {
      final items = cardItemsFor(kind);
      final sold = items.where((item) => !item.isSkillOnly).toList();
      expect(items.length, 20);
      expect(sold.length, 17);
      expect(items.where((item) => item.isSkillOnly).length, 3);
      expect(sold.map((item) => item.rarity), [
        ...List.filled(6, Rarity.common),
        ...List.filled(5, Rarity.rare),
        ...List.filled(4, Rarity.epic),
        ...List.filled(2, Rarity.legendary),
      ]);
      for (final item in sold) {
        expect(item.price, item.rarity!.price);
        expect(item.layer, SkinLayer.card);
        expect(item.cardKind, kind);
      }
    }
    expect(kCards.map((i) => i.id).toSet().length, 60);
    expect(kCardItems.length, 51);
    expect(kSkillCardItems.length, 9);
    expect(kCardItems.every((item) => !item.isSkillOnly), isTrue);
    expect(kSkillCardItems.every((item) => item.isSkillOnly), isTrue);
    expect(itemsFor(SkinLayer.card), isEmpty);
    expect(allItems.length, 150);
    expect(kCollectibleTotal, 148);
    expect(kCollectibleTotal, allItems.where((i) => !i.isNone).length);
  });

  test('F9 names and sold prices match the approved catalogue', () {
    final design = File(
      'docs/p26/design/approvals_v26/versus_cards.html',
    ).readAsStringSync();
    final rows = RegExp(
      "\\{id:'([^']+)',kind:'([^']+)',name:'([^']+)',price:(\\d+)",
    ).allMatches(design).toList();
    expect(rows.length, 51);
    for (final row in rows) {
      final item = itemById(SkinLayer.card, row.group(1)!)!;
      expect(item.name, row.group(3));
      expect(item.price, int.parse(row.group(4)!));
    }
  });

  test('F9 all slot combinations survive wire and JSON round trips', () {
    for (final frame in ['', ...kCardFrames.map((i) => i.id)]) {
      for (final name in ['', ...kCardNames.map((i) => i.id)]) {
        for (final sticker in ['', ...kCardStickers.map((i) => i.id)]) {
          final card = '$frame|$name|$sticker';
          final look = Look(card: card == '||' ? '' : card);
          final map = lookToMap(look);
          if (look.card.isEmpty) {
            expect(map.containsKey('card'), isFalse);
          } else {
            expect(map['card']!.length, lessThanOrEqualTo(48));
            expect('|'.allMatches(map['card']!).length, 2);
          }
          expect(lookFromMap(map), look);
          expect(Look.fromJson(look.toJson()), look);
        }
      }
    }
    expect(const Look(card: 'f_orbit||'), isNot(Look.defaults));
  });

  test('F9 old runs decode empty; malformed and wrong-kind slots are safe', () {
    expect(lookFromMap({'bird': 'classic'}).card, '');
    expect(Look.fromJson({}).card, '');
    for (final value in [null, 42, '', '|', '|||', 'x' * 49]) {
      expect(lookFromMap({'card': value}).card, '');
    }
    expect(lookFromMap({'card': 'n_fire|f_orbit|unknown'}).card, '');
    expect(lookFromMap({'card': 'unknown|n_fire|s_gg'}).card, '|n_fire|s_gg');
  });

  test(
    'F9 purchases preserve other equipped slots, persist and clear',
    () async {
      SharedPreferences.setMockInitialValues({'coins': 10000});
      final storage = GameStorage();
      await storage.load();
      final items = ItemStore(storage, Wallet(storage));
      for (final id in ['f_bubblegum', 'n_ocean', 's_gg']) {
        expect(
          await items.purchase(SkinLayer.card, id),
          ItemPurchaseResult.purchased,
        );
        expect(items.isEquipped(SkinLayer.card, id), isTrue);
      }
      expect(items.look.card, 'f_bubblegum|n_ocean|s_gg');
      expect(
        await items.purchase(SkinLayer.card, 'f_orbit'),
        ItemPurchaseResult.purchased,
      );
      expect(items.look.card, 'f_orbit|n_ocean|s_gg');
      final reloaded = GameStorage();
      await reloaded.load();
      final restored = ItemStore(reloaded, Wallet(reloaded));
      expect(restored.look.card, items.look.card);
      await restored.clearCard(CardKind.name);
      expect(restored.look.card, 'f_orbit||s_gg');
      await restored.equip(SkinLayer.card, 'n_ocean');
      expect(restored.look.card, 'f_orbit|n_ocean|s_gg');
      await restored.resetAll();
      expect(restored.look.card, '');
      final reset = GameStorage();
      await reset.load();
      expect(ItemStore(reset, Wallet(reset)).look.card, '');
    },
  );

  test(
    'F9 unowned slots are cleared individually and skill items are not sold',
    () async {
      SharedPreferences.setMockInitialValues({'coins': 10000});
      final storage = GameStorage();
      await storage.load();
      await storage.saveOwnedItems({'card:n_ocean'});
      await storage.saveEquippedItem(SkinLayer.card, 'f_orbit|n_ocean|s_gg');
      final items = ItemStore(storage, Wallet(storage));
      expect(items.look.card, '|n_ocean|');
      await items.equip(SkinLayer.card, 'f_orbit');
      expect(items.look.card, '|n_ocean|');
      for (final item in kCards.where((i) => i.isSkillOnly)) {
        expect(items.isOwned(SkinLayer.card, item.id), isFalse);
        expect(
          await items.purchase(SkinLayer.card, item.id),
          ItemPurchaseResult.unknown,
        );
        expect(items.isNew(SkinLayer.card, item.id), isFalse);
      }
      expect(storage.coins, 10000);
    },
  );
}
