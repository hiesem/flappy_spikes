// Records every portal roller-coaster ride from the real game (same code,
// assets and render path as the store screenshots) as raw RGBA frames for
// ffmpeg. Dev tool, skipped unless FS_RECORD_RIDES=<out dir> is set:
//   FS_RECORD_RIDES=/tmp/rides flutter test test/tools/record_rides_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Future<void> _loadFonts() async {
  final fonts = {
    'LVDC Common2': 'assets/fonts/LVDCC.TTF',
    'Opificio Neue': 'assets/fonts/Opificio_neue-regular.ttf',
    'Fredoka': 'assets/fonts/Fredoka-SemiBold.ttf',
  };
  await Future.wait([
    for (final e in fonts.entries)
      (FontLoader(e.key)..addFont(rootBundle.load(e.value))).load(),
  ]);
}

void main() async {
  final out = Platform.environment['FS_RECORD_RIDES'];
  if (out == null) {
    test('record rides (set FS_RECORD_RIDES)', () {}, skip: true);
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFonts();

  final size = Vector2(540, 1200); // 320 × 711 pt at 1.6875×
  const dt = 1 / 60;

  Future<void> frame(FlappySpikesGame game, IOSink sink) async {
    game.onGameResize(size);
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size.x, size.y),
      ui.Paint()..color = game.backgroundColor(),
    );
    game.render(canvas);
    final img = await rec.endRecording().toImage(size.x.toInt(), size.y.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    sink.add(data!.buffer.asUint8List());
  }

  for (final id in RideId.values) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 711, seed: 5),
      gameSize: size,
    ).testGameWidget(
      'record ${id.name}',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        game.onGameResize(size);
      },
      verify: (game, tester) async {
        final run = await startRun(game, startHoopIndex: 25, ride: id);
        final f = run.features.whereType<PortalRideFeature>().single;
        final bot = Autopilot(run);
        Hoop? portal() {
          for (final h in run.spawner.hoops) {
            if (h.plan.kind == HoopKindId.portal) return h;
          }
          return null;
        }

        // Fly until the portal is about one screen ahead of the bird.
        for (var i = 0; i < 60 * 60; i++) {
          final p = portal();
          final b = run.birdTrackPosition();
          if (p != null && b != null && p.planeX - b.x < 250) break;
          if (bot.shouldFlap()) game.onScreenTap();
          game.update(dt);
          if (i % 10 == 0) await flushAndMount(game);
        }
        final file = File('$out/${id.name}.rgba');
        // Real IO only completes outside the test's fake clock.
        late final IOSink sink;
        await tester.runAsync(() async {
          await file.parent.create(recursive: true);
          sink = file.openWrite();
        });
        var frames = 0;
        var started = false;
        var after = 0.0;
        for (var i = 0; i < 60 * 40; i++) {
          if (f.ride != null) started = true;
          if (started && f.ride == null) {
            after += dt;
            if (after > 1.5) break;
          }
          if (bot.shouldFlap()) game.onScreenTap();
          game.update(dt);
          if (i % 10 == 0) await flushAndMount(game);
          if (i.isEven) {
            await tester.runAsync(() => frame(game, sink));
            frames++;
          }
        }
        await tester.runAsync(() => sink.close());
        // ignore: avoid_print
        print('RIDE ${id.name}: $frames frames, started=$started');
        expect(started, isTrue);
      },
    );
  }
}
