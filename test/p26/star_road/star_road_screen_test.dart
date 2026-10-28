import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/star_road/star_road_card.dart';
import 'package:flappy_spikes/components/star_road/star_road_screen.dart';
import 'package:flappy_spikes/components/star_road/star_road_art.dart';
import 'package:flappy_spikes/components/skins/item_tile.dart';
import 'package:flappy_spikes/components/ui/mystery_box.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/progression/star_road.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers.dart';

void main() {
  test('track viewport fits both supported heights and all 25 rows', () {
    for (final height in [568.0, 711.0]) {
      final viewport = StarRoadLayout.viewport(height);
      expect(viewport.top, 252);
      expect(viewport.bottom, height);
      expect(StarRoadLayout.header.bottom, lessThan(viewport.top));
    }
    for (var tier = 1; tier < 25; tier++) {
      expect(
        StarRoadLayout.rowTop(tier + 1),
        greaterThan(StarRoadLayout.rowTop(tier)),
      );
    }
  });
  for (final height in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame({}, height),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      'card opens 25-tier track with coloured mystery boxes at $height',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, _) async {
        await game.storage.saveStarRoadSeason(3);
        await game.storage.saveStarRoadXp(80);
        var left = false;
        var returned = false;
        final card = StarRoadCard.open(
          game: game,
          road: StarRoad(season: 3, xp: 80),
          daysLeft: 5,
          compact: true,
          leavePanel: () {
            expect(
              game.modalPopupOpen,
              isTrue,
              reason: 'the popup queue stays blocked during panel close',
            );
            left = true;
          },
          returnToPanel: () => returned = true,
        );
        card.onPressed();
        await flushAndMount(game);
        final screen = game.starRoadScreen!;
        expect(left, isTrue);
        expect(screen.rows.length, 25);
        expect(screen.scroll.viewport, Rect.fromLTRB(0, 252, 320, height));
        for (final entry in {
          10: Rarity.rare,
          20: Rarity.epic,
          25: Rarity.legendary,
        }.entries) {
          final row = screen.rows[entry.key]!;
          final descendants = row.children
              .expand((child) => child.children)
              .toList();
          final box = descendants.whereType<MysteryBoxComponent>().single;
          expect(box.look.main, entry.value.color);
          expect(box.look.dark, switch (entry.value) {
            Rarity.rare => const Color(0xFF0E6FA6),
            Rarity.epic => const Color(0xFF6A1A9C),
            _ => const Color(0xFFC98A00),
          });
          expect(box.look.label, isNull);
          final texts = descendants
              .whereType<MenuText>()
              .map((t) => t.text)
              .toList();
          expect(texts.where((text) => text == 'MYSTERY'), hasLength(2));
          expect(texts, isNot(contains(entry.value.label)));
        }
        final states = screen.rows.map(
          (tier, row) => MapEntry(
            tier,
            row.children.whereType<StarRoadTierNode>().single.state,
          ),
        );
        expect(states[1], StarRoadNodeState.claimable);
        expect(states[11], StarRoadNodeState.next);
        expect(states[12], StarRoadNodeState.locked);
        final headerTexts = screen.children
            .expand((c) => c.children)
            .whereType<MenuText>()
            .map((t) => t.text);
        expect(headerTexts, contains('TIER 10 OF 25 ·'));
        expect(headerTexts, contains('8 STARS TO TIER 11'));
        expect(
          screen.rows[1]!.children.whereType<MenuButton>().single.size,
          Vector2(70, 32),
        );
        var incorrectlyLeft = false;
        StarRoadCard.open(
          game: game,
          road: StarRoad(season: 3),
          daysLeft: 5,
          compact: true,
          leavePanel: () => incorrectlyLeft = true,
          returnToPanel: () {},
        ).onPressed();
        expect(incorrectlyLeft, isFalse);
        screen.backButton.onPressed();
        expect(returned, isTrue);
        expect(game.starRoadScreen, isNull);
      },
    );
  }
  FlameTester<FlappySpikesGame>(
    () => createTestGame({}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'coin claim pays and plays its cue from the track',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      await game.storage.saveStarRoadSeason(1);
      await game.storage.saveStarRoadXp(8);
      game.reduceMotionOverride = false;
      final sounds = <Sfx>[];
      game.sound.onPlay = sounds.add;
      game.openStarRoad(daysLeft: 10, onBack: () {});
      await flushAndMount(game);
      final row = game.starRoadScreen!.rows[1]!;
      final button = row.children.whereType<MenuButton>().single;
      button.onPressed();
      for (var i = 0; i < 30 && game.storage.coins == 0; i++) {
        await Future<void>.value();
        await flushAndMount(game);
      }
      await flushAndMount(game);
      expect(game.storage.coins, 25);
      expect(
        game.coinPill.held,
        isTrue,
        reason: 'hold until the coin flight ends',
      );
      stepGame(game, 2);
      await flushAndMount(game);
      expect(game.coinPill.held, isFalse);
      expect(sounds, contains(Sfx.bnCoin));
      expect(game.storage.starRoadClaimed, contains(1));
      expect(
        row.children.whereType<MenuText>().map((t) => t.text),
        contains('CLAIMED'),
      );
      button.onPressed();
      await flushAndMount(game);
      expect(game.storage.coins, 25);
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createTestGame({}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'claim opens J4 after item is paid; a kill during reveal keeps it once',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      await game.storage.saveStarRoadSeason(1);
      await game.storage.saveStarRoadXp(80);
      await game.menu.levels.recordRun(25);
      expect(game.menu.levels.pending, hasLength(1));
      game.openStarRoad(daysLeft: 10, onBack: () {});
      await flushAndMount(game);
      final row = game.starRoadScreen!.rows[10]!;
      row.children.whereType<MenuButton>().single.onPressed();
      for (var i = 0; i < 30 && game.starRoadReveal == null; i++) {
        await Future<void>.value();
        await flushAndMount(game);
      }
      final sheet = game.starRoadReveal!;
      expect(sheet.item, isNotNull);
      expect(game.storage.ownedItems, contains(sheet.item!.key));
      expect(game.storage.starRoadClaimed, contains(10));
      final restarted = GameStorage();
      await restarted.load();
      expect(restarted.ownedItems, contains(sheet.item!.key));
      expect(restarted.starRoadClaimed, contains(10));
      stepGame(game, 2);
      await sheet.choose(false);
      expect(
        game.menu.levels.pending,
        hasLength(1),
        reason: 'Star Road reveal must not pay the unrelated J4 level reward',
      );
      await flushAndMount(game);
      expect(game.starRoadReveal, isNull);
      await flushAndMount(game);
      expect(
        row.children
            .expand((child) => child.children)
            .whereType<ItemTile>()
            .single
            .item
            .key,
        sheet.item!.key,
      );
      expect(
        game.storage.ownedItems.where((key) => key == sheet.item!.key),
        hasLength(1),
      );
      game.closeStarRoad();
      await flushAndMount(game);
      game.openStarRoad(daysLeft: 10, onBack: () {});
      await flushAndMount(game);
      final restoredRow = game.starRoadScreen!.rows[10]!;
      expect(
        restoredRow.children.whereType<StarRoadTierNode>().single.state,
        StarRoadNodeState.claimed,
      );
      expect(
        restoredRow.children
            .expand((c) => c.children)
            .whereType<ItemTile>()
            .single
            .item
            .key,
        sheet.item!.key,
      );
    },
  );
  FlameTester<FlappySpikesGame>(
    () => createTestGame({}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'removing an item reveal unblocks back',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      await game.storage.saveStarRoadSeason(1);
      await game.storage.saveStarRoadXp(80);
      game.openStarRoad(daysLeft: 10, onBack: () {});
      await flushAndMount(game);
      game.starRoadScreen!.rows[10]!.children
          .whereType<MenuButton>()
          .single
          .onPressed();
      for (var i = 0; i < 30 && game.starRoadReveal == null; i++) {
        await Future<void>.value();
        await flushAndMount(game);
      }
      final sheet = game.starRoadReveal!;
      await flushAndMount(game);
      sheet.removeFromParent();
      await flushAndMount(game);
      expect(game.starRoadReveal, isNull);
      game.closeStarRoad();
      expect(game.starRoadScreen, isNull);
      expect(game.storage.starRoadClaimed, contains(10));
    },
  );
}
