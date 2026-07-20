import 'package:flappy_spikes/game/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GameStorage', () {
    test('loads defaults when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      expect(storage.bestScore, 0);
      expect(storage.gamesPlayed, 0);
      expect(storage.muteSound, false);
    });

    test('loads persisted values', () async {
      SharedPreferences.setMockInitialValues({
        'bestScore': 12,
        'gamesPlayed': 34,
        'muteSound': true,
      });
      final storage = GameStorage();
      await storage.load();
      expect(storage.bestScore, 12);
      expect(storage.gamesPlayed, 34);
      expect(storage.muteSound, true);
    });

    test('bestScore round-trips across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final writer = GameStorage();
      await writer.saveBestScore(42);
      expect(writer.bestScore, 42);

      final reader = GameStorage();
      await reader.load();
      expect(reader.bestScore, 42);
    });

    test('gamesPlayed increments and round-trips across instances', () async {
      SharedPreferences.setMockInitialValues({'gamesPlayed': 7});
      final writer = GameStorage();
      await writer.load();
      await writer.incrementGamesPlayed();
      await writer.incrementGamesPlayed();
      expect(writer.gamesPlayed, 9);

      final reader = GameStorage();
      await reader.load();
      expect(reader.gamesPlayed, 9);
    });

    test('muteSound round-trips across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final writer = GameStorage();
      await writer.saveMuteSound(true);
      expect(writer.muteSound, true);

      final reader = GameStorage();
      await reader.load();
      expect(reader.muteSound, true);

      await reader.saveMuteSound(false);
      final third = GameStorage();
      await third.load();
      expect(third.muteSound, false);
    });
  });
}
