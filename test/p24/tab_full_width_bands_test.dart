import 'dart:async';

import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/parts_config.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/services/e2e.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'backdrop_harness.dart' show rgbaOf;
import 'support/tablet.dart';

/// WP-TAB (tablet emulator bug, 2026-10-17): every full-width band — the
/// VS intro's FLY SOLO banner (a centred column) and the run banners (the
/// run column) — covers the whole screen, [0, screen width], at 3:4.
void main() {
  setUp(E2EHooks.reset);
  final size = canvasFor(3, 4);

  /// The band's colour at both screen edges and the middle of [banner]'s
  /// band row (px of the rendered 3:4 frame).
  Future<void> expectFullWidth(
    FlappySpikesGame g,
    WidgetTester tester,
    RunBanner banner,
    String name,
  ) async {
    await tester.runAsync(() async {
      final img = await renderGame(g, size);
      await saveTabEvidence(img, 'bands', name);
      final px = await rgbaOf(img);
      final k = img.height / g.viewHeight;
      // a row inside the band, above the text
      final y = ((banner.absolutePosition.y + 2) * k).round();
      final c = banner.color;
      bool isBand(int x) {
        final i = (y * img.width + x) * 4;
        return (px[i] - (c.r * 255).round()).abs() <= 3 &&
            (px[i + 1] - (c.g * 255).round()).abs() <= 3 &&
            (px[i + 2] - (c.b * 255).round()).abs() <= 3;
      }

      for (final x in [1, img.width ~/ 4, img.width ~/ 2, img.width * 3 ~/ 4, img.width - 2]) {
        expect(isBand(x), isTrue, reason: '$name: band colour at x $x of ${img.width}');
      }
      img.dispose();
    });
  }

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      worldHeight: worldHeightFor(3, 4),
      versus: FakeVersusService(
        loadingIntro: true,
        onSearch: () => Completer<bool>().future,
      ),
    ),
    gameSize: size,
  ).testGameWidget(
    'WP-TAB @3:4: the VS intro FLY SOLO band spans the whole screen',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, tester) async {
      expect(g.viewWidth, 426);
      g.onScreenTap();
      await flushAndMount(g);
      final intro = g.versusIntro!;
      for (var i = 0; i < 900 && intro.soloBanner == null; i++) {
        g.update(1 / 60);
        await Future<void>.value();
      }
      final banner = intro.soloBanner!;
      // past the scale-in (12 % of the banner's time)
      for (var i = 0; i < 30; i++) {
        g.update(1 / 60);
        await Future<void>.value();
      }
      await flushAndMount(g);
      expect(banner.isMounted, isTrue);
      await expectFullWidth(g, tester, banner, 'fly_solo_3x4');
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      prefs: {'firstRunHintSeen': true},
      worldHeight: worldHeightFor(3, 4),
    ),
    gameSize: size,
  ).testGameWidget(
    'WP-TAB @3:4: a run banner band spans the whole screen',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, tester) async {
      g.runDebug.god = true;
      final run = await startRun(g);
      await flyUntil(g, (r) => r.state.runClock > 1);
      final banner = RunHud.of(run)!.banners.show(
        ElementBanner('BULLSEYE!', color: PartsConfig.pink, duration: 5),
      );
      await flushAndMount(g);
      await flyUntil(g, (r) => r.state.runClock > 2);
      expect(banner.isMounted, isTrue);
      // the band is screen-centred too
      expect(
        banner.absolutePosition.x - g.camera.viewfinder.position.x +
            g.extraWidth / 2 + 160,
        closeTo(g.viewWidth / 2, 1e-3),
      );
      await expectFullWidth(g, tester, banner, 'run_banner_3x4');
    },
  );

  // The first-run hint (and the tap reminder) is centred on the screen;
  // unchanged on a phone.
  for (final (name, w, h) in [('3x4', 3.0, 4.0), ('phone', 9.0, 19.5)]) {
    for (final first in [true, false]) {
      final sz = canvasFor(w, h);
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(
          prefs: {'firstRunHintSeen': !first},
          worldHeight: worldHeightFor(w, h),
        ),
        gameSize: sz,
      ).testGameWidget(
        'WP-TAB @$name: the ${first ? 'first-run hint' : 'tap reminder'} is '
        'centred on the screen',
        setUp: (g, _) async {
          await g.ready();
          await preloadImages(g);
        },
        verify: (g, tester) async {
          await openRun(g);
          stepGame(g, 6);
          await flushAndMount(g);
          final hint = g.firstRunHint!;
          expect(hint.shown, isTrue);
          final hud = RunHud.of(g.run!)!;
          final screenX = hud.position.x + hint.position.x + hint.tapBannerCentre.dx;
          expect(screenX, closeTo(g.viewWidth / 2, 1e-3));
          if (name == 'phone') {
            expect(hint.centreShift, 0);
            expect(hint.tapBannerCentre.dx, 160);
          }
          await tester.runAsync(() async {
            final img = await renderGame(g, sz);
            await saveTabEvidence(img, 'bands', 'hint_${first ? 'first' : 'reminder'}_$name');
            img.dispose();
          });
        },
      );
    }
  }
}
