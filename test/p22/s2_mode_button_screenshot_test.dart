import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/home_mode.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts, mockPrefs;

/// PRD-2.2 §2.1 / §5: the Home with the mode button at 568, 640 and 711 in
/// both modes, written to `build/menu_shots/mode_<h>_<mode>@1.5x.png` for
/// comparison with `design/menu_v2/screen_mode_toggle3.html` (drawn at
/// 1.5x).
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  for (final h in [568.0, 640.0, 711.0]) {
    for (final mode in HomeMode.values) {
      FlameTester<FlappySpikesGame>(
        () => createTestGame({...mockPrefs, 'homeMode': mode.key}, h),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        'mode screenshot ${h.toInt()} ${mode.key}',
        setUp: (game, tester) async {
          await game.ready();
          await preloadImages(game);
          game.menu.slot.debugForce = Powerup.bigHoops;
          game.menu.slot.rollForArrival();
          await flushAndMount(game);
        },
        verify: (game, tester) async {
          final home = game.homeScreen!;
          expect(home.modeButton.mode, mode);
          expect(home.vsTag.shown, mode == HomeMode.versus);
          await tester.runAsync(
            () => captureShot(game, 1.5, 'mode_${h.toInt()}_${mode.key}@1.5x'),
          );
        },
      );
    }
  }
}
