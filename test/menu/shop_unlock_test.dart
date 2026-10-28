import 'package:flappy_spikes/run/config/tuning_values.dart';
import 'package:flappy_spikes/menu/menu_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R8 opens on best, games, or level', () {
    TuningValues.current = TuningValues.defaults();
    expect(MenuState.menuUnlocked(24, 2, 0), isFalse);
    expect(MenuState.menuUnlocked(25, 0, 0), isTrue);
    expect(MenuState.menuUnlocked(0, 3, 0), isTrue);
    expect(MenuState.menuUnlocked(0, 0, 1), isTrue);
  });
}
