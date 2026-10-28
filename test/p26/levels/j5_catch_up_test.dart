import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/screens/level_reveal_sheet.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(), gameSize: Vector2(320, 711),
  ).testGameWidget(
    'equipping before payout marks the later reward log',
    setUp: (g, _) async { await g.ready(); await preloadImages(g); },
    verify: (g, _) async {
      await g.menu.levels.recordRun(25);
      final row = g.menu.levels.pending.single;
      final item = allItems.singleWhere((i) => i.key == row['item']);
      await g.menu.items.grant(item.key);
      await g.menu.items.equip(item.layer, item.id);
      await g.menu.levels.payPending();
      expect(g.menu.levels.rewardLog.single['equipped'], isTrue);
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'J5 reveals every stored reward before one payout',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      await g.menu.levels.recordRun(25);
      await g.menu.levels.recordRun(50);
      final rows = g.menu.levels.pending;
      expect(rows, hasLength(2));
      final balance = g.menu.wallet.balance;
      final look = g.menu.items.look;
      var finished = 0;
      final sheet = LevelCatchUpSheet(
        rewards: rows,
        onFinished: () => finished++,
      );
      g.world.add(sheet);
      await flushAndMount(g);
      await flushAndMount(g);
      for (var i = 0; i < rows.length; i++) {
        expect(sheet.current.item?.key, rows[i]['item']);
        stepGame(g, 2);
        await sheet.current.choose(false);
        await flushAndMount(g);
        if (i == 0) {
          expect(g.menu.levels.pending, hasLength(2));
          expect(g.menu.wallet.balance, balance);
        }
      }
      expect(finished, 1);
      expect(g.menu.levels.pending, isEmpty);
      expect(
        g.menu.wallet.balance,
        balance +
            rows.fold<int>(
              0,
              (sum, row) =>
                  sum + (row['coins'] as int) + (row['extraCoins'] as int),
            ),
      );
      expect(g.menu.items.look, look);
      for (final row in rows) {
        final item = allItems.singleWhere((i) => i.key == row['item']);
        expect(g.menu.items.isOwned(item.layer, item.id), isTrue);
      }
      expect(await g.menu.levels.payPending(), 0);
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'J5 re-entering Home claim pays exactly once',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      await g.menu.levels.recordRun(25);
      final row = g.menu.levels.pending.single;
      final before = g.menu.wallet.balance;
      g.openLevelUpPopup();
      await flushAndMount(g);
      final first = g.claimLevelUp();
      final second = g.claimLevelUp();
      await Future.wait([first, second]);
      expect(g.levelUpPopup, isNull);
      expect(g.menu.levels.pending, isEmpty);
      expect(
        g.menu.wallet.balance,
        before + (row['coins'] as int) + (row['extraCoins'] as int),
      );
      expect(await g.menu.levels.payPending(), 0);
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'J5 equip waits for the final choice and survives the payout',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      await g.menu.levels.recordRun(25);
      await g.menu.levels.recordRun(50);
      final rows = g.menu.levels.pending;
      final item = allItems.singleWhere((it) => it.key == rows.first['item']);
      final previous = g.menu.items.look.idFor(item.layer);
      var finished = false;
      final sheet = LevelCatchUpSheet(
        rewards: rows,
        onFinished: () => finished = true,
      );
      g.world.add(sheet);
      await flushAndMount(g);
      await flushAndMount(g);
      stepGame(g, 2);
      await sheet.current.choose(true);
      expect(g.menu.levels.pending, hasLength(2));
      expect(g.menu.items.look.idFor(item.layer), previous);
      stepGame(g, 1.7);
      await flushAndMount(g);
      await flushAndMount(g);
      expect(sheet.current.item?.key, rows.last['item']);
      stepGame(g, 2);
      await sheet.current.choose(false);
      expect(finished, isTrue);
      expect(g.menu.levels.pending, isEmpty);
      expect(g.menu.items.look.idFor(item.layer), item.id);
      final storage = GameStorage();
      await storage.load();
      expect(storage.lvlPending, isEmpty);
      expect(storage.ownedItems, contains(item.key));
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'J5 kill after roll preserves the item for the Home popup',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      await g.menu.levels.recordRun(25);
      final key = g.menu.levels.pending.single['item'];
      final reloaded = GameStorage();
      await reloaded.load();
      expect(reloaded.lvlPending.single['item'], key);
      // Rehydrate the running game's store from the persisted image, as on restart.
      await g.storage.load();
      g.openLevelUpPopup();
      await flushAndMount(g);
      await flushAndMount(g);
      await flushAndMount(g);
      final popup = g.levelUpPopup!;
      expect(popup.reveal.current.item?.key, key);
      stepGame(g, 2);
      await popup.reveal.current.choose(false);
      await flushAndMount(g);
      expect(g.menu.levels.pending, isEmpty);
    },
  );
}
