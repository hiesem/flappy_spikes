import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/parts_config.dart';
import 'package:flappy_spikes/run/config/streak_config.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/items/streak.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §29.4 50 streak names with 10 rotating colours.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('§29 names and colours', () {
    test('50 names, 10 colours in the config', () {
      expect(StreakConfig.names, hasLength(50));
      expect(StreakConfig.names.toSet(), hasLength(50));
      expect(StreakConfig.colours, hasLength(10));
      expect(StreakConfig.names, isNot(contains('PHOENIX')));
      expect(StreakConfig.names, isNot(contains('LEGEND')));
    });

    test('banner text for ×1, ×2, ×3, ×40, ×50, ×51', () {
      expect(StreakBanner(1).text, 'PERFECT');
      expect(StreakBanner(2).text, 'GREAT ×2');
      expect(StreakBanner(3).text, 'ON FIRE ×3');
      expect(StreakBanner(40).text, 'IMMORTAL ×40');
      expect(StreakBanner(50).text, 'FLAPPY GOD ×50');
      expect(StreakBanner(51).text, 'FLAPPY GOD ×51');
      expect(StreakBanner(123).text, 'FLAPPY GOD ×123');
    });

    test('colour for ×1, ×10, ×11, ×48 (rotating); white text', () {
      expect(StreakBanner(1).color, const Color(0xFFEC008C));
      expect(StreakBanner(10).color, const Color(0xFF7A0044));
      expect(StreakBanner(11).color, const Color(0xFFEC008C));
      expect(StreakBanner(48).color, const Color(0xFF1E9BE0));
      expect(StreakBanner(51).color, const Color(0xFFEC008C));
      for (var n = 1; n <= 50; n++) {
        expect(
          StreakBanner(n).color,
          StreakConfig.colours[(n - 1) % 10],
          reason: '×$n',
        );
      }
    });

    test('every name fits the 320 pt banner at its computed font size '
        '(Opificio Neue)', () async {
      final data = await rootBundle.load(
        'assets/fonts/Opificio_neue-regular.ttf',
      );
      final loader = FontLoader(Config.uiFont)..addFont(Future.value(data));
      await loader.load();
      for (var n = 1; n <= 60; n++) {
        final b = StreakBanner(n);
        final fs = b.fontSize;
        expect(fs, lessThanOrEqualTo(34));
        final tp = TextPainter(
          text: TextSpan(
            text: b.text,
            style: TextStyle(
              fontFamily: Config.uiFont,
              fontSize: fs,
              letterSpacing: fs * PartsConfig.bannerLetterSpacing,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(
          tp.width,
          lessThanOrEqualTo(320 - 2 * PartsConfig.bannerPadding),
          reason: '${b.text} at $fs pt',
        );
      }
      // The longest name of the table, ×48.
      expect(StreakBanner(48).text, 'KING OF BIRDS ×48');
    });
  });

  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  );

  tester.testGameWidget(
    '§29 effects and tier sounds unchanged at ×3 and ×12 (tier capped at '
    '10, gold bird, trail); the banner shows the streak name',
    setUp: (g, _) async {
      await g.ready();
      g.sound.enabled = false;
      await preloadImages(g);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      final sfx = sfxLog(game);
      final streak = run.features.whereType<StreakFeature>().single;
      for (var i = 0; i < 3; i++) {
        run.debugPass(perfect: true);
        game.update(1 / 60);
      }
      expect(run.state.tier, 3);
      expect((streak.banners!.current! as StreakBanner).text, 'ON FIRE ×3');
      expect(game.runBird!.lookComponent.goldTier, isTrue);
      expect(streak.trailActive, isTrue);
      for (var i = 0; i < 9; i++) {
        run.debugPass(perfect: true);
        game.update(1 / 60);
      }
      expect(run.state.streak, 12);
      expect(run.state.tier, 10);
      expect((streak.banners!.current! as StreakBanner).text, 'SKYLARK ×12');
      expect(sfx.where((s) => s.startsWith('perfect')).toList(), [
        'perfect1',
        'perfect2',
        for (var i = 0; i < 10; i++) 'perfect3',
      ]);
    },
  );
}
