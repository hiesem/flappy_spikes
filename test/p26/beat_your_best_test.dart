import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/effects/gold_sticker.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_scaled_world.dart';
import 'package:flappy_spikes/run/run_setup.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

class _Spy extends GameServices {
  final events = <(String, Map<String, Object>?)>[];
  @override
  void logEvent(String name, [Map<String, Object>? parameters]) =>
      events.add((name, parameters));
}

class _UpdateProbe extends Component {
  double elapsed = 0;
  @override
  void update(double dt) {
    super.update(dt);
    elapsed += dt;
  }
}

void main() {
  void check(
    String name,
    Future<void> Function(FlappySpikesGame, _Spy) body, {
    int best = 42,
    int hoops = 1,
    String mode = 'freeFly',
    double height = 711,
    double width = 320,
  }) {
    final spy = _Spy();
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {'bestScore': best, 'bestRunHoops': hoops, 'homeMode': mode},
        worldHeight: height,
        services: spy,
      )..runDebug.ignoreGates = false,
      gameSize: Vector2(width, height),
    ).testGameWidget(
      name,
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) => body(g, spy),
    );
  }

  for (final mode in ['freeFly', 'versus']) {
    check('$mode solo chip and marker; score moment once with analytics', (
      g,
      spy,
    ) async {
      final run = await startRun(g);
      final hud = RunHud.ensureFor(run);
      expect(run.countsForUpload, isTrue);
      expect(hud.bestChipVisible, isTrue);
      expect(hud.bestChipScore, 42);
      expect(run.bestLine, isNotNull);
      run.state.hoopsPassed = 3;
      run.ctx.addScore(42);
      expect(hud.bestSticker, isNull);
      run.ctx.addScore(5); // streak/bonus can beat the score before the line
      await flushAndMount(g);
      final sticker = hud.bestSticker!;
      expect(sticker.text, 'NEW BEST!');
      expect(sticker.position.y, 114);
      hud.update(.17);
      expect(hud.bestChipGold, isFalse);
      hud.update(.02);
      // WP-K approved bestChip design: flip begins at .18 s; gold and
      // the live score appear halfway through its .22 s squash, at .29 s.
      expect(hud.bestChipGold, isFalse);
      expect(hud.bestChipScore, 42);
      hud.update(.099);
      expect(hud.bestChipGold, isFalse);
      hud.update(.002);
      expect(hud.bestChipGold, isTrue);
      expect(hud.bestChipScore, 47);
      run.ctx.addScore(2);
      expect(identical(sticker, hud.bestSticker), isTrue);
      expect(hud.bestChipScore, 49);
      expect(hud.descendants().whereType<GoldSticker>(), hasLength(1));
      hud.update(1.02);
      await flushAndMount(g);
      expect(hud.bestSticker, isNull);
      run.ctx.addScore(1);
      expect(hud.bestSticker, isNull);
      final beaten = spy.events.where((e) => e.$1 == 'best_beaten').toList();
      expect(beaten, hasLength(1));
      expect(beaten.single.$2, {
        'mode': mode == 'freeFly' ? 'free_fly' : 'versus',
        'hoop': 3,
        'best_before': 42,
        'games': 1,
      });
      run.endRun();
      expect(
        spy.events.singleWhere((e) => e.$1 == 'run_end').$2!['beat_best_hoop'],
        3,
      );
    }, mode: mode);
  }

  check('pause freezes only the best sticker clock and chip timing', (
    g,
    _,
  ) async {
    final run = await startRun(g);
    final hud = RunHud.ensureFor(run);
    run.ctx.addScore(43);
    await flushAndMount(g);
    final sticker = hud.bestSticker!;
    final stickerProbe = _UpdateProbe();
    final otherHudProbe = _UpdateProbe();
    sticker.add(stickerProbe);
    hud.add(otherHudProbe);
    await flushAndMount(g);
    hud.updateTree(.19);
    expect(hud.bestChipGold, isFalse);
    final stickerTime = stickerProbe.elapsed;
    final otherTime = otherHudProbe.elapsed;
    g.state = GameState.paused;
    hud.updateTree(.5);
    expect(stickerProbe.elapsed, stickerTime);
    expect(otherHudProbe.elapsed, closeTo(otherTime + .5, 1e-9));
    expect(hud.bestChipGold, isFalse);
    expect(hud.bestChipScore, 42);
    expect(hud.bestSticker, same(sticker));
    g.state = GameState.playing;
    hud.updateTree(.11);
    expect(stickerProbe.elapsed, closeTo(stickerTime + .11, 1e-9));
    expect(hud.bestChipGold, isTrue);
    expect(hud.bestChipScore, 43);
  });

  check('best zero has no chip, marker or celebration', (g, spy) async {
    final run = await startRun(g);
    expect(RunHud.ensureFor(run).bestChipVisible, isFalse);
    expect(run.bestLine, isNull);
    run.ctx.addScore(100);
    expect(run.beatBestHoop, -1);
    expect(spy.events.where((e) => e.$1 == 'best_beaten'), isEmpty);
    run.endRun();
    expect(
      spy.events.singleWhere((e) => e.$1 == 'run_end').$2!['beat_best_hoop'],
      -1,
    );
  }, best: 0);

  check('legacy best without hoop history keeps chip but hides marker', (
    g,
    _,
  ) async {
    final run = await startRun(g);
    expect(RunHud.ensureFor(run).bestChipVisible, isTrue);
    expect(run.bestLine, isNull);
  }, hoops: 0);

  check('debug, opponent and weekly context suppress the goal', (g, _) async {
    final run = await startRun(g);
    run.bestGoalSuppressed = true; // G5 integration seam
    expect(RunHud.ensureFor(run).bestChipVisible, isFalse);
    run.ctx.addScore(43);
    expect(run.beatBestHoop, -1);
    run.bestGoalSuppressed = false;
    run.markDebugAssist();
    expect(RunHud.ensureFor(run).bestChipVisible, isFalse);
    final opponentRun = RunController(
      game: g,
      setup: RunSetup(
        seed: 7,
        viewHeight: 711,
        opponent: OpponentRun(
          uid: 'other',
          name: 'Other',
          score: 5,
          best: 42,
          level: 0,
          timeline: RunTimeline.empty(),
        ),
      ),
    );
    expect(opponentRun.bestGoalEligible, isFalse);
    final debugRun = RunController(
      game: g,
      setup: const RunSetup(seed: 7, viewHeight: 711, debugStarter: true),
    );
    expect(debugRun.bestGoalEligible, isFalse);
  });

  for (final dimensions in [
    (320.0, 568.0),
    (320.0, 711.0),
    (320.0, 320 * 4 / 3),
  ]) {
    check(
      'marker follows actual hoop plane at $dimensions',
      (g, _) async {
        final run = await startRun(g);
        run.state.camX = 320;
        run.spawner.update(0);
        final hoop = run.spawner.hoops.singleWhere((h) => h.plan.index == 1);
        final line = run.bestLine!;
        line.update(0);
        expect(line.screenX, closeTo(hoop.planeX - 320, .001));
        expect(line.visible, isFalse); // more than 1.25 s ahead
        run.state.camX = hoop.planeX - 200;
        line.update(0);
        expect(line.screenX, closeTo(200, .001));
        expect(line.visible, isTrue);
        expect(RunScaledWorld.isRunColumn(line), isTrue);
        final shift = (g.world as RunScaledWorld).columnShift;
        if (dimensions.$2 < 568) {
          // WP-K / PRD §WP-K: actually enter tablet layout, as WP-TAB does.
          expect(g.extraWidth, greaterThan(0));
          expect(g.viewHeight, 568);
        } else {
          expect(g.extraWidth, 0);
        }
        expect(shift, closeTo(g.extraWidth / 2, .001));
        final shiftedLineX =
            line.screenX + shift - g.camera.viewfinder.position.x;
        expect(
          shiftedLineX,
          closeTo(hoop.planeX - run.state.camX + g.extraWidth, .001),
        );
        run.ctx.addScore(43);
        final before = line.screenX;
        line.update(.16);
        expect(line.screenX, lessThan(before));
        expect(line.screenX, greaterThan(70));
        line.update(.16);
        expect(line.screenX, closeTo(70, .001));
      },
      width: dimensions.$1,
      height: dimensions.$2,
    );
  }

  check('run end saves hoops only when score sets a new best', (g, _) async {
    final run = await startRun(g);
    run.state.hoopsPassed = 9;
    run.ctx.addScore(50);
    g.endRun(run.endRun());
    expect(g.storage.bestRunHoops, 9);
    expect(g.storage.bestScore, 50);
    run.state.hoopsPassed = 20;
    run.saveBestRunHoops(50, 50);
    run.saveBestRunHoops(49, 50);
    expect(g.storage.bestRunHoops, 9);
    await flushAndMount(g);
    expect((await SharedPreferences.getInstance()).getInt('bestRunHoops'), 9);
  });
}
