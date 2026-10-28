import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/star_road/star_road_card.dart';
import 'package:flappy_spikes/components/star_road/star_road_screen.dart';
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
          final box = row.children.whereType<MysteryBoxComponent>().single;
          expect(box.look.main, entry.value.color);
          expect(box.look.label, isNull);
          final texts = row.children
              .whereType<MenuText>()
              .map((t) => t.text)
              .toList();
          expect(texts.where((text) => text == 'MYSTERY'), hasLength(2));
          expect(texts, isNot(contains(entry.value.label)));
        }
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
      game.reduceMotionOverride = true;
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
      expect(
        game.storage.ownedItems.where((key) => key == sheet.item!.key),
        hasLength(1),
      );
    },
  );
}
