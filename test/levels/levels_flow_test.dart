import 'package:flame/extensions.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/levels/level_up_popup.dart';
import 'package:flappy_spikes/components/levels/levels_screen.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flutter/gestures.dart' show TapDownDetails;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../home_layout_test.dart' show loadFonts;

/// PRD-home-v3 §3.3 / §4.3 / §4.4: emblem tap -> LEVELS, the LEVELS list,
/// the LEVEL UP popup and its interim trigger (Q-H1: on home, after a
/// run's return or the first home after the update).
class _Events extends GameServices {
  final List<(String, Map<String, Object>?)> events = [];

  List<Map<String, Object>?> params(String name) => [
    for (final e in events)
      if (e.$1 == name) e.$2,
  ];

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    events.add((name, parameters));
  }
}

TapDownEvent _tapDown() => TapDownEvent(1, _FakeGame(), TapDownDetails());

class _FakeGame extends FlameGame {}

KeyDownEvent _esc() => const KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.escape,
  logicalKey: LogicalKeyboardKey.escape,
  timeStamp: Duration.zero,
);

List<String> _claimed(int upTo) => [for (var l = 1; l <= upTo; l++) '$l'];

/// Lets fire-and-forget persistence writes land.
Future<void> _flush(FlappySpikesGame game) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.value();
  }
  await flushAndMount(game);
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  void levelsTest(
    String name,
    Future<void> Function(FlappySpikesGame game, _Events events, WidgetTester t)
    verify, {
    Map<String, Object> prefs = const {},
    double height = 711,
  }) {
    final events = _Events();
    FlameTester<FlappySpikesGame>(
      () => createTestGame(prefs, height, events),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      name,
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) => verify(game, events, tester),
    );
  }

  // --- §3.3 tap -> LEVELS ----------------------------------------------------

  levelsTest(
    'emblem tap: bird hops, LEVELS opens 0.17 s later, back / Esc home',
    prefs: {'bestScore': 640, 'gamesPlayed': 34, 'claimedLevels': _claimed(6)},
    (game, events, t) async {
      final sounds = <Sfx>[];
      game.sound.onPlay = sounds.add;
      final home = game.homeScreen!;
      // The tap area is the whole emblem stage.
      expect(
        home.bird.containsPoint(Vector2(40, 160)),
        isTrue,
        reason: 'stage corner (28,148)',
      );
      home.bird.onTapDown(_tapDown());
      expect(sounds, [Sfx.flap]);
      expect(home.bird.idle.velocity, lessThan(0));
      stepGame(game, 0.15);
      expect(game.menuScene, MenuScene.home);
      stepGame(game, 0.05);
      await flushAndMount(game);
      expect(game.menuScene, MenuScene.levels);
      expect(events.params('levels_open'), [
        {'source': 'home_emblem'},
      ]);
      final screen = game.levelsScreen!;
      // Fade + 14 pt rise over 0.22 s.
      expect(screen.rise, greaterThan(0));
      stepGame(game, 0.3);
      expect(screen.rise, 0);
      expect(screen.opacity, 1);
      expect(screen.titleText.text, 'LEVELS');
      // LEVELS has no coin pill; the corner box shows the back chevron.
      expect(game.coinPill.opacity, 0);
      expect(game.cornerBox.gearMix, 0);

      sounds.clear();
      game.onKeyEvent(_esc(), {});
      expect(sounds, [Sfx.skClose]);
      expect(game.levelsScreen, isNull);
      expect(game.menuScene, MenuScene.home);
      await flushAndMount(game);
      stepGame(game, 0.3);
      expect(game.coinPill.opacity, 1);

      // The back button too.
      game.openLevels();
      await flushAndMount(game);
      stepGame(game, 0.3);
      game.levelsScreen!.backButton.onPressed();
      expect(game.menuScene, MenuScene.home);
    },
  );

  // --- §4.4 list -------------------------------------------------------------

  levelsTest(
    'LEVELS: header, row states, opens scrolled to the current row',
    prefs: {'bestScore': 640, 'gamesPlayed': 34, 'claimedLevels': _claimed(6)},
    (game, events, t) async {
      game.openLevels();
      await flushAndMount(game);
      stepGame(game, 0.3);
      final screen = game.levelsScreen!;
      final header = screen.header;
      expect(header.nameText.text, 'FALCON');
      expect(header.statsText.text, 'BEST 640 · GAMES 34');
      expect(header.barText.text, '160 TO HAWK');
      expect(header.progress, closeTo(40 / 200, 1e-9));
      expect(
        header.position,
        Config.levelsHeaderRect.topLeft.toVector2(),
      );

      expect(screen.rows, hasLength(10));
      expect(screen.rows.first.def.name, 'EGG');
      for (final row in screen.rows) {
        final l = row.def.level;
        expect(
          row.state,
          l < 6
              ? LevelRowState.reached
              : l == 6
              ? LevelRowState.current
              : LevelRowState.locked,
        );
        // Static rows are pictures; only the current row animates.
        expect(row.picture == null, l == 6);
        expect(row.liveEmblem != null, l == 6);
        expect(row.bird != null, l == 6);
      }
      expect(screen.rows[3].chipLabel, '+250');
      expect(screen.rows[9].chipLabel, '+5 000');
      expect(screen.currentRow, screen.rows[5]);

      // Scrolled so the current row is in the viewport.
      final scroll = screen.scroll;
      final row = screen.rows[5];
      final top = scroll.screenY(row.y);
      expect(top, greaterThanOrEqualTo(scroll.viewport.top));
      expect(
        top + row.height,
        lessThanOrEqualTo(scroll.viewport.bottom),
      );
      expect(scroll.offset, greaterThan(0));
      // The list scrolls to the bottom spike tips.
      expect(scroll.viewport.top, Config.levelsListTop);
      expect(scroll.viewport.bottom, 711 - Config.menuSpikeHeight);
      expect(scroll.scrollable, isTrue);
    },
  );

  levelsTest(
    'LEVELS unranked: no current row, top of the list, EGG next',
    prefs: {'bestScore': 4, 'gamesPlayed': 2},
    height: 568,
    (game, events, t) async {
      game.openLevels();
      await flushAndMount(game);
      stepGame(game, 0.3);
      final screen = game.levelsScreen!;
      expect(screen.currentRow, isNull);
      expect(screen.header.nameText.text, 'UNRANKED');
      expect(screen.header.barText.text, '6 TO EGG');
      expect(screen.scroll.offset, 0);
      expect(
        screen.rows.every((r) => r.state == LevelRowState.locked),
        isTrue,
      );
    },
  );

  levelsTest(
    'LEVELS at LEGEND: MAX LEVEL, scrolled to the last row',
    prefs: {'bestScore': 6000, 'claimedLevels': _claimed(10)},
    height: 568,
    (game, events, t) async {
      game.openLevels();
      await flushAndMount(game);
      stepGame(game, 0.3);
      final screen = game.levelsScreen!;
      expect(screen.header.barText.text, 'MAX LEVEL');
      expect(screen.header.progress, 1);
      expect(screen.scroll.offset, screen.scroll.maxOffset);
    },
  );

  // --- §4.3 popup + Q-H1 trigger -----------------------------------------------

  levelsTest(
    'catch-up on the first home: one popup paying every reached level',
    prefs: {'bestScore': 640, 'coins': 100},
    (game, events, t) async {
      final sounds = <Sfx>[];
      game.sound.onPlay = sounds.add;
      final home = game.homeScreen!;
      // Until the claim, home shows the last claimed level (none).
      expect(home.emblem.level, 0);
      expect(game.levelUpPopup, isNull);
      stepGame(game, Config.levelUpSettleDelay + 0.05);
      await flushAndMount(game);
      final popup = game.levelUpPopup!;
      expect(popup.pending.toLevel, 6);
      expect(popup.pending.reward, 50 + 100 + 150 + 250 + 400 + 600);
      expect(sounds, contains(Sfx.skBuyEpic));
      expect(events.params('level_up'), [
        {'level': 6, 'best': 640},
      ]);
      expect(popup.nameText.text, 'FALCON');
      expect(popup.articleText.text, 'YOU ARE NOW A');
      expect(popup.nextText.text, 'Next: HAWK at 800');
      expect(popup.claimText.text, '+1 550');
      // Popups pause the idle motion.
      expect(game.liveMotionPaused, isTrue);
      // Confetti 0.18 s in: 90 pieces for lv 5-8.
      stepGame(game, 0.2);
      await flushAndMount(game);
      expect(popup.confetti, isNotNull);
      expect(popup.confetti!.count, 90);

      // CLAIM: paid, all claimed, coins fly and count up, emblem pops.
      popup.claimButton.onPressed();
      await _flush(game);
      expect(game.levelUpPopup, isNull);
      expect(game.menu.wallet.balance, 1650);
      expect(game.storage.claimedLevels, {1, 2, 3, 4, 5, 6});
      expect(game.menu.levels.pendingLevelUp, isNull);
      expect(events.params('level_reward_claimed'), [
        {'level': 6, 'coins': 1550},
      ]);
      final reward = game.coinReward!;
      expect(reward.amount, 1550);
      expect(reward.level, 6);
      expect(game.coinPill.held, isTrue);
      // The emblem upgrades with its pop after the count-up (§4.3).
      expect(home.emblem.level, 0);
      expect(home.popping, isFalse);
      while (game.coinReward != null) {
        stepGame(game, 0.05);
        await flushAndMount(game);
      }
      expect(game.coinPill.shownBalance, 1650);
      expect(home.emblem.level, 6);
      expect(home.popping, isTrue);
      expect(home.emblem.popScale, closeTo(0.6, 0.1));
      stepGame(game, Config.homeEmblemPopDuration + 0.05);
      await flushAndMount(game);
      expect(home.popping, isFalse);
      expect(home.emblem.popScale, 1);
      // Never again.
      stepGame(game, 2);
      expect(game.levelUpPopup, isNull);
    },
  );

  levelsTest(
    '✕ also claims (the reward is never lost); Esc too',
    prefs: {'bestScore': 55, 'coins': 0},
    (game, events, t) async {
      stepGame(game, 0.5);
      await flushAndMount(game);
      final popup = game.levelUpPopup!;
      expect(popup.pending.reward, 150); // EGG + CHICK
      final sounds = <Sfx>[];
      game.sound.onPlay = sounds.add;
      popup.closeButton.onPressed();
      await _flush(game);
      expect(sounds.first, Sfx.skClose);
      expect(game.levelUpPopup, isNull);
      expect(game.menu.wallet.balance, 150);
      expect(game.storage.claimedLevels, {1, 2});

      // Debug LEVEL UP: next threshold -> popup at once; Esc claims.
      await game.menu.levels.debugForceLevelUp();
      game.openLevelUpPopup();
      await flushAndMount(game);
      expect(game.levelUpPopup!.pending.toLevel, 3);
      expect(game.levelUpPopup!.articleText.text, 'YOU ARE NOW A');
      game.onKeyEvent(_esc(), {});
      await _flush(game);
      expect(game.levelUpPopup, isNull);
      expect(game.menu.wallet.balance, 300);
    },
  );

  levelsTest(
    'a run crossing several levels: one popup for the highest, summed',
    prefs: {
      'bestScore': 20,
      'coins': 0,
      'claimedLevels': _claimed(1),
    },
    (game, events, t) async {
      stepGame(game, 1);
      expect(game.levelUpPopup, isNull, reason: 'EGG already claimed');
      await game.startRun();
      game.score = 120; // CHICK + FLEDGLING in one run
      game.onBirdHit();
      await _flush(game);
      expect(game.storage.lastScore, 120);
      stepGame(game, 1);
      expect(game.levelUpPopup, isNull, reason: 'not on game over');
      game.goHome();
      await flushAndMount(game);
      final home = game.homeScreen!;
      expect(home.lastStat.value, '120');
      expect(home.bestStat.value, '120');
      expect(home.emblem.level, 1, reason: 'old level until claimed');
      stepGame(game, Config.levelUpSettleDelay + 0.1);
      await flushAndMount(game);
      final popup = game.levelUpPopup!;
      expect(popup.pending.fromLevel, 1);
      expect(popup.pending.toLevel, 3);
      expect(popup.pending.reward, 100 + 150);
      expect(popup.nameText.text, 'FLEDGLING');
      popup.claimButton.onPressed();
      await _flush(game);
      // +120 run coins, +250 rewards.
      expect(game.menu.wallet.balance, 370);
      expect(game.homeScreen!.emblem.level, 1, reason: 'until the pop');
      stepGame(game, 4);
      await flushAndMount(game);
      expect(game.homeScreen!.emblem.level, 3);
    },
  );

  levelsTest(
    'no double popups: the no-ads launch popup goes first',
    prefs: {'bestScore': 15, 'installDay': 1},
    (game, events, t) async {
      expect(game.noAdsPopup, isNotNull);
      stepGame(game, 2);
      expect(game.levelUpPopup, isNull);
      game.closeNoAdsPopup();
      await flushAndMount(game);
      stepGame(game, 0.2);
      expect(game.levelUpPopup, isNull, reason: 'home must settle first');
      stepGame(game, Config.levelUpSettleDelay);
      await flushAndMount(game);
      expect(game.levelUpPopup, isNotNull);
      expect(game.levelUpPopup!.articleText.text, 'YOU ARE NOW AN');
      // While it is up nothing else opens over home.
      game.openNoAdsPopup();
      expect(game.noAdsPopup, isNull);
      game.openSettings();
      expect(game.menuScene, MenuScene.home);
      game.tapHomeEmblem();
      stepGame(game, 0.3);
      expect(game.levelsScreen, isNull);
      expect(
        game.world.children.query<LevelUpPopup>(),
        hasLength(1),
      );
    },
  );

  levelsTest(
    'no popup while LEVELS / Shop is up; it shows back on home',
    prefs: {'bestScore': 15},
    (game, events, t) async {
      game.openShop();
      await flushAndMount(game);
      stepGame(game, 1);
      expect(game.levelUpPopup, isNull);
      game.closeShop();
      await flushAndMount(game);
      stepGame(game, 0.6);
      await flushAndMount(game);
      expect(game.levelUpPopup, isNotNull);
    },
  );

  levelsTest(
    'popup at LEGEND: highest-level line, 140 confetti',
    prefs: {'bestScore': 5000, 'claimedLevels': _claimed(9)},
    (game, events, t) async {
      final sounds = <Sfx>[];
      game.sound.onPlay = sounds.add;
      stepGame(game, 0.4);
      await flushAndMount(game);
      final popup = game.levelUpPopup!;
      expect(sounds, contains(Sfx.skBuyLegendary));
      expect(popup.nextText.text, 'The highest level. Legendary!');
      expect(popup.claimText.text, '+5 000');
      stepGame(game, 0.2);
      expect(popup.confetti!.count, 140);
    },
  );

  // --- §3.2 reduce motion ------------------------------------------------------

  levelsTest(
    'reduce motion: emblem static (no sweep, t frozen), no popup confetti',
    prefs: {'bestScore': 900, 'claimedLevels': _claimed(6)},
    (game, events, t) async {
      game.reduceMotionOverride = true;
      final home = game.homeScreen!;
      for (var i = 0; i < 60; i++) {
        game.update(1 / 10);
        expect(home.emblem.t, 0);
        expect(home.emblem.shine, isFalse);
      }
      // Level 7 (HAWK) is owed: the popup opens without confetti.
      await flushAndMount(game);
      final popup = game.levelUpPopup!;
      stepGame(game, 0.5);
      expect(popup.confetti, isNull);
      popup.claimButton.onPressed();
      await _flush(game);

      // Motion on: the emblem's clock runs and its sweep shines.
      game.reduceMotionOverride = false;
      stepGame(game, 0.5);
      expect(home.emblem.t, greaterThan(0));
      expect(home.emblem.shine, isTrue);
    },
  );

  levelsTest(
    'the emblem idle pauses under popups',
    prefs: {'bestScore': 30, 'claimedLevels': _claimed(1), 'installDay': 1},
    (game, events, t) async {
      expect(game.noAdsPopup, isNotNull);
      final home = game.homeScreen!;
      final t0 = home.emblem.t;
      stepGame(game, 1);
      expect(home.emblem.t, t0);
      game.closeNoAdsPopup();
      stepGame(game, 1);
      expect(home.emblem.t, greaterThan(t0));
    },
  );

  levelsTest(
    'LAST is the score of the most recent run (persisted)',
    prefs: {'bestScore': 9},
    (game, events, t) async {
      expect(game.homeScreen!.lastStat.value, '—');
      await game.startRun();
      game.score = 4;
      game.onBirdHit();
      await _flush(game);
      expect(game.storage.lastScore, 4);
      game.goHome();
      await flushAndMount(game);
      expect(game.homeScreen!.lastStat.value, '4');
      expect(game.homeScreen!.bestStat.value, '9');
    },
  );
}
