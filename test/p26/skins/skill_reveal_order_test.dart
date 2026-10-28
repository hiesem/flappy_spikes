import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/screens/level_reveal_sheet.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

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
      // PRD-2.6 F10 / approved skill_cosmetics.html:1118: achievement
      // pills play after the level reveal and before the skill reveal.
      var sawToast = false;
      for (var i = 0; i < 3600 && game.skillReveal == null; i++) {
        game.update(1 / 60);
        if (i % 10 == 0) await flushAndMount(game);
        if (game.achievementToast != null) {
          sawToast = true;
          expect(game.skillReveal, isNull);
          game.achievementToast!.dismiss();
        }
      }
      expect(sawToast, isTrue);
      await flushAndMount(game);
      final skill = game.skillReveal!;
      expect(skill.skill, isTrue);
      expect(skill.item!.id, 'spikes');
      expect(skill.parent, same(game.resultsScreen));
      expect(game.achievementToast, isNull);
      expect(game.modalPopupOpen, isTrue);
      for (final key in [LogicalKeyboardKey.space, LogicalKeyboardKey.enter, LogicalKeyboardKey.escape]) {
        final event = KeyDownEvent(physicalKey: PhysicalKeyboardKey.space,
          logicalKey: key, timeStamp: Duration.zero);
        expect(game.onKeyEvent(event, {key}), KeyEventResult.handled);
        expect(game.state, GameState.results);
      }
      game.openNoAdsPopup();
      expect(game.queuedPopups, greaterThan(0));
      expect(game.noAdsPopup, isNull);
      stepGame(game, 2);
      expect(game.noAdsPopup, isNull);
      await skill.choose(false);
      expect(game.menu.items.isOwned(SkinLayer.hoop, 'spikes'), isTrue);
      expect(game.menu.items.isNew(SkinLayer.hoop, 'spikes'), isTrue);
      await game.menu.items.markSeen(SkinLayer.hoop, 'spikes');
      expect(game.menu.items.isNew(SkinLayer.hoop, 'spikes'), isFalse);
      stepGame(game, 1.7);
      await flushAndMount(game);
      expect(game.skillReveal, isNull);
      final equipSheet = LevelRevealSheet(item: skill.item, skill: true, onFinished: (_) {});
      game.world.add(equipSheet);
      await flushAndMount(game);
      stepGame(game, 2);
      await equipSheet.choose(true);
      expect(game.menu.items.look.idFor(SkinLayer.hoop), 'spikes');
      stepGame(game, 1.7);
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
      // PRD-2.6 F10: an achievement earned in the shop is revealed
      // on Home after the achievement toast, without requiring another run.
      game.openSkins();
      await flushAndMount(game);
      stepGame(game, .7);
      expect(game.skinShop, isNotNull);
      expect(game.achievements.unlock(AchievementId.secondWind), isTrue);
      await game.achievements.flush();
      stepGame(game, .3);
      expect(game.skillReveal, isNull);
      game.closeSkins();
      for (var i = 0; i < 3600 && game.skillReveal == null; i++) {
        game.update(1 / 60);
        if (i % 10 == 0) await flushAndMount(game);
        game.achievementToast?.dismiss();
      }
      await flushAndMount(game);
      expect(game.skillReveal!.skillHome, isTrue);
      expect(game.modalPopupOpen, isTrue);
      expect(game.systemBackWanted, isTrue);
      final interrupted = game.skillReveal!;
      expect(interrupted.item!.id, 'n_sky');
      interrupted.removeFromParent();
      await flushAndMount(game);
      final skill = game.skillReveal!;
      expect(identical(skill, interrupted), isFalse);
      expect(skill.item!.id, 'n_sky');
      game.openNoAdsPopup();
      expect(game.queuedPopups, greaterThan(0));
      expect(game.noAdsPopup, isNull);
      expect(game.handleSystemBack(), isTrue);
      expect(game.state, GameState.start);
      stepGame(game, 2);
      expect(game.noAdsPopup, isNull);
      await skill.choose(true);
      expect(game.menu.items.look.cardIdFor(CardKind.name), 'n_sky');
      expect(game.menu.items.look.cardIdFor(CardKind.frame), 'f_orbit');
      stepGame(game, 1.7);
      await flushAndMount(game);
      expect(game.skillReveal, isNull);
      expect(game.noAdsPopup, isNotNull);
    },
  );
  tester.testGameWidget(
    'F10: a run-slot skill reward does not block starting the next run',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      game.achievements.countDebugRuns = true;
    },
    verify: (game, _) async {
      final run = await startRun(game);
      run.events.emit(const EggHatched());
      killRunThroughSaves(game);
      await declineRevive(game);
      await flushAndMount(game);
      await game.achievements.flush();
      expect(game.achievements.isUnlocked(AchievementId.masterHatch), isTrue);
      game.goHome();
      await flushAndMount(game);
      for (var i = 0; i < 180; i++) {
        game.update(1 / 60);
        if (i % 10 == 0) await flushAndMount(game);
        game.achievementToast?.dismiss();
        expect(game.skillReveal, isNull);
      }
      final next = await startRun(game);
      expect(next, isNotNull);
      killRunThroughSaves(game);
      await declineRevive(game);
      await flushAndMount(game);
      for (var i = 0; i < 3600 && game.skillReveal == null; i++) {
        game.update(1 / 60);
        if (i % 10 == 0) await flushAndMount(game);
        game.achievementToast?.dismiss();
      }
      await flushAndMount(game);
      expect(game.skillReveal?.item?.id, 'nest');
      expect(game.skillReveal?.parent, same(game.resultsScreen));
    },
  );

}
