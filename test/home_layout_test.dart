import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Home screen geometry (PRD-1 §4.1 table + alignment rules, §4.2 vertical
/// rule) at the 711 pt reference height and the 568 pt minimum.
Future<void> loadFonts() async {
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  await opificio.load();
}

Rect rectOf(PositionComponent c) {
  final topLeft = c.absolutePositionOfAnchor(Anchor.topLeft);
  return Rect.fromLTWH(topLeft.x, topLeft.y, c.width, c.height);
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  test('Config reproduces the PRD-1 §4.1 table exactly at 711', () {
    const h = 711.0;
    expect(Config.homeCoinPillPositionFor(h), Vector2(14, 58));
    expect(Config.homeGearRectFor(h), const Rect.fromLTWH(268, 58, 38, 38));
    expect(Config.homeTitlePositionFor(h), Vector2(160, 128));
    expect(Config.homeBirdRectFor(h), const Rect.fromLTWH(38, 293, 44, 36));
    expect(Config.homeStartRectFor(h), const Rect.fromLTWH(96, 277, 186, 68));
    expect(Config.homeSlotRectFor(h), const Rect.fromLTWH(96, 347, 186, 32));
    for (var i = 0; i < 4; i++) {
      expect(
        Config.homeTileRectFor(h, i),
        Rect.fromLTWH(14 + 74.0 * i, 456, 70, 92),
      );
    }
    expect(Config.homeTileRectFor(h, 3).right, 306);
    expect(
      Config.homeLeaderboardRectFor(h),
      const Rect.fromLTWH(14, 574, 292, 70),
    );
    expect(Config.homeTrophyRectFor(h), const Rect.fromLTWH(14, 574, 70, 70));
  });

  test('vertical rule: top pinned, bottom rows pinned to the bottom edge', () {
    for (final h in [711.0, 730.0]) {
      // Above 711 the bottom rows keep their 711 distance to the bottom.
      expect(Config.homeLeaderboardRectFor(h).bottom, h - 67);
      expect(Config.homeTileRowTopFor(h), h - 255);
      expect(Config.homeTitlePositionFor(h).y, 128);
    }
    // 568 compresses, 711..568 is monotonic.
    var lastStart = double.infinity;
    for (var h = 711.0; h >= 568; h -= 11) {
      final start = Config.homeStartTopFor(h);
      expect(start, lessThanOrEqualTo(lastStart));
      lastStart = start;
    }
  });

  for (final height in [711.0, 568.0]) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame(
        const {'coins': 1250, 'bestScore': 12, 'gamesPlayed': 34},
        height,
      ),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      'home layout at ${height.toInt()}',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        final h = game.viewHeight;
        expect(h, height);
        final home = game.homeScreen!;

        // Every element sits at its Config rect.
        final pill = rectOf(home.coinPill);
        final gear = rectOf(home.gearButton);
        final bird = rectOf(home.bird);
        final start = rectOf(home.startButton);
        final slot = rectOf(home.slotButton);
        final tiles = home.tiles.map(rectOf).toList();
        final board = rectOf(home.leaderboard);
        final trophy = Config.homeTrophyRectFor(h);
        expect(pill.topLeft, const Offset(14, 58));
        expect(pill.height, 38);
        expect(gear, Config.homeGearRectFor(h));
        expect(bird, Config.homeBirdRectFor(h));
        expect(start, Config.homeStartRectFor(h));
        expect(slot, Config.homeSlotRectFor(h));
        for (var i = 0; i < 4; i++) {
          expect(tiles[i], Config.homeTileRectFor(h, i));
        }
        expect(board, Config.homeLeaderboardRectFor(h));

        // Coin pill: 145 x 38 for "1 250" (the mock's width), grows with
        // the number of digits.
        expect(home.coinPill.label.text, '1 250');
        expect(pill.width, closeTo(145, 1.5));

        // Title + subtitle: centred, 42 pt / 19 pt, tops 128 / 178.
        final title = rectOf(home.title);
        expect(title.top, 128);
        expect(title.center.dx, closeTo(160, 1e-9));
        expect(title.height, closeTo(42, 1e-6), reason: 'line-height 1');
        final subtitle = home.subtitle.map(rectOf).toList();
        expect(subtitle.first.top, 178);
        expect(subtitle.last.bottom, closeTo(178 + 2 * 19 * 0.9, 0.25));

        // --- PRD-1 §4.1 alignment rules -------------------------------------
        // Pill and gear share the 58..96 band.
        expect(pill.top, gear.top);
        expect(pill.bottom, gear.bottom);
        expect(gear.top, 58);
        expect(gear.bottom, 96);
        // Left edges 14: pill, shop tile, trophy tile.
        expect(pill.left, 14);
        expect(tiles.first.left, 14);
        expect(trophy.left, 14);
        expect(board.left, 14);
        // Right edges 306: gear, no-ads tile.
        expect(gear.right, 306);
        expect(tiles.last.right, 306);
        // START centre y == bird centre y.
        expect(start.center.dy, bird.center.dy);
        // Start block (bird + START/slot) centred on x = 160.
        expect((bird.left + start.right) / 2, 160);
        expect(slot.left, start.left);
        expect(slot.right, start.right);
        // 4 tiles of 70 x 92 with 4 pt gaps.
        for (var i = 1; i < 4; i++) {
          expect(tiles[i].left - tiles[i - 1].right, 4);
        }

        // Start block centred between the subtitle band and the tile row.
        final above = start.top - Config.homeStartBandTopFor(h);
        final below = tiles.first.top - slot.bottom;
        expect(above, closeTo(below, 1e-9));

        // --- no overlaps, everything between the (menu) spike strips -------
        final outlinedSlot = slot.inflate(Config.homeSlotOutline);
        final named = <String, Rect>{
          'pill': pill,
          'gear': gear,
          'title': title,
          'subtitle': subtitle.first.expandToInclude(subtitle.last),
          'bird': bird,
          'start': start,
          'slot': slot,
          for (var i = 0; i < 4; i++) 'tile$i': tiles[i],
          'leaderboard': board,
        };
        final keys = named.keys.toList();
        for (var i = 0; i < keys.length; i++) {
          for (var j = i + 1; j < keys.length; j++) {
            final a = named[keys[i]]!;
            final b = named[keys[j]]!;
            if ({keys[i], keys[j]}.containsAll(['start', 'slot'])) {
              continue; // attached by design (2 pt gap under the outline)
            }
            final overlap = a.intersect(b);
            expect(
              overlap.width <= 0 || overlap.height <= 0,
              isTrue,
              reason: '${keys[i]} overlaps ${keys[j]} at $h',
            );
          }
        }
        expect(start.bottom, lessThan(slot.top));
        expect(outlinedSlot.bottom, lessThan(tiles.first.top));
        // The subtitle ink ends ~10 pt above its band top; keep clear of it.
        expect(start.top, greaterThan(subtitle.last.bottom));

        const stripTip = Config.spikeHeight - Config.menuSpikeInset; // 44
        for (final entry in named.entries) {
          expect(entry.value.top, greaterThanOrEqualTo(stripTip),
              reason: '${entry.key} under the ceiling strip at $h');
          expect(entry.value.bottom, lessThanOrEqualTo(h - stripTip),
              reason: '${entry.key} under the ground strip at $h');
          expect(entry.value.left, greaterThanOrEqualTo(0));
          expect(entry.value.right, lessThanOrEqualTo(320));
        }

        // The 711 reference reproduces the PRD table.
        if (h == 711) {
          expect(start, const Rect.fromLTWH(96, 277, 186, 68));
          expect(bird, const Rect.fromLTWH(38, 293, 44, 36));
          expect(slot, const Rect.fromLTWH(96, 347, 186, 32));
          expect(tiles.first.top, 456);
          expect(board.top, 574);
        }
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => createTestGame(const {'coins': 1234567}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'coin pill grows with the balance and stays clear of the gear',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final pill = game.homeScreen!.coinPill;
      expect(pill.label.text, '1 234 567');
      expect(pill.width, greaterThan(145));
      expect(pill.x + pill.width, lessThan(Config.homeGearRectFor(711).left));

      await game.menu.wallet.add(1, CoinSource.play);
      game.update(0);
      expect(pill.label.text, '1 234 568');
    },
  );
}
