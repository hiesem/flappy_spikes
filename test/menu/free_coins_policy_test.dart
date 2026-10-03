import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/free_coins_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FreeCoinsPolicy', () {
    test('reward and limits match the PRD', () {
      expect(FreeCoinsPolicy.reward, 40);
      expect(FreeCoinsPolicy.maxPerDay, 5);
      expect(FreeCoinsPolicy.cooldown, const Duration(minutes: 5));
    });

    test('five claims per day with a five-minute cooldown', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 5, 10, 12);
      final storage = GameStorage(clock: () => now);
      await storage.load();
      final policy = FreeCoinsPolicy(storage);

      expect(policy.claimedToday, 0);
      expect(policy.remainingToday, 5);
      expect(policy.cooldownRemaining, Duration.zero);
      expect(policy.canClaim, true);

      await policy.recordClaim();
      expect(policy.claimedToday, 1);
      expect(policy.remainingToday, 4);
      expect(policy.cooldownRemaining, const Duration(minutes: 5));
      expect(policy.canClaim, false);

      now = now.add(const Duration(minutes: 5));
      expect(policy.cooldownRemaining, Duration.zero);
      expect(policy.canClaim, true);

      for (var i = 0; i < 4; i++) {
        await policy.recordClaim();
        now = now.add(const Duration(minutes: 5));
      }
      expect(policy.claimedToday, 5);
      expect(policy.remainingToday, 0);
      expect(policy.canClaim, false);

      // Partial cooldown still blocks even when a claim remains.
      now = now.add(const Duration(days: 1));
      expect(policy.claimedToday, 0);
      expect(policy.remainingToday, 5);
      expect(policy.canClaim, true);
      await policy.recordClaim();
      expect(policy.claimedToday, 1);
      expect(storage.freeCoinsLastMs, now.millisecondsSinceEpoch);
    });

    test('day rollover resets the count but keeps the cooldown', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 5, 10, 23, 58);
      final storage = GameStorage(clock: () => now);
      await storage.load();
      final policy = FreeCoinsPolicy(storage);

      await policy.recordClaim();
      expect(policy.claimedToday, 1);

      now = DateTime(2026, 5, 11, 0, 0);
      expect(policy.claimedToday, 0);
      expect(policy.remainingToday, 5);
      expect(policy.cooldownRemaining, const Duration(minutes: 3));
      expect(policy.canClaim, false);

      now = DateTime(2026, 5, 11, 0, 3);
      expect(policy.canClaim, true);
    });

    test('claims persist across instances', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 5, 10, 12);
      final storage = GameStorage(clock: () => now);
      await storage.load();
      final policy = FreeCoinsPolicy(storage);
      await policy.recordClaim();

      final reader = GameStorage(clock: () => now);
      await reader.load();
      final readerPolicy = FreeCoinsPolicy(reader);
      expect(readerPolicy.claimedToday, 1);
      expect(reader.freeCoinsLastMs, now.millisecondsSinceEpoch);
    });

    test('no cooldown before the first claim', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage(clock: () => DateTime(2026, 5, 10, 12));
      await storage.load();
      expect(FreeCoinsPolicy(storage).cooldownRemaining, Duration.zero);
    });
  });
}
