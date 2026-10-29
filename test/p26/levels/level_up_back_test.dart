import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'FIX2 Back closes the Home LEVEL UP popup and pays its reward',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      await game.menu.levels.recordRun(25);
      final row = game.menu.levels.pending.single;
      final before = game.menu.wallet.balance;
      game.homeMoments.beginVisit(
        HomeVisit(
          day: game.storage.now(),
          gamesPlayed: game.storage.gamesPlayed,
          requests: const HomeVisitRequests(levelUpCatchUp: true),
        ),
      );
      game.openLevelUpPopup();
      await flushAndMount(game);
      await flushAndMount(game);

      final popup = game.levelUpPopup!;
      expect(popup.reveal.current.revealed, isFalse);
      expect(game.handleBack(), isTrue, reason: 'Back reveals the box');
      await flushAndMount(game);
      expect(popup.reveal.current.revealed, isTrue);
      expect(game.levelUpPopup, same(popup));
      expect(game.menu.wallet.balance, before);

      expect(game.handleBack(), isTrue, reason: 'Back then chooses LATER');
      for (var i = 0; i < 10 && game.levelUpPopup != null; i++) {
        await flushAndMount(game);
      }
      expect(game.levelUpPopup, isNull);
      expect(game.menu.levels.pending, isEmpty);
      expect(
        game.menu.wallet.balance,
        before + (row['coins'] as int) + (row['extraCoins'] as int),
      );
    },
  );
}
