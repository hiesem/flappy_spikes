import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/menu_screen_chrome.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'menu_screenshot_test.dart' show captureShot, loadFonts, mockPrefs;

/// Menu scroll lists continue behind the bottom spike strip: the ground strip
/// draws above open menu screens and the lists draw (and take touches) down
/// into the gaps between the teeth, instead of being cut off flat at the
/// tips. Captures `build/menu_shots/spike_bleed_*.png` for a visual check.
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  for (final (name, height, open, pick)
      in <
        (
          String,
          double,
          void Function(FlappySpikesGame),
          MenuScreen? Function(FlappySpikesGame),
        )
      >[
        ('skins', 711, (g) => g.openSkins(), (g) => g.skinShop),
        ('shop', 711, (g) => g.openShop(), (g) => g.shopScreen),
        // The Shop fits at 711; it scrolls behind the teeth at 568.
        ('shop', 568, (g) => g.openShop(), (g) => g.shopScreen),
        ('levels', 711, (g) => g.openLevels(), (g) => g.levelsScreen),
      ]) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame(mockPrefs, height),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      'list shows between the bottom spike teeth: $name at $height',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        expect(game.groundStripPriority, SpikeStrip.basePriority);
        open(game);
        await flushAndMount(game);
        stepGame(game, Config.uiFadeDuration + 0.4);
        await flushAndMount(game);
        final screen = pick(game)!;
        final scroll = screen.scroll;

        // The strip draws over the screen (and so over its list).
        expect(game.groundStripPriority, greaterThan(screen.priority));

        // Same scroll range (viewport), but the list draws and takes
        // touches down to the tooth base.
        expect(scroll.viewport.bottom, height - Config.menuSpikeHeight);
        expect(
          scroll.visibleRect.bottom,
          scroll.viewport.bottom + Config.menuSpikeToothDepth,
        );
        final x = scroll.viewport.center.dx;
        expect(
          scroll.containsPoint(Vector2(x, scroll.viewport.bottom + 10)),
          isTrue,
        );
        expect(
          scroll.containsPoint(Vector2(x, scroll.visibleRect.bottom + 2)),
          isFalse,
        );

        // At the top (rows run on behind the teeth) and part way down.
        await tester.runAsync(
          () =>
              captureShot(game, 2, 'spike_bleed_${name}_${height.round()}@2x'),
        );
        if (scroll.scrollable) {
          scroll.offset = scroll.maxOffset / 2;
          await tester.runAsync(
            () => captureShot(
              game,
              2,
              'spike_bleed_${name}_${height.round()}_mid@2x',
            ),
          );
        }

        // Back home: the strip returns under everything once the screen
        // is gone.
        game.handleBack();
        stepGame(game, Config.uiFadeDuration + 0.4);
        await flushAndMount(game);
        expect(pick(game), isNull);
        expect(game.groundStripPriority, SpikeStrip.basePriority);
      },
    );
  }
}
