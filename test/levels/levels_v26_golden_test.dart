import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/components/levels/levels_screen.dart';
import 'package:flappy_spikes/components/levels/emblem_view.dart';
import 'package:flappy_spikes/components/skins/item_tile.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

Future<void> loadFonts() async {
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  await opificio.load();
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  await fredoka.load();
}

Future<ui.Image> frame(FlappySpikesGame game) async {
  game.onGameResize(Vector2(320, 711));
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 320, 711),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  return recorder.endRecording().toImage(320, 711);
}

void main() {
  setUpAll(() async {
    await loadFonts();
    final images = await Future.wait([
      for (var slot = 1; slot <= 32; slot++) EmblemView.loadImageForLevel(slot),
    ]);
    expect(images.last, isNotNull, reason: 'J7 ETERNAL WING slot 32');
  });
  for (final level in [0, 10, 40]) {
    FlameTester<FlappySpikesGame>(() {
      final log = [
        for (var i = 1; i <= level; i++)
          {
            'lvl': i,
            'coins': i >= 32 ? 2500 : 175,
            'item': 'bird:sky',
            'rarity': 'common',
            'fallback': 'none',
          },
      ];
      SharedPreferences.setMockInitialValues({
        'lvlIndex': level,
        'lvlPoints': level == 40
            ? 6240
            : level == 10
            ? 420
            : 0,
        'bestScore': 640,
        'gamesPlayed': 34,
        'lvlRewardLog': jsonEncode(log),
      });
      return FlappySpikesGame(worldHeight: 711, soundEnabled: false);
    }, gameSize: Vector2(320, 711)).testGameWidget(
      'J6 levels screen L$level',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        game.openLevels();
        await flushAndMount(game);
        await flushAndMount(game);
        for (var i = 0; i < 120; i++) {
          game.update(1 / 60);
        }
        final screen = game.levelsScreen!;
        await tester.pump();
        await tester.runAsync(() async {
          await screen.header.emblem.imageReady;
          final current = screen.currentRow?.liveEmblem;
          if (current != null) await current.imageReady;
        });
        expect(screen.rows, hasLength(32));
        expect(
          screen.rows.where((r) => r.liveEmblem != null).length,
          level == 0 ? 0 : 1,
        );
        if (level == 40) {
          expect(screen.currentRow!.def.level, 32);
          expect(screen.header.barText.text, '3 760 TO LEVEL 41');
          expect(screen.currentRow!.eternalRewards.map((r) => r['lvl']), [
            40,
            39,
            38,
            37,
            36,
            35,
            34,
            33,
            32,
          ]);
          expect(
            screen.currentRow!.children.whereType<LevelRewardCarousel>(),
            hasLength(1),
          );
          game.onGameResize(Vector2(320, 711));
          final carousel = screen.currentRow!.children
              .whereType<LevelRewardCarousel>()
              .single;
          final tiles = carousel.descendants().whereType<ItemTile>().toList();
          expect(tiles, hasLength(9));
          expect(
            tiles.every((tile) => tile.rewardTile && tile.width == 40),
            isTrue,
          );
          final rowTiles = screen.rows.first
              .descendants()
              .whereType<ItemTile>();
          expect(rowTiles.single.width, 50);
          final point = game.convertLocalToGlobalCoordinate(
            Vector2(190, screen.scroll.screenY(screen.currentRow!.y) + 125),
          );
          final start = Offset(point.x, point.y);
          final horizontal = await tester.startGesture(start);
          await horizontal.moveBy(const Offset(-80, 0));
          await tester.pump();
          await horizontal.up();
          await tester.pump();
          expect(carousel.offset, greaterThan(0));
          final before = carousel.offset;
          final scrollBefore = screen.scroll.offset;
          final vertical = await tester.startGesture(start);
          await vertical.moveBy(const Offset(0, 70));
          await tester.pump();
          await vertical.up();
          await tester.pump();
          expect(carousel.offset, before);
          expect(screen.scroll.offset, lessThan(scrollBefore));
          carousel.offset = 0;
          screen.scroll.offset = scrollBefore;
          await tester.pump(const Duration(seconds: 1));
        }
        final image = await tester.runAsync(() => frame(game));
        await expectLater(
          image!,
          matchesGoldenFile('goldens/levels_v26_$level.png'),
        );
        image.dispose();
      },
    );
  }
}
