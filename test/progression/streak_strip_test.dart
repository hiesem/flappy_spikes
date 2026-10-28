import 'dart:ui' as ui;

import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/progression/streak_strip.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/home_moments.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/progression/day_streak.dart';
import 'package:flappy_spikes/run/effects/fetch_flight.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  setUpAll(() async {
    for (final (family, asset) in [
      ('Opificio Neue', 'assets/fonts/Opificio_neue-regular.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });

  test('unseen pre-midnight reward expires on next Home day', () {
    final before = streakLocalDay(DateTime(2026, 10, 27, 23, 59));
    final after = streakLocalDay(DateTime(2026, 10, 28, 0, 1));
    final state = const DayStreak().finishRun(today: before, runNumber: 4);
    expect(state.rewardPending(today: before, runNumber: 5), isTrue);
    expect(state.rewardPending(today: after, runNumber: 5), isFalse);
    final collect = state.collect(
      today: after,
      runNumber: 5,
      canReceiveFeather: true,
      canReceivePiece: true,
    );
    expect(collect.reward, isNull);
    expect(collect.state.streakPaidDay, -1);
  });

  test('grey and reduced-motion flames never advance their animation', () {
    final grey = StreakFlame(lit: false)..update(12);
    final still = StreakFlame(still: true)..update(12);
    final lit = StreakFlame()..update(.25);
    expect(grey.time, 0);
    expect(still.time, 0);
    expect(lit.time, .25);
    expect(StreakFlame.periods, [1.2, .9, .6]);
  });

  FlameTester<FlappySpikesGame>(() => createTestGame()).testGameWidget(
    'game-four gate, explicit card and COLLECT-only payout with duplicate guard',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, tester) async {
      await flushAndMount(game);
      await game.storage.saveGamesPlayed(2);
      await game.recordStreakRun(runNumber: 3);
      game.openStreakCard();
      expect(game.streakCard, isNull);
      expect(game.storage.streakDays, 0);
      await game.storage.saveGamesPlayed(4);
      await game.recordStreakRun(runNumber: 4);
      expect(game.storage.streakDays, 1);
      final before = game.menu.wallet.balance;
      game.openStreakCard();
      await flushAndMount(game);
      expect(game.streakCard!.reward, isFalse);
      expect(game.streakCard!.collectButton, isNull);
      game.closeStreakCard();
      stepGame(game, 2);
      await flushAndMount(game);
      expect(game.streakCard!.reward, isTrue);
      expect(game.menu.wallet.balance, before);
      game.closeStreakCard();
      expect(game.storage.streakPaidDay, -1);
      stepGame(game, 2);
      expect(game.streakCard, isNull); // One automatic popup per visit.
      game.homeMoments.beginVisit(
        HomeVisit(
          day: game.storage.now(),
          gamesPlayed: 4,
          requests: const HomeVisitRequests(streakReward: true),
        ),
      );
      stepGame(game, 2);
      await flushAndMount(game);
      final first = game.collectStreakReward(
        const ui.Rect.fromLTWH(20, 300, 200, 50),
      );
      final duplicate = game.collectStreakReward(
        const ui.Rect.fromLTWH(20, 300, 200, 50),
      );
      await first;
      await duplicate;
      expect(game.menu.wallet.balance, before + 20);
      expect(game.storage.streakPaidDay, game.storage.today);
      stepGame(game, 2);
      expect(game.streakCard, isNull);
    },
  );

  for (final (day, powerup) in [(3, Powerup.bigHoops), (5, Powerup.shield)]) {
    FlameTester<FlappySpikesGame>(() => createTestGame()).testGameWidget(
      'day $day free start persists, flies, and plain START consumes once',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        await flushAndMount(game);
        await game.storage.saveGamesPlayed(4);
        await game.storage.saveStreakDays(day);
        await game.storage.saveStreakLastDay(game.storage.today);
        stepGame(game, 2);
        await flushAndMount(game);
        expect(game.streakCard, isNotNull);
        await game.collectStreakReward(
          const ui.Rect.fromLTWH(20, 300, 200, 50),
        );
        expect(game.streakFreeStart, isTrue);
        expect(game.streakStarter, powerup);
        expect(game.storage.armedPowerup, 'streak:${powerup.name}');
        final reloaded = GameStorage();
        await reloaded.load();
        expect(reloaded.armedPowerup, 'streak:${powerup.name}');
        game.menu.slot.rollForArrival();
        expect(game.streakStarter, powerup);
        await flushAndMount(game);
        expect(game.world.children.whereType<FetchFlight>(), hasLength(1));
        stepGame(game, .8);
        await flushAndMount(game);
        expect(game.homeScreen!.slotButton.shown, powerup);
        expect(game.homeScreen!.slotButton.showsVideo, isFalse);
        expect(game.homeScreen!.slotButton.unavailable, isFalse);
        await game.startRun();
        expect(game.menu.slot.armed, Powerup.none);
      },
    );
  }

  FlameTester<FlappySpikesGame>(
    () => createTestGame({Obf.prefArmedPowerup: 'streak:shield'}),
  ).testGameWidget(
    'collected free start survives launch and slot skips ad with reduced motion',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, tester) async {
      await flushAndMount(game);
      expect(game.streakFreeStart, isTrue);
      game.reduceMotionOverride = true;
      stepGame(game, .5);
      expect(game.homeScreen!.slotButton.showsVideo, isFalse);
      await game.tapPowerupSlot();
      expect(game.storage.armedPowerup, 'none');
      expect(game.state, GameState.playing);
    },
  );

  for (final feathers in [0, 3]) {
    FlameTester<FlappySpikesGame>(() => createTestGame()).testGameWidget(
      'day seven collect resolves inventory at tap, feathers $feathers',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        await flushAndMount(game);
        game.reduceMotionOverride = true;
        await game.storage.saveGamesPlayed(4);
        await game.storage.saveStreakDays(7);
        await game.storage.saveStreakLastDay(game.storage.today);
        stepGame(game, 2);
        await flushAndMount(game);
        expect(game.streakCard, isNotNull);
        await game.storage.saveFeathers(feathers);
        final before = game.menu.wallet.balance;
        await game.collectStreakReward(
          const ui.Rect.fromLTWH(20, 300, 200, 50),
        );
        expect(game.menu.wallet.balance, before + 60);
        expect(game.storage.feathers, feathers == 0 ? 1 : 3);
        expect(game.storage.puzzlePieces, feathers == 0 ? 0 : 1);
        await flushAndMount(game);
        expect(game.world.children.whereType<FetchFlight>(), isEmpty);
      },
    );
  }

  for (final feathers in [0, 3]) {
    FlameTester<FlappySpikesGame>(() => createTestGame()).testGameWidget(
      'day seven inventory reward flies for feathers $feathers',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, _) async {
        await flushAndMount(game);
        await game.storage.saveGamesPlayed(4);
        await game.storage.saveStreakDays(7);
        await game.storage.saveStreakLastDay(game.storage.today);
        await game.storage.saveFeathers(feathers);
        stepGame(game, 2);
        await flushAndMount(game);
        expect(game.streakCard, isNotNull);
        await game.collectStreakReward(
          const ui.Rect.fromLTWH(20, 300, 200, 50),
        );
        await flushAndMount(game);
        expect(game.world.children.whereType<FetchFlight>(), hasLength(1));
        expect(game.storage.feathers, feathers == 0 ? 1 : 3);
        expect(game.storage.puzzlePieces, feathers == 0 ? 0 : 1);
      },
    );
  }

  FlameTester<FlappySpikesGame>(() => createTestGame()).testGameWidget(
    'day seven tile reflects full feather and piece inventories',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, _) async {
      await game.storage.saveGamesPlayed(4);
      await game.storage.saveStreakDays(7);
      await game.storage.saveStreakLastDay(game.storage.today);
      await game.storage.saveFeathers(3);
      await game.storage.savePuzzlePieces(15);
      await flushAndMount(game);
      game.openStreakCard();
      await flushAndMount(game);
      final labels = game.streakCard!.descendants().whereType<MenuText>().map(
        (t) => t.text,
      );
      expect(labels, contains('110'));
    },
  );

  for (final lit in [true, false]) {
    FlameTester<FlappySpikesGame>(() => createTestGame()).testGameWidget(
      'chip golden ${lit ? "lit" : "grey"}',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, tester) async {
        await flushAndMount(game);
        await game.storage.saveGamesPlayed(4);
        await game.storage.saveStreakDays(4);
        await game.storage.saveStreakLastDay(
          game.storage.today - (lit ? 0 : 1),
        );
        final chip = StreakStrip(isActive: () => true);
        game.world.add(chip);
        await flushAndMount(game);
        expect(chip.visible, isTrue);
        expect(chip.y, 102);
        expect(chip.flame.lit, lit);
        expect(chip.pending, lit);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawColor(const ui.Color(0xFFF1F1F1), ui.BlendMode.src);
        canvas.translate(8 - chip.x, 8 - chip.y);
        chip.renderTree(canvas);
        final picture = recorder.endRecording();
        final frame = await tester.runAsync(() => picture.toImage(80, 48));
        await expectLater(
          frame!,
          matchesGoldenFile('goldens/streak_chip_${lit ? "lit" : "grey"}.png'),
        );
        frame.dispose();
        picture.dispose();
      },
    );
  }
}
