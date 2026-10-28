import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  final tester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      prefs: const {
        'lvlIndex': 1,
        'claimedLevels': ['1'],
      },
      worldHeight: 568,
    ),
    gameSize: Vector2(320, 568),
  );

  tester.testGameWidget(
    'F10: a level item is paid and revealed before the same run skill item',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      game.runDebug.ignoreGates = false;
    },
    verify: (game, _) async {
      final run = await startRun(game);
      run.ctx.addScore(60);
      expect(game.achievements.unlock(AchievementId.rankSpikeAce), isTrue);
      await game.achievements.flush();
      killRunThroughSaves(game);
      await declineRevive(game);
      await flushAndMount(game);
      expect(game.state, GameState.results);
      for (
        var i = 0;
        i < 1200 && game.resultsScreen!.revealSheet == null;
        i++
      ) {
        game.update(1 / 60);
        if (i % 60 == 0) await flushAndMount(game);
        expect(game.skillReveal, isNull);
      }
      await flushAndMount(game);
      final level = game.resultsScreen!.revealSheet!;
      expect(level.skill, isFalse);
      expect(game.menu.levels.pending, isNotEmpty);
      stepGame(game, 2);
      expect(game.skillReveal, isNull);
      await level.choose(false);
      await flushAndMount(game);
      expect(game.menu.levels.pending, isEmpty);
      for (var i = 0; i < 1200 && game.skillReveal == null; i++) {
        game.update(1 / 60);
        if (i % 60 == 0) await flushAndMount(game);
      }
      await flushAndMount(game);
      final skill = game.skillReveal!;
      expect(skill.skill, isTrue);
      expect(skill.item!.id, 'spikes');
      expect(game.achievementToast, isNull);
      stepGame(game, 2);
      expect(game.achievementToast, isNull);
      await skill.choose(true);
      expect(game.menu.items.look.idFor(SkinLayer.hoop), 'spikes');
      stepGame(game, 1.7);
      expect(game.skillReveal, isNull);
    },
  );
  tester.testGameWidget(
    'F10: a card skill reveal equips only its own card slot',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await game.menu.items.grant('card:f_orbit');
      await game.menu.items.equip(SkinLayer.card, 'f_orbit');
    },
    verify: (game, _) async {
      expect(game.achievements.unlock(AchievementId.secondWind), isTrue);
      await game.achievements.flush();
      for (var i = 0; i < 600 && game.skillReveal == null; i++) {
        game.update(1 / 60);
        if (i % 60 == 0) await flushAndMount(game);
      }
      await flushAndMount(game);
      final skill = game.skillReveal!;
      expect(skill.item!.id, 'n_sky');
      stepGame(game, 2);
      await skill.choose(true);
      expect(game.menu.items.look.cardIdFor(CardKind.name), 'n_sky');
      expect(game.menu.items.look.cardIdFor(CardKind.frame), 'f_orbit');
    },
  );
}
