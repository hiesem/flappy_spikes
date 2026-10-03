import 'package:flappy_spikes/game/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GameStorage menu state', () {
    test('loads menu defaults when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage(clock: () => DateTime(2026, 1, 15, 23, 59));
      await storage.load();
      expect(storage.coins, 0);
      expect(storage.ownedSkins, {'pink'});
      expect(storage.equippedSkin, 'pink');
      expect(storage.seenSkins, isEmpty);
      expect(storage.noAds, false);
      expect(storage.armedPowerup, 'none');
      expect(storage.slotHistory, isEmpty);
      expect(storage.installDay, storage.today);
      expect(storage.noAdsPopupLastDay, -1);
      expect(storage.noAdsPopupDismissals, 0);
      expect(storage.freeCoinsDay, -1);
      expect(storage.freeCoinsCount, 0);
      expect(storage.freeCoinsLastMs, 0);
      expect(storage.debugDayOffset, 0);
    });

    test('round-trips every new key across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final writer = GameStorage(clock: () => DateTime(2026, 1, 15));
      await writer.load();
      await writer.saveCoins(250);
      await writer.saveOwnedSkins({'blue', 'crown'});
      await writer.saveEquippedSkin('crown');
      await writer.saveSeenSkins({'blue'});
      await writer.saveNoAds(true);
      await writer.saveArmedPowerup('shield');
      await writer.saveSlotHistory(['bigHoops', 'shield', 'shield']);
      await writer.saveInstallDay(20000);
      await writer.saveNoAdsPopupLastDay(20003);
      await writer.saveNoAdsPopupDismissals(2);
      await writer.saveFreeCoinsDay(20005);
      await writer.saveFreeCoinsCount(3);
      await writer.saveFreeCoinsLastMs(123456789);
      await writer.saveDebugDayOffset(4);

      final reader = GameStorage(clock: () => DateTime(2026, 1, 15));
      await reader.load();
      expect(reader.coins, 250);
      expect(reader.ownedSkins, unorderedEquals(['pink', 'blue', 'crown']));
      expect(reader.equippedSkin, 'crown');
      expect(reader.seenSkins, {'blue'});
      expect(reader.noAds, true);
      expect(reader.armedPowerup, 'shield');
      expect(reader.slotHistory, ['bigHoops', 'shield', 'shield']);
      expect(reader.installDay, 20000);
      expect(reader.noAdsPopupLastDay, 20003);
      expect(reader.noAdsPopupDismissals, 2);
      expect(reader.freeCoinsDay, 20005);
      expect(reader.freeCoinsCount, 3);
      expect(reader.freeCoinsLastMs, 123456789);
      expect(reader.debugDayOffset, 4);
    });

    test('pink is always owned after load, even if not stored', () async {
      SharedPreferences.setMockInitialValues({
        'ownedSkins': <String>['blue'],
      });
      final storage = GameStorage();
      await storage.load();
      expect(storage.ownedSkins, contains('pink'));
      expect(storage.ownedSkins, unorderedEquals(['pink', 'blue']));

      await storage.saveOwnedSkins({'green'});
      expect(storage.ownedSkins, unorderedEquals(['pink', 'green']));
    });

    test('equippedSkin falls back to pink when not owned', () async {
      SharedPreferences.setMockInitialValues({
        'ownedSkins': <String>['blue'],
        'equippedSkin': 'ghost',
      });
      final storage = GameStorage();
      await storage.load();
      expect(storage.equippedSkin, 'pink');
    });

    test('installDay is set on first load and kept afterwards', () async {
      SharedPreferences.setMockInitialValues({});
      final first = GameStorage(clock: () => DateTime(2026, 1, 15));
      await first.load();
      expect(first.installDay, first.today);

      final second = GameStorage(clock: () => DateTime(2026, 3, 1));
      await second.load();
      expect(second.installDay, first.installDay);
      expect(second.today, greaterThan(second.installDay!));
    });

    test('today is a whole local calendar day plus debugDayOffset', () async {
      final storage = GameStorage(clock: () => DateTime(2026, 1, 15, 12));
      final expected =
          DateTime.utc(2026, 1, 15).difference(DateTime.utc(1970)).inDays;
      expect(storage.today, expected);

      final lateNight = GameStorage(clock: () => DateTime(2026, 1, 15, 23, 59));
      expect(lateNight.today, expected);

      storage.debugDayOffset = 3;
      expect(storage.today, expected + 3);
    });

    test('slotHistory is capped to the last 3 on load and save', () async {
      SharedPreferences.setMockInitialValues({
        'slotHistory': <String>['a', 'b', 'c', 'd', 'e'],
      });
      final storage = GameStorage();
      await storage.load();
      expect(storage.slotHistory, ['c', 'd', 'e']);

      await storage.saveSlotHistory(['1', '2', '3', '4']);
      expect(storage.slotHistory, ['2', '3', '4']);
      final reader = GameStorage();
      await reader.load();
      expect(reader.slotHistory, ['2', '3', '4']);
    });

    test('resetMenuState restores menu defaults and keeps progression', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage(clock: () => DateTime(2026, 1, 15));
      await storage.load();
      await storage.saveBestScore(99);
      await storage.incrementGamesPlayed();
      await storage.saveMuteSound(true);
      await storage.saveMusicVolume(0.1);
      await storage.saveCoins(500);
      await storage.saveOwnedSkins({'crown'});
      await storage.saveEquippedSkin('crown');
      await storage.saveSeenSkins({'crown'});
      await storage.saveNoAds(true);
      await storage.saveArmedPowerup('shield');
      await storage.saveSlotHistory(['shield']);
      await storage.saveNoAdsPopupLastDay(123);
      await storage.saveNoAdsPopupDismissals(2);
      await storage.saveFreeCoinsDay(123);
      await storage.saveFreeCoinsCount(4);
      await storage.saveFreeCoinsLastMs(999);
      final installDay = storage.installDay;

      await storage.resetMenuState();

      expect(storage.coins, 0);
      expect(storage.ownedSkins, {'pink'});
      expect(storage.equippedSkin, 'pink');
      expect(storage.seenSkins, isEmpty);
      expect(storage.noAds, false);
      expect(storage.armedPowerup, 'none');
      expect(storage.slotHistory, isEmpty);
      expect(storage.noAdsPopupLastDay, -1);
      expect(storage.noAdsPopupDismissals, 0);
      expect(storage.freeCoinsDay, -1);
      expect(storage.freeCoinsCount, 0);
      expect(storage.freeCoinsLastMs, 0);
      // Kept.
      expect(storage.bestScore, 99);
      expect(storage.gamesPlayed, 1);
      expect(storage.muteSound, true);
      expect(storage.musicVolume, 0.1);
      expect(storage.installDay, installDay);

      final reader = GameStorage(clock: () => DateTime(2026, 1, 15));
      await reader.load();
      expect(reader.coins, 0);
      expect(reader.ownedSkins, {'pink'});
      expect(reader.seenSkins, isEmpty);
      expect(reader.noAds, false);
      expect(reader.armedPowerup, 'none');
      expect(reader.slotHistory, isEmpty);
      expect(reader.installDay, installDay);
      expect(reader.bestScore, 99);
    });
  });
}
