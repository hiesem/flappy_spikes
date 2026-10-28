import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/levels/tabs/levels_tabs.dart';
import 'package:flappy_spikes/components/levels/tabs/album_tab.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import '../../home_layout_test.dart' show loadFonts;

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  void shellTest(
    String name,
    Future<void> Function(FlappySpikesGame) verify, {
    double height = 711,
  }) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame({'gamesPlayed': 4}, height),
      gameSize: Vector2(320, height),
    ).testGameWidget(
      name,
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) => verify(game),
    );
  }

  for (final height in [568.0, 711.0]) {
    shellTest('G4 tabs geometry and Levels host at $height', height: height, (
      game,
    ) async {
      game.openLevels();
      await flushAndMount(game);
      stepGame(game, .3);
      final screen = game.levelsScreen!;
      expect(screen.selectedTab, LevelsTab.levels);
      expect(screen.header.position, Vector2(14, 172));
      expect(screen.header.size, Vector2(292, 84));
      // PRD 2.6 G4 / O69 moves the list top; the existing spike-tip
      // bottom and touch bleed remain part of the LEVELS screen.
      expect(
        screen.scroll.viewport,
        Rect.fromLTWH(0, 264, 320, height - Config.menuSpikeHeight - 264),
      );
      expect(screen.rows, isNotEmpty);
      expect(screen.rows.first.y, greaterThanOrEqualTo(264));
      for (final tab in LevelsTab.values) {
        final button = screen.tabs.buttons[tab]!;
        expect(button.position, Vector2(14 + tab.index * 74, 134));
        expect(button.size, Vector2(70, 28));
        expect(screen.tabs.labels[tab]!.text, tab.label);
        expect(screen.tabs.labels[tab]!.fontSize, 11);
        expect(
          button.color,
          tab == LevelsTab.levels ? Config.menuPink : Config.menuSoft,
        );
      }
      // PRD 933: G6c installs the real album in the G4 host.
      final area = screen.tabScroll(LevelsTab.album)!;
      await flushAndMount(game);
      screen.selectTab(LevelsTab.album);
      expect(area.viewport, screen.scroll.viewport);
      expect(area.bleedBottom, Config.menuSpikeToothDepth);
      expect(
        area.visibleRect.bottom,
        height - Config.menuSpikeHeight + Config.menuSpikeToothDepth,
      );
      expect(
        area.containsPoint(Vector2(160, area.viewport.bottom + 10)),
        isTrue,
      );
      expect(
        area.containsPoint(Vector2(160, area.visibleRect.bottom + 2)),
        isFalse,
      );
    });
  }

  shellTest('G4 tabs switch titles and sound, back goes Home, reopens LEVELS', (
    game,
  ) async {
    final sounds = <Sfx>[];
    game.sound.onPlay = sounds.add;
    game.openLevels();
    await flushAndMount(game);
    stepGame(game, .3);
    final screen = game.levelsScreen!;
    for (final tab in LevelsTab.values.skip(1)) {
      screen.tabs.buttons[tab]!.onPressed();
      expect(screen.selectedTab, tab);
      expect(screen.titleText.text, tab.title);
      expect(
        screen.isActive(),
        isFalse,
        reason: 'hidden Levels list cannot scroll',
      );
      expect(screen.tabs.buttons[tab]!.color, Config.menuPink);
    }
    expect(sounds.where((s) => s == Sfx.skTab), hasLength(3));
    screen.selectTab(LevelsTab.album);
    expect(sounds.where((s) => s == Sfx.skTab), hasLength(3));
    screen.backButton.onPressed();
    await flushAndMount(game);
    stepGame(game, .3);
    expect(game.menuScene, MenuScene.home);
    game.openLevels();
    await flushAndMount(game);
    stepGame(game, .3);
    expect(game.levelsScreen!.selectedTab, LevelsTab.levels);
    expect(game.levelsScreen!.isActive(), isTrue);
  });

  shellTest('G4 opening shell clears Home hint only; dots clear independently', (
    game,
  ) async {
    await game.storage.saveHomeLevelsTag(true);
    await game.storage.saveWorldsReached(3);
    await game.storage.saveMetElements({'normal_hoop', 'heart'});
    game.homeScreen!.refresh();
    await flushAndMount(game);
    expect(game.homeScreen!.levelsNewTag, isA<MenuTag>());
    game.openLevels();
    await flushAndMount(game);
    stepGame(game, .3);
    final screen = game.levelsScreen!;
    expect(game.storage.homeLevelsTag, isFalse);
    expect(screen.tabs.hasDot(LevelsTab.worlds), isTrue);
    expect(screen.tabs.hasDot(LevelsTab.guide), isTrue);
    screen.selectTab(LevelsTab.worlds);
    expect(game.storage.worldsSeen, 3);
    expect(screen.tabs.hasDot(LevelsTab.worlds), isFalse);
    expect(screen.tabs.hasDot(LevelsTab.guide), isTrue);
    screen.selectTab(LevelsTab.guide);
    expect(game.storage.guideSeenCount, 2);
    screen.selectTab(LevelsTab.levels);
    expect(screen.tabs.hasDot(LevelsTab.guide), isFalse);
    screen.backButton.onPressed();
    await flushAndMount(game);
    stepGame(game, .3);
    expect(
      game.homeScreen!.levelsNewTag,
      isNull,
      reason:
          'pending world/guide dots must not re-arm the cleared one-shot hint',
    );
  });

  shellTest(
    'G4 Home tag never in runs 1-3; waits behind a claim and uses existing master',
    (game) async {
      await game.storage.saveHomeLevelsTag(true);
      // POL3: world 1 starts seen; world 2 supplies the pending hint.
      await game.storage.saveWorldsReached(2);
      final home = game.homeScreen!;
      for (var run = 1; run <= 3; run++) {
        game.storage.gamesPlayed = run;
        home.refresh();
        expect(home.levelsNewTag, isNull);
      }
      game.storage.gamesPlayed = 4;
      home.refresh();
      await flushAndMount(game);
      expect(home.levelsNewTag, isA<MenuTag>());
      expect(
        home.levelsNewTag!.children.whereType<MenuText>().single.text,
        'NEW',
      );
      await game.menu.levels.recordRun(10000);
      expect(game.menu.levels.pendingLevelUp, isNotNull);
      home.refresh();
      expect(home.levelsNewTag, isNull);
      expect(
        game.storage.homeLevelsTag,
        isTrue,
        reason: 'claim suppression does not consume hint',
      );
      await game.menu.levels.claim();
      home.refresh();
      await flushAndMount(game);
      expect(home.levelsNewTag, isA<MenuTag>());
      game.reduceMotionOverride = true;
      stepGame(game, .1);
      expect(home.levelsNewTag!.position.x, greaterThan(160));
    },
  );

  shellTest('G4 future tabs host fixed header and independent list band', (
    game,
  ) async {
    game.openLevels();
    await flushAndMount(game);
    stepGame(game, .3);
    final screen = game.levelsScreen!;
    // PRD 933: the real album occupies the fixed G4 header and list.
    final header = screen.children.whereType<AlbumHeader>().single;
    await flushAndMount(game);
    expect(header.position, Vector2(14, 172));
    expect(header.size, Vector2(292, 84));
    screen.selectTab(LevelsTab.album);
    expect(screen.tabIsActive(LevelsTab.album), isTrue);
    expect(screen.isActive(), isFalse);
    screen.active = false;
    screen.selectTab(LevelsTab.worlds);
    expect(screen.selectedTab, LevelsTab.album);
    expect(screen.tabIsActive(LevelsTab.album), isFalse);
  });
}
