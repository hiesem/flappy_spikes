import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Home screen v3 geometry (PRD-home-v3 §3.1 table + alignment rules, the
/// vertical rule) at the 711 pt reference height, 568, 640 and 730.
Future<void> loadFonts() async {
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  await opificio.load();
}

Matcher rectNear(Rect r) => isA<Rect>()
    .having((x) => x.left, 'left', closeTo(r.left, 1e-3))
    .having((x) => x.top, 'top', closeTo(r.top, 1e-3))
    .having((x) => x.width, 'width', closeTo(r.width, 1e-3))
    .having((x) => x.height, 'height', closeTo(r.height, 1e-3));

Rect rectOf(PositionComponent c) {
  final topLeft = c.absolutePositionOfAnchor(Anchor.topLeft);
  return Rect.fromLTWH(topLeft.x, topLeft.y, c.width, c.height);
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  test('Config reproduces the PRD-home-v3 §3.1 table exactly at 711', () {
    const h = 711.0;
    // 2.0 DEVIATION (2026-10-04): gear top-left, pill top-right (the
    // pill position is its top-right corner).
    expect(Config.homeCoinPillPositionFor(h), Vector2(306, 58));
    expect(Config.homeGearRectFor(h), const Rect.fromLTWH(14, 58, 38, 38));
    expect(Config.homeTrophyRectFor(h), const Rect.fromLTWH(60, 58, 38, 38));
    // Owner 2026-10-17: the logo (size S) replaces the title text; the
    // tagline sits under it.
    expect(Config.homeTitlePositionFor(h), Vector2(160, 100));
    expect(Config.homeLogoWidthFor(h), 150);
    expect(Config.homeSubtitlePositionFor(h), Vector2(160, 183));
    expect(Config.homeSubtitleFontSize, 13);
    expect(Config.homeStageRectFor(h), const Rect.fromLTWH(28, 148, 264, 204));
    final plate = Config.homePlateCentreFor(h);
    expect(plate.dx, 160);
    expect(plate.dy, closeTo(254, 0.1));
    expect(Config.homeEmblemScaleFor(h), 0.936);
    expect(Config.homeBirdScaleFor(h), 1.32);
    // PRD-2.2 §2.1: the mode button row (21 + 5) joined the centred START
    // block, so START moved from 390 to 403 (the mode button at 377).
    expect(Config.homeStartRectFor(h), const Rect.fromLTWH(52, 403, 216, 67));
    expect(Config.homeSlotRectFor(h), const Rect.fromLTWH(52, 474, 216, 31));
    expect(Config.homeModeRectFor(h), const Rect.fromLTWH(121, 377, 147, 21));
    expect(Config.homeVsTagRectFor(h), const Rect.fromLTWH(61, 395, 31, 17));
    expect(Config.homeStartFontSize, 34);
    final best = Config.homeFlankRectFor(h, right: false);
    final last = Config.homeFlankRectFor(h, right: true);
    expect(best.left, 14);
    expect(best.width, 70);
    expect(best.top, closeTo(230, 0.1));
    expect(last.right, 306);
    for (var i = 0; i < 4; i++) {
      expect(
        Config.homeTileRectFor(h, i),
        Rect.fromLTWH(14 + 74.0 * i, 562, 70, 92),
      );
    }
    expect(Config.homeTileRectFor(h, 3).right, 306);
    // Mode button + START + slot centred between the emblem bottom (≈ 320)
    // and the tiles: ≈ 57 pt above and below (PRD-2.2 §2.1; 70 before).
    final above = 377 - Config.homeEmblemBottomFor(h);
    final below = 562 - Config.homeSlotRectFor(h).bottom;
    expect(above, closeTo(57, 0.5));
    expect(below, closeTo(57, 0.5));
  });

  test('vertical rule: top pinned, tiles bottom-anchored, START centred', () {
    for (final h in [711.0, 730.0]) {
      expect(Config.homeTileRowTopFor(h), h - 149);
      expect(Config.homeTitlePositionFor(h).y, 100);
      expect(Config.homeStageScaleFor(h), 1);
    }
    // Short screens: the emblem shrinks to 0.78 / 1.1; PRD-2.2 §2.1 (the
    // mode row joined the START block): on the very shortest screens it
    // shrinks a little further so the block keeps 8 pt above and below.
    expect(Config.homeEmblemScaleFor(590), closeTo(0.78, 1e-9));
    expect(Config.homeBirdScaleFor(590), closeTo(1.1, 1e-9));
    expect(Config.homeEmblemScaleFor(568), closeTo(0.709, 0.002));
    for (var h = 568.0; h <= 730; h += 2) {
      final k = Config.homeStageScaleFor(h);
      expect(k, inInclusiveRange(0.75, 1));
      final slot = Config.homeSlotRectFor(h);
      // PRD-2.2 §2.1: the block starts at the mode button.
      final above =
          Config.homeModeRectFor(h).top - Config.homeEmblemBottomFor(h);
      final below = Config.homeTileRowTopFor(h) - slot.bottom;
      expect((above - below).abs(), lessThanOrEqualTo(1.01), reason: '$h');
      expect(
        above,
        greaterThanOrEqualTo(Config.homeStartTightGap - 0.51),
        reason: '$h',
      );
    }
    // 711..568 is monotonic.
    var lastStart = double.infinity;
    for (var h = 711.0; h >= 568; h -= 11) {
      final start = Config.homeStartTopFor(h);
      expect(start, lessThanOrEqualTo(lastStart));
      lastStart = start;
    }
  });

  for (final height in [568.0, 640.0, 711.0, 730.0]) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame(const {
        'coins': 1250,
        'bestScore': 640,
        'lvlIndex': 6,
        'lastScore': 12,
        'gamesPlayed': 34,
        'claimedLevels': ['1', '2', '3', '4', '5', '6'],
      }, height),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      'home v3 layout at ${height.toInt()}',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        final h = game.viewHeight;
        expect(h, height);
        final home = game.homeScreen!;
        // PRD 2.6 G1 / 877 and missions.html §1 reserve 30 pt for the strip.
        final layout = Config.homeLayoutHeightFor(h, missions: true);

        // Every element sits at its Config rect.
        final pill = rectOf(home.coinPill);
        final gear = rectOf(home.gearButton);
        final trophy = rectOf(home.trophyButton);
        final stage = rectOf(home.bird);
        final best = rectOf(home.bestStat);
        final last = rectOf(home.lastStat);
        final start = rectOf(home.startButton);
        final slot = rectOf(home.slotButton);
        final tiles = home.tiles.map(rectOf).toList();
        expect(pill.topRight, const Offset(306, 58));
        expect(pill.height, 38);
        expect(gear, rectNear(Config.homeGearRectFor(h)));
        expect(trophy, rectNear(Config.homeTrophyRectFor(h)));
        expect(stage, rectNear(Config.homeStageRectFor(layout)));
        expect(best, rectNear(Config.homeFlankRectFor(layout, right: false)));
        expect(last, rectNear(Config.homeFlankRectFor(layout, right: true)));
        expect(start, rectNear(Config.homeStartRectFor(layout)));
        expect(slot, rectNear(Config.homeSlotRectFor(layout)));
        for (var i = 0; i < 4; i++) {
          expect(tiles[i], rectNear(Config.homeTileRectFor(h, i)));
        }
        final plate = Config.homePlateCentreFor(layout);
        expect(home.emblem.position.x, closeTo(plate.dx, 1e-3));
        expect(home.emblem.position.y, closeTo(plate.dy, 1e-3));
        expect(
          home.emblem.artScale,
          closeTo(Config.homeEmblemScaleFor(layout), 1e-9),
        );
        expect(home.emblem.level, 6);

        // Coin pill: 145 x 38 for "1 250", grows with the digits.
        expect(home.coinPill.label.text, '1 250');
        expect(pill.width, closeTo(145, 1.5));

        // Logo + subtitle (owner 2026-10-17, size S): centred; the logo is
        // 150 pt wide from 100 where it fits, the tagline 47 pt above the
        // BEST / LAST row (183 on 640 pt and taller).
        final title = rectOf(home.title);
        expect(title.top, 100);
        expect(title.center.dx, closeTo(160, 1e-9));
        expect(title.width, closeTo(Config.homeLogoWidthFor(h), 1e-3));
        final subtitle = rectOf(home.subtitle);
        expect(subtitle.top, closeTo(Config.homeSubtitleTopFor(h), 1e-3));
        expect(subtitle.bottom, lessThan(best.top), reason: 'above BEST');
        expect(subtitle.center.dx, closeTo(160, 1e-9));
        expect(home.subtitle.text, 'FLAP FAST, FLY FAR'); // PRD-2.3 §12

        // BEST / LAST: label + number, BEST gold, LAST the stage fg.
        expect(home.bestStat.value, '640');
        expect(home.lastStat.value, '12');
        expect(home.bestStat.numberText.color, Config.menuGold);
        expect(home.lastStat.numberText.color, game.foregroundColor);

        // --- Alignment rules (§3.1 GUIDES) -----------------------------------
        // Top row band 58..96.
        for (final r in [pill, gear, trophy]) {
          expect(r.top, 58);
          expect(r.bottom, 96);
        }
        // Left margin 14: gear, BEST, Shop tile.
        expect(gear.left, 14);
        expect(best.left, 14);
        expect(tiles.first.left, 14);
        // Right margin 306: pill, LAST, No-ads tile.
        expect(pill.right, 306);
        expect(last.right, 306);
        expect(tiles.last.right, 306);
        // LAST's number is right-aligned on 306, BEST's left on 14.
        final lastNumber = rectOf(home.lastStat.numberText);
        expect(lastNumber.right, closeTo(306, 1e-3));
        expect(rectOf(home.bestStat.numberText).left, closeTo(14, 1e-3));
        // Centre line x 160: title, subtitle, emblem + bird, START, slot.
        expect(stage.center.dx, closeTo(160, 1e-3));
        expect(start.center.dx, 160);
        expect(slot.center.dx, 160);
        expect(slot.left, start.left);
        expect(slot.right, start.right);
        // BEST / LAST centred vertically on the plate centre.
        expect(best.center.dy, closeTo(plate.dy, 1e-3));
        expect(last.center.dy, closeTo(plate.dy, 1e-3));
        // 4 tiles of 70 x 92 with 4 pt gaps.
        for (var i = 1; i < 4; i++) {
          expect(tiles[i].left - tiles[i - 1].right, 4);
        }
        // START block (from the PRD-2.2 mode button) centred between the
        // emblem bottom and the tiles.
        final mode = rectOf(home.modeButton);
        final vsTag = rectOf(home.vsTag);
        expect(mode, rectNear(Config.homeModeRectFor(layout)));
        expect(vsTag, rectNear(Config.homeVsTagRectFor(layout)));
        final above = mode.top - Config.homeEmblemBottomFor(layout);
        final below = Config.homeTileRowTopFor(layout) - slot.bottom;
        expect((above - below).abs(), lessThanOrEqualTo(1.01));

        // --- no overlaps, everything between the (menu) spike strips -------
        // The emblem's ink: wings ±100, LEGEND's gem / flags up to ≈ -85 art
        // units (its faint rays reach further).
        final emblemInk = Rect.fromLTRB(
          plate.dx - 100 * Config.homeEmblemScaleFor(layout),
          plate.dy - 90 * Config.homeEmblemScaleFor(layout),
          plate.dx + 100 * Config.homeEmblemScaleFor(layout),
          Config.homeEmblemBottomFor(layout),
        );
        final named = <String, Rect>{
          'pill': pill,
          'gear': gear,
          'trophy': trophy,
          'title': title,
          'subtitle': subtitle,
          'emblem': emblemInk,
          'best': best,
          'last': last,
          'start': start,
          'mode': mode,
          'vstag': vsTag,
          'slot': slot.inflate(Config.homeSlotOutline),
          for (var i = 0; i < 4; i++) 'tile$i': tiles[i],
        };
        const allowed = {
          // The flank columns sit beside the plate, under the wing tips.
          {'emblem', 'best'},
          {'emblem', 'last'},
          // Attached by design (4 pt gap, the slot's 3 pt outline).
          {'start', 'slot'},
          // PRD-2.2 §2.1: the VS tag sits half outside START's corner.
          {'vstag', 'start'},
          // Owner 2026-10-17 logo layout: the tagline and the logo's soft
          // shadow reach into the emblem's faint outer rays (its ink box
          // spans 90 art units up); the plate itself stays clear.
          {'subtitle', 'emblem'},
          {'title', 'subtitle'},
          {'title', 'emblem'},
        };
        final keys = named.keys.toList();
        for (var i = 0; i < keys.length; i++) {
          for (var j = i + 1; j < keys.length; j++) {
            if (allowed.any((p) => p.containsAll([keys[i], keys[j]]))) {
              continue;
            }
            final a = named[keys[i]]!;
            final b = named[keys[j]]!;
            final overlap = a.intersect(b);
            expect(
              overlap.width <= 0 || overlap.height <= 0,
              isTrue,
              reason: '${keys[i]} overlaps ${keys[j]} at $h',
            );
          }
        }
        expect(start.bottom, lessThan(slot.top));

        const stripTip = Config.spikeHeight - Config.menuSpikeInset; // 44
        for (final entry in named.entries) {
          expect(
            entry.value.top,
            greaterThanOrEqualTo(stripTip),
            reason: '${entry.key} under the ceiling strip at $h',
          );
          expect(
            entry.value.bottom,
            lessThanOrEqualTo(h - stripTip),
            reason: '${entry.key} under the ground strip at $h',
          );
          expect(entry.value.left, greaterThanOrEqualTo(0));
          expect(entry.value.right, lessThanOrEqualTo(320));
        }

        // The 711 reference reproduces the PRD table.
        if (h == 711) {
          // PRD 2.6 G1: the missions reservation shifts the START group.
          expect(start, rectNear(const Rect.fromLTWH(52, 388, 216, 67)));
          expect(slot, rectNear(const Rect.fromLTWH(52, 459, 216, 31)));
          expect(mode, rectNear(const Rect.fromLTWH(121, 362, 147, 21)));
          expect(stage, rectNear(const Rect.fromLTWH(28, 148, 264, 204)));
          expect(tiles.first.top, 562);
        }
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => createTestGame(const {'gamesPlayed': 2}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'pre-unlock Home retains the 2.5 layout',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final home = game.homeScreen!;
      expect(
        rectOf(home.startButton),
        rectNear(const Rect.fromLTWH(52, 403, 216, 67)),
      );
      expect(
        rectOf(home.slotButton),
        rectNear(const Rect.fromLTWH(52, 474, 216, 31)),
      );
      expect(
        rectOf(home.bird),
        rectNear(const Rect.fromLTWH(28, 148, 264, 204)),
      );
    },
  );

  // §3.1 unranked: grey dashed frame, LAST "—" before the first run.
  FlameTester<FlappySpikesGame>(
    () => createTestGame(const {'bestScore': 7}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'unranked home: dashed frame (level 0), BEST 0-9, LAST — before a run',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final home = game.homeScreen!;
      expect(home.emblem.level, 0);
      expect(home.bestStat.value, '7');
      expect(home.lastStat.value, '—');
      expect(game.levelUpPopup, isNull);
      // A run sets LAST.
      await game.storage.saveLastScore(3);
      game.update(0);
      expect(home.lastStat.value, '3');
    },
  );

  // §3.1: 4+ digit numbers shrink to fit the column (clear of LEGEND's
  // wings); 3 digits keep 30 pt.
  FlameTester<FlappySpikesGame>(
    () => createTestGame({
      'bestScore': 6000,
      'lvlIndex': 10,
      'lastScore': 12345,
      'claimedLevels': [for (var l = 1; l <= 10; l++) '$l'],
    }, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'BEST / LAST numbers shrink for 4+ digits',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final home = game.homeScreen!;
      expect(home.emblem.level, 10);
      for (final stat in [home.bestStat, home.lastStat]) {
        final number = rectOf(stat.numberText);
        final shown = stat.numberText.width * stat.numberText.scale.x;
        expect(stat.numberText.scale.x, lessThan(1));
        expect(shown, closeTo(Config.homeFlankNumberMaxWidth, 1e-6));
        expect(number.left, greaterThanOrEqualTo(14 - 1e-6));
        expect(number.left + shown, lessThanOrEqualTo(306 + 1e-6));
      }
      expect(home.bestStat.value, '6 000');
      expect(home.lastStat.value, '12 345');
      // LEGEND's wing tips: x 80 / 240 at the home scale.
      final best = home.bestStat.numberText;
      expect(best.x + best.width * best.scale.x + 14, lessThanOrEqualTo(80));
      final last = home.lastStat;
      expect(last.x + last.numberText.x, greaterThanOrEqualTo(240));

      await game.storage.saveLastScore(999);
      game.update(0);
      expect(home.lastStat.numberText.scale.x, 1);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createTestGame(const {'coins': 1234567}, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'coin pill grows leftwards with the balance and stays clear of the gear',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final pill = game.homeScreen!.coinPill;
      expect(pill.label.text, '1 234 567');
      expect(pill.width, greaterThan(145));
      expect(pill.x + pill.width, 306);
      expect(pill.x, greaterThan(Config.homeGearRectFor(711).right));

      await game.menu.wallet.add(1, CoinSource.play);
      game.update(0);
      expect(pill.label.text, '1 234 568');
      expect(pill.x + pill.width, 306);
    },
  );

  // 2.0 DEVIATION (2026-10-04): the pill is right-anchored on every screen
  // with the shared chrome; its right edge never moves with the balance.
  for (final coins in [0, 1250, 1000000]) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame({'coins': coins}, 711),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      'coin pill right edge stays at 306 for $coins coins (home, shop)',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        final home = game.homeScreen!;
        expect(home.coinPill.balance, coins);
        expect(rectOf(home.coinPill).topRight, const Offset(306, 58));
        expect(home.coinPill.x, greaterThan(home.gearButton.x + 38));

        game.openShop();
        await flushAndMount(game);
        final shop = game.shopScreen!;
        expect(rectOf(shop.coinPill).topRight, const Offset(306, 58));
        expect(rectOf(shop.backButton), const Rect.fromLTWH(14, 58, 38, 38));

        // A balance change mid-screen relayouts the pill leftwards.
        final before = shop.coinPill.width;
        await game.menu.wallet.add(9000000, CoinSource.play);
        game.update(0);
        expect(shop.coinPill.width, greaterThan(before));
        expect(rectOf(shop.coinPill).topRight, const Offset(306, 58));
      },
    );
  }
}
