// P6 release e2e suite (PRD-2 §7, ARCH §7.3). The final device sign-off:
//
//   flutter test integration_test/release_e2e_test.dart \
//     -d 38300DLJH004SD --dart-define=FS_E2E=true
//
// Local check on the Linux desktop target (notifications and versus live are
// skipped there — only a phone can do them):
//
//   flutter test integration_test/release_e2e_test.dart \
//     -d linux --dart-define=FS_E2E=true
//
// Opt-in live versus round trip against the real `flappy-spikes-a2b55`
// project (Android only):
//
//   … --dart-define=FS_LIVE_VERSUS=true \
//     [--dart-define=FS_APPCHECK_DEBUG_TOKEN=<registered token>]
//
// 1. Journey: launch → home → START → bot run → death at ≥ 6 hoops → revive
//    with the (fake) ad → death → revive with coins (debug coins) → death →
//    No thanks → results with a level-up (forced best) → CLAIM → NEXT → home.
// 2. Element sweep: every `ElementId` of the §3.0.8 catalogue forced and
//    flown by the bot until it was on screen and resolved, plus Big Hoops
//    (home starter) and the spike squeeze.
// 3. Rides: the 5 portal rides plus the cannon, each forced.
// 4. Reminders: the 7-day plan through the real plugin (≤ 14 pending, none
//    in quiet hours). Android only.
// 5. Versus live round trip (opt-in, Android only).
// 6. Frame-time logging (not a gate): tier 3, a comet and a ride.
//
// Screenshots are PNGs of the game's RepaintBoundary (works on Linux and
// Android without `convertFlutterSurfaceToImage`). Linux: `build/e2e/release/`
// under the project; Android: the app's cache dir (the path and an
// `adb … run-as` pull command are printed). Frame timings go to
// `binding.reportData` and `frame_timings.json` next to the shots.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flappy_spikes/firebase_options.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/levels/levels.dart';
import 'package:flappy_spikes/main.dart' as app;
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/run/debug/force_menu.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/kinds/registry.dart' as hoops;
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/pickups/registry.dart' as pickups;
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flappy_spikes/services/e2e.dart';
import 'package:flappy_spikes/services/firebase_versus_backend.dart';
import 'package:flappy_spikes/services/reminders.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/run_entry.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flappy_spikes/versus/upload_queue.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `--dart-define=FS_LIVE_VERSUS=true`: run the live Firebase round trip.
const bool kLiveVersus = bool.fromEnvironment('FS_LIVE_VERSUS');

final IntegrationTestWidgetsFlutterBinding binding =
    IntegrationTestWidgetsFlutterBinding.ensureInitialized();

bool get _isAndroid => !kIsWeb && Platform.isAndroid;

// ------------------------------------------------------------------ harness

/// Clean, deterministic persistence for every launch: an in-memory store
/// (also on the device), no first-session popups.
void _freshPrefs([Map<String, Object> extra = const {}]) {
  SharedPreferences.setMockInitialValues({
    'bestScore': 0,
    'coins': 0,
    'firstSessionDone': true,
    ...extra,
  });
}

/// `app.main()` and wait for the loaded game on its home screen.
Future<FlappySpikesGame> _launch(WidgetTester tester) async {
  unawaited(app.main());
  FlappySpikesGame? game;
  for (var i = 0; i < 300 && game == null; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    final w = find.byType(GameWidget<FlappySpikesGame>);
    if (w.evaluate().isNotEmpty) {
      final g = tester.widget<GameWidget<FlappySpikesGame>>(w).game;
      if (g != null && g.isLoaded) game = g;
    }
  }
  expect(game, isNotNull, reason: 'the game loaded');
  final g = game!;
  for (var i = 0; i < 100 && g.homeScreen?.isLoaded != true; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _settleHome(tester, g);
  return g;
}

/// Closes launch popups (back) until START is accepted.
Future<void> _settleHome(WidgetTester tester, FlappySpikesGame g) async {
  for (var i = 0; i < 10 && g.modalPopupOpen; i++) {
    g.handleBack();
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pump(const Duration(milliseconds: 600));
}

/// Pumps real frames until [done] (or [seconds] pass). True when [done].
Future<bool> _waitFor(
  WidgetTester tester,
  bool Function() done, {
  double seconds = 10,
  Duration step = const Duration(milliseconds: 100),
}) async {
  final sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsedMilliseconds > seconds * 1000) return false;
    await tester.pump(step);
  }
  return true;
}

/// START from the home screen (retried while the home screen still settles).
Future<RunController> _start(WidgetTester tester, FlappySpikesGame g) async {
  for (var i = 0; i < 40 && g.state != GameState.playing; i++) {
    if (g.state == GameState.start) {
      if (g.modalPopupOpen) g.handleBack();
      await g.startRun();
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(g.state, GameState.playing, reason: 'START began a run');
  return g.run!;
}

/// Kills the running run (through shields / extra lives) and waits for the
/// revive offer or the results page.
Future<void> _killToPostRun(WidgetTester tester, FlappySpikesGame g) async {
  g.runDebug.god = false;
  for (var i = 0; i < 10 && g.state == GameState.playing; i++) {
    g.run?.state.invulnerable = 0;
    g.onBirdHit(MistakeCause.spikes);
    await tester.pump(const Duration(milliseconds: 200));
  }
  await _waitFor(
    tester,
    () =>
        (g.state == GameState.reviving && g.reviveScreen?.isLoaded == true) ||
        g.state == GameState.results,
    seconds: 15,
  );
}

/// From any post-run state to the results page (No thanks on an offer,
/// back on a bonus screen).
Future<void> _toResults(WidgetTester tester, FlappySpikesGame g) async {
  await _waitFor(tester, () {
    if (g.state == GameState.reviving) {
      final s = g.reviveScreen;
      if (s != null && s.ui >= 1) s.tapNoThanks();
    } else if (g.state == GameState.bonus) {
      g.handleBack();
    }
    return g.state == GameState.results && g.resultsScreen != null;
  }, seconds: 30);
}

/// Results → home.
Future<void> _resultsToHome(WidgetTester tester, FlappySpikesGame g) async {
  if (g.state != GameState.results) return;
  await _waitFor(tester, () => g.resultsScreen?.canContinue ?? true);
  g.goHome();
  await _waitFor(
    tester,
    () => g.state == GameState.start && g.homeScreen?.isLoaded == true,
  );
  await _settleHome(tester, g);
}

/// Tears the app down so the binding finds no leftover frame callbacks
/// (audioplayers' position updater).
Future<void> _teardown(WidgetTester tester) async {
  E2EHooks.reset();
  try {
    await FlameAudio.bgm.stop();
    await FlameAudio.bgm.audioPlayer.dispose();
  } catch (_) {}
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 200));
}

// -------------------------------------------------------------- screenshots

Directory get _outDir => Directory(
  _isAndroid
      ? '${Directory.systemTemp.path}/e2e_release'
      : '${Directory.current.path}/build/e2e/release',
);

final List<String> _shots = [];

/// PNG of the game's RepaintBoundary (`main.dart` wraps the GameWidget).
Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  try {
    RenderObject? r = tester.renderObject(
      find.byType(GameWidget<FlappySpikesGame>),
    );
    while (r != null && r is! RenderRepaintBoundary) {
      r = r.parent;
    }
    if (r is! RenderRepaintBoundary) {
      fail('no RepaintBoundary above the GameWidget');
    }
    final image = await r.toImage(pixelRatio: 1.5);
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    final file = File('${_outDir.path}/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    _shots.add(file.path);
    debugPrint('SHOT ${file.path} (${bytes.length} bytes)');
    expect(bytes.length, greaterThan(5000), reason: 'shot $name not blank');
  } on TestFailure {
    rethrow;
  } catch (e) {
    fail('screenshot $name failed: $e');
  }
}

void _printShotsHint() {
  if (_shots.isEmpty) return;
  debugPrint('E2E SHOTS: ${_shots.length} PNGs in ${_outDir.path}');
  if (_isAndroid) {
    debugPrint(
      'E2E SHOTS pull: adb -s 38300DLJH004SD exec-out run-as '
      'com.flappyspikes.flappy_spikes tar c -C cache e2e_release '
      '> e2e_release.tar',
    );
  }
}

// ----------------------------------------------------- RunEvents error trap

/// `RunEvents` catches a throwing handler and only debug-prints it: trap
/// those lines so the suite fails on them.
final List<String> _handlerErrors = [];
DebugPrintCallback? _origDebugPrint;

void _trapHandlerErrors() {
  _origDebugPrint ??= debugPrint;
  final orig = _origDebugPrint!;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null &&
        message.startsWith('RunEvents:') &&
        message.contains('threw')) {
      _handlerErrors.add(message);
    }
    orig(message, wrapWidth: wrapWidth);
  };
}

void _restoreDebugPrint() {
  final orig = _origDebugPrint;
  if (orig != null) debugPrint = orig;
}

// ------------------------------------------------------------ frame timings

/// FrameTiming summary of [action] (build / raster ms) into
/// `binding.reportData[key]` and `frame_timings.json`. Not a gate: never
/// fails the test.
final Map<String, Object?> _frameReport = {};

Future<void> _recordFrames(String key, Future<void> Function() action) async {
  final timings = <ui.FrameTiming>[];
  void cb(List<ui.FrameTiming> t) => timings.addAll(t);
  SchedulerBinding.instance.addTimingsCallback(cb);
  try {
    await action();
  } finally {
    // The engine batches timings (≈ once a second): give the last batch a
    // moment to arrive.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    SchedulerBinding.instance.removeTimingsCallback(cb);
  }
  try {
    double ms(Duration d) => d.inMicroseconds / 1000;
    Map<String, num> stats(List<double> v) {
      if (v.isEmpty) return {'n': 0};
      final s = List.of(v)..sort();
      double p(double q) => s[min(s.length - 1, (q * s.length).floor())];
      return {
        'n': s.length,
        'avg': double.parse(
          (s.reduce((a, b) => a + b) / s.length).toStringAsFixed(2),
        ),
        'p50': double.parse(p(.5).toStringAsFixed(2)),
        'p90': double.parse(p(.9).toStringAsFixed(2)),
        'p99': double.parse(p(.99).toStringAsFixed(2)),
        'max': double.parse(s.last.toStringAsFixed(2)),
      };
    }

    final build = [for (final t in timings) ms(t.buildDuration)];
    final raster = [for (final t in timings) ms(t.rasterDuration)];
    final total = [for (final t in timings) ms(t.totalSpan)];
    final summary = <String, Object?>{
      'frames': timings.length,
      'build_ms': stats(build),
      'raster_ms': stats(raster),
      'total_ms': stats(total),
      'over_16ms': total.where((t) => t > 1000 / 60).length,
    };
    _frameReport[key] = summary;
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['frame_timings'] = _frameReport;
    debugPrint('FRAMES $key ${jsonEncode(summary)}');
    final file = File('${_outDir.path}/frame_timings.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_frameReport),
    );
  } catch (e) {
    debugPrint('FRAMES $key not recorded: $e');
  }
}

// ------------------------------------------------------------- sweep model

/// What one forced element did.
class _Sweep {
  _Sweep(this.name);
  final String name;
  int attempts = 0;
  bool onScreen = false;
  bool resolved = false;

  /// 'continues' | 'died (saved)' | 'died before it appeared'.
  String end = '';
  final List<String> problems = [];

  bool get ok => onScreen && problems.isEmpty;

  @override
  String toString() =>
      '$name: ${ok ? 'OK' : 'FAIL'} (on screen $onScreen, resolved $resolved, '
      '$end, attempts $attempts${problems.isEmpty ? '' : ', $problems'})';
}

/// Elements that are not forced in the sweep, with where they are covered.
/// A new `ElementId` must be swept or listed here (the sweep test fails
/// otherwise).
const Map<ElementId, String> _coveredElsewhere = {
  ElementId.capsule: 'swept through its three types (hourglass, mini bird, '
      'coin frenzy)',
  ElementId.piggyCoins: 'follow-up of the forced piggy bank',
  ElementId.fireflySwarm: 'follow-up of the forced firefly jar',
  ElementId.perfectStreak: 'every bot run + the tier-3 frame log',
  ElementId.coins: 'every run (wallet per pass) + the journey',
  ElementId.rumble: 'every run (Rumble sink; no-op on Linux)',
  ElementId.revive: 'journey (ad, coins, No thanks)',
  ElementId.results: 'journey (level-up, CLAIM, NEXT)',
  ElementId.versus: 'live round trip (FS_LIVE_VERSUS, Android)',
};

/// Elements the build has registered (an unregistered element — e.g. one of
/// a work package that is not merged yet — is never placed by the
/// director; the sweep reports it as SKIP).
Set<ElementId> get _registered => {
  ...hoops.registeredElements(),
  ...pickups.registeredPickupElements(),
  ElementId.squeeze, // a run feature, not a registry entry
};

/// Forces one element (or ride / starter) and flies the bot until it was on
/// screen and resolved, or the run ended cleanly. Screenshots: `_on` while
/// on screen, `_done` after it resolved (or `_end` on a death).
Future<_Sweep> _sweepOne(
  WidgetTester tester,
  FlappySpikesGame g, {
  required String name,
  ElementId? element,
  RideId? ride,
  bool bigHoops = false,
  int startHoop = 0,
  String? frameKey,
}) async {
  final r = _Sweep(name);
  for (var attempt = 0; attempt < 3 && !r.onScreen; attempt++) {
    r.attempts = attempt + 1;
    r.problems.clear();
    await _resultsToHome(tester, g);
    expect(g.state, GameState.start);
    E2EHooks.reset();
    E2EHooks.autopilot = true;
    E2EHooks.startHoopIndex = startHoop;
    if (element != null && element != ElementId.squeeze) {
      E2EHooks.force.add(element);
    }
    E2EHooks.forcedRide = ride;
    g.runSeed = kE2ESeed + attempt * 101;
    if (bigHoops) await g.storage.saveArmedPowerup(Powerup.bigHoops.name);
    final gamesBefore = g.storage.gamesPlayed;
    final run = await _start(tester, g);
    if (element == ElementId.squeeze) run.debugForce(ElementId.squeeze);

    // Event watch.
    double? spawnCamX;
    var rideStarted = false, rideEnded = false;
    final squeezePhases = <SqueezePhase>[];
    void onEvent(RunEvent e) {
      switch (e) {
        case RideStarted(:final rideId)
            when ride == null || rideId == ride:
          rideStarted = true;
        case RideEnded(:final rideId) when ride == null || rideId == ride:
          if (rideStarted) rideEnded = true;
        case SqueezePhaseChanged(:final phase):
          squeezePhases.add(phase);
        default:
      }
    }

    final target = ride != null ? ElementId.portal : element;
    void onSpawn(ElementSpawned e) {
      if (e.onScreen && spawnCamX == null && e.element == target) {
        spawnCamX = run.state.camX;
      }
    }

    run.events.onAny(onEvent);
    run.events.on<ElementSpawned>(onSpawn);
    // A target already on screen before the listeners (e.g. a forced
    // modifier on the run's first hoop).
    if (target != null) {
      final early =
          run.spawner.hoops.any(
            (h) =>
                h.announced &&
                (h.plan.element == target ||
                    (target == ElementId.angledRing && h.plan.tiltDeg != 0) ||
                    (target == ElementId.movingRing && h.plan.motion != null)),
          ) ||
          run.spawner.pickups.any((p) {
            final extra = p.plan?.extra;
            return p.announced &&
                (p.id == target ||
                    (extra is CapsuleType && extra.element == target));
          });
      if (early) spawnCamX = run.state.camX;
    }

    bool appeared() {
      if (bigHoops) return run.state.hoopsPassed >= 1;
      if (element == ElementId.squeeze) {
        return squeezePhases.contains(SqueezePhase.warning) ||
            squeezePhases.contains(SqueezePhase.closing);
      }
      return spawnCamX != null;
    }

    bool resolved() {
      if (bigHoops) return run.state.hoopsPassed >= 4;
      if (element == ElementId.squeeze) {
        return squeezePhases.contains(SqueezePhase.opening) &&
            run.state.squeeze.phase == SqueezePhase.idle;
      }
      final x = spawnCamX;
      final bird = run.birdTrackPosition();
      if (x == null || bird == null) return false;
      // The bird reached the spot where the element entered the screen
      // (plus a margin for long elements: trains, star trails, pairs).
      final past = bird.x > x + 320 + 120;
      if (rideStarted && !rideEnded) return false;
      if ((ride != null || element == ElementId.portal) && !rideEnded) {
        return false;
      }
      return past;
    }

    bool alive() =>
        g.state == GameState.playing || g.state == GameState.paused;

    Future<void> fly() async {
      double? appearedAt;
      double? rideAt;
      final sw = Stopwatch()..start();
      var onShot = false;
      while (alive() && sw.elapsed.inSeconds < 75) {
        await tester.pump(const Duration(milliseconds: 100));
        final now = sw.elapsedMilliseconds / 1000;
        if (!r.onScreen && appeared()) {
          r.onScreen = true;
          appearedAt = now;
        }
        if (r.onScreen && !onShot && alive()) {
          final isRide = ride != null || element == ElementId.portal;
          final sx = spawnCamX;
          final bool ready;
          if (isRide) {
            // Shoot the ride itself, not the portal hoop.
            rideAt ??= rideStarted ? now : null;
            ready = rideAt != null && now - rideAt >= 1.5;
          } else if (sx != null) {
            // The element entered at the right edge: shoot it near the
            // middle of the screen (the world moved ~140 pt since).
            ready = run.state.camX - sx >= 140 || now - appearedAt! >= 3;
          } else if (element == ElementId.squeeze) {
            // The walls at their deepest.
            ready = run.state.squeeze.phase == SqueezePhase.hold;
          } else {
            ready = now - appearedAt! >= 1;
          }
          if (ready) {
            onShot = true;
            await _shot(tester, 'sweep_${name}_on');
          }
        }
        if (r.onScreen && resolved()) {
          r.resolved = true;
          await _waitFor(tester, () => !alive(), seconds: 1.2);
          if (alive()) await _shot(tester, 'sweep_${name}_done');
          break;
        }
      }
    }

    if (frameKey != null) {
      await _recordFrames(frameKey, fly);
    } else {
      await fly();
    }

    if (alive()) {
      r.end = r.onScreen ? 'continues' : 'never appeared (retry)';
      if (r.onScreen && !r.resolved) r.problems.add('not resolved within 75 s');
      await _killToPostRun(tester, g);
    } else {
      r.end = r.onScreen ? 'died (saved)' : 'died before it appeared';
      await _waitFor(tester, () => g.state != GameState.dying, seconds: 5);
      if (g.state == GameState.reviving) {
        await _shot(tester, 'sweep_${name}_end');
      }
    }
    await _toResults(tester, g);
    if (g.state != GameState.results) {
      r.problems.add('the run did not end cleanly (state ${g.state})');
    } else if (g.storage.gamesPlayed != gamesBefore + 1) {
      r.problems.add('the run was not saved (gamesPlayed)');
    }
    final ex = tester.takeException();
    if (ex != null) r.problems.add('exception: $ex');
    if (_handlerErrors.isNotEmpty) {
      r.problems.addAll(_handlerErrors);
      _handlerErrors.clear();
    }
    if (r.problems.isNotEmpty) break; // a real problem: no retry
  }
  if (!r.onScreen && r.problems.isEmpty) {
    r.problems.add('never on screen in ${r.attempts} runs');
  }
  debugPrint('SWEEP $r');
  return r;
}

// ------------------------------------------------------------------- tests

void main() {
  setUpAll(() {
    // Real-time game: the engine draws every vsync instead of only on the
    // test's pumps (the game clamps dt to Config.maxFrameStep, so 100 ms
    // pumps alone would run it at a fraction of real time).
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    _trapHandlerErrors();
  });
  tearDownAll(() {
    _restoreDebugPrint();
    _printShotsHint();
    if (_frameReport.isNotEmpty) {
      debugPrint('FRAME REPORT ${jsonEncode(_frameReport)}');
    }
  });

  testWidgets('P6 §7 journey: home → START → bot → death ≥ 6 hoops → ad '
      'revive → death → coin revive → death → No thanks → results level-up '
      '→ CLAIM → NEXT → home', (tester) async {
    expect(kE2E, isTrue, reason: 'run with --dart-define=FS_E2E=true');
    E2EHooks.reset();
    E2EHooks.autopilot = true;
    _freshPrefs();
    final g = await _launch(tester);
    expect(g.state, GameState.start);
    expect(g.storage.bestScore, 0);
    await _shot(tester, 'journey_01_home');

    // START → the bot flies (god mode while flying, so the deaths are the
    // test's, at the right moments).
    final run = await _start(tester, g);
    expect(run.setup.seed, kE2ESeed);
    g.runDebug.god = true;
    await tester.pump(const Duration(milliseconds: 800));
    await _shot(tester, 'journey_02_run');
    expect(
      await _waitFor(tester, () => run.state.hoopsPassed >= 6, seconds: 90),
      isTrue,
      reason: 'the bot passed 6 hoops',
    );

    // Death 1 → the ad offer → watch → phoenix → playing.
    await _killToPostRun(tester, g);
    expect(g.state, GameState.reviving, reason: '≥ 6 hoops: revive offer');
    var offer = g.reviveScreen!;
    await _waitFor(tester, () => offer.ui >= 1);
    expect(offer.offer.isAd, isTrue, reason: '1st offer: the ad step');
    await _shot(tester, 'journey_03_revive_ad');
    offer.tapHeart();
    await tester.pump(const Duration(milliseconds: 900));
    await _shot(tester, 'journey_04_fake_ad');
    expect(
      await _waitFor(tester, () => g.state == GameState.playing, seconds: 40),
      isTrue,
      reason: 'the ad revive brought the run back',
    );
    expect(run.state.revivesThisGame, 1);
    await _shot(tester, 'journey_05_revived_ad');
    g.runDebug.god = true;
    await tester.pump(const Duration(seconds: 3));

    // Death 2 → coins from the debug hook → pay 250 → playing.
    await g.menu.wallet.add(1000, CoinSource.debug);
    final balance = g.menu.wallet.balance;
    await _killToPostRun(tester, g);
    expect(g.state, GameState.reviving);
    offer = g.reviveScreen!;
    await _waitFor(tester, () => offer.ui >= 1);
    expect(offer.offer.isAd, isFalse);
    expect(offer.offer.price, 250);
    expect(offer.locked, isFalse);
    await _shot(tester, 'journey_06_revive_coins');
    offer.tapHeart();
    expect(
      await _waitFor(tester, () => g.state == GameState.playing, seconds: 20),
      isTrue,
      reason: 'the coin revive brought the run back',
    );
    expect(g.menu.wallet.balance, balance - 250);
    expect(run.state.revivesThisGame, 2);
    g.runDebug.god = true;
    await tester.pump(const Duration(seconds: 3));

    // Force a best score that levels up twice (EGG 10, CHICK 50).
    final forced = max(60, run.state.score);
    run.ctx.addScore(forced - run.state.score);
    final expectedLevel = levelFor(forced);
    expect(expectedLevel, greaterThanOrEqualTo(2));

    // Death 3 → 500 offer → No thanks → results.
    await _killToPostRun(tester, g);
    expect(g.state, GameState.reviving);
    offer = g.reviveScreen!;
    await _waitFor(tester, () => offer.ui >= 1);
    expect(offer.offer.price, 500);
    await _shot(tester, 'journey_07_revive_500');
    offer.tapNoThanks();
    await _toResults(tester, g);
    expect(g.state, GameState.results);
    expect(run.ended, isTrue);
    expect(g.storage.bestScore, greaterThanOrEqualTo(forced));
    expect(g.storage.gamesPlayed, 1);
    final page = g.resultsScreen!;
    expect(page.model.levelReward, greaterThan(0));
    expect(g.storage.unclaimedLevelReward, page.model.levelReward);
    await _shot(tester, 'journey_08_results');

    // The level-up celebration → CLAIM.
    expect(
      await _waitFor(tester, () => page.claimShowing, seconds: 20),
      isTrue,
      reason: 'CLAIM came up',
    );
    await _shot(tester, 'journey_09_claim');
    final beforeClaim = g.menu.wallet.balance;
    page.claimButton.onPressed();
    await _waitFor(
      tester,
      () => g.storage.unclaimedLevelReward == 0,
      seconds: 5,
    );
    expect(g.storage.unclaimedLevelReward, 0);
    expect(g.menu.wallet.balance, beforeClaim + page.model.levelReward);
    await tester.pump(const Duration(seconds: 3));
    await _shot(tester, 'journey_10_claimed');

    // NEXT → home.
    page.nextButton.onPressed();
    expect(
      await _waitFor(
        tester,
        () => g.state == GameState.start && g.homeScreen?.isLoaded == true,
        seconds: 10,
      ),
      isTrue,
    );
    expect(g.run, isNull);
    expect(g.resultsScreen, isNull);
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, 'journey_11_home');
    expect(g.menu.levels.level, expectedLevel);
    expect(_handlerErrors, isEmpty);
    await _teardown(tester);
  });

  testWidgets('P6 §3.0.8 element sweep: every catalogue element forced, on '
      'screen and resolved (or a clean, saved end); Big Hoops; squeeze', (
    tester,
  ) async {
    expect(kE2E, isTrue, reason: 'run with --dart-define=FS_E2E=true');
    // Every ElementId is swept or covered elsewhere.
    final swept = {...ForceMenu.forceable, ElementId.bigHoops};
    final uncovered = ElementId.values.where(
      (e) => !swept.contains(e) && !_coveredElsewhere.containsKey(e),
    );
    expect(uncovered, isEmpty, reason: 'sweep or list every element');

    // Every element met: no first-meet forcing gets in the way of the
    // forced one.
    _freshPrefs({
      'metElements': [for (final e in ElementId.values) e.storageId],
    });
    final g = await _launch(tester);
    final registered = _registered;
    final results = <_Sweep>[];
    final skipped = <String>[];
    for (final e in ForceMenu.forceable) {
      if (!registered.contains(e)) {
        skipped.add(e.storageId);
        debugPrint('SWEEP SKIP ${e.storageId}: not registered in this build');
        continue;
      }
      results.add(
        await _sweepOne(
          tester,
          g,
          name: e.storageId,
          element: e,
          startHoop: e.firstPossible ?? 0,
          frameKey: e == ElementId.comet ? 'comet' : null,
        ),
      );
    }
    results.add(
      await _sweepOne(tester, g, name: 'big_hoops', bigHoops: true),
    );
    await _resultsToHome(tester, g);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['element_sweep'] = {
      for (final r in results) r.name: r.toString(),
      for (final s in skipped) s: 'SKIP (not registered)',
    };
    debugPrint('SWEEP SUMMARY\n${results.join('\n')}');
    expect(
      results.where((r) => !r.ok).map((r) => r.toString()).toList(),
      isEmpty,
    );
    // Only elements of work packages that are not in this build may be
    // missing (WP-4a feathers / puzzle pieces).
    expect(
      skipped.toSet().difference({
        ElementId.feather.storageId,
        ElementId.puzzlePiece.storageId,
      }),
      isEmpty,
      reason: 'an element is in the catalogue but not registered',
    );
    await _teardown(tester);
  });

  testWidgets('P6 §3.12 rides: the 5 portal rides plus the cannon, each '
      'forced; tier-3 frame log', (tester) async {
    expect(kE2E, isTrue, reason: 'run with --dart-define=FS_E2E=true');
    _freshPrefs({
      'metElements': [for (final e in ElementId.values) e.storageId],
    });
    final g = await _launch(tester);

    // Frame log (not a gate): a run at streak tier 3 (trail, gold bird).
    E2EHooks.reset();
    E2EHooks.autopilot = true;
    final run = await _start(tester, g);
    g.runDebug.god = true;
    await _waitFor(tester, () => run.state.hoopsPassed >= 1, seconds: 15);
    run.events.emit(const StreakAtLeast(3));
    await _recordFrames(
      'tier3',
      () => _waitFor(tester, () => false, seconds: 5),
    );
    expect(run.state.tier, greaterThanOrEqualTo(3));
    await _shot(tester, 'rides_00_tier3');
    g.runDebug.god = false;
    await _killToPostRun(tester, g);
    await _toResults(tester, g);

    final results = <_Sweep>[];
    for (final r in RideId.values) {
      results.add(
        await _sweepOne(
          tester,
          g,
          name: 'ride_${r.name}',
          ride: r,
          startHoop: ElementId.portal.firstPossible!,
          frameKey: r == RideId.space ? 'ride_space' : null,
        ),
      );
    }
    await _resultsToHome(tester, g);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['rides'] = {
      for (final r in results) r.name: r.toString(),
    };
    debugPrint('RIDES SUMMARY\n${results.join('\n')}');
    expect(
      results.where((r) => !r.ok || !r.resolved).map((r) => '$r').toList(),
      isEmpty,
      reason: 'every ride ran and ended',
    );
    await _teardown(tester);
  });

  testWidgets('P6 §3.34 reminders: pending 7-day plan (≤ 14), none in quiet '
      'hours', (tester) async {
    expect(kE2E, isTrue, reason: 'run with --dart-define=FS_E2E=true');
    if (!_isAndroid) {
      debugPrint('SKIP reminders: needs the phone (notification plugin)');
      markTestSkipped('reminders need Android');
      return;
    }
    E2EHooks.reset();
    E2EHooks.clockOffset = const Duration(days: 1);
    _freshPrefs({'bestScore': 12, 'coins': 250});
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.cancelAll();
    final store = GameStorage(
      clock: () => DateTime.now().add(E2EHooks.clockOffset),
    );
    await store.load();
    final reminders = LocalReminders(storage: store);
    await reminders.initialize();
    await reminders.requestPermissionIfNeeded();
    await reminders.reschedule();

    final pending = await plugin.pendingNotificationRequests();
    expect(pending.length, inInclusiveRange(1, ReminderScheduler.windowSlots));
    expect(pending.length, lessThanOrEqualTo(14));
    expect(store.notifPosition, pending.length);
    for (final request in pending) {
      final payload = ReminderPayload.decode(request.payload);
      expect(payload, isNotNull, reason: '§3.34 payload on every request');
      final at = DateTime.fromMillisecondsSinceEpoch(payload!.epochMs);
      expect(
        at.hour >= ReminderScheduler.awakeHourFrom &&
            at.hour < ReminderScheduler.awakeHourTo,
        isTrue,
        reason: '§3.34 never 22:00–09:00 (got $at)',
      );
      expect(request.title, isNotEmpty);
      expect(request.body, isNotEmpty);
    }
    debugPrint('REMINDERS ${pending.length} pending');
    await plugin.cancelAll();
    E2EHooks.reset();
  });

  testWidgets('P6 §3.13 versus live round trip (FS_LIVE_VERSUS): anonymous '
      'sign-in, upload, pool read, deleteMyData', (tester) async {
    if (!kLiveVersus || !_isAndroid) {
      debugPrint(
        'SKIP versus live: needs Android and '
        '--dart-define=FS_LIVE_VERSUS=true',
      );
      markTestSkipped('versus live is opt-in (Android)');
      return;
    }
    final token = kAppCheckDebugToken.isNotEmpty
        ? kAppCheckDebugToken
        : _uuidV4();
    debugPrint('''
=====================================================================
 APP CHECK DEBUG TOKEN: $token
 ${kAppCheckDebugToken.isEmpty ? 'NEW: register it in the Firebase console (flappy-spikes-a2b55 →\n App Check → Apps → Android → Manage debug tokens), then rerun with\n --dart-define=FS_APPCHECK_DEBUG_TOKEN=$token' : '(from FS_APPCHECK_DEBUG_TOKEN)'}
=====================================================================''');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseVersusBackend.activateAppCheck(debugToken: token);
    final backend = FirebaseVersusBackend();
    final uid = await backend.start().timeout(const Duration(seconds: 30));
    debugPrint('VERSUS uid $uid');

    // One real-shaped run: 5 points 1.2 s apart (the cheat filter wants
    // ≥ 0.9 s between plain points and score ≥ 3); timeline v2 (PRD-2.2
    // §13.5, one entry of value 1 each).
    final t = RunTimeline();
    for (var i = 1; i <= 5; i++) {
      t.addPoint(i * 1.2);
    }
    t.end(7.5);
    final now = DateTime.now().toUtc();
    final day =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final entry = RunEntry(
      runId: 'e2e-${now.millisecondsSinceEpoch}',
      score: 5,
      best: 5,
      ts: now,
      name: 'E2E bot',
      tl: t.encodeTl(),
      end: t.endCs,
      fl: t.encodeFlags(),
    );
    final write = await backend
        .writeRun(
          QueuedRun(entry, newBest: true),
          PlayerFields(
            name: entry.name,
            avatar: '',
            platform: 'android',
            look: Look.defaults,
            uploadsDay: day,
            uploadsCount: 0,
          ),
        )
        .timeout(const Duration(seconds: 30));
    expect(
      write,
      UploadWrite.done,
      reason: 'players/$uid write (App Check token registered?)',
    );

    // onPlayerRunWrite copies it into pools/{level}_{random shard}.
    final level = levelFor(entry.best);
    PoolEntry? mine;
    final sw = Stopwatch()..start();
    while (mine == null && sw.elapsed.inSeconds < 90) {
      for (var shard = 0; shard < VersusConfig.shards && mine == null; shard++) {
        final pool = await backend.readPool('${level}_$shard');
        mine = pool.where((p) => p.uid == uid).firstOrNull;
      }
      if (mine == null) await Future<void>.delayed(const Duration(seconds: 3));
    }
    expect(mine, isNotNull, reason: 'the run reached a level-$level pool');
    expect(mine!.runId, entry.runId);
    expect(mine.score, 5);
    debugPrint('VERSUS pool hit after ${sw.elapsed.inSeconds} s');
    // PRD-2.2 §13.5 timeline v2: our run and every (converted or new) run in
    // the low-level pools replays to its score; v1 entries would be skipped.
    expect(mine.run.timeline.points, 5);
    var replayed = 0;
    for (var l = 0; l <= 2; l++) {
      for (var shard = 0; shard < VersusConfig.shards; shard++) {
        for (final p in await backend.readPool('${l}_$shard')) {
          final o = p.toOpponent();
          expect(o.timeline.points, p.score, reason: 'pool ${l}_$shard ${p.runId}');
          expect(o.scoreAt(o.timeline.lengthSeconds + 1), p.score);
          replayed++;
        }
      }
    }
    debugPrint('VERSUS replayed $replayed pool runs (v2)');

    final deleted = await backend.deleteMyData().timeout(
      const Duration(seconds: 60),
    );
    expect(deleted, isTrue, reason: 'deleteMyData confirmed');
    debugPrint('VERSUS deleteMyData ok');
  });
}

String _uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final s = [for (var i = 0; i < 16; i++) h(i)].join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20)}';
}
