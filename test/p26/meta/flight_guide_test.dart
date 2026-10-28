import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/components/levels/tabs/levels_tabs.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/progression/flight_guide.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import '../../helpers.dart';
import '../../home_layout_test.dart' show loadFonts;

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();
  await (FontLoader(
    'Fredoka',
  )..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'))).load();
  test('guide has 32 unique entries in the approved groups', () {
    expect(flightGuideEntries, hasLength(32));
    for (final entry in flightGuideEntries) {
      expect(entry.nameFor({}), '? ? ?');
      expect(entry.ruleFor({}), 'Not met yet.');
      expect(entry.nameFor({entry.id}), entry.name);
      expect(entry.ruleFor({entry.id}), entry.rule);
    }
    expect(flightGuideEntries.map((e) => e.id).toSet(), hasLength(32));
    expect(
      [
        for (final g in ['HOOPS', 'PICK-UPS', 'POWER-UPS', 'RIDES', 'HAZARDS'])
          flightGuideEntries.where((e) => e.group == g).length,
      ],
      [10, 7, 5, 7, 3],
    );
    expect(
      flightGuideMetCount({'heart', 'portal', 'capsule', 'piggy_coins'}),
      1,
    );
    expect(flightGuideHasDot({'heart', 'portal'}, 1), isFalse);
    expect(flightGuideHasDot({'heart', 'portal_space'}, 1), isTrue);
  });

  for (final height in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(prefs: {'gamesPlayed': 4}, worldHeight: height),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      'guide tab seen count at $height',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await game.images.loadAll([
          'achievements/ach_birdwatcher.png',
          for (final ride in RideId.values)
            'achievements/ach_ride_${ride.storageId}.png',
        ]);
        await flushAndMount(game);
      },
      verify: (game, tester) => tester.runAsync(() async {
        await game.storage.saveMetElements({'heart', 'portal', 'capsule'});
        game.openLevels();
        await flushAndMount(game);
        stepGame(game, .3);
        final screen = game.levelsScreen!;
        expect(screen.tabs.hasDot(LevelsTab.guide), isTrue);
        screen.selectTab(LevelsTab.guide);
        await flushAndMount(game);
        expect(game.storage.guideSeenCount, 1);
        game.onGameResize(Vector2(320, height));
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        game.render(canvas);
        final picture = recorder.endRecording();
        final image = await picture.toImage(320, height.toInt());
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/p26')..createSync(recursive: true);
        File(
          '${dir.path}/flight_guide_${height.toInt()}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
        screen.selectTab(LevelsTab.levels);
        expect(screen.tabs.hasDot(LevelsTab.guide), isFalse);
        await game.storage.markElementMet('portal_space');
        screen.sync();
        expect(screen.tabs.hasDot(LevelsTab.guide), isTrue);
      }),
    );
  }

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(prefs: {'gamesPlayed': 4}),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'run records spikes, each portal theme, and unlocks BIRDWATCHER',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final ids = flightGuideEntries.map((e) => e.id).toSet()
        ..remove('spikes')
        ..remove('portal_space');
      await game.storage.saveMetElements(ids);
      game.achievements.countDebugRuns = true;
      final run = await startRun(game);
      expect(game.storage.metElements, contains('spikes'));
      expect(game.achievements.isUnlocked(AchievementId.birdwatcher), isFalse);
      run.events.emit(const RideStarted(RideKind.portal, RideId.space));
      expect(game.storage.metElements, contains('portal_space'));
      expect(game.achievements.isUnlocked(AchievementId.birdwatcher), isTrue);
      for (final id in RideId.values) {
        run.events.emit(RideStarted(RideKind.portal, id));
        expect(game.storage.metElements, contains('portal_${id.storageId}'));
      }
    },
  );
}
