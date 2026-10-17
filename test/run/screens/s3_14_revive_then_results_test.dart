import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/screens/phoenix_rise.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// P2 merge (WP-2d + WP-2e), PRD-2 §3.14: the revive offer comes before the
/// run ends; declining it leads to the results page (which replaced the
/// game-over panel), and NEXT goes home.
void main() {
  for (final h in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(prefs: {'bestScore': 40, 'playerLevel': 1}, worldHeight: h),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§3.14 ($h) ≥ 6 hoops: revive offer → No thanks → results with level '
      'up → NEXT → home',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        final run = await startRun(g);
        run.state.invulnerable = 0;
        for (var i = 0; i < 6; i++) {
          run.debugPass(perfect: true);
        }
        run.ctx.addScore(60 - run.state.score); // past EGG (50)
        run.ctx.earn(9, CoinSource.hoop);
        killRun(g);
        await flushAndMount(g);
        // The offer: the run has not ended yet (nothing saved).
        expect(g.state, GameState.reviving);
        expect(g.reviveScreen, isNotNull);
        expect(g.resultsScreen, isNull);
        expect(g.storage.bestScore, 40, reason: 'saved only at the real end');
        await declineRevive(g);
        expect(g.state, GameState.results);
        expect(g.reviveScreen, isNull);
        expect(g.world.children.query<ReviveDim>(), isEmpty,
            reason: 'the offer dim does not linger over the results page');
        final page = g.resultsScreen!;
        expect(g.storage.bestScore, 60);
        expect(page.model.levelReward, greaterThan(0));
        expect(g.storage.unclaimedLevelReward, page.model.levelReward);
        // The level-up celebration, then CLAIM.
        for (var i = 0; i < 300 && !page.claimShowing; i++) {
          g.update(1 / 60);
        }
        await flushAndMount(g);
        expect(page.claimShowing, isTrue);
        final before = g.menu.wallet.balance;
        page.nextButton.onPressed();
        await flushAndMount(g);
        expect(g.menu.wallet.balance, before + page.model.levelReward,
            reason: 'NEXT while CLAIM shows claims first');
        stepGame(g, 2);
        await flushAndMount(g);
        expect(g.state, GameState.start);
        expect(g.resultsScreen, isNull);
        expect(g.levelUpPopup, isNull);
        expect(g.storage.unclaimedLevelReward, 0);
      },
    );

    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      '§3.14 ($h) ≤ 5 hoops: no offer, straight to the results page',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        final run = await startRun(g);
        run.state.invulnerable = 0;
        for (var i = 0; i < 5; i++) {
          run.debugPass(perfect: true);
        }
        killRun(g);
        await flushAndMount(g);
        expect(g.state, GameState.results);
        expect(g.reviveScreen, isNull);
        expect(g.world.children.query<ResultsScreen>(), hasLength(1));
        stepGame(g, .4);
        g.resultsScreen!.nextButton.onPressed();
        await flushAndMount(g);
        stepGame(g, .1);
        await flushAndMount(g);
        expect(g.state, GameState.start);
      },
    );
  }
}
