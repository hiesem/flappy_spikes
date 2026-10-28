import 'dart:io';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/levels/tabs/levels_tabs.dart';
import 'package:flappy_spikes/components/levels/tabs/worlds_tab.dart';
import 'package:flappy_spikes/components/menu_screen_chrome.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/run_summary.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/run/screens/versus_intro.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import '../../home_layout_test.dart' show loadFonts;
import '../../versus/s3_13_service_test.dart' show FakeBackend, FakeIdentity;
import '../../versus/s3_13_upload_entry_test.dart' show entry, summary;

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  void gt(
    String name,
    Future<void> Function(FlappySpikesGame) verify, {
    double height = 711,
  }) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(prefs: {'gamesPlayed': 4}, worldHeight: height),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      name,
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
        await flushAndMount(g);
      },
      verify: (g, tester) => tester.runAsync(() => verify(g)),
    );
  }

  for (final height in [568.0, 711.0]) {
    gt(
      'G4b ordered map, furthest scroll, mystery locks, dot and reveal $height',
      (g) async {
        await g.storage.saveWorldsReached(4);
        await g.storage.saveWorldsSeen(3);
        await g.storage.saveBestHoops(63);
        final sounds = <Sfx>[];
        g.sound.onPlay = sounds.add;
        g.openLevels();
        await flushAndMount(g);
        stepGame(g, .3);
        final screen = g.levelsScreen!;
        final area = screen.children.whereType<MenuScrollArea>().firstWhere(
          (a) => a.content.children.whereType<WorldCard>().isNotEmpty,
        );
        final cards = area.content.children.whereType<WorldCard>().toList();
        expect(
          cards.map((c) => c.index),
          orderedEquals(List.generate(10, (i) => i)),
        );
        expect(cards.last.y, greaterThan(cards.first.y));
        expect(cards[3].scene.colour, 0);
        expect(screen.tabs.hasDot(LevelsTab.worlds), isTrue);
        screen.selectTab(LevelsTab.worlds);
        expect(g.storage.worldsSeen, 4);
        expect(screen.tabs.hasDot(LevelsTab.worlds), isFalse);
        expect(area.offset, greaterThan(0));
        expect(
          cards[3].y - area.offset,
          greaterThanOrEqualTo(area.viewport.top),
        );
        expect(
          cards[3].y + 96 - area.offset,
          lessThanOrEqualTo(area.viewport.bottom),
        );
        expect(cards[4].nameText!.text, "GIANT'S DESK");
        for (final card in cards.skip(5)) {
          expect(card.nameText, isNull);
          expect(card.children.whereType<MenuText>().map((t) => t.text), [
            '${card.index + 1}',
          ]);
          expect(card.scene.colour, 0);
        }
        stepGame(g, 1);
        expect(cards[3].scene.colour, 1);
        expect(sounds.where((s) => s == Sfx.lvUp), hasLength(1));
        screen.selectTab(LevelsTab.levels);
        screen.selectTab(LevelsTab.worlds);
        expect(sounds.where((s) => s == Sfx.lvUp), hasLength(1));
        // Exercise every cached scene and the short/tall clipping in headless rendering.
        g.onGameResize(Vector2(320, height));
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        g.render(canvas);
        final picture = recorder.endRecording();
        final image = await picture.toImage(320, height.toInt());
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        final dir = Directory('build/p26')..createSync(recursive: true);
        File(
          '${dir.path}/worlds_${height.toInt()}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      },
      height: height,
    );
  }

  for (final hoops in [0, 19, 20, 179, 180, 214]) {
    gt('G4b run end $hoops actual hoops sets finite worlds and Home hint', (
      g,
    ) async {
      g.achievements.countDebugRuns = true;
      await startRun(g);
      // Score includes bonuses; only hoopsPassed establishes the world.
      final s = summary(hoops);
      g.endRun(s);
      expect(g.storage.worldsReached, (hoops ~/ 20 + 1).clamp(1, 10));
      expect(g.storage.homeLevelsTag, isTrue);
      await g.storage.saveHomeLevelsTag(false);
      g.goHome();
      await flushAndMount(g);
      stepGame(g, .5);
      await startRun(g);
      g.endRun(summary(0));
      expect(g.storage.worldsReached, (hoops ~/ 20 + 1).clamp(1, 10));
      expect(
        g.storage.homeLevelsTag,
        isFalse,
        reason: 'an existing pending dot cannot re-arm the cleared hint',
      );
    });
  }

  gt('G4b debug run cannot unlock SPACE', (g) async {
    await startRun(g);
    g.runDebug.god = true;
    g.endRun(summary(180));
    expect(g.storage.worldsReached, 0);
    expect(g.storage.homeLevelsTag, isFalse);
  });

  gt('G4b new guide meet arms Home hint at run end', (g) async {
    g.achievements.countDebugRuns = true;
    await g.storage.saveWorldsReached(1);
    await startRun(g);
    await g.storage.saveMetElements({...g.storage.metElements, 'heart'});
    g.endRun(summary(0));
    expect(g.storage.homeLevelsTag, isTrue);
  });

  gt('G4b SPACE title on settled intro and results columns only', (g) async {
    for (final space in [false, true]) {
      await g.storage.saveWorldsReached(space ? 10 : 9);
      final intro = VersusIntro(
        myName: 'Mine',
        myLook: Look.defaults,
        myLevel: 1,
        opponent: OpponentRun(
          uid: 'u',
          name: 'Rival',
          score: 2,
          best: 999,
          level: 10,
          timeline: RunTimeline.empty(),
          space: space,
        ),
      );
      g.world.add(intro);
      await flushAndMount(g);
      expect(intro.youPlate.spaceFlyer, space);
      expect(
        intro.oppPlate.spaceFlyer,
        isFalse,
        reason: 'no title on filler names',
      );
      intro.oppPlate.bird = Look.defaults;
      expect(intro.oppPlate.spaceFlyer, space);
      final column = ResultsPlayerColumn(
        name: 'Rival',
        score: 12,
        centreX: 84,
        mine: false,
        space: space,
      );
      g.world.add(column);
      await flushAndMount(g);
      expect(
        column.children.whereType<MenuText>().any(
          (t) => t.text == 'SPACE FLYER',
        ),
        space,
      );
      intro.removeFromParent();
      column.removeFromParent();
      await flushAndMount(g);
    }
  });

  gt('G4b SPACE title appears on the race card but not solo results', (
    g,
  ) async {
    await g.storage.saveWorldsReached(10);
    final solo = summary(3);
    final soloPage = ResultsScreen(summary: solo, model: ResultsModel.of(solo));
    g.world.add(soloPage);
    await flushAndMount(g);
    expect(soloPage.you.space, isFalse);
    expect(soloPage.them, isNull);
    soloPage.removeFromParent();
    await flushAndMount(g);

    final race = RunSummary(
      score: 3,
      hoopsPassed: 3,
      coins: 0,
      bestBefore: 0,
      bestAfter: 3,
      runSeconds: 4,
      cause: MistakeCause.missedHoop,
      hoopIndex: 3,
      timeline: RunTimeline.empty(),
      opponent: OpponentRun(
        uid: 'u',
        name: 'Rival',
        score: 2,
        best: 2,
        level: 1,
        timeline: RunTimeline.empty(),
        space: true,
      ),
    );
    final racePage = ResultsScreen(summary: race, model: ResultsModel.of(race));
    g.world.add(racePage);
    await flushAndMount(g);
    expect(racePage.you.space, isTrue);
    expect(racePage.them!.space, isTrue);
  });

  gt('POL3 first world is already seen', (g) async {
    await g.storage.saveWorldsReached(1);
    expect(g.storage.worldsSeen, 0);
    g.openLevels();
    await flushAndMount(g);
    expect(g.levelsScreen!.tabs.hasDot(LevelsTab.worlds), isFalse);
    g.levelsScreen!.selectTab(LevelsTab.worlds);
    await flushAndMount(g);
    final area = g.levelsScreen!.children.whereType<MenuScrollArea>().firstWhere(
      (a) => a.content.children.whereType<WorldCard>().isNotEmpty,
    );
    expect(area.content.children.whereType<WorldCard>().first.unseen, isFalse);
  });

  gt('G4b bonus score never advances a world', (g) async {
    g.achievements.countDebugRuns = true;
    await startRun(g);
    g.endRun(
      RunSummary(
        score: 500,
        hoopsPassed: 19,
        coins: 0,
        bestBefore: 0,
        bestAfter: 500,
        runSeconds: 60,
        cause: MistakeCause.missedHoop,
        hoopIndex: 19,
        timeline: RunTimeline.empty(),
      ),
    );
    expect(g.storage.worldsReached, 1);
  });

  test(
    'G4b service writes SPACE eligibility from local reached worlds',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      final backend = FakeBackend();
      final identity = FakeIdentity();
      final service = FirebaseVersusService(
        storageOf: () => storage,
        backend: backend,
        identity: identity,
      );
      await service.initialize();
      await service.submitRun(summary(3), Look.defaults);
      expect(backend.writes.last.$2.space, isFalse);
      await storage.saveWorldsReached(10);
      await service.submitRun(summary(4), Look.defaults);
      expect(backend.writes.last.$2.space, isTrue);
      service.dispose();
      await identity.controller.close();
    },
  );

  test(
    'G4b player-doc flag is monotonic and old pools never infer SPACE from score',
    () {
      Map<String, Object?> doc({
        bool space = false,
        Map<String, Object?>? old,
      }) => nextPlayerDoc(
        old: old,
        run: entry(3).toMap(),
        newBest: false,
        name: 'Flappy',
        platform: 'android',
        look: Look.defaults,
        uploadsDay: '2026-10-27',
        uploadsCount: 1,
        space: space,
      );
      expect(doc().containsKey('space'), isFalse);
      expect(doc(space: true)['space'], true);
      expect(doc(old: {'space': true})['space'], true);
      for (final flag in [null, false, true, 'true']) {
        final pool = PoolEntry.fromMap({
          ...entry(200).toMap(),
          'uid': 'u',
          'level': 10,
          'space': ?flag,
        })!;
        expect(pool.toOpponent().space, flag == true);
      }
    },
  );
  test(
    'G4b SPACE and E1 player progression survive the same pool entry and write',
    () {
      final pool = PoolEntry.fromMap({
        ...entry(200).toMap(),
        'uid': 'u',
        'level': 10,
        'plv': 27,
        'space': true,
      })!;
      final opponent = pool.toOpponent();
      expect(opponent.level, 27);
      expect(opponent.space, isTrue);
      final doc = nextPlayerDoc(
        old: null,
        run: entry(3).toMap(),
        newBest: true,
        name: 'Flappy',
        platform: 'android',
        look: Look.defaults,
        uploadsDay: '2026-10-27',
        uploadsCount: 1,
        level: 27,
        space: true,
      );
      expect(doc['level'], 27);
      expect(doc['space'], isTrue);
      final legacy = PoolEntry.fromMap({
        ...entry(200).toMap(),
        'uid': 'u',
        'level': 10,
      })!.toOpponent();
      expect(legacy.level, 0);
      expect(legacy.space, isFalse);
    },
  );
}
