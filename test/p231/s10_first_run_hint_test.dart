import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/home_mode.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hud/first_run_hint.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// PRD-2.3.1 §10: the full first-run instructions show on every run until
/// the first pass of hoop 0 saves `firstRunHintSeen`; after that only the
/// tap reminder. A tap alone saves nothing; a graze through hoop 0 counts.
void main() {
  FlameTester<FlappySpikesGame> tester({
    Map<String, Object> prefs = const {},
    VersusService? versus,
  }) => FlameTester<FlappySpikesGame>(
    () => createRunTestGame(prefs: prefs, worldHeight: 711, versus: versus),
    gameSize: Vector2(320, 711),
  );

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  /// The run's hoop 0 (the fixed opening) after its first tap, flown past at
  /// [dy] (a rim touch when it is large).
  Future<Hoop> passHoop0(FlappySpikesGame g, {double dy = 0}) async {
    g.onPlayfieldTap();
    final hoop0 = hoopsOf(g).singleWhere((h) => h.plan.index == 0);
    expect(await passHoopAt(g, hoop0, dy: dy), isTrue);
    expect(hoop0.takenRing, 0, reason: 'passed, not missed');
    return hoop0;
  }

  /// Ends the current run (a death before any hoop-0 pass) and gets to the
  /// next run's waiting screen.
  Future<void> dieAndRestart(FlappySpikesGame g) async {
    killRun(g);
    await declineRevive(g);
    g.replay();
    await flushAndMount(g);
    await stepSeconds(g, .5);
  }

  /// Every stored preference of the mock store, as a new game would load it.
  Future<Map<String, Object>> storedPrefs(WidgetTester t) => t
      .runAsync(() async {
        final p = await SharedPreferences.getInstance();
        return {for (final k in p.getKeys()) k: p.get(k)!};
      })
      .then((m) => m!);

  tester().testGameWidget(
    'a fresh player who dies before hoop 0 sees the full instructions on '
    'every run; the first tap saves nothing and the key is written false',
    setUp: boot,
    verify: (g, t) async {
      expect(g.storage.firstRunHintSeen, isFalse);
      for (var failure = 1; failure <= 2; failure++) {
        await openRun(g);
        expect(
          g.firstRunHint!.mode,
          FirstRunHintMode.firstRun,
          reason: 'run after $failure failure(s)',
        );
        expect(g.firstRunHint!.shown, isTrue);
        g.onPlayfieldTap();
        expect(
          g.storage.firstRunHintSeen,
          isFalse,
          reason: 'a tap saves nothing',
        );
        await dieAndRestart(g);
        expect(g.storage.firstRunHintSeen, isFalse);
      }
      await openRun(g);
      expect(g.firstRunHint!.mode, FirstRunHintMode.firstRun);
      final stored = await storedPrefs(t);
      expect(
        stored['firstRunHintSeen'],
        isFalse,
        reason: 'written explicitly, so the gamesPlayed fallback cannot apply',
      );
    },
  );

  tester().testGameWidget(
    'a fresh player who passes hoop 0 and dies later: the next run shows only '
    'the tap reminder',
    setUp: boot,
    verify: (g, _) async {
      await openRun(g);
      expect(g.firstRunHint!.mode, FirstRunHintMode.firstRun);
      await passHoop0(g);
      expect(g.storage.firstRunHintSeen, isTrue);
      await flyRun(g, maxSeconds: 3);
      killRunThroughSaves(g);
      await declineRevive(g);
      g.replay();
      await flushAndMount(g);
      await stepSeconds(g, .5);
      await openRun(g);
      expect(g.firstRunHint!.mode, FirstRunHintMode.reminder);
      expect(g.firstRunHint!.shown, isFalse);
    },
  );

  tester().testGameWidget(
    'a graze through hoop 0 (a rim touch, still passed) counts as passed',
    setUp: boot,
    verify: (g, _) async {
      await openRun(g);
      final hoop0 = await passHoop0(g, dy: 50);
      expect(hoop0.touched, isTrue, reason: 'it really grazed');
      expect(g.storage.firstRunHintSeen, isTrue);
      killRunThroughSaves(g);
      await declineRevive(g);
      g.replay();
      await flushAndMount(g);
      await stepSeconds(g, .5);
      await openRun(g);
      expect(g.firstRunHint!.mode, FirstRunHintMode.reminder);
    },
  );

  tester().testGameWidget(
    'quitting before hoop 0 (the app killed, storage reloaded after a counted '
    'run) shows the full instructions again',
    setUp: boot,
    verify: (g, t) async {
      await openRun(g);
      g.onPlayfieldTap();
      await stepSeconds(g, 1.5);
      final hoop0 = hoopsOf(g).singleWhere((h) => h.plan.index == 0);
      expect(hoop0.resolved, isFalse, reason: 'no pass of hoop 0');
      // The app is killed: the run counted as a game, and the next launch
      // loads the stored values.
      await g.storage.saveGamesPlayed(1);
      expect((await storedPrefs(t))['firstRunHintSeen'], isFalse);
      await g.storage.load();
      expect(g.storage.gamesPlayed, 1);
      expect(g.storage.firstRunHintSeen, isFalse);
      killRun(g);
      await declineRevive(g);
      g.replay();
      await flushAndMount(g);
      await stepSeconds(g, .5);
      await openRun(g);
      expect(g.firstRunHint!.mode, FirstRunHintMode.firstRun);
    },
  );

  tester(prefs: {'firstRunHintSeen': true}).testGameWidget(
    'an existing player (firstRunHintSeen = true) never sees the full '
    'instructions; the key stays true',
    setUp: boot,
    verify: (g, _) async {
      for (var i = 0; i < 2; i++) {
        await openRun(g);
        expect(g.firstRunHint!.mode, FirstRunHintMode.reminder);
        g.onPlayfieldTap();
        await dieAndRestart(g);
      }
      expect(g.storage.firstRunHintSeen, isTrue);
    },
  );

  tester(prefs: {'gamesPlayed': 3}).testGameWidget(
    'a pre-2.3 install (key missing, gamesPlayed > 0) counts as seen: the '
    'reminder only',
    setUp: boot,
    verify: (g, _) async {
      expect(g.storage.firstRunHintSeen, isTrue);
      await openRun(g);
      expect(g.firstRunHint!.mode, FirstRunHintMode.reminder);
    },
  );

  final versus = FakeVersusService(
    pool: [
      OpponentRun(
        uid: 'u1',
        name: 'BrightOwl',
        score: 3,
        best: 9,
        level: 1,
        timeline: RunTimeline()
          ..addPoint(1)
          ..addPoint(2)
          ..addPoint(3)
          ..end(4),
      ),
    ],
  );
  tester(versus: versus).testGameWidget(
    'VERSUS: a fresh player who dies before hoop 0 sees the full instructions '
    'again; after hoop 0 only the reminder',
    setUp: (g, t) async {
      await boot(g, t);
      await g.versus.prefetch();
    },
    verify: (g, _) async {
      expect(g.homeMode, HomeMode.versus);
      await openRun(g);
      expect(g.firstRunHint!.mode, FirstRunHintMode.firstRun);
      g.onPlayfieldTap();
      await dieAndRestart(g);
      await openRun(g);
      expect(g.firstRunHint!.mode, FirstRunHintMode.firstRun);
      await passHoop0(g);
      expect(g.storage.firstRunHintSeen, isTrue);
      killRunThroughSaves(g);
      await declineRevive(g);
      g.replay();
      await flushAndMount(g);
      await stepSeconds(g, .5);
      await openRun(g);
      expect(g.firstRunHint!.mode, FirstRunHintMode.reminder);
    },
  );

  tester(prefs: {'homeMode': HomeMode.freeFly.key}).testGameWidget(
    'FREE FLY: the same rule (the full instructions until hoop 0 is passed)',
    setUp: boot,
    verify: (g, _) async {
      expect(g.homeMode, HomeMode.freeFly);
      await openRun(g);
      expect(g.firstRunHint!.mode, FirstRunHintMode.firstRun);
      g.onPlayfieldTap();
      await dieAndRestart(g);
      await openRun(g);
      expect(g.firstRunHint!.mode, FirstRunHintMode.firstRun);
      await passHoop0(g);
      killRunThroughSaves(g);
      await declineRevive(g);
      g.replay();
      await flushAndMount(g);
      await stepSeconds(g, .5);
      await openRun(g);
      expect(g.firstRunHint!.mode, FirstRunHintMode.reminder);
    },
  );
}
