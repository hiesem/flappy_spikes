import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GameStorage item state', () {
    test('defaults: nothing owned, five free defaults equipped', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();

      expect(storage.ownedItems, isEmpty);
      expect(storage.seenItems, isEmpty);
      expect(storage.equippedItems.keys.toSet(), SkinLayer.values.toSet());
      expect(storage.equippedItems[SkinLayer.bird], 'classic');
      expect(storage.equippedItems[SkinLayer.gear], 'none');
      expect(storage.equippedItems[SkinLayer.hat], 'none');
      expect(storage.equippedItems[SkinLayer.hoop], 'pink');
      expect(storage.equippedItems[SkinLayer.trail], 'flame');
    });

    test('round-trips ownedItems / equippedItems / seenItems', () async {
      SharedPreferences.setMockInitialValues({});
      final writer = GameStorage();
      await writer.load();
      await writer.saveOwnedItems({'bird:sky', 'hat:crown'});
      await writer.saveEquippedItem(SkinLayer.hat, 'crown');
      await writer.saveSeenItems({'bird:sky'});

      final reader = GameStorage();
      await reader.load();
      expect(reader.ownedItems, unorderedEquals(['bird:sky', 'hat:crown']));
      expect(reader.equippedItems[SkinLayer.hat], 'crown');
      expect(reader.equippedItems[SkinLayer.bird], 'classic');
      expect(reader.seenItems, {'bird:sky'});

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('ownedItems'),
          unorderedEquals(['bird:sky', 'hat:crown']));
      expect(prefs.getString('equippedItem.hat'), 'crown');
      // Only the equipped layer that was saved gets a key.
      expect(prefs.getString('equippedItem.bird'), isNull);
      expect(prefs.getStringList('seenItems'), ['bird:sky']);
    });

    test('saveEquippedItems replaces the whole map', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      await storage.saveEquippedItems({
        for (final layer in SkinLayer.values)
          layer: layer == SkinLayer.bird ? 'ghost' : 'none',
      });

      final reader = GameStorage();
      await reader.load();
      expect(reader.equippedItems[SkinLayer.bird], 'ghost');
      expect(reader.equippedItems[SkinLayer.hoop], 'none');
    });
  });

  group('GameStorage legacy PRD-1 reset', () {
    test('drops the old single-skin keys on load, no refund', () async {
      SharedPreferences.setMockInitialValues({
        'coins': 500,
        'ownedSkins': ['pink', 'blue', 'ghost'],
        'equippedSkin': 'ghost',
        'seenSkins': ['blue'],
      });
      final storage = GameStorage();
      await storage.load();

      // New wardrobe starts clean.
      expect(storage.ownedItems, isEmpty);
      expect(storage.seenItems, isEmpty);
      expect(storage.equippedItems[SkinLayer.bird], 'classic');
      // No refunds: the coin balance is untouched.
      expect(storage.coins, 500);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('ownedSkins'), isFalse);
      expect(prefs.containsKey('equippedSkin'), isFalse);
      expect(prefs.containsKey('seenSkins'), isFalse);
    });

    test('deletes a legacy key that appears alone', () async {
      SharedPreferences.setMockInitialValues({
        'equippedSkin': 'crown',
      });
      final storage = GameStorage();
      await storage.load();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('equippedSkin'), isFalse);
    });

    test('item state survives the legacy cleanup', () async {
      SharedPreferences.setMockInitialValues({
        'ownedSkins': ['pink', 'blue'],
        'equippedSkin': 'blue',
        'ownedItems': ['bird:ghost'],
        'equippedItem.bird': 'ghost',
        'seenItems': ['bird:ghost'],
      });
      final storage = GameStorage();
      await storage.load();

      expect(storage.ownedItems, {'bird:ghost'});
      expect(storage.equippedItems[SkinLayer.bird], 'ghost');
      expect(storage.seenItems, {'bird:ghost'});
    });

    test('resetMenuState clears the wardrobe too', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      await storage.saveCoins(500);
      await storage.saveOwnedItems({'bird:sky', 'hat:crown'});
      await storage.saveEquippedItem(SkinLayer.bird, 'sky');
      await storage.saveEquippedItem(SkinLayer.hat, 'crown');
      await storage.saveSeenItems({'bird:sky'});

      await storage.resetMenuState();

      expect(storage.ownedItems, isEmpty);
      expect(storage.seenItems, isEmpty);
      expect(storage.equippedItems[SkinLayer.bird], 'classic');
      expect(storage.equippedItems[SkinLayer.hat], 'none');

      final reader = GameStorage();
      await reader.load();
      expect(reader.ownedItems, isEmpty);
      expect(reader.seenItems, isEmpty);
      expect(reader.equippedItems[SkinLayer.bird], 'classic');
      expect(reader.equippedItems[SkinLayer.hoop], 'pink');
    });
  });
}
