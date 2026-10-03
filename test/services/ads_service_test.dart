import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdPlacement', () {
    test('analytics names', () {
      expect(AdPlacement.shopFreeCoins.analyticsName, 'shop_free_coins');
      expect(AdPlacement.homeSlot.analyticsName, 'home_slot');
      expect(AdPlacement.revive.analyticsName, 'revive');
      expect(AdPlacement.doubleCoins.analyticsName, 'double_coins');
    });
  });

  group('NoopRewardedAds', () {
    test('is never available and never shows', () async {
      final ads = NoopRewardedAds();
      await ads.initialize();
      expect(ads.isAvailable, isFalse);
      for (final p in AdPlacement.values) {
        expect(await ads.show(p), AdResult.unavailable);
      }
    });
  });

  group('FakeRewardedAds', () {
    test('defaults to succeed: completed and counted', () async {
      final ads = FakeRewardedAds();
      await ads.initialize();
      expect(ads.mode, FakeAdMode.succeed);
      expect(ads.isAvailable, isTrue);
      expect(await ads.show(AdPlacement.homeSlot), AdResult.completed);
      expect(await ads.show(AdPlacement.shopFreeCoins), AdResult.completed);
      expect(ads.shown, 2);
      expect(ads.placements, [AdPlacement.homeSlot, AdPlacement.shopFreeCoins]);
    });

    test('fail mode: available, plays, but no reward', () async {
      final ads = FakeRewardedAds()..mode = FakeAdMode.fail;
      expect(ads.isAvailable, isTrue);
      expect(await ads.show(AdPlacement.revive), AdResult.failed);
      expect(ads.shown, 1);
    });

    test('unavailable mode: nothing plays, not counted', () async {
      final ads = FakeRewardedAds()..mode = FakeAdMode.unavailable;
      expect(ads.isAvailable, isFalse);
      expect(await ads.show(AdPlacement.doubleCoins), AdResult.unavailable);
      expect(ads.shown, 0);
      expect(ads.placements, isEmpty);
    });

    test('delay is honoured before the result', () async {
      final ads = FakeRewardedAds()..delay = const Duration(milliseconds: 30);
      final sw = Stopwatch()..start();
      expect(await ads.show(AdPlacement.homeSlot), AdResult.completed);
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(25));
    });
  });
}
