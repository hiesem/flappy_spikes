import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/fake_ad_overlay.dart';
import 'package:flappy_spikes/components/home/home_screen.dart';
import 'package:flappy_spikes/components/menu_screen_chrome.dart';
import 'package:flappy_spikes/components/noads_popup.dart';
import 'package:flappy_spikes/components/shop/shop_screen.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/mistakes.dart';
import 'package:flappy_spikes/run/pickups/pickup.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/services/reminders.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All sprite assets the game may load, so that component onLoads complete
/// on cache hits (microtasks) instead of real async decodes.
final kAllImages = [
  ...kHomeImages,
  ...kMenuChromeImages,
  ...kShopImages,
  ...kNoAdsPopupImages,
  ...kFakeAdOverlayImages,
  // region WP-2e — results page images
  ...kResultsImages,
  // endregion WP-2e

  'bird.png',
  'bird_flap.png',
  'bird_dead.png',
  'ground_spikes.png',
  'background_score.png',
  'title.png',
  'gameover_title.png',
  'pointsfield.png',
  'replaybutton.png',
  'sharebutton.png',
  'soundbutton.png',
  'mutebutton.png',
  'gamcenter.png',
  'gamecenter_gameover.png',
  'settings_gear.png',
  'back_arrow.png',
  'music_note.png',
];

/// Creates a [FlappySpikesGame] with mocked SharedPreferences.
///
/// Must be called inside a testWidgets binding (e.g. via [FlameTester]'s
/// createGame callback) so the mock is installed before the game's onLoad
/// reads persistence. [worldHeight] overrides the playfield height (default:
/// the 568 pt design height).
FlappySpikesGame createTestGame(
  [Map<String, Object> initialPrefs = const {},
  double? worldHeight,
  GameServices? services,
  Monetization? monetization,
  Reminders? reminders,
]) {
  SharedPreferences.setMockInitialValues(initialPrefs);
  // soundEnabled: false — no audioplayers platform-channel calls in tests.
  final game = FlappySpikesGame(
    worldHeight: worldHeight,
    services: services,
    monetization: monetization,
    reminders: reminders,
    soundEnabled: false,
  );
  // A fixed run seed (the director's course, same as e2e builds), so
  // journeys that fly the autopilot meet the same hoops every run.
  game.runSeed = _pipeSeed;
  return game;
}

/// Seed for the deterministic test course ([createTestGame]).
const int _pipeSeed = 7;

/// Pre-decodes every sprite into the game's image cache. Call in setUp
/// (which runs inside runAsync, where real image decoding works).
Future<void> preloadImages(FlappySpikesGame game) =>
    game.images.loadAll(kAllImages);

/// Lets components that were added during fixed-stepping finish mounting:
/// flushes pending microtasks (their onLoads only need cache hits after
/// [preloadImages]) and processes queued lifecycle events via a zero-dt
/// update (which does not advance game time).
Future<void> flushAndMount(FlappySpikesGame game) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.value();
    game.update(0);
  }
}

/// Fixed-steps the game (and its Forge2D world) for [seconds] of game time.
///
/// When [flapBelow] is provided, taps the screen whenever the bird drops
/// below that y coordinate while playing. This keeps the bird airborne in a
/// safe altitude band (unlike a fixed flap interval, which can staircase the
/// bird into the ceiling spikes).
void stepGame(
  FlappySpikesGame game,
  double seconds, {
  double dt = 1 / 60,
  double? flapBelow,
}) {
  var elapsed = 0.0;
  while (elapsed < seconds - 1e-9) {
    game.update(dt);
    elapsed += dt;
    if (flapBelow != null && game.state == GameState.playing) {
      final birds = game.world.children.query<Bird>();
      if (birds.isNotEmpty && birds.first.body.position.y > flapBelow) {
        game.onScreenTap();
      }
    }
  }
}

/// Lets a menu list finish the momentum it carries after a release (product
/// decision 2026-10-07): steps game time until the fling/spring back has come
/// to rest, pumping the widget clock alongside. Without this a tap that lands
/// while the list is still moving only stops the motion (and presses nothing),
/// so journeys that tap a tile after dragging must settle first.
Future<void> settleMenuScroll(
  MenuScrollArea scroll,
  FlappySpikesGame game,
  WidgetTester tester,
) async {
  for (var frame = 0; frame < 300 && scroll.isBusy; frame++) {
    stepGame(game, 1 / 60);
    await tester.pump(const Duration(milliseconds: 16));
  }
}

// region WP-0b — hoop-aware run harness (PRD-2 ARCH §7.1; append-only)

/// [createTestGame] with named options: the run [seed] and a [versus]
/// service. (Dart cannot mix optional positional and named parameters, so
/// this is a sibling of [createTestGame] rather than an overload.)
FlappySpikesGame createRunTestGame({
  Map<String, Object> prefs = const {},
  double? worldHeight,
  GameServices? services,
  Monetization? monetization,
  int seed = 7,
  VersusService? versus,
}) {
  SharedPreferences.setMockInitialValues(prefs);
  final game = FlappySpikesGame(
    worldHeight: worldHeight,
    services: services,
    monetization: monetization,
    soundEnabled: false,
    versus: versus,
  );
  game.runSeed = seed;
  return game;
}

/// Starts a run from the home screen (START → playing; the first tap is
/// done) with the given [starter], `startHoopIndex`, forced elements and
/// forced portal ride, then lets the spawned parts mount.
Future<RunController> startRun(
  FlappySpikesGame g, {
  Powerup starter = Powerup.none,
  int startHoopIndex = 0,
  List<ElementId> force = const [],
  RideId? ride,
}) async {
  g.runDebug
    ..startHoopIndex = startHoopIndex
    ..forcedRide = ride;
  g.runDebug.force
    ..clear()
    ..addAll(force);
  if (starter != Powerup.none) g.storage.armedPowerup = starter.name;
  g.onScreenTap();
  await flushAndMount(g);
  return g.run!;
}

/// The outcome of [flyRun].
class RunFlight {
  int hoops = 0;
  int score = 0;
  int coins = 0;
  double seconds = 0;
  MistakeCause? cause;

  /// One line per notable event (spawns, passes, deaths).
  final List<String> trace = [];
}

/// Fixed-steps the run for at most [maxSeconds] (or until [untilHoops]
/// hoops are passed, or the run ends), the hoop-aware [Autopilot] flapping
/// when [autopilot]. Flushes microtasks every 10 frames so parts spawned
/// mid-flight finish mounting.
Future<RunFlight> flyRun(
  FlappySpikesGame g, {
  double maxSeconds = 120,
  int? untilHoops,
  bool autopilot = true,
  double dt = 1 / 60,
  void Function(RunController r)? onFrame,
}) async {
  final run = g.run!;
  final flight = RunFlight();
  final bot = Autopilot(run);
  void log(RunEvent e) {
    switch (e) {
      case HoopSpawned(:final plan):
        flight.trace.add('spawn $plan');
      case HoopPassed():
        flight.trace.add('pass ${run.state.hoopsPassed}');
      case RunDied(:final mistake):
        flight.cause = mistake.cause;
        flight.trace.add('died ${mistake.cause.name}');
      default:
        break;
    }
  }

  run.events.onAny(log);
  var frame = 0;
  while (flight.seconds < maxSeconds - 1e-9) {
    if (g.state != GameState.playing || run.ended) break;
    if (untilHoops != null && run.state.hoopsPassed >= untilHoops) break;
    if (autopilot && bot.shouldFlap()) g.onScreenTap();
    g.update(dt);
    flight.seconds += dt;
    onFrame?.call(run);
    if (++frame % 10 == 0) await flushAndMount(g);
  }
  run.events.offAny(log);
  flight
    ..hoops = run.state.hoopsPassed
    ..score = run.state.score
    ..coins = run.state.coinsThisRun;
  return flight;
}

/// Debug-force shortcut (next slot / gap).
void forceNext(RunController r, ElementId e) => r.debugForce(e);

Iterable<Hoop> hoopsOf(FlappySpikesGame g) => g.run?.spawner.hoops ?? const [];

Iterable<Pickup> pickupsOf(FlappySpikesGame g) =>
    g.run?.spawner.pickups ?? const [];

final Expando<List<String>> _sfxLogs = Expando();

/// Every sound requested from now on (`Sfx.name`), recorded through
/// `SoundService.onPlay`.
List<String> sfxLog(FlappySpikesGame g) {
  final existing = _sfxLogs[g];
  if (existing != null) return existing;
  final log = <String>[];
  _sfxLogs[g] = log;
  final previous = g.sound.onPlay;
  g.sound.onPlay = (sfx) {
    previous?.call(sfx);
    log.add(sfx.name);
  };
  return log;
}

/// Every rumble that fired (the recorder of `Rumble`).
List<RumbleKind> rumbleLog(FlappySpikesGame g) => g.rumble.fired;

/// Records analytics events instead of sending them.
class AnalyticsSpy extends GameServices {
  final List<(String, Map<String, Object>?)> events = [];

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) =>
      events.add((name, parameters));
}

List<(String, Map<String, Object>?)> analyticsLog(AnalyticsSpy s) =>
    s.events;
// endregion WP-0b

// region WP-1a — hoops replace pipes (PRD-2 §3.0.5)

/// Ends the running run through the mistake pipeline (`onBirdHit`) and
/// steps through the §3.0.5 death tumble until the post-run flow is up
/// (state leaves [GameState.dying]; at most 1.5 s of tumble). Replaces the
/// 1.0 tests' instant `onBirdHit()` → game over.
void killRun(
  FlappySpikesGame g, [
  MistakeCause cause = MistakeCause.missedHoop,
]) {
  g.onBirdHit(cause);
  var t = 0.0;
  while (g.state == GameState.dying && t < 3) {
    g.update(1 / 60);
    t += 1 / 60;
  }
}
// endregion WP-1a
