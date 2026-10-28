import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/skins/skill_earn_sheet.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(prefs: const {'gamesPlayed': 10}, worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'F10: each shop section separates its skill tiles and shows the trophy',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      game.openSkins();
      await flushAndMount(game);
      stepGame(game, .7);
      await flushAndMount(game);
      final shop = game.skinShop!;
      for (final tab in kShopLayers) {
        shop.selectTab(tab);
        await flushAndMount(game);
        final skill = shop.tiles
            .where((tile) => tile.item.isSkillOnly)
            .toList();
        final sold = shop.tiles
            .where((tile) => !tile.item.isSkillOnly)
            .toList();
        expect(skill, hasLength(3), reason: tab.name);
        expect(shop.skillSectionHeader!.text, 'EARNED BY SKILL · NOT SOLD');
        expect(skill.every((tile) => tile.trophyImage != null), isTrue);
        expect(
          skill.first.toRect().top,
          greaterThan(
            sold
                .map((tile) => tile.toRect().bottom)
                .reduce((a, b) => a > b ? a : b),
          ),
        );
        expect(skill.map((tile) => tile.toRect().top).toSet(), hasLength(1));
      }
      for (final kind in CardKind.values) {
        shop.selectCardKind(kind);
        await flushAndMount(game);
        final skill = shop.tiles
            .where((tile) => tile.item.isSkillOnly)
            .toList();
        expect(skill, hasLength(3), reason: kind.name);
        expect(shop.skillSectionHeader!.text, 'EARNED BY SKILL · NOT SOLD');
        expect(skill.every((tile) => tile.trophyImage != null), isTrue);
      }
      final tile = shop.tiles.firstWhere((tile) => tile.item.isSkillOnly);
      tile.onPressed();
      await flushAndMount(game);
      expect(shop.tryOnId, tile.item.id);
      expect(shop.children.query<SkillEarnSheet>(), hasLength(1));
      shop.children.query<SkillEarnSheet>().single.close();
      await flushAndMount(game);
      shop.actionButton.onPressed();
      await flushAndMount(game);
      expect(shop.children.query<SkillEarnSheet>(), hasLength(1));
    },
  );
}
