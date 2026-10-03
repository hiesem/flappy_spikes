import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/noads_popup_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(GameStorage, NoAdsPopupPolicy)> build() async {
    SharedPreferences.setMockInitialValues({});
    final storage = GameStorage(clock: () => DateTime(2026, 5, 10, 12));
    await storage.load();
    return (storage, NoAdsPopupPolicy(storage));
  }

  group('NoAdsPopupPolicy', () {
    test('never shows on install day', () async {
      final (_, policy) = await build();
      expect(policy.shouldShowOnLaunch(), false);
    });

    test('shows from the next day, at most once per day', () async {
      final (storage, policy) = await build();
      storage.debugDayOffset = 1;
      expect(policy.shouldShowOnLaunch(), true);

      await policy.markShown();
      expect(storage.noAdsPopupLastDay, storage.today);
      expect(policy.shouldShowOnLaunch(), false);

      storage.debugDayOffset = 2;
      expect(policy.shouldShowOnLaunch(), true);
    });

    test('a next-day clock advance also unlocks it', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 5, 10, 12);
      final storage = GameStorage(clock: () => now);
      await storage.load();
      final policy = NoAdsPopupPolicy(storage);
      expect(policy.shouldShowOnLaunch(), false);

      now = DateTime(2026, 5, 11, 12);
      expect(policy.shouldShowOnLaunch(), true);
    });

    test('stops after maxDismissals dismissals', () async {
      final (storage, policy) = await build();
      for (var day = 1; day <= NoAdsPopupPolicy.maxDismissals; day++) {
        storage.debugDayOffset = day;
        expect(policy.shouldShowOnLaunch(), true);
        await policy.markDismissed();
      }
      expect(storage.noAdsPopupDismissals, NoAdsPopupPolicy.maxDismissals);

      storage.debugDayOffset = NoAdsPopupPolicy.maxDismissals + 1;
      expect(policy.shouldShowOnLaunch(), false);
    });

    test('never shows to no-ads owners', () async {
      final (storage, policy) = await build();
      storage.debugDayOffset = 5;
      await storage.saveNoAds(true);
      expect(policy.shouldShowOnLaunch(), false);
    });

    test('markShown and markDismissed persist', () async {
      final (storage, policy) = await build();
      storage.debugDayOffset = 1;
      final today = storage.today;
      await policy.markShown();
      await policy.markDismissed();

      final reader = GameStorage(clock: () => DateTime(2026, 5, 10, 12));
      await reader.load();
      expect(reader.noAdsPopupLastDay, today);
      expect(reader.noAdsPopupDismissals, 1);
    });
  });
}
