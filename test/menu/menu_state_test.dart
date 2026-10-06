import 'dart:math';

import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/menu_state.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MenuState wires storage, wallet, items, slot and policies', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage();
    await storage.load();
    final earned = <(int, CoinSource)>[];
    final menu = MenuState(storage,
        random: Random(1),
        onEarned: (amount, source) => earned.add((amount, source)));

    expect(menu.storage, same(storage));
    expect(menu.wallet.balance, 0);
    expect(menu.items.look, isNotNull);
    expect(menu.slot.offered, anyOf(Powerup.bigHoops, Powerup.shield));
    expect(menu.noAdsPopup.shouldShowOnLaunch(), false);
    expect(menu.freeCoins.remainingToday, 5);

    await menu.wallet.add(10, CoinSource.play);
    expect(earned, [(10, CoinSource.play)]);

    expect(menu.noAds, false);
    await menu.setNoAds(true);
    expect(menu.noAds, true);
    final reader = GameStorage();
    await reader.load();
    expect(reader.noAds, true);
  });
}
