// PRD-2.3.1 §12.5 / §12.9 UI: the unlock toasts queue on the results page
// (after the LEVEL UP and its CLAIM), one pill at a time, "+N more" past 5;
// the shop toast shows at once; the Home medal button sits right of the
// trophy without overlap at 568 and 730 and opens the native list. Plus the
// §12.3 persistence (round trip, resetMenuState clears, Delete my data keeps).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/components/home/home_screen.dart';
import 'package:flappy_spikes/achievements/achievement_toast.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show loadFonts;
import '../skin_shop_flow_test.dart' show allSeen, openSkinShop;

const _evidence =
    '/home/killerhis/Projects/flappyspikes/.worktrees/briefs9/evidence/wpE';

/// Renders the game at 2× into the evidence folder (outside git).
Future<void> shot(FlappySpikesGame game, WidgetTester t, String name) =>
    t.runAsync(() => _shot(game, name));

Future<void> _shot(FlappySpikesGame game, String name) async {
  final size = Vector2(640, (game.viewHeight * 2).roundToDouble());
  game.onGameResize(size);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.x, size.y),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  final image = await recorder.endRecording().toImage(
    size.x.toInt(),
    size.y.toInt(),
  );
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  // Evidence only: CI has no such folder, so a write failure never fails
  // the test.
  try {
    final file = File('$_evidence/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  } on FileSystemException catch (_) {}
}

/// Opens the list instead of the plugin.
class _ListSpy extends AnalyticsSpy {
  int opened = 0;
  @override
  Future<ShowAchievementsResult> showAchievements() async {
    opened++;
    return ShowAchievementsResult.opened;
  }
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();
  late _ListSpy spy;
  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
    double height = 568,
  }) => FlameTester<FlappySpikesGame>(() {
    spy = _ListSpy();
    return createRunTestGame(prefs: prefs, services: spy, worldHeight: height);
  }, gameSize: Vector2(320, height));

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
    try {
      await g.images.loadAll([for (final a in AchievementId.values) a.asset]);
    } catch (_) {} // before the §12.6 export (the toast draws without)
    g.achievements.countDebugRuns = true;
  }

  /// A run that ends with [score] on the results page.
  Future<void> play(FlappySpikesGame g, int score) async {
    final run = await startRun(g);
    run.ctx.addScore(score);
    killRunThroughSaves(g);
    await declineRevive(g);
    await flushAndMount(g);
    expect(g.state, GameState.results);
  }

  tester(
    prefs: const {
      'lvlIndex': 1, // PRD-2.6 J5 explicit track state.
      'claimedLevels': ['1'],
    },
  ).testGameWidget(
    '§12.5 the run\'s toasts wait for the LEVEL UP and its CLAIM, then show '
    'one at a time',
    setUp: boot,
    verify: (g, w) async {
      g.runDebug.ignoreGates = false; // PRD-2.6 J3 counting level-up fixture.
      await play(g, 60); // J9: EGG + CHICK score thresholds earned.
      // PRD-2.3.1 §19.2: the run unlocks one (EGG); CHICK waits in
      // achPending. A second pill (e.g. the jackpot's) queues behind it.
      expect(g.achievements.toastQueue.map((a) => a.key), ['rank_egg']);
      expect(g.storage.achPending, ['rank_chick']);
      g.achievements.toastQueue.add(AchievementId.rankChick);
      expect(g.resultsScreen!.model.levelUp, isTrue);
      var claimSeen = false;
      for (var i = 0; i < 900; i++) {
        final page = g.resultsScreen!;
        expect(
          g.achievementToast == null || !page.claimShowing,
          isTrue,
          reason: 'no toast while CLAIM waits',
        );
        if (page.claimShowing) {
          claimSeen = true;
          stepGame(g, 1); // it keeps waiting
          expect(g.achievementToast, isNull);
          page.claimButton.onPressed();
        }
        if (g.achievementToast != null) break;
        g.update(1 / 60);
      }
      expect(claimSeen, isTrue);
      await flushAndMount(g);
      final t = g.achievementToast!;
      expect(t.current, AchievementId.rankEgg);
      expect(t.label, 'ACHIEVEMENT UNLOCKED');
      expect(t.title, 'EGG');
      expect(t.points, '+5');
      stepGame(g, 1);
      await shot(g, w, 's12_toast_results_568');
      stepGame(g, Config.achToastDuration - .9);
      expect(g.achievementToast!.current, AchievementId.rankChick);
      // Tapping dismisses it early.
      g.achievementToast!.dismiss();
      stepGame(g, Config.achToastSlide + .05);
      expect(g.achievementToast, isNull);
    },
  );

  tester().testGameWidget(
    '§12.5 at most one pill; more than 5 queued: the 5th reads "+N more"',
    setUp: boot,
    verify: (g, w) async {
      await play(g, 5); // no level up
      g.achievements.toastQueue.addAll([
        AchievementId.hoops10,
        AchievementId.itemHeart,
        AchievementId.itemShield,
        AchievementId.itemEgg,
        AchievementId.itemJar,
        AchievementId.itemPiggy,
        AchievementId.firstRevive,
      ]);
      final titles = <String>[];
      for (var i = 0; i < 60 * 30; i++) {
        g.update(1 / 60);
        if (i % 10 == 0) await flushAndMount(g);
        final t = g.achievementToast;
        expect(
          g.world.children.whereType<AchievementToast>().length,
          lessThanOrEqualTo(1),
        );
        if (t != null &&
            t.title.isNotEmpty &&
            (titles.isEmpty || titles.last != t.title)) {
          titles.add(t.title);
          if (titles.length == 5) await shot(g, w, 's12_toast_more_568');
        }
        if (t == null && titles.isNotEmpty) break;
      }
      expect(titles, [
        'FIRST FLIGHT',
        'TWEETHEART',
        'TOUGH EGG',
        'EGGCELLENT!',
        '+3 MORE',
      ]);
      expect(g.achievements.toastQueue, isEmpty);
    },
  );

  tester(prefs: {'coins': 6000, 'seenItems': allSeen}).testGameWidget(
    '§12.5 the shop: FRESH FEATHERS toasts at once, over the shop',
    setUp: boot,
    verify: (g, w) async {
      await openSkinShop(g, layer: SkinLayer.bird);
      g.tapItem(SkinLayer.bird, 'sky');
      stepGame(g, .5);
      await g.buyTriedOnItem();
      await flushAndMount(g);
      expect(g.storage.achUnlocked, {'skin_first'});
      expect(g.achievementToast?.current, AchievementId.skinFirst);
      expect(kCollectibleTotal, greaterThan(g.menu.items.ownedCount));
      stepGame(g, .6);
      await shot(g, w, 's12_toast_shop_568');
    },
  );

  // PRD 2.6 O63: Home has no medal; achievements open from the board.
  for (final h in [568.0, 730.0]) {
    tester(height: h, prefs: {'coins': 99999}).testGameWidget(
      'O63 Home trophy opens board and achievements tab at ${h.toInt()}',
      setUp: boot,
      verify: (g, w) async {
        final home = g.homeScreen!;
        expect(kHomeImages, isNot(contains('menu/medal.png')));
        final gear = Config.homeGearRectFor(h);
        final trophy = home.trophyButton.toAbsoluteRect();
        expect(trophy, Config.homeTrophyRectFor(h));
        expect(trophy.overlaps(gear), isFalse);
        expect(g.coinPill.label.text, '99 999');
        expect(trophy.right, lessThan(g.coinPill.toAbsoluteRect().left));
        expect(trophy.bottom, lessThanOrEqualTo(Config.homeTitleTop));
        home.trophyButton.onPressed();
        await flushAndMount(g);
        await flushAndMount(g);
        final board = g.boardScreen!;
        expect(board.tabs, hasLength(3));
        board.tabs[2].onPressed();
        await flushAndMount(g);
        expect(spy.opened, 1);
        expect(spy.events.where((e) => e.$1 == 'achievements_open').single.$2, {
          'result': 'opened',
        });
      },
    );
  }

  // --- persistence (§12.3) ---------------------------------------------------

  test('§12.9 every achievement key round-trips; resetMenuState clears '
      'them; Delete my data keeps them', () async {
    SharedPreferences.setMockInitialValues({});
    final s = GameStorage();
    await s.load();
    await s.saveAchUnlocked({'rank_egg', 'vs_1'});
    await s.saveAchReported({'rank_egg'});
    await s.saveAchReportedPlayer('p1');
    await s.saveAchRides({'cannon'});
    await s.saveAchItems({'item_heart'});
    await s.saveAchVersusWins(3);
    await s.saveAchDays(4, 20000);
    Future<GameStorage> reload() async {
      final r = GameStorage();
      await r.load();
      return r;
    }

    var r = await reload();
    expect(r.achUnlocked, {'rank_egg', 'vs_1'});
    expect(r.achReported, {'rank_egg'});
    expect(r.achReportedPlayer, 'p1');
    expect(r.achRides, {'cannon'});
    expect(r.achItems, {'item_heart'});
    expect(r.achVersusWins, 3);
    expect(r.achDayStreak, 4);
    expect(r.achLastPlayDay, 20000);
    await r.resetVersusData();
    r = await reload();
    expect(r.achUnlocked, {'rank_egg', 'vs_1'});
    expect(r.achVersusWins, 3);
    await r.resetMenuState();
    r = await reload();
    expect(r.achUnlocked, isEmpty);
    expect(r.achReported, isEmpty);
    expect(r.achReportedPlayer, '');
    expect(r.achRides, isEmpty);
    expect(r.achItems, isEmpty);
    expect(r.achVersusWins, 0);
    expect(r.achDayStreak, 0);
    expect(r.achLastPlayDay, -1);
  });
}
