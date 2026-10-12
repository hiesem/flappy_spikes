import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/bonus_config.dart';
import 'package:flappy_spikes/run/screens/bonus_screen.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

/// PRD-2.2 §7.7 / §7.8 visual checks → `build/menu_shots/`: the NO ADS
/// owner's free revive heart (pink, REVIVE only) and the bonus offer while
/// it waits for its ad (dimmed, spinner) and once active.
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  FlameTester<FlappySpikesGame> tester(Map<String, Object> prefs) =>
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(
          prefs: prefs,
          worldHeight: 711,
          monetization: Monetization(
            ads: FakeRewardedAds()..mode = FakeAdMode.unavailable,
          ),
        ),
        gameSize: Vector2(320, 711),
      );

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
  }

  tester({'noAds': true}).testGameWidget(
    'shot: §7.7 the free revive heart',
    setUp: boot,
    verify: (g, tester) async {
      final run = await startRun(g);
      for (var i = 0; i < 6; i++) {
        run.debugPass(perfect: true);
      }
      run.state.invulnerable = 0;
      killRunThroughSaves(g);
      for (var i = 0; i < 600 && g.state == GameState.dying; i++) {
        g.update(1 / 60);
      }
      await flushAndMount(g);
      final screen = g.reviveScreen!;
      for (var i = 0; i < 40; i++) {
        g.update(1 / 60);
      }
      expect(screen.offer.isFree, isTrue);
      await tester.runAsync(() => captureShot(g, 2, 'p22_s7_7_free_revive'));
      // The empty heart waiting (§7.15).
      for (var i = 0; i < 8 * 60; i++) {
        g.update(1 / 60);
      }
      await tester.runAsync(
        () => captureShot(g, 2, 'p22_s7_15_revive_waiting'),
      );
    },
  );

  tester({'feathers': 3}).testGameWidget(
    'shot: §7.8 the bonus offer waiting for its ad, then active',
    setUp: boot,
    verify: (g, tester) async {
      await startRun(g);
      killRunThroughSaves(g);
      await flushAndMount(g);
      final b = g.bonusScreen!;
      await stepSeconds(g, .2);
      for (final i in [0, 1, 2]) {
        b.tapTile(i);
        await stepSeconds(g, BonusConfig.busy + .05);
      }
      for (var i = 0; i < 240 && b.phase == BonusPhase.pick; i++) {
        g.update(1 / 60);
      }
      await stepSeconds(g, .5);
      expect(b.adWaiting, isTrue);
      await tester.runAsync(() => captureShot(g, 2, 'p22_s7_8_bonus_waiting'));
      (g.monetization.ads as FakeRewardedAds).mode = FakeAdMode.succeed;
      await stepSeconds(g, .5);
      expect(b.adWaiting, isFalse);
      await tester.runAsync(() => captureShot(g, 2, 'p22_s7_8_bonus_active'));
    },
  );
}
