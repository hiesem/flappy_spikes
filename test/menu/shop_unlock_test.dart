import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/menu/menu_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('R8 opens on best, games, or level', () {
    TuningValues.current = TuningValues.defaults();
    expect(MenuState.menuUnlocked(24, 2, 0), isFalse);
    expect(MenuState.menuUnlocked(25, 0, 0), isTrue);
    expect(MenuState.menuUnlocked(0, 3, 0), isTrue);
    expect(MenuState.menuUnlocked(0, 0, 1), isTrue);
  });
  test('R8: stored games unlock the actual menu', () async {
    TuningValues.current = TuningValues.defaults();
    SharedPreferences.setMockInitialValues({'gamesPlayed': 3});
    final storage = GameStorage();
    await storage.load();
    expect(MenuState(storage).locked, isFalse);
  });
}
