import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/kinds/saw/saw_kind.dart';
import 'package:flappy_spikes/run/hoops/kinds/switch/switch_kind.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-3d screenshot check (ARCH §7.1): real run frames of the saw rings
/// (§5.17 `sawring_{electric,ice,hole}_{fly,death}.png`), the switch rings
/// (§5.19 `switchring_{lock,laser,iris,sleepy,gift}_{off,open,fail}.png`)
/// and the Gift Box pairs (§5.20 `giftpair_{approach,pick}.png`). Writes
/// PNGs to `build/shots/run/hazard/` (never committed); nothing is asserted
/// beyond "rendered".
const String outDir = 'build/shots/run/hazard';

Future<void> _fonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  await Future.wait([lvdc.load(), opificio.load()]);
}

/// Same render path as `captureShot` (menu_screenshot_test.dart): resize
/// right before rendering (the harness reverts earlier resizes).
Future<void> shot(FlappySpikesGame game, double scale, String name) async {
  final size = Vector2(320 * scale, (game.viewHeight * scale).roundToDouble());
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
  final file = File('$outDir/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  debugPrint('SHOT ${file.path}: ${bytes.length} bytes');
  expect(bytes.length, greaterThan(10000));
}

/// Steps [seconds] (the autopilot flies while the run is playing),
/// flushing so parts added on the way mount and animate.
Future<void> _steps(FlappySpikesGame g, double seconds) async {
  if (g.state == GameState.playing) {
    await flyUntil(g, (_) => false, maxSeconds: seconds);
    return;
  }
  var frame = 0;
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    g.update(1 / 60);
    if (++frame % 5 == 0) await flushAndMount(g);
  }
  await flushAndMount(g);
}

void main() {
  setUpAll(_fonts);

  FlameTester<FlappySpikesGame> tester(double h) =>
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: h, seed: 4),
        gameSize: Vector2(320, h),
      );

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    await preloadImages(g);
    g.sound.enabled = false;
  }

  for (final h in [711.0, 568.0]) {
    // §5.17 saw rings.
    for (final (design, name) in [
      (SawDesign.liveWire, 'electric'),
      (SawDesign.frostRing, 'ice'),
      (SawDesign.blackHole, 'hole'),
    ]) {
      for (final moment in ['fly', 'death']) {
        final shotName = 'sawring_${name}_${moment}_${h.round()}';
        tester(h).testGameWidget(
          '§5.17 shot $shotName',
          setUp: (g, _) => prepare(g),
          verify: (game, tester) async {
            final run = await startRun(
              game,
              startHoopIndex: 20,
              force: [ElementId.saw],
            );
            final hoop = await flyToHoop(
              game,
              HoopKindId.saw,
              ElementId.saw,
              where: (x) => SawHoopKind.designOf(x) == design,
              maxSeconds: 120,
            );
            expect(hoop, isNotNull);
            if (moment == 'fly') {
              await flyUntil(game, (r) => hoop!.planeX - r.state.camX <= 165);
            } else {
              final ry = hoop!.opening / 2 + hoop.kind.rimRadius(hoop);
              await glideInto(
                game,
                hoop,
                hoop.position.y - ry + 4,
                seconds: .3,
                until: (r) => r.dying,
              );
              await _steps(game, switch (design) {
                SawDesign.liveWire => .3,
                SawDesign.frostRing => .5,
                SawDesign.blackHole => .55,
              });
            }
            await flushAndMount(game);
            run.debugFreeze();
            await tester.runAsync(() => shot(game, 1.5, shotName));
          },
        );
      }
    }

    // §5.19 switch rings.
    for (final (design, name) in [
      (SwitchDesign.lockdown, 'lock'),
      (SwitchDesign.laserGate, 'laser'),
      (SwitchDesign.powerIris, 'iris'),
      (SwitchDesign.snoozer, 'sleepy'),
      (SwitchDesign.giftWrap, 'gift'),
    ]) {
      for (final moment in ['off', 'open', 'fail']) {
        final shotName = 'switchring_${name}_${moment}_${h.round()}';
        tester(h).testGameWidget(
          '§5.19 shot $shotName',
          setUp: (g, _) => prepare(g),
          verify: (game, tester) async {
            final run = await startRun(
              game,
              startHoopIndex: 12,
              force: [ElementId.switchRing],
            );
            // The next switch takes this design (the course is otherwise
            // free; a 120 s wait for a random design is seed luck).
            run.director.debugForceSwitchDesign(design);
            final hoop = await flyToHoop(
              game,
              HoopKindId.switchRing,
              ElementId.switchRing,
              where: (x) {
                final p = SwitchRingKind.stateOf(x)?.pickup;
                final b = run.birdTrackPosition();
                return SwitchRingKind.designOf(x) == design &&
                    p != null &&
                    b != null &&
                    p.position.x > b.x + 120;
              },
              maxSeconds: 120,
            );
            expect(hoop, isNotNull);
            final st = SwitchRingKind.stateOf(hoop!)!;
            final p = st.pickup!;
            switch (moment) {
              case 'off':
                await flyUntil(game, (r) => p.position.x - r.state.camX <= 150);
              case 'open':
                await flyUntil(game, (_) => p.collected);
                await _steps(game, .55);
              case 'fail':
                p.position.y = hoop.position.y + 400;
                bool hold(_) {
                  final b = game.runBirdPosition!;
                  return b.y > hoop.position.y + 6 &&
                      (game.runBirdVelocityY ?? 0) > -40;
                }

                await flyUntil(game, (r) => r.dying, flap: hold);
                await _steps(game, .3);
            }
            await flushAndMount(game);
            run.debugFreeze();
            await tester.runAsync(() => shot(game, 1.5, shotName));
          },
        );
      }
    }

    // §5.20 Gift Box pairs.
    for (final moment in ['approach', 'pick']) {
      final shotName = 'giftpair_${moment}_${h.round()}';
      tester(h).testGameWidget(
        '§5.20 shot $shotName',
        setUp: (g, _) => prepare(g),
        verify: (game, tester) async {
          final run = await startRun(
            game,
            startHoopIndex: 12,
            force: [ElementId.pair],
          );
          final Hoop? hoop = await flyToHoop(
            game,
            HoopKindId.pair,
            ElementId.pair,
            maxSeconds: 120,
          );
          expect(hoop, isNotNull);
          if (moment == 'approach') {
            await flyUntil(game, (r) => hoop!.planeX - r.state.camX <= 210);
          } else {
            await glideInto(
              game,
              hoop!,
              hoop.position.y + hoop.rings.first,
              seconds: .5,
              until: (_) => hoop.resolved,
            );
            await _steps(game, .15);
          }
          await flushAndMount(game);
          run.debugFreeze();
          await tester.runAsync(() => shot(game, 1.5, shotName));
        },
      );
    }
  }
}
