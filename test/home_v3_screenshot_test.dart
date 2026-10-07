import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'menu_screenshot_test.dart' show captureShot, loadFonts;

/// Renders home v3, LEVELS and the LEVEL UP popup (PRD-home-v3 §3 / §4) to
/// `build/menu_shots/` for a side-by-side look with the approved
/// `design/menu_v2/home_v3*.png`, `levels_list.png` and
/// `levels_levelup.png` (640 x 1422 = 2x of 320 x 711).
Map<String, Object> prefsFor(int best, {int? last, int claimedUpTo = -1}) => {
  'bestScore': best,
  'gamesPlayed': 34,
  'coins': 1250,
  'lastScore': ?last,
  'claimedLevels': [
    for (var l = 1; l <= (claimedUpTo < 0 ? 10 : claimedUpTo); l++) '$l',
  ],
};

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  void shot(
    String name, {
    required Map<String, Object> prefs,
    double height = 711,
    Future<void> Function(FlappySpikesGame game)? act,
  }) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame(prefs, height),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      'home v3 screenshot: $name',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        game.reduceMotionOverride = true; // deterministic frames
        game.menu.slot.debugForce = Powerup.bigHoops;
        game.menu.slot.rollForArrival();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        await act?.call(game);
        await flushAndMount(game);
        await tester.runAsync(() => captureShot(game, 2, name));
      },
    );
  }

  shot('home_v3_711', prefs: prefsFor(640, last: 12));
  shot('home_v3_711_legend', prefs: prefsFor(6000, last: 1234));
  shot('home_v3_711_unranked', prefs: prefsFor(6));
  shot('home_v3_568', prefs: prefsFor(640, last: 12), height: 568);
  shot('home_v3_640', prefs: prefsFor(640, last: 12), height: 640);
  shot('home_v3_730', prefs: prefsFor(640, last: 12), height: 730);
  shot(
    'levels_list_711',
    prefs: prefsFor(640, last: 12),
    act: (game) async {
      game.openLevels();
      await flushAndMount(game);
      stepGame(game, 0.4);
    },
  );
  shot(
    'levels_list_568_unranked',
    prefs: prefsFor(3),
    height: 568,
    act: (game) async {
      game.openLevels();
      await flushAndMount(game);
      stepGame(game, 0.4);
    },
  );
  shot(
    'levels_levelup_711',
    prefs: prefsFor(850, last: 850, claimedUpTo: 6),
    act: (game) async {
      stepGame(game, 0.5);
      await flushAndMount(game);
      stepGame(game, 0.6);
    },
  );
}
