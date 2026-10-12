import 'dart:ui' show Rect;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/config/revive_config.dart';
import 'package:flappy_spikes/run/screens/pause_screen.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §7.5.4 / §7.5.5 / §7.12 "Layout and playability": the run
/// heights a banner leaves (663 Pixel 8, 596, 524 = a 16:9 phone with a
/// 50 dp banner) with the lowered bottom strip.
///
/// (screen height, banner height) in points, with a 320 dp wide fake
/// banner (1 dp = 1 pt).
const _cases = <(double, double)>[(711, 48), (640, 44), (568, 44)];

FlappySpikesGame _game(double screen, double banner, {int seed = 7}) =>
    createRunTestGame(
      worldHeight: screen,
      seed: seed,
      monetization: Monetization(
        banner: FakeBannerAds(enabled: true, heightDp: banner, widthDp: 320),
      ),
    );

void main() {
  test('§7.5.5 Config: minRunViewHeight 500, bannerStripDrop 20 (gap 6)', () {
    expect(Config.minRunViewHeight, 500);
    expect(Config.bannerStripDrop, 20);
    // 26 pt base − 20 pt drop = the 6 pt grey gap, never smaller (§7.5.3).
    expect(26 - Config.bannerStripDrop, greaterThanOrEqualTo(6));
    expect(FlappySpikesGame.clampRunViewHeight(480), 500);
    expect(FlappySpikesGame.clampRunViewHeight(524), 524);
    expect(FlappySpikesGame.clampRunViewHeight(900), Config.maxViewHeight);
  });

  for (final (screen, banner) in _cases) {
    final visible = screen - banner;
    final label = '${visible.round()} pt';

    // ---- autopilot gate ---------------------------------------------------
    for (final seed in [7, 21, 1234]) {
      for (final big in [false, true]) {
        FlameTester<FlappySpikesGame>(
          () => _game(screen, banner, seed: seed),
          gameSize: Vector2(320, visible),
        ).testGameWidget(
          'AUTOPILOT ($label, banner, lowered strip) seed $seed'
          '${big ? ' Big Hoops' : ''}: the bot passes >= 12 hoops',
          setUp: (g, _) async {
            await g.ready();
            await preloadImages(g);
          },
          verify: (g, _) async {
            final run = await startRun(
              g,
              starter: big ? Powerup.bigHoops : Powerup.none,
            );
            expect(g.visibleHeight, visible);
            expect(g.bottomStripInset, 24);
            final flight = await flyRun(g, maxSeconds: 90, untilHoops: 30);
            expect(
              flight.hoops,
              greaterThanOrEqualTo(12),
              reason:
                  'died at ${flight.hoops} hoops (${flight.cause}, '
                  't=${flight.seconds.toStringAsFixed(1)} s, $label)\n'
                  '${flight.trace.reversed.take(12).join('\n')}',
            );
            expect(run.state.hoopsPassed, flight.hoops);
          },
        );
      }
    }

    // ---- every run screen ---------------------------------------------------
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: const {'feathers': 3},
        worldHeight: screen,
        monetization: Monetization(
          banner: FakeBannerAds(enabled: true, heightDp: banner, widthDp: 320),
        ),
      ),
      gameSize: Vector2(320, visible),
    ).testGameWidget(
      '§7.5.5 layout ($label): run, pause, revive, bonus and results keep '
      'every button between the top teeth and the lowered bottom teeth',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        // Menus: full height, the full 44 pt bottom strip.
        expect(g.visibleHeight, FlappySpikesGame.clampRunViewHeight(screen));
        expect(g.bottomStripInset, 44);
        final run = await startRun(g);
        expect(g.visibleHeight, visible);
        final deadly = visible - g.bottomStripInset;
        void inside(Rect r, String what) {
          expect(r.top, greaterThanOrEqualTo(Config.spikeHeight), reason: what);
          expect(r.bottom, lessThanOrEqualTo(deadly), reason: what);
        }

        // Run: the deadly line follows the teeth.
        expect(run.geo.floorTooth, closeTo(deadly, 1e-6));
        final ground = g.world.children.query<SpikeStrip>().firstWhere(
          (s) => !s.isCeiling,
        );
        expect(
          ground.body.position.y - Config.spikeHeight / 2 + ground.toothReach,
          closeTo(g.viewHeight, 1e-6),
        );
        // The bird's normal line is inside the band.
        final normal = run.geo.normalBirdPosition();
        expect(normal.y, inExclusiveRange(Config.spikeHeight, deadly));

        // Pause.
        g.pause();
        await flushAndMount(g);
        final pause = g.camera.viewport.children.query<PauseScreen>().single;
        inside(pause.card, 'pause card');
        inside(pause.resumeRect, 'RESUME');
        inside(pause.settingsRect, 'pause settings');
        g.resume();
        await flushAndMount(g);
        stepGame(g, 1);

        // Revive (≥ 6 hoops).
        run.state.invulnerable = 0;
        for (var i = 0; i < 8; i++) {
          run.debugPass(perfect: true);
        }
        killRun(g);
        await flushAndMount(g);
        expect(g.state, GameState.reviving);
        final revive = g.reviveScreen!;
        stepGame(g, 1);
        inside(revive.heartRect, 'revive heart');
        expect(
          revive.heartRect.bottom + ReviveConfig.noThanksGap + 20,
          lessThanOrEqualTo(deadly),
          reason: 'No thanks',
        );
        await declineRevive(g);

        // Bonus.
        expect(g.state, GameState.bonus);
        final bonus = g.bonusScreen!;
        stepGame(g, .5);
        inside(bonus.nextRect, 'bonus NEXT');
        inside(bonus.adRect, 'bonus ad button');
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

        // Results.
        expect(g.state, GameState.results);
        stepGame(g, 1.5);
        await flushAndMount(g);
        final next = g.resultsScreen!.nextButton.toAbsoluteRect();
        inside(next, 'results NEXT');
        expect(g.bannerState.value.name, 'showing');
      },
    );
  }
}
