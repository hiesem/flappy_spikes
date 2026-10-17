// Audit HIDE (2026-10-17, owner bug): "when the bird has an egg (not
// hatched) and goes through the roller coaster, when the bird is hidden
// (like at the rocket or cannon) the egg is still visible."
//
// Owner rule: when the bird is hidden, everything attached to or following
// it hides with it and comes back exactly when the bird does. One signal:
// `Bird.presented` (the bird art's drawn opacity > 0), read by every
// `BirdAttachment`. These tests fly every portal ride (and the comet) with
// the attachments on and check, frame by frame, attachment drawn ⇔ bird
// drawn; and they hide the bird by the other sources' path (the drawn
// opacity: Black Hole swallow, phoenix no-body start) for the attachments
// that never meet a ride (Hourglass clock, Mini Bird bubbles).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/effects/bird_attachment.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/egg.dart';
import 'package:flappy_spikes/run/items/extra_life.dart';
import 'package:flappy_spikes/run/items/fever.dart';
import 'package:flappy_spikes/run/items/hourglass.dart';
import 'package:flappy_spikes/run/items/mini_bird.dart';
import 'package:flappy_spikes/run/items/shield.dart';
import 'package:flappy_spikes/run/items/timed_powerup.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/rides/ride_theme.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const String _outDir = 'build/shots/audit/hide';

/// Counts every draw call a render makes.
class _CountingCanvas implements ui.Canvas {
  int draws = 0;
  int depth = 1;

  @override
  void save() => depth++;

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) => depth++;

  @override
  void restore() => depth--;

  @override
  int getSaveCount() => depth;

  @override
  dynamic noSuchMethod(Invocation i) {
    final n = i.memberName.toString();
    if (n.contains('draw')) draws++;
    return null;
  }
}

int _draws(Component c) {
  final canvas = _CountingCanvas();
  c.renderTree(canvas);
  expect(canvas.depth, 1, reason: 'balanced save / restore');
  return canvas.draws;
}

T _f<T>(RunController r) => r.features.whereType<T>().single;

EggView _egg(RunController r) => _f<EggFeature>(r).view!;
ShieldCircle _shield(RunController r) => _f<ShieldFeature>(r).circle!;
HeartBadge _badge(RunController r) => _f<ExtraLifeFeature>(r).badge!;
FireMaster _fire(RunController r) => _f<FeverFeature>(r).fire!;

/// The streak's trail component (private type; read through the mixin).
BirdAttachment _trail(FlappySpikesGame g) => g.world.children
    .whereType<BirdAttachment>()
    .firstWhere((c) => c.runtimeType.toString() == '_TrailComponent');

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
      () {
        final g = createRunTestGame(worldHeight: h, seed: 5);
        // Nothing may knock the attachments off on the way in.
        g.runDebug.god = true;
        return g;
      },
      gameSize: Vector2(320, h),
    );

Future<void> _setUp(FlappySpikesGame game, _) async {
  await game.ready();
  await preloadImages(game);
}

/// Puts every worn attachment on the bird (egg or chick, shield, extra-life
/// badge, fire); called every frame so a graze or a streak reset on the
/// approach cannot take one off.
void _wear(RunController run, {required bool chick}) {
  final s = run.state;
  if (s.egg == null || (chick && s.egg!.stage != EggStage.chick)) {
    s.egg = EggState()..stage = chick ? EggStage.chick : EggStage.egg;
    // As a fresh pickup does: forget a chick that already left.
    _f<EggFeature>(run).view?.reset();
  }
  s.shield = true;
  s.extraLife = true;
  s.onFire = true;
}

/// One frame's check: every attachment is drawn exactly while the bird is.
void _checkFrame(FlappySpikesGame game, RunController run, {required bool chick}) {
  final shown = game.runBird!.presented;
  final egg = _egg(run);
  final why = 'bird presented: $shown';
  if (chick) {
    expect(egg.paintsChick, shown, reason: why);
  } else {
    expect(egg.paintsEgg, shown, reason: why);
  }
  expect(_draws(egg) > 0, shown, reason: 'egg view, $why');
  expect(_draws(_shield(run)) > 0, shown, reason: 'shield, $why');
  expect(_draws(_badge(run)) > 0, shown, reason: 'heart badge, $why');
  final fire = _fire(run);
  if (!shown) {
    expect(fire.showing, isFalse, reason: 'fire halo, $why');
    expect((_trail(game) as dynamic).active, isFalse, reason: 'trail, $why');
  }
  // Every wholly worn attachment in the world, generically.
  for (final a in game.world.children.whereType<BirdAttachment>()) {
    expect(a.birdPresented, shown);
    if (a.hidesWholly && !shown) expect(_draws(a), 0, reason: '$a');
  }
}

Future<RunController> _wornRide(
  FlappySpikesGame game,
  RideId id, {
  required bool chick,
}) async {
  final run = await startRun(game, startHoopIndex: 25, ride: id);
  for (var i = 0; i < 60; i++) {
    _wear(run, chick: chick);
    game.update(1 / 60);
  }
  await flushAndMount(game);
  _wear(run, chick: chick);
  game.update(1 / 60);
  _checkFrame(game, run, chick: chick);
  expect(game.runBird!.presented, isTrue);
  expect(_draws(_egg(run)), greaterThan(0));
  expect(_draws(_badge(run)), greaterThan(0));
  return run;
}

/// Same render path as the screenshot tests.
Future<void> _shot(FlappySpikesGame game, String name) async {
  const scale = 2.0;
  final size = Vector2(320 * scale, (game.viewHeight * scale).roundToDouble());
  game.onGameResize(size);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.x, size.y),
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
  final file = File('$_outDir/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  debugPrint('SHOT ${file.path}');
}

void main() {
  // The rides that hide the bird, with a frame where it is hidden and the
  // frame it is back (as in test/p231/s13_shield_hidden_test.dart).
  final hides = <RideId, (bool Function(PortalRide), bool Function(PortalRide))>{
    RideId.cannon: (
      (r) => r.phase == RidePhase.exit && r.view.et > .5,
      (r) => r.phase == RidePhase.fly && r.view.ft > .1,
    ),
    RideId.volcano: (
      (r) => r.phase == RidePhase.exit && r.view.et > .2,
      (r) => r.phase == RidePhase.fly && r.view.ft > .1,
    ),
    RideId.space: (
      (r) => r.phase == RidePhase.exit && r.view.et > 1.3,
      (r) => r.phase == RidePhase.fly && r.view.ft > 1.0,
    ),
  };

  group('Audit HIDE: attachments hide with the bird', () {
    for (final id in RideId.values) {
      for (final chick in [false, true]) {
        final what = chick ? 'chick' : 'egg';
        final hidesBird = hides.containsKey(id);
        _tester().testGameWidget(
          '${id.name} ride with $what + shield + heart badge + fire: every '
          'frame, each attachment is drawn exactly while the bird is'
          '${hidesBird ? ' (hidden in the ride, back after)' : ' (never hidden)'}',
          setUp: _setUp,
          verify: (game, _) async {
            final run = await _wornRide(game, id, chick: chick);
            final f = _f<PortalRideFeature>(run);
            var rideFrames = 0, hiddenFrames = 0, backFrames = 0;
            var wasHidden = false;
            await _flyUntil(
              game,
              run,
              () => rideFrames > 0 && f.ride == null,
              maxSeconds: 60,
              each: () {
                _wear(run, chick: chick);
                if (f.ride == null) return;
                rideFrames++;
                final shown = game.runBird!.presented;
                if (!shown) {
                  hiddenFrames++;
                  wasHidden = true;
                } else if (wasHidden) {
                  backFrames++;
                }
                _checkFrame(game, run, chick: chick);
              },
            );
            expect(rideFrames, greaterThan(60));
            if (hidesBird) {
              expect(hiddenFrames, greaterThan(0));
              expect(backFrames, greaterThan(0));
            } else {
              expect(hiddenFrames, 0);
            }
            // Home again: all back.
            game.update(1 / 60);
            expect(game.runBird!.presented, isTrue);
            _checkFrame(game, run, chick: chick);
            expect(_draws(_egg(run)), greaterThan(0));
          },
        );
      }
    }

    _tester().testGameWidget(
      'comet ride never hides the bird: egg, shield and badge stay drawn',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(
          game,
          startHoopIndex: ElementId.comet.firstPossible!,
          force: [ElementId.comet],
        );
        var rideFrames = 0;
        await _flyUntil(
          game,
          run,
          () => rideFrames > 0 && run.state.ride == null,
          maxSeconds: 60,
          each: () {
            _wear(run, chick: false);
            if (run.state.ride?.kind != RideKind.comet) return;
            rideFrames++;
            expect(game.runBird!.presented, isTrue);
            _checkFrame(game, run, chick: false);
          },
        );
        expect(rideFrames, greaterThan(60));
      },
    );

    _tester().testGameWidget(
      'any other hide (Black Hole swallow, phoenix no-body start: the drawn '
      'opacity 0) hides egg, shield, badge, fire and trail; opacity back, '
      'all back',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await _wornRide(game, RideId.sea, chick: false);
        final bird = game.runBird!;
        bird.setSpriteOpacity(0);
        _checkFrame(game, run, chick: false);
        expect(_draws(_egg(run)), 0);
        expect(_draws(_shield(run)), 0);
        expect(_draws(_badge(run)), 0);
        expect(_fire(run).showing, isFalse);
        // A fade keeps them (they hide only with the bird).
        bird.setSpriteOpacity(.25);
        expect(_draws(_egg(run)), greaterThan(0));
        expect(_draws(_badge(run)), greaterThan(0));
        bird.setSpriteOpacity(1);
        _checkFrame(game, run, chick: false);
        expect(_fire(run).showing, isTrue);
      },
    );

    _tester().testGameWidget(
      'Hourglass clock ring and ghosts: none from a hidden bird',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game, startHoopIndex: 25);
        final slot = _f<TimedPowerupSlot>(run);
        expect(slot.start(CapsuleType.hourglass), isTrue);
        for (var i = 0; i < 30; i++) {
          game.update(1 / 60);
        }
        await flushAndMount(game);
        final hg = _f<HourglassFeature>(run);
        final trail = hg.trail!;
        expect(trail.paintsClock, isTrue);
        hg.ghosts.clear();
        game.runBird!.setSpriteOpacity(0);
        expect(trail.paintsClock, isFalse);
        for (var i = 0; i < 30; i++) {
          game.runBird!.setSpriteOpacity(0);
          game.update(1 / 60);
        }
        expect(hg.ghosts, isEmpty, reason: 'no ghosts of a hidden bird');
        expect(_draws(trail), 0);
        game.runBird!.setSpriteOpacity(1);
        expect(trail.paintsClock, isTrue);
        expect(_draws(trail), greaterThan(0));
      },
    );

    _tester().testGameWidget(
      'Mini Bird bubbles: none from a hidden bird',
      setUp: _setUp,
      verify: (game, _) async {
        final run = await startRun(game, startHoopIndex: 25);
        expect(_f<TimedPowerupSlot>(run).start(CapsuleType.miniBird), isTrue);
        final mini = _f<MiniBirdFeature>(run);
        for (var i = 0; i < 60; i++) {
          game.update(1 / 60);
        }
        expect(mini.on, isTrue);
        run.particles.clear();
        for (var i = 0; i < 60; i++) {
          game.runBird!.setSpriteOpacity(0);
          mini.step(1 / 60, 1 / 60);
        }
        expect(run.particles.alive, 0, reason: 'no bubbles while hidden');
        game.runBird!.setSpriteOpacity(1);
        for (var i = 0; i < 60; i++) {
          mini.step(1 / 60, 1 / 60);
        }
        expect(run.particles.alive, greaterThan(0));
      },
    );
  });

  group('Audit HIDE evidence PNGs', () {
    for (final id in [RideId.cannon, RideId.space]) {
      _tester().testGameWidget(
        'egg + ${id.name}: hidden, then back',
        setUp: _setUp,
        verify: (game, tester) async {
          final run = await _wornRide(game, id, chick: false);
          final f = _f<PortalRideFeature>(run);
          final (hidden, back) = hides[id]!;
          await _flyUntil(
            game,
            run,
            () => f.ride != null && f.ride!.phase == RidePhase.ride && f.ride!.view.rt > 1,
            each: () => _wear(run, chick: false),
          );
          await tester.runAsync(() => _shot(game, 'egg_${id.name}_1_riding'));
          await _flyUntil(
            game,
            run,
            () => f.ride != null && hidden(f.ride!),
            each: () => _wear(run, chick: false),
          );
          expect(game.runBird!.presented, isFalse);
          await tester.runAsync(() => _shot(game, 'egg_${id.name}_2_hidden'));
          await _flyUntil(
            game,
            run,
            () => f.ride == null || back(f.ride!),
            each: () => _wear(run, chick: false),
          );
          expect(game.runBird!.presented, isTrue);
          await tester.runAsync(() => _shot(game, 'egg_${id.name}_3_back'));
        },
      );
    }
  });
}
