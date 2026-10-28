import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/skins/item_store.dart';
import 'package:flappy_spikes/progression/star_road_claims.dart';
import 'package:flappy_spikes/progression/star_road_season.dart';
import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  StarRoadSeason coordinator(GameStorage storage) {
    final wallet = Wallet(storage);
    return StarRoadSeason(
      storage,
      StarRoadClaims(storage, wallet, ItemStore(storage, wallet)),
    );
  }

  test('epoch is UTC Monday and seasons advance every 28 days', () async {
    var clock = DateTime.utc(2026, 10, 26, 23, 59);
    final storage = GameStorage(clock: () => clock);
    await storage.load();
    final season = coordinator(storage);
    expect(tuning.i('star_road_epoch_day'), 20752);
    expect(season.currentSeason, 1);
    expect(season.daysLeft, 28);
    clock = DateTime.utc(2026, 11, 23);
    expect(season.currentSeason, 2);
    expect(season.daysLeft, 28);
  });

  test(
    'rollover pays unclaimed tiers once and preserves one summary',
    () async {
      final storage = GameStorage(clock: () => DateTime.utc(2026, 11, 23));
      await storage.load();
      await storage.saveStarRoadSeason(1);
      await storage.saveStarRoadXp(24);
      await storage.saveStarRoadClaimed({1});
      final season = coordinator(storage);
      final settling = season.settle();
      expect(season.settling, isTrue);
      await settling;
      expect(season.settling, isFalse);
      expect(storage.coins, 55);
      expect(storage.starRoadSeason, 2);
      expect(storage.starRoadXp, 0);
      expect(storage.starRoadClaimed, isEmpty);
      await season.settle();
      expect(storage.coins, 55);
      final summary = season.takeSummary();
      expect(summary!['tiers'], [2, 3]);
      final awards = summary['awards'] as Map;
      expect(awards['2']['coins'], 25);
      expect(awards['3']['coins'], 30);
      expect(season.takeSummary(), isNull);
    },
  );

  test('interrupted rollover resumes after an already claimed tier', () async {
    final storage = GameStorage(clock: () => DateTime.utc(2026, 11, 23));
    await storage.load();
    await storage.saveStarRoadSeason(1);
    await storage.saveStarRoadXp(16);
    final season = coordinator(storage);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      Obf.prefStarRoadRollover,
      jsonEncode({
        'pending': true,
        'from': 1,
        'to': 2,
        'tiers': [1, 2],
      }),
    );
    await season.claims.claim(1);
    await season.settle();
    expect(storage.coins, 50);
    expect(storage.starRoadSeason, 2);
    final summary = season.takeSummary()!;
    expect(summary['tiers'], [1, 2]);
    expect((summary['awards'] as Map).keys, containsAll(['1', '2']));
  });

  test(
    'mission journal repairs star target and daily watermark on reload',
    () async {
      final storage = GameStorage();
      await storage.load();
      await storage.saveStarRoadSeason(1);
      await storage.saveMissionJournal({
        'day': 1,
        'tier': 0,
        'rerollDay': -1,
        'missions': <Object>[],
        'balanceBefore': 0,
        'earnedBefore': 0,
        'amount': 0,
        'applied': true,
        'roadSeason': 1,
        'roadXp': 11,
        'roadDay': 20752,
      });
      final recovered = GameStorage();
      await recovered.load();
      expect(recovered.starRoadXp, 11);
      expect(recovered.starRoadRunDay, 20752);
      expect(recovered.missionJournal, isEmpty);
    },
  );
  test('an unread summary survives another season rollover', () async {
    var now = DateTime.utc(2026, 11, 23);
    final storage = GameStorage(clock: () => now);
    await storage.load();
    await storage.saveStarRoadSeason(1);
    await storage.saveStarRoadXp(8);
    final season = coordinator(storage);
    await season.settle();
    now = DateTime.utc(2026, 12, 21);
    await season.settle();
    expect(storage.starRoadSeason, 3);
    expect(season.takeSummary()!['from'], 1);
  });
  test('rollover waits for an in-flight manual claim', () async {
    final storage = GameStorage(clock: () => DateTime.utc(2026, 11, 23));
    await storage.load();
    await storage.saveStarRoadSeason(1);
    await storage.saveStarRoadXp(16);
    final season = coordinator(storage);
    final manual = season.claims.claim(1);
    final rollover = season.settle();
    await Future.wait([manual, rollover]);
    expect(storage.coins, 50);
    expect(storage.starRoadSeason, 2);
    expect(storage.starRoadXp, 0);
  });
}
