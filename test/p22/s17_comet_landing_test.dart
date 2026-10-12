import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/run/config/comet_config.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/screen_edge_glow.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/items/hourglass.dart';
import 'package:flappy_spikes/run/items/timed_powerup.dart';
import 'package:flappy_spikes/run/rides/comet_ride.dart';
import 'package:flappy_spikes/run/rides/landing_slow_mo.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §17 comet landing: one automatic flap at control return and a
/// quiet slow motion (0.5× for 0.8 s, eased back to 1× by 1.5 s real time).
CometFeature _comet(RunController r) =>
    r.features.whereType<CometFeature>().single;

T _f<T>(RunController r) => r.features.whereType<T>().single;

FlameTester<FlappySpikesGame> _tester({double h = 711}) =>
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: h, seed: 5),
      gameSize: Vector2(320, h),
    );

Future<void> _setUp(FlappySpikesGame game, _) async {
  await game.ready();
  await preloadImages(game);
}

/// A pair COMET gift right after the start (or [star]: the forced star),
/// flown until the frame control returns. Returns the ride.
Future<CometRide> _toLanding(
  FlappySpikesGame game, {
  bool star = false,
  List<String>? sfx,
}) async {
  late RunController run;
  if (star) {
    run = await startRun(
      game,
      startHoopIndex: ElementId.comet.firstPossible!,
      force: [ElementId.comet],
    );
    final bot = Autopilot(run);
    for (var f = 0; f < 40 * 60 && !_comet(run).active; f++) {
      if (bot.shouldFlap()) game.onScreenTap();
      game.update(1 / 60);
      if (f % 10 == 0) await flushAndMount(game);
    }
  } else {
    run = await startRun(game);
    game.update(1 / 60);
    run.events.emit(const PickupCollected(ElementId.comet, null));
  }
  final ride = _comet(run).ride!;
  for (var f = 0; f < 12 * 60 && !ride.done; f++) {
    sfx?.clear();
    game.update(1 / 60);
    if (f % 20 == 0) await flushAndMount(game);
  }
  expect(ride.done, isTrue);
  return ride;
}

void _frames(FlappySpikesGame game, int n) {
  for (var i = 0; i < n; i++) {
    game.update(1 / 60);
  }
}

void main() {
  group('§17 rules (pure)', () {
    test('§17.1 0.5× for 0.8 s, smoothstep back to 1× over 0.7 s', () {
      expect(CometConfig.landingScale, .5);
      expect(CometConfig.landingHold, .8);
      expect(CometConfig.landingEase, .7);
      expect(LandingSlowMo.length, closeTo(1.5, 1e-9));
      expect(LandingSlowMo.scaleAt(0), .5);
      expect(LandingSlowMo.scaleAt(.79), .5);
      expect(LandingSlowMo.scaleAt(1.15), closeTo(.75, 1e-9));
      expect(LandingSlowMo.scaleAt(1.5), 1);
      expect(LandingSlowMo.scaleAt(3), 1);
      var prev = 0.0;
      for (var t = 0.0; t <= 1.6; t += .01) {
        final v = LandingSlowMo.scaleAt(t);
        expect(v, greaterThanOrEqualTo(prev - 1e-12));
        prev = v;
      }
    });

    test('§17 / §27 the comet activity lasts until the landing is done', () {
      final s = RunState(seed: 1, viewHeight: 711)..cometLanding = true;
      expect(RunActivity.of(s), RunActivity.comet);
      s.cometLanding = false;
      expect(RunActivity.of(s), isNull);
    });
  });

  group('§17 comet landing in a run', () {
    for (final star in [false, true]) {
      _tester().testGameWidget(
        '§17.1 ${star ? 'star' : 'pair COMET gift'}: control returns with '
        'one flap (impulse, flap.mp3 once, 45–65 pt rise) and the quiet '
        'slow motion (0.5 → 1 by +1.5 s real time)',
        setUp: _setUp,
        verify: (game, _) async {
          final sfx = sfxLog(game);
          final rateCalls = <double>[];
          final ride = await _toLanding(game, star: star, sfx: sfx);
          final r = game.run!;
          // The frame control returned: the flap impulse, one flap.mp3.
          final vy = game.runBirdVelocityY!;
          expect(vy, closeTo(-Config.flapVelocity, 1e-6));
          expect(sfx.where((e) => e == Sfx.flap.name).length, 1,
              reason: sfx.toString());
          expect(game.runBird!.inRide, isFalse);
          expect(r.state.timeScale, .5);
          expect(r.clock.timeScale, .5);
          expect(game.sound.musicRate, 1);
          // The rise stays in the flap band.
          final y0 = game.runBirdPosition!.y;
          var top = y0;
          final scales = <(double, double)>[];
          for (var f = 1; f <= 120; f++) {
            game.update(1 / 60);
            rateCalls.add(game.sound.musicRate);
            scales.add((f / 60, r.state.timeScale));
            top = math.min(top, game.runBirdPosition!.y);
          }
          final rise = y0 - top;
          expect(rise, inInclusiveRange(45, 65));
          for (final (t, v) in scales) {
            if (t < .8 - 1e-9) {
              expect(v, .5, reason: 't=$t');
            } else if (t >= 1.5 - 1e-9) {
              expect(v, 1, reason: 't=$t');
            } else {
              expect(v, closeTo(LandingSlowMo.scaleAt(t), 1e-9));
            }
          }
          expect(rateCalls.every((v) => v == 1), isTrue);
          // Quiet: no hourglass sounds, no vignette.
          expect(sfx, isNot(contains(Sfx.hourglassStart.name)));
          expect(sfx, isNot(contains(Sfx.hourglassTick.name)));
          expect(game.world.children.whereType<ScreenEdgeGlow>(), isEmpty);
          expect(r.state.cometLanding, isFalse);
          expect(ride.done, isTrue);
        },
      );
    }

    _tester().testGameWidget(
      '§17.1 a tap at +0.2 s flaps normally',
      setUp: _setUp,
      verify: (game, _) async {
        await _toLanding(game);
        _frames(game, 12);
        final sfx = sfxLog(game)..clear();
        game.onScreenTap();
        expect(game.runBirdVelocityY, closeTo(-Config.flapVelocity, 1e-6));
        expect(sfx, contains(Sfx.flap.name));
      },
    );

    _tester().testGameWidget(
      '§17.2 Hourglass during the landing: the lower scale wins; the '
      'landing still ends at +1.5 s, the Hourglass keeps its own',
      setUp: _setUp,
      verify: (game, _) async {
        await _toLanding(game);
        final run = game.run!;
        _frames(game, 6);
        expect(_f<TimedPowerupSlot>(run).start(CapsuleType.hourglass), isTrue);
        for (var f = 7; f <= 60 * 2; f++) {
          game.update(1 / 60);
          final t = f / 60;
          final want = math.min(
            LandingSlowMo.scaleAt(t),
            _f<HourglassFeature>(run).scale,
          );
          expect(run.state.timeScale, closeTo(want, 1e-9), reason: 't=$t');
          if (t > 1.5 + 1e-9) expect(run.state.cometLanding, isFalse);
        }
        expect(run.state.timeScale, closeTo(.45, 1e-9));
      },
    );

    _tester().testGameWidget(
      '§17.2 pause freezes the landing; it resumes where it was',
      setUp: _setUp,
      verify: (game, _) async {
        await _toLanding(game);
        final run = game.run!;
        _frames(game, 18);
        final t0 = _comet(run).landing!.t;
        game.pause();
        _frames(game, 120);
        expect(_comet(run).landing!.t, t0);
        expect(run.state.timeScale, .5);
        game.resume();
        _frames(game, 90);
        expect(run.state.timeScale, 1);
        expect(_comet(run).landing!.active, isFalse);
      },
    );

    _tester().testGameWidget(
      '§17.2 a death clears it (no resume after a revive)',
      setUp: _setUp,
      verify: (game, _) async {
        await _toLanding(game);
        final run = game.run!;
        _frames(game, 6);
        killRun(game);
        expect(run.state.timeScale, 1);
        expect(run.clock.timeScale, 1);
        expect(run.state.cometLanding, isFalse);
        expect(_comet(run).landing!.active, isFalse);
        run.revive(ReviveKind.ad);
        expect(_comet(run).landing!.active, isFalse);
      },
    );

    _tester().testGameWidget(
      '§17.2 a portal ride starting during the landing ends it at once',
      setUp: _setUp,
      verify: (game, _) async {
        await _toLanding(game);
        final run = game.run!;
        _frames(game, 6);
        run.events.emit(const RideStarted(RideKind.portal, RideId.cannon));
        expect(run.state.timeScale, 1);
        expect(_comet(run).landing!.active, isFalse);
      },
    );
  });
}
