// PRD-2.3.1 §13: the shield ring follows the bird's visibility exactly —
// hidden while a ride hides the bird (cannon barrel, volcano, space rocket),
// back (and still armed) when the bird reappears; it never hides in a ride
// that never hides the bird.
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/items/shield.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

PortalRideFeature _feature(RunController r) =>
    r.features.whereType<PortalRideFeature>().single;

ShieldCircle _circle(RunController r) =>
    r.features.whereType<ShieldFeature>().single.circle!;

/// Counts every draw call (and layer) [ShieldCircle.render] makes.
class _CountingCanvas implements Canvas {
  int draws = 0;
  int depth = 1;

  @override
  void save() => depth++;

  @override
  void saveLayer(Rect? bounds, Paint paint) => depth++;

  @override
  void restore() => depth--;

  @override
  dynamic noSuchMethod(Invocation i) {
    final n = i.memberName.toString();
    if (n.contains('draw')) draws++;
    return null;
  }
}

int _drawCalls(ShieldCircle c) {
  final canvas = _CountingCanvas();
  c.render(canvas);
  expect(canvas.depth, 1, reason: 'balanced save / restore');
  return canvas.draws;
}

/// Flies with the bot until [until] holds; [each] runs after every frame.
Future<void> _flyUntil(
  FlappySpikesGame game,
  RunController run,
  bool Function() until, {
  double maxSeconds = 40,
  void Function()? each,
}) async {
  final bot = Autopilot(run);
  for (var f = 0; f < maxSeconds * 60 && !until(); f++) {
    if (bot.shouldFlap()) game.onScreenTap();
    game.update(1 / 60);
    each?.call();
    if (f % 10 == 0) await flushAndMount(game);
  }
}

FlameTester<FlappySpikesGame> _tester([double h = 711]) =>
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, seed: 5),
      gameSize: Vector2(320, h),
    );

Future<void> _setUp(FlappySpikesGame game, _) async {
  await game.ready();
  await preloadImages(game);
}

/// Starts a run into ride [id] with the shield armed and the ring fully
/// formed before the portal.
Future<RunController> _shieldedRide(FlappySpikesGame game, RideId id) async {
  final run = await startRun(game, startHoopIndex: 25, ride: id);
  run.state.shield = true;
  for (var i = 0; i < 60; i++) {
    game.update(1 / 60);
  }
  await flushAndMount(game);
  final circle = _circle(run);
  expect(circle.shown, isTrue);
  expect(circle.paints, isTrue);
  expect(_drawCalls(circle), greaterThan(0));
  return run;
}

void main() {
  // The moment each theme hides the bird, and the moment it is back.
  final hides = <RideId, (bool Function(PortalRide), bool Function(PortalRide))>{
    // In the barrel (exit, after the muzzle entry); back after the shot.
    RideId.cannon: (
      (r) => r.phase == RidePhase.exit && r.view.et > .5,
      (r) => r.phase == RidePhase.fly && r.view.ft > .1,
    ),
    // Swallowed by the volcano for the whole exit; back on the eruption.
    RideId.volcano: (
      (r) => r.phase == RidePhase.exit && r.view.et > .2,
      (r) => r.phase == RidePhase.fly && r.view.ft > .1,
    ),
    // In the rocket from 1.15 s of the exit; the rocket is drawn instead of
    // the bird for the first .85 s of the flight; back after that.
    RideId.space: (
      (r) => r.phase == RidePhase.exit && r.view.et > 1.3,
      (r) => r.phase == RidePhase.fly && r.view.ft > 1.0,
    ),
  };

  group('PRD-2.3.1 §13 the shield ring follows the bird', () {
    for (final e in hides.entries) {
      _tester().testGameWidget(
        '§13.3 ${e.key.name} ride, shield active: no ring while the bird is '
        'hidden; the ring is back (shield still armed) when it reappears',
        setUp: _setUp,
        verify: (game, _) async {
          final run = await _shieldedRide(game, e.key);
          final f = _feature(run);
          final circle = _circle(run);
          final (hidden, back) = e.value;
          await _flyUntil(game, run, () => f.ride != null && hidden(f.ride!));
          expect(f.ride, isNotNull);
          expect(hidden(f.ride!), isTrue);
          expect(run.state.ride!.birdHidden, isTrue);
          expect(game.runBird!.drawnOpacity, 0);
          expect(circle.paints, isFalse);
          expect(_drawCalls(circle), 0);
          // Still armed while hidden: nothing is used up.
          expect(run.state.shield, isTrue);
          expect(circle.shown, isTrue);

          await _flyUntil(game, run, () => f.ride == null || back(f.ride!));
          expect(f.ride, isNotNull);
          expect(run.state.ride!.birdHidden, isFalse);
          expect(game.runBird!.drawnOpacity, greaterThan(0));
          expect(run.state.shield, isTrue);
          expect(circle.paints, isTrue);
          expect(_drawCalls(circle), greaterThan(0));

          // Home again: the ring is still there with the shield.
          await _flyUntil(game, run, () => f.ride == null);
          game.update(1 / 60);
          expect(run.state.shield, isTrue);
          expect(circle.paints, isTrue);
        },
      );
    }

    for (final id in [RideId.sea, RideId.storm, RideId.pinball]) {
      _tester().testGameWidget(
        '§13.3 ${id.name} never hides the bird: the ring stays visible the '
        'whole ride (and follows the bird\'s scale)',
        setUp: _setUp,
        verify: (game, _) async {
          final run = await _shieldedRide(game, id);
          final f = _feature(run);
          final circle = _circle(run);
          await _flyUntil(game, run, () => f.ride != null);
          var frames = 0;
          var hiddenFrames = 0;
          await _flyUntil(
            game,
            run,
            () => f.ride == null,
            each: () {
              if (f.ride == null) return;
              frames++;
              final bird = game.runBird!;
              if (bird.drawnOpacity <= 0) hiddenFrames++;
              expect(circle.paints, isTrue);
              expect(circle.birdScale, bird.drawnScale);
            },
          );
          expect(frames, greaterThan(60));
          expect(hiddenFrames, 0);
          expect(run.state.shield, isTrue);
        },
      );
    }

    _tester().testGameWidget(
      '§13.2 one source of truth: the ring fades with the bird art',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await _shieldedRide(game, RideId.sea);
        final circle = _circle(run);
        final bird = game.runBird!;
        bird.setSpriteOpacity(.4);
        expect(circle.birdOpacity, closeTo(.4, 1e-9));
        expect(circle.paints, isTrue);
        bird.setSpriteOpacity(0);
        expect(circle.paints, isFalse);
        expect(_drawCalls(circle), 0);
        bird.setSpriteOpacity(1);
        expect(circle.paints, isTrue);
      },
    );
  });
}
