import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/mode_button.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/menu/home_mode.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/services/e2e.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import '../versus/s3_13_versus_run_test.dart' show opponentAt;

Rect _rectOf(PositionComponent c) {
  final tl = c.absolutePositionOfAnchor(Anchor.topLeft);
  return Rect.fromLTWH(tl.x, tl.y, c.width * c.scale.x, c.height * c.scale.y);
}

Future<void> _boot(FlappySpikesGame g) async {
  await g.ready();
  await preloadImages(g);
  await flushAndMount(g);
}

/// Ends the run with [score] points and lets the results page mount.
Future<void> _finishWith(FlappySpikesGame g, RunController run, int score) async {
  for (var i = 0; i < score; i++) {
    run.debugPass(perfect: false);
  }
  run.state.invulnerable = 0;
  killRun(g);
  await flushAndMount(g);
  for (var i = 0; i < 30 && g.resultsScreen == null; i++) {
    g.update(1 / 60);
    await flushAndMount(g);
  }
}

void _modeTest(
  String name,
  Future<void> Function(
    FlappySpikesGame g,
    AnalyticsSpy spy,
    FakeVersusService versus,
    WidgetTester tester,
  ) body, {
  Map<String, Object> prefs = const {},
  double h = 711,
  FakeVersusService Function()? versus,
}) {
  late AnalyticsSpy spy;
  late FakeVersusService v;
  FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    v = versus?.call() ?? FakeVersusService();
    return createRunTestGame(
      prefs: prefs,
      worldHeight: h,
      services: spy,
      versus: v,
    );
  },
    // A 1:1 surface so real taps land on world points.
    pumpWidget: (gameWidget, tester) async {
      tester.view
        ..physicalSize = Size(320, h)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(gameWidget);
    },
  ).testGameWidget(
    name,
    setUp: (g, _) => _boot(g),
    verify: (g, tester) => body(g, spy, v, tester),
  );
}

/// PRD-2.2 §2 the Home mode button (VERSUS / FREE FLY) and §2.2 the FREE FLY
/// run path; §2.3 analytics; §4 `versus_solo` on a solo VERSUS START.
void main() {
  setUp(E2EHooks.reset);

  group('PRD-2.2 §2.2 storage', () {
    test('§2.2 homeMode: versus on the first start, remembered, reset by '
        '"Delete my data"', () async {
      SharedPreferences.setMockInitialValues({});
      final s = GameStorage();
      await s.load();
      expect(s.homeMode, HomeMode.versus);
      await s.saveHomeMode(HomeMode.freeFly);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('homeMode'), 'freeFly');
      final again = GameStorage();
      await again.load();
      expect(again.homeMode, HomeMode.freeFly);
      await again.resetVersusData();
      expect(again.homeMode, HomeMode.versus);
      expect(prefs.containsKey('homeMode'), isFalse);
      expect(HomeMode.parse('junk'), HomeMode.versus);
      expect(HomeMode.parse(null), HomeMode.versus);
    });
  });

  group('PRD-2.2 §2.1 layout', () {
    test('§2.1 the mode button: 147 x 21, right edge = START right edge, '
        '5 pt above START; the VS tag 31 x 17, 9 pt in, 8 pt above', () {
      for (final h in [568.0, 640.0, 711.0, 730.0]) {
        final start = Config.homeStartRectFor(h);
        final mode = Config.homeModeRectFor(h);
        final tag = Config.homeVsTagRectFor(h);
        expect(mode.width, 147);
        expect(mode.height, 21);
        expect(mode.right, start.right);
        expect(start.top - mode.bottom, 5);
        expect(tag.size, const Size(31, 17));
        expect(tag.left - start.left, 9);
        expect(start.top - tag.top, 8);
        expect(tag.right, lessThan(mode.left), reason: 'tag clear of button');
        // §2.1: the block (mode row + START + slot) is centred between the
        // emblem and the tiles, nothing overlaps at 568.
        final above = mode.top - Config.homeEmblemBottomFor(h);
        final below =
            Config.homeTileRowTopFor(h) - Config.homeSlotRectFor(h).bottom;
        expect(above, greaterThanOrEqualTo(0), reason: '$h');
        expect(below, greaterThanOrEqualTo(0), reason: '$h');
        expect((above - below).abs(), lessThanOrEqualTo(1.01), reason: '$h');
      }
      // The approved 711 mock: MODE part 41, the field the rest.
      expect(Config.homeModePartWidth, 41);
    });
  });

  group('PRD-2.2 §2 mode button', () {
    _modeTest(
      '§2.2 the default is VERSUS: button, VS tag shown',
      (g, spy, versus, tester) async {
        expect(g.homeMode, HomeMode.versus);
        final home = g.homeScreen!;
        expect(home.modeButton.mode, HomeMode.versus);
        expect(home.modeButton.label, 'VERSUS');
        expect(home.vsTag.shown, isTrue);
        expect(home.vsTag.opacity, 1);
        expect(
          _rectOf(home.modeButton),
          Config.homeModeRectFor(g.viewHeight),
        );
        // VERSUS: MODE on the left, the field on the right.
        expect(home.modeButton.part.position.x, 0);
        expect(home.modeButton.field.position.x, Config.homeModePartWidth);
        expect(home.modeButton.fieldColor, Config.homeModeVersusField);
      },
    );

    _modeTest(
      '§2.2 a real tap switches to FREE FLY (mode_to_ff, knock, '
      'mode_changed, remembered) and back to VERSUS (mode_to_vs); the parts '
      'swap sides with an overshoot; the VS tag fades out / pops in',
      (g, spy, versus, tester) async {
        final sfx = sfxLog(g);
        final home = g.homeScreen!;
        final rect = Config.homeModeRectFor(g.viewHeight);
        await tester.tapAt(rect.center);
        await tester.pump(const Duration(milliseconds: 20));
        expect(g.homeMode, HomeMode.freeFly);
        expect(sfx, contains('modeToFf'));
        expect(rumbleLog(g), contains(RumbleKind.knock));
        expect(
          analyticsLog(spy).where((e) => e.$1 == 'mode_changed').single.$2,
          {'mode': 'free_fly'},
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('homeMode'), 'freeFly');
        expect(home.modeButton.label, 'FREE FLY');
        expect(home.modeButton.swapping, isTrue);
        // Overshoot: the MODE part passes its end spot (106) on the way.
        var maxX = 0.0;
        for (var i = 0; i < 20; i++) {
          g.update(1 / 60);
          maxX = maxX < home.modeButton.part.position.x
              ? home.modeButton.part.position.x
              : maxX;
        }
        expect(maxX, greaterThan(home.modeButton.fieldWidth));
        expect(home.modeButton.swapping, isFalse);
        expect(home.modeButton.part.position.x, home.modeButton.fieldWidth);
        expect(home.modeButton.field.position.x, 0);
        expect(home.modeButton.fieldColor, Config.homeModeFreeFlyField);
        expect(home.vsTag.shown, isFalse);
        expect(home.vsTag.opacity, 0);

        // Tap again: VERSUS.
        await tester.tapAt(rect.center);
        await tester.pump(const Duration(milliseconds: 20));
        expect(g.homeMode, HomeMode.versus);
        expect(sfx.last, 'modeToVs');
        expect(
          analyticsLog(spy).where((e) => e.$1 == 'mode_changed').last.$2,
          {'mode': 'versus'},
        );
        expect(home.vsTag.shown, isTrue);
        g.update(0.05);
        expect(home.vsTag.scale.x, lessThan(1), reason: 'pops in from 0.4');
        for (var i = 0; i < 20; i++) {
          g.update(1 / 60);
        }
        expect(home.vsTag.scale.x, closeTo(1, 1e-9));
        expect(home.vsTag.opacity, 1);
        expect(home.modeButton.part.position.x, 0);
        await tester.pump(const Duration(seconds: 1)); // knock timers
      },
    );

    _modeTest(
      '§2.2 the hit area is the button plus 6 pt; a tap 7 pt out misses; '
      'START still owns its own top edge',
      (g, spy, versus, tester) async {
        final rect = Config.homeModeRectFor(g.viewHeight);
        await tester.tapAt(Offset(rect.left - 5, rect.top - 5));
        await tester.pump(const Duration(milliseconds: 20));
        expect(g.homeMode, HomeMode.freeFly);
        await tester.tapAt(Offset(rect.right + 5, rect.center.dy));
        await tester.pump(const Duration(milliseconds: 20));
        expect(g.homeMode, HomeMode.versus);
        await tester.tapAt(Offset(rect.left - 7, rect.top - 7));
        await tester.pump(const Duration(milliseconds: 20));
        expect(g.homeMode, HomeMode.versus);
        await tester.pump(const Duration(seconds: 1)); // knock timers
      },
    );

    _modeTest(
      '§2.2 the choice persists after a restart',
      (g, spy, versus, tester) async {
        expect(g.homeMode, HomeMode.freeFly);
        final home = g.homeScreen!;
        expect(home.modeButton.mode, HomeMode.freeFly);
        expect(home.modeButton.label, 'FREE FLY');
        expect(home.vsTag.shown, isFalse);
        expect(home.vsTag.opacity, 0);
        expect(home.modeButton.part.position.x, home.modeButton.fieldWidth);
      },
      prefs: const {'homeMode': 'freeFly'},
    );

    _modeTest(
      '§2.2 "Delete my data" resets the mode to VERSUS',
      (g, spy, versus, tester) async {
        g.openSettings();
        await flushAndMount(g);
        for (var i = 0; i < 40; i++) {
          g.update(1 / 60);
        }
        await flushAndMount(g);
        g.openDeleteDataConfirm();
        await flushAndMount(g);
        await g.confirmDeleteMyData();
        await flushAndMount(g);
        expect(versus.deleteCalls, 1);
        expect(g.homeMode, HomeMode.versus);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('homeMode'), isFalse);
      },
      prefs: const {'homeMode': 'freeFly'},
    );

    _modeTest(
      '§2.2 disabled while a popup is up or a run starts',
      (g, spy, versus, tester) async {
        g.openSettings();
        await flushAndMount(g);
        g.toggleHomeMode();
        expect(g.homeMode, HomeMode.versus);
        g.closeSettings();
        for (var i = 0; i < 60; i++) {
          g.update(1 / 60);
        }
        await flushAndMount(g);
        g.onScreenTap(); // START (solo: no opponent)
        expect(g.state, GameState.playing);
        g.toggleHomeMode();
        expect(g.homeMode, HomeMode.versus);
        expect(analyticsLog(spy).where((e) => e.$1 == 'mode_changed'), isEmpty);
      },
    );
  });

  group('PRD-2.2 §2.2 FREE FLY run', () {
    _modeTest(
      '§2.2 FREE FLY + START: no VS intro, no versus bar, no versus result '
      'or bonus, the solo results page; the run still queues an upload; '
      'run_start {mode: free_fly}; the prefetched opponent stays',
      (g, spy, versus, tester) async {
        g.onScreenTap();
        expect(g.state, GameState.playing, reason: 'no intro');
        expect(g.versusIntro, isNull);
        await flushAndMount(g);
        final run = g.run!;
        expect(run.setup.opponent, isNull);
        expect(g.runHud!.versus, isNull);
        expect(versus.pool, hasLength(1), reason: 'not taken in FREE FLY');
        expect(versus.runStarts, 1);
        final events = analyticsLog(spy);
        expect(events.where((e) => e.$1 == 'run_start').single.$2, {
          'mode': 'free_fly',
        });
        expect(events.where((e) => e.$1.startsWith('versus_')), isEmpty);
        await _finishWith(g, run, 4);
        final page = g.resultsScreen!;
        expect(page.header, isNull);
        expect(page.them, isNull);
        expect(page.duel, isNull);
        expect(run.summarize().duel, isNull);
        expect(versus.submitted, hasLength(1), reason: 'FREE FLY uploads');
        expect(versus.submitted.single.score, 4);
        expect(
          analyticsLog(spy).where((e) => e.$1.startsWith('versus_')),
          isEmpty,
        );
      },
      prefs: const {'homeMode': 'freeFly'},
      versus: () => FakeVersusService(pool: [opponentAt([1, 2, 3])]),
    );

    _modeTest(
      '§2.2 VERSUS + START with an opponent: the VS intro and the versus '
      'bar as in 2.1; run_start {mode: versus, opponent: 1}',
      (g, spy, versus, tester) async {
        await startRun(g);
        expect(g.run!.setup.opponent, isNotNull);
        expect(g.runHud!.versus, isNotNull);
        expect(
          analyticsLog(spy).where((e) => e.$1 == 'run_start').single.$2,
          {'mode': 'versus', 'opponent': 1},
        );
        expect(analyticsLog(spy).where((e) => e.$1 == 'versus_solo'), isEmpty);
      },
      versus: () => FakeVersusService(pool: [opponentAt([1, 2, 3])]),
    );

    _modeTest(
      '§4 VERSUS + START without an opponent: a solo run, nothing shown; '
      'versus_solo {reason, reads, level}; run_start opponent 0',
      (g, spy, versus, tester) async {
        versus
          ..reason = VersusSoloReason.appCheck
          ..searchInfo = const VersusSearchInfo(
            state: VersusSearchState.solo,
            reason: VersusSoloReason.appCheck,
            reads: 3,
            level: 4,
          );
        g.onScreenTap();
        expect(g.state, GameState.playing);
        expect(g.versusIntro, isNull);
        final events = analyticsLog(spy);
        expect(events.where((e) => e.$1 == 'versus_solo').single.$2, {
          'reason': 'app_check',
          'reads': 3,
          'level': g.menu.levels.level,
        });
        expect(events.where((e) => e.$1 == 'run_start').single.$2, {
          'mode': 'versus',
          'opponent': 0,
        });
      },
      prefs: const {'bestScore': 250},
    );
  });

  test('§4 the logcat line', () {
    expect(
      versusSoloLogLine(VersusSoloReason.noRival, 44),
      'versus: solo (no_rival, 44 reads)',
    );
  });

  test('§2.1 ModeButton keeps its mode when set to the same value', () {
    final b = ModeButton(
      rect: const Rect.fromLTWH(0, 0, 147, 21),
      mode: HomeMode.versus,
      onPressed: () {},
    );
    b.setMode(HomeMode.versus);
    expect(b.swapping, isFalse);
    b.setMode(HomeMode.freeFly, animate: false);
    expect(b.swapping, isFalse);
    expect(b.part.position.x, b.fieldWidth);
  });
}
