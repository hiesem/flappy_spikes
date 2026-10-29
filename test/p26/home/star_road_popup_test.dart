import 'dart:ui' show Color;

import 'package:flappy_spikes/components/progression/star_road_popup.dart';
import 'package:flappy_spikes/components/star_road/star_road_art.dart';
import 'package:flappy_spikes/components/ui/confetti.dart';
import 'package:flappy_spikes/components/ui/mystery_box.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/progression/star_road.dart';
import 'package:flappy_spikes/skins/look.dart' show Rarity;
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import '../../levels/progression_fixture.dart';

const _claimedThrough8 = <int>{1, 2, 3, 4, 5, 6, 7, 8};

StarRoad _road(int xp, {Set<int> claimed = _claimedThrough8}) =>
    StarRoad(season: 1, xp: xp, claimed: claimed);

FlameTester<FlappySpikesGame> _tester(double height) =>
    FlameTester<FlappySpikesGame>(
      () => createTestGame(const {}, height),
      gameSize: Vector2(Config.worldWidth, height),
    );

Future<StarRoadPopup> _mount(
  FlappySpikesGame game, {
  required StarRoad road,
  bool reduceMotion = false,
  void Function()? onDismiss,
  void Function()? onGo,
}) async {
  game.reduceMotionOverride = reduceMotion;
  final popup = StarRoadPopup(
    road: road,
    onGo: onGo ?? () {},
    onDismiss: onDismiss ?? () {},
  );
  game.world.add(popup);
  await flushAndMount(game);
  return popup;
}

void _suite(double height) {
  final tester = _tester(height);

  tester.testGameWidget(
    'P1 card fits and shows one waiting tier',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      final popup = await _mount(game, road: _road(72));
      stepGame(game, 2);
      await flushAndMount(game);

      expect(popup.size, Vector2(Config.worldWidth, height));
      expect(popup.cardHeight, 364);
      expect(popup.card.height, 364);
      expect(popup.card.x, (Config.worldWidth - Config.p1PopupWidth) / 2);
      expect(popup.card.y, greaterThanOrEqualTo(0));
      expect(popup.card.y + popup.card.height, lessThanOrEqualTo(height));
      expect(popup.claimable, [9]);
      expect(popup.shownTiers, [9]);
      expect(popup.hiddenTiers, 0);
      expect(popup.tiles, hasLength(1));
      expect(popup.titleText, 'TIER 9 REACHED');
      expect(popup.subtitleText, 'A REWARD IS WAITING');
      expect(popup.title.text, 'TIER 9 REACHED');
      expect(popup.subtitle.text, 'A REWARD IS WAITING');
      expect(popup.tiles.single.label, '40 COINS');
      expect(popup.opacity, greaterThan(0));
    },
  );

  tester.testGameWidget(
    'three tiles plus a +N tile and the multi-tier texts',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      final popup = await _mount(game, road: _road(88));
      stepGame(game, 2);
      await flushAndMount(game);

      expect(popup.claimable, [9, 10, 11]);
      expect(popup.shownTiers, [9, 10, 11]);
      expect(popup.hiddenTiers, 0);
      expect(popup.tiles, hasLength(3));
      expect(popup.titleText, 'TIERS 9\u201311 REACHED');
      expect(popup.subtitleText, '3 REWARDS ARE WAITING');
      expect(popup.tiles[0].label, '40 COINS');
      expect(popup.tiles[1].label, 'MYSTERY');
      expect(popup.tiles[2].label, '45 COINS');
      expect(popup.tiles[0].position.x, lessThan(popup.tiles[1].position.x));
      expect(popup.tiles[1].position.x, lessThan(popup.tiles[2].position.x));

      popup.removeFromParent();
      final many = await _mount(game, road: _road(104));
      stepGame(game, 2);
      await flushAndMount(game);
      expect(many.claimable, [9, 10, 11, 12, 13]);
      expect(many.shownTiers, [9, 10, 11]);
      expect(many.hiddenTiers, 2);
      expect(many.tiles, hasLength(4));
      expect(many.tiles.last.label, '+2');
      expect(many.titleText, 'TIERS 9\u201313 REACHED');
      expect(many.subtitleText, '5 REWARDS ARE WAITING');
    },
  );

  tester.testGameWidget(
    'item tiers stay a mystery in their rarity colours',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      final popup = await _mount(game, road: _road(88));
      stepGame(game, 2);
      await flushAndMount(game);

      final rare = popup.tiles[1];
      expect(rare.rarity, Rarity.rare);
      expect(rare.label, 'MYSTERY');
      expect(rare.border, Rarity.rare.color);
      expect(rare.background, const Color(0xFFF4F4F4));
      final box = rare.descendants().whereType<MysteryBoxComponent>().single;
      expect(box.look.label, isNull);
      expect(box.look.main, Rarity.rare.color);
      expect(popup.title.text.toLowerCase(), isNot(contains('rare')));
      expect(popup.subtitle.text.toLowerCase(), isNot(contains('rare')));
    },
  );

  tester.testGameWidget(
    'reduced motion keeps the content but freezes every pose and skips confetti',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      final popup = await _mount(
        game,
        road: _road(88),
        reduceMotion: true,
      );
      stepGame(game, 2.4);
      await flushAndMount(game);

      expect(popup.title.text, 'TIERS 9\u201311 REACHED');
      expect(popup.subtitle.text, '3 REWARDS ARE WAITING');
      expect(popup.tiles, hasLength(3));
      expect(popup.descendants().whereType<ConfettiBurst>(), isEmpty);
      expect(popup.rays.phase, 0);
      expect(popup.rays.motion(), isFalse);
      expect(popup.cardPose.scale, 1);
      expect(popup.badge.position, Vector2(140, 53));
      expect(popup.badge.scale.x, 1);
      expect(popup.badge.angle, 0);
      final badgeNodes = popup.badge.children
          .whereType<StarRoadTierNode>()
          .toList();
      expect(
        badgeNodes.map((node) => node.tier).toList(),
        [11],
        reason: 'exactly one tier plate after the reduced-motion jump',
      );
      expect(popup.goButton.position, Vector2(16, 298));
      expect(popup.goPulse.scale, 1);
      expect(popup.goPulse.k, 0);
      expect(popup.goStreak.progress, isNull);
      for (final tile in popup.tiles) {
        expect(tile.opacity, 1);
        expect(tile.scale.x, 1);
        expect(tile.scale.y, 1);
      }
    },
  );

  tester.testGameWidget(
    'GO and the close box fire their callbacks',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      var go = 0;
      var dismiss = 0;
      late final StarRoadPopup popup;
      popup = await _mount(
        game,
        road: _road(72),
        onGo: () {
          go++;
          // The real game removes the card as the road opens; the puff must
          // outlive it (it is added to the world, not the popup).
          popup.removeFromParent();
        },
        onDismiss: () => dismiss++,
      );
      stepGame(game, 1.7);
      await flushAndMount(game);

      popup.closeButton.onPressed();
      expect(dismiss, 1);
      expect(go, 0);
      expect(popup.active, isTrue);

      popup.goButton.onPressed();
      expect(go, 1);
      await flushAndMount(game);
      expect(
        game.world.children.whereType<ConfettiBurst>(),
        isNotEmpty,
        reason: 'GO adds its star puff to the world, so removing the popup '
            'does not take the puff with it',
      );
    },
  );
}

void main() {
  _suite(568);
  _suite(711);

  // region P26-G6f
  final starHome = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      prefs: trackPrefs({
        'gamesPlayed': 3,
        'firstSessionDone': true,
        'playerLevel': 1,
        'claimedLevels': ['1'],
        'starRoadSeason': 1,
        'starRoadXp': 8,
      }),
      worldHeight: Config.worldHeight,
      clock: () => DateTime(2026, 11, 1, 12),
    ),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );

  starHome.testGameWidget(
    'the real Home flow opens the Star Road popup and GO opens the road',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      final sounds = <Sfx>[];
      game.sound.onPlay = sounds.add;
      game.reduceMotionOverride = true;
      stepGame(game, Config.levelUpSettleDelay + .2);
      await flushAndMount(game);

      final popup = game.starRoadPopup;
      expect(popup, isNotNull);
      expect(popup!.claimable, [1]);
      expect(popup.title.text, 'TIER 1 REACHED');
      expect(popup.subtitle.text, 'A REWARD IS WAITING');
      expect(game.storage.starRoadPopupDay, game.storage.today);
      stepGame(game, 1.2);
      await flushAndMount(game);
      expect(
        sounds,
        containsAll([Sfx.skDialog, Sfx.lvUp, Sfx.vsPop]),
        reason: 'O91: card pop, landing burst and one cue per tile',
      );

      // The opener is not a per-frame rebuild: the same card stays up.
      stepGame(game, .5);
      await flushAndMount(game);
      expect(game.starRoadPopup, same(popup));

      popup.goButton.onPressed();
      await flushAndMount(game);
      expect(popup.active, isFalse);
      expect(sounds, contains(Sfx.skTap));
      expect(game.starRoadPopup, isNull);
      expect(game.starRoadScreen, isNotNull);
      expect(
        game.world.children.whereType<ConfettiBurst>(),
        isEmpty,
        reason: 'reduced motion keeps GO free of confetti (O91)',
      );

      expect(game.handleBack(), isTrue);
      await flushAndMount(game);
      expect(game.starRoadScreen, isNull);
      expect(game.starRoadPopup, isNull);
      expect(game.menuScene, MenuScene.home);
      expect(game.homeScreen!.active, isTrue);
      expect(game.homeScreen!.opacity, 1);
    },
  );

  starHome.testGameWidget(
    'the real Home flow Back closes the popup and spends the day',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      final sounds = <Sfx>[];
      game.sound.onPlay = sounds.add;
      game.reduceMotionOverride = true;
      stepGame(game, Config.levelUpSettleDelay + .2);
      await flushAndMount(game);

      expect(game.starRoadPopup, isNotNull);
      expect(game.modalPopupOpen, isTrue);
      expect(game.handleBack(), isTrue);
      await flushAndMount(game);

      expect(game.starRoadPopup, isNull);
      expect(game.starRoadScreen, isNull);
      expect(game.modalPopupOpen, isFalse);
      expect(sounds, contains(Sfx.skClose));
      expect(game.storage.starRoadPopupDay, game.storage.today);
    },
  );

  starHome.testGameWidget(
    'the real Home flow ✕ closes the popup and spends the day',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      final sounds = <Sfx>[];
      game.sound.onPlay = sounds.add;
      game.reduceMotionOverride = true;
      stepGame(game, Config.levelUpSettleDelay + .2);
      await flushAndMount(game);

      final popup = game.starRoadPopup;
      expect(popup, isNotNull);
      popup!.closeButton.onPressed();
      await flushAndMount(game);

      expect(game.starRoadPopup, isNull);
      expect(game.starRoadScreen, isNull);
      expect(sounds, contains(Sfx.skClose));
      expect(game.storage.starRoadPopupDay, game.storage.today);
      stepGame(game, Config.levelUpSettleDelay + .5);
      await flushAndMount(game);
      expect(
        game.starRoadPopup,
        isNull,
        reason: 'at most one Star Road popup a day (O75)',
      );
    },
  );
  // endregion
}
