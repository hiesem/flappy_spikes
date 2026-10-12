import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart' show BodyType;
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flappy_spikes/run/config/portal_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

PortalRideFeature _feature(RunController r) =>
    r.features.whereType<PortalRideFeature>().single;

/// What one forced ride did, frame by frame.
class _Trace {
  double portalAt = -1, exitAt = -1, flyAt = -1, glideAt = -1, endAt = -1;
  double clockAtStart = 0, clockAtEnd = 0;
  int scoreBefore = 0, coinsBefore = 0, hoopsBefore = 0;
  int ridePasses = 0;
  int coinsAfterRide = 0, scoreAfterRide = 0;
  double minStripOpacity = 1;
  bool flappedInRide = false;
  final List<RunEvent> events = [];
  double? firstHoopAt;
  double landedAt = -1;
}

/// Flies to the forced portal with the autopilot, then lets the ride run
/// (no input needed) until normal play is back and [after] more hoops are
/// passed.
Future<_Trace> _ride(
  FlappySpikesGame game,
  RunController run, {
  int after = 2,
  bool tapDuringRide = false,
}) async {
  final tr = _Trace();
  final f = _feature(run);
  run.events.onAny(tr.events.add);
  run.events.on<HoopPassed>((e) {
    if (e.duringRide) tr.ridePasses++;
  });
  var t = 0.0;
  RidePhase? last;
  final bot = AutopilotHarness(run);
  var hoopsAfterRide = 0;
  var seen = false;
  for (var frame = 0; frame < 60 * 60; frame++) {
    final r = f.ride;
    if (r != null) seen = true;
    if (r == null && !seen) {
      // Before the ride: fly with the bot until the portal is passed.
      if (bot.shouldFlap()) game.onScreenTap();
      tr.scoreBefore = run.state.score;
      tr.coinsBefore = run.state.coinsThisRun;
      tr.hoopsBefore = run.state.hoopsPassed;
      tr.clockAtStart = run.state.runClock;
    } else if (r != null) {
      if (tapDuringRide && frame % 7 == 0) {
        final vy = game.runBird!.body.linearVelocity.y;
        game.onScreenTap();
        if (game.runBird!.body.linearVelocity.y != vy) tr.flappedInRide = true;
      }
      for (final s in game.world.children.whereType<SpikeStrip>()) {
        tr.minStripOpacity = math.min(tr.minStripOpacity, s.teethOpacity);
      }
      if (r.phase != last) {
        last = r.phase;
        switch (r.phase) {
          case RidePhase.ride:
            tr.portalAt = t;
          case RidePhase.exit:
            tr.exitAt = t;
          case RidePhase.fly:
            tr.flyAt = t;
          case RidePhase.glide:
            tr.glideAt = t;
          case RidePhase.done:
            break;
        }
      }
      if (r.phase == RidePhase.glide &&
          tr.landedAt < 0 &&
          r.view.gt >= PortalConfig.glideTime) {
        tr.landedAt = t;
      }
    } else {
      // Back in normal play.
      if (tr.endAt < 0) {
        tr.endAt = t;
        tr.coinsAfterRide = run.state.coinsThisRun;
        tr.scoreAfterRide = run.state.score;
        tr.clockAtEnd = run.state.runClock;
      }
      if (bot.shouldFlap()) game.onScreenTap();
    }
    final before = run.state.hoopsPassed;
    game.update(1 / 60);
    t += 1 / 60;
    if (tr.endAt >= 0 && run.state.hoopsPassed > before) {
      hoopsAfterRide++;
      tr.firstHoopAt ??= t;
    }
    if (frame % 10 == 0) await flushAndMount(game);
    if (run.ended || game.state != GameState.playing) break;
    if (hoopsAfterRide >= after) break;
  }
  return tr;
}

/// The test's autopilot (the shared bot).
typedef AutopilotHarness = Autopilot;

void main() {
  group('§3.12 / §5.12b portal rides', () {
    for (final ride in RideId.values) {
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: 711, seed: 5, services: AnalyticsSpy()),
        gameSize: Vector2(320, 711),
      ).testGameWidget(
        '§3.12 ${ride.name}: forced from the debug menu, runs start to '
        'finish (12 passes, points by the streak, +2 coins per ride ring) and returns to normal play',
        setUp: (game, _) async {
          await game.ready();
          await preloadImages(game);
        },
        verify: (game, _) async {
          final sfx = sfxLog(game);
          final spy = game.services as AnalyticsSpy;
          final run = await startRun(game, startHoopIndex: 25, ride: ride);
          final tr = await _ride(game, run, tapDuringRide: true);
          final f = _feature(run);
          expect(f.started, [ride]);
          expect(tr.endAt, greaterThan(0), reason: 'the ride ended');
          expect(run.ended, isFalse);
          expect(game.state, GameState.playing);
          // Portal + 11 ride rings = 12 passes, all perfect.
          expect(tr.ridePasses, PortalConfig.rideRings);
          expect(run.state.hoopsPassed - tr.hoopsBefore, greaterThanOrEqualTo(12));
          // The portal pass happened before the ride started (counted in
          // hoopsBefore); 11 ride passes give +11 / +22, the portal +1 / +2.
          final rideScore = tr.events
              .whereType<ScoreChanged>()
              .where((e) => e.flags == PointFlags.ride)
              .length;
          expect(rideScore, 11);
          // The portal + 11 ride rings: +12 score, +24 coins (+2 per perfect
          // pass), no extra ride bonus.
          // PRD-2.2 §11: the portal ring itself is judged by the perfect
          // zone (+2 centred, +1 off-centre); the 11 ride rings are always
          // perfect (+2 each).
          expect(tr.coinsAfterRide - tr.coinsBefore, anyOf(23, 24));
          // PRD-2.2 §13.1 ride rings follow the streak: max(2, streak).
          final rideDeltas = [
            for (final e in tr.events.whereType<ScoreChanged>())
              if (e.flags == PointFlags.ride) e.newScore - e.oldScore,
          ];
          var streakNow = 0;
          final wanted = <int>[];
          for (final e in tr.events) {
            if (e is StreakChanged) streakNow = e.newStreak;
            if (e is ScoreChanged && e.flags == PointFlags.ride) {
              wanted.add(math.max(2, streakNow));
            }
          }
          expect(rideDeltas, hasLength(11));
          expect(rideDeltas, wanted);
          for (var k = 1; k < rideDeltas.length; k++) {
            expect(rideDeltas[k], greaterThanOrEqualTo(rideDeltas[k - 1]));
          }
          // The rest is the portal ring's own pass (1, or max(2, streak)).
          final rideSum = rideDeltas.fold(0, (a, b) => a + b);
          expect(
            tr.scoreAfterRide - tr.scoreBefore - rideSum,
            inInclusiveRange(1, math.max(2, rideDeltas.first)),
          );
          expect(
            tr.events.whereType<HoopPassed>().where(
              (e) => e.hoop?.plan.kind == HoopKindId.portal,
            ),
            hasLength(1),
            reason: 'the portal itself counts as a pass',
          );
          expect(tr.flappedInRide, isFalse, reason: 'input ignored in rides');
          expect(tr.minStripOpacity, lessThan(.01), reason: 'strips fade out');
          for (final s in game.world.children.whereType<SpikeStrip>()) {
            expect(s.teethOpacity, 1);
          }
          // Back in normal play: dynamic bird at x 70.
          final bird = game.runBird!;
          expect(bird.inRide, isFalse);
          expect(bird.body.bodyType, BodyType.dynamic);
          expect(run.state.ride, isNull);
          expect(run.rideHold, isFalse);
          expect(run.spawner.hold, isFalse);
          // Timeline.
          final ride0 = tr.exitAt - tr.portalAt;
          expect(ride0, inInclusiveRange(8.0, 10.6), reason: 'ride ≈ 9.6 s');
          expect(tr.glideAt - tr.flyAt, closeTo(1.65, .05));
          expect(tr.endAt - tr.glideAt, closeTo(3.1, .05));
          expect(tr.clockAtEnd - tr.clockAtStart, greaterThan(12),
              reason: 'the run clock keeps running in rides');
          // Events, analytics, persistence, sounds, rumble.
          expect(tr.events.whereType<RideStarted>().single.rideId, ride);
          expect(tr.events.whereType<RideEnded>().single.rideId, ride);
          expect(
            analyticsLog(spy).where((e) => e.$1 == 'portal_entered').single.$2,
            {'ride': ride.storageId},
          );
          expect(game.storage.lastPortalRide, ride.storageId);
          expect(sfx, contains('puPortal'));
          expect(sfx, contains('puLand'));
          if (ride == RideId.cannon) {
            expect(sfx, containsAll(['puCannonAim', 'puCannonShot']));
          }
          expect(
            rumbleLog(game).where((k) => k == RumbleKind.shake).length,
            greaterThanOrEqualTo(11),
          );
          // §3.12 normal hoops resume ≈ 1 s after the landing.
          expect(tr.firstHoopAt, isNotNull);
          expect(tr.firstHoopAt! - tr.landedAt, closeTo(1.0, .25));
        },
      );
    }
  });
}
