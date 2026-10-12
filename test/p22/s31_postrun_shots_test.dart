import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

/// PRD-2.2 §31.5 frame captures: the balloon bonus and the results page at
/// 711, 568 and 524 pt (the last one with a 50 dp banner: the lowered strip).
/// Compare with `design/menu_v2/flow_postrun.html` and the approved bonus and
/// results mocks. Writes to `build/menu_shots/p22/s31/` (never committed).
const _cases = <(double, double)>[(711, 0), (568, 0), (574, 50)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (screen, banner) in _cases) {
    final visible = screen - banner;
    final label = '${visible.round()}';
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: const {'feathers': 3},
        worldHeight: screen,
        monetization: banner > 0
            ? Monetization(
                banner: FakeBannerAds(
                  enabled: true,
                  heightDp: banner,
                  widthDp: 320,
                ),
              )
            : null,
      ),
      gameSize: Vector2(320, visible),
    ).testGameWidget(
      '§31 shots ($label pt): the balloon bonus and the results page',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
        await loadFonts();
      },
      verify: (g, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(g);
          run.state.invulnerable = 0;
          for (var i = 0; i < 8; i++) {
            run.debugPass(perfect: true);
          }
          killRun(g);
          await flushAndMount(g);
          expect(g.state, GameState.reviving);
          await declineRevive(g);
          expect(g.state, GameState.bonus);
          final bonus = g.bonusScreen!;
          stepGame(g, .5);
          await flushAndMount(g);
          await captureShot(g, 2, 'p22/s31/bonus_$label');

          for (final i in [0, 1, 2]) {
            bonus.tapTile(i);
            stepGame(g, 1.2);
            await flushAndMount(g);
          }
          for (var i = 0; i < 600 && !bonus.noThanksShown; i++) {
            g.update(1 / 60);
          }
          bonus.tapNoThanks();
          await flushAndMount(g);
          expect(g.state, GameState.results);
          stepGame(g, 1.5);
          await flushAndMount(g);
          g.resultsScreen!.stage.rays = 1;
          await captureShot(g, 2, 'p22/s31/results_$label');
        });
      },
    );
  }
}
