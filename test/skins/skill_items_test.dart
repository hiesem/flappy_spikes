import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/item_store.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PRD F10 O81: achievement state alone owns all 24 skill items', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage();
    await storage.load();
    final items = ItemStore(storage, Wallet(storage));
    final skills = allItems.where((item) => item.isSkillOnly).toList();
    expect(skills, hasLength(24));
    expect(kCollectibleTotal, 223);
    expect(kSoldCollectibleTotal, 199);
    for (final item in skills) {
      expect(item.unlock, isNotNull);
      expect(item.rarity, Rarity.legendary);
      expect(items.isOwned(item.layer, item.id), isFalse);
      storage.ownedItems.add(item.key);
      expect(items.isOwned(item.layer, item.id), isFalse);
      expect(await items.purchase(item.layer, item.id), ItemPurchaseResult.unknown);
      storage.ach.unlocked.add(item.unlock!.key);
      expect(items.isOwned(item.layer, item.id), isTrue);
    }
    expect(items.ownedCount, 27);
    expect(items.soldOwnedCount, 3);
    await items.equip(SkinLayer.bird, 'magpie');
    expect(items.look.bird, 'magpie');
    storage.ach.unlocked.clear();
    expect(items.look.bird, 'classic');
    expect(() => items.grant('bird:magpie'), throwsArgumentError);
  });
}
