import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/run/screens/level_reveal_sheet.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(), gameSize: Vector2(320, 711),
  ).testGameWidget(
    'legendary reveal plays its large cue and second burst',
    setUp: (game, _) async { await game.ready(); await preloadImages(game); },
    verify: (game, _) async {
      final sounds = <Sfx>[];
      game.sound.onPlay = sounds.add;
      final item = allItems.firstWhere((i) => i.rarity == Rarity.legendary && !i.isSkillOnly);
      final sheet = LevelRevealSheet(item: item, onFinished: (_) {});
      game.world.add(sheet);
      await flushAndMount(game);
      stepGame(game, 1.3);
      expect(sounds.where((s) => s == Sfx.lvUpBig), hasLength(1));
      await flushAndMount(game);
      final before = sheet.card.children.length;
      stepGame(game, .25);
      await flushAndMount(game);
      expect(sheet.card.children.length, greaterThan(before));
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'later pays once and does not equip; interrupted reveal retains pending',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      await game.menu.levels.recordRun(25);
      final row = game.menu.levels.pending.single;
      final item = allItems.firstWhere((item) => item.key == row['item']);
      final before = game.menu.items.look.idFor(item.layer);
      final balance = game.menu.wallet.balance;
      var finished = false;
      var sheet = LevelRevealSheet(
        item: item,
        onFinished: (_) {
          finished = true;
        },
      );
      game.world.add(sheet);
      await flushAndMount(game);
      sheet.removeFromParent();
      await flushAndMount(game);
      expect(game.menu.levels.pending, hasLength(1));
      sheet = LevelRevealSheet(
        item: item,
        onFinished: (_) {
          finished = true;
        },
      );
      game.world.add(sheet);
      await flushAndMount(game);
      await sheet.choose(false);
      expect(sheet.choosing, isFalse);
      expect(game.menu.levels.pending, hasLength(1));
      stepGame(game, 2);
      expect(sheet.revealed, isTrue);
      await sheet.choose(false);
      expect(finished, isTrue);
      expect(game.menu.items.look.idFor(item.layer), before);
      expect(game.menu.items.isOwned(item.layer, item.id), isTrue);
      expect(
        game.menu.wallet.balance,
        balance + (row['coins'] as int) + (row['extraCoins'] as int),
      );
      expect(await game.menu.levels.payPending(), 0);
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'equip pays once, updates the look, and closes after the stamp',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      // PRD-2.6 J4 (PRD:1084-1099).
      await game.menu.levels.recordRun(25);
      final row = game.menu.levels.pending.single;
      final item = allItems.firstWhere((i) => i.key == row['item']);
      final balance = game.menu.wallet.balance;
      bool? result;
      final sheet = LevelRevealSheet(
        item: item,
        onFinished: (equipped) {
          result = equipped;
        },
      );
      game.world.add(sheet);
      await flushAndMount(game);
      stepGame(game, 2);
      await sheet.choose(true);
      expect(game.menu.items.look.idFor(item.layer), item.id);
      expect(
        game.menu.wallet.balance,
        balance + (row['coins'] as int) + (row['extraCoins'] as int),
      );
      expect(await game.menu.levels.payPending(), 0);
      expect(result, isNull);
      stepGame(game, .7);
      expect(sheet.equippedLabel.text, 'EQUIPPED');
      expect(sheet.equippedCheckVisible, isTrue);
      expect(result, isNull);
      stepGame(game, 1);
      expect(result, isTrue);
    },
  );
}
