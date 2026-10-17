import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'support/tablet.dart';

/// Owner 2026-10-17: the home logo (size S) at the phone heights and the
/// tablet shapes; evidence PNGs in evidence/tab/logo (LOOK at them).
void main() {
  const prefs = {
    'bestScore': 115,
    'playerLevel': 1,
    'gamesPlayed': 3,
    'claimedLevels': ['1'],
  };
  final shapes = <(String, double, double)>[
    ('phone568', 320, 568),
    ('phone711', 320, 711),
    ('phone730', 320, 730),
    ...kShapes.where((s) => s.$2 / s.$3 > 0.6),
  ];
  for (final (name, w, h) in shapes) {
    final size = canvasFor(w, h);
    FlameTester<FlappySpikesGame>(
      () => createTestGame(prefs, worldHeightFor(w, h)),
      gameSize: size,
    ).testGameWidget(
      'home logo @$name',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) async {
        stepGame(g, 1);
        await flushAndMount(g);
        expect(g.homeScreen!.title.sprite, isNotNull);
        await shoot(tester, g, size, 'logo', 'home_$name');
      },
    );
  }
}
