// Records one forced comet ride (PRD-2.3.1 §16 layout check) from the real
// game as raw RGBA frames for ffmpeg, plus a text log of the comet layout.
// Dev tool, skipped unless FS_RECORD_COMET=<out dir> is set:
//   FS_RECORD_COMET=/tmp/comet flutter test test/tools/record_comet_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/items/comet.dart';
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
  final out = Platform.environment['FS_RECORD_COMET'];
  if (out == null) {
    test('record comet (set FS_RECORD_COMET)', () {}, skip: true);
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
    final img = await rec.endRecording().toImage(
      size.x.toInt(),
      size.y.toInt(),
    );
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    sink.add(data!.buffer.asUint8List());
  }

  final start = int.tryParse(Platform.environment['FS_COMET_AT'] ?? '') ?? 30;
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711, seed: 5),
    gameSize: size,
  ).testGameWidget(
    'record comet',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      game.onGameResize(size);
    },
    verify: (game, tester) async {
      final run = await startRun(
        game,
        startHoopIndex: start,
        force: [ElementId.comet],
      );
      final f = run.features.whereType<CometFeature>().single;
      final bot = Autopilot(run);
      // Fly until the comet star hoop is about one screen ahead.
      for (var i = 0; i < 60 * 60; i++) {
        final b = run.birdTrackPosition();
        final star = run.spawner.hoops.where((h) => h.plan.cometHang);
        if (b != null && star.isNotEmpty && star.first.planeX - b.x < 260) {
          break;
        }
        if (bot.shouldFlap()) game.onScreenTap();
        game.update(dt);
        if (i % 10 == 0) await flushAndMount(game);
      }
      final file = File('$out/comet.rgba');
      final log = StringBuffer();
      late final IOSink sink;
      await tester.runAsync(() async {
        await file.parent.create(recursive: true);
        sink = file.openWrite();
      });
      var frames = 0;
      var started = false;
      var after = 0.0;
      double? endX;
      for (var i = 0; i < 60 * 30; i++) {
        if (!started && f.active) {
          started = true;
          log
            ..writeln(
              'comet start frame $frames, bird x '
              '${run.state.camX + RunConfig.birdX}',
            )
            ..writeln('stations ${run.director.cometStations}')
            ..writeln('locked end ${run.director.cometLockedEnd}');
        }
        if (started && !f.active && endX == null) {
          endX = run.state.camX + RunConfig.birdX;
          log.writeln('comet end frame $frames, bird x $endX');
        }
        if (endX != null) {
          after += dt;
          if (after > 4) break;
        }
        if (bot.shouldFlap()) game.onScreenTap();
        game.update(dt);
        if (i % 10 == 0) await flushAndMount(game);
        if (i.isEven) {
          await tester.runAsync(() => frame(game, sink));
          frames++;
        }
      }
      for (final p in run.spawner.slotLog.where((p) => p.index >= start)) {
        log.writeln(
          'slot ${p.index} x ${p.trackX.toStringAsFixed(1)} '
          'y ${p.centreY.toStringAsFixed(1)} ride ${p.duringRide} '
          '${p.kind.name}${p.cometHang ? ' (star)' : ''}',
        );
      }
      log.writeln(
        'run ended: ${run.ended}, hoops passed '
        '${run.state.hoopsPassed}',
      );
      await tester.runAsync(() async {
        await sink.close();
        await File('$out/comet_layout.txt').writeAsString(log.toString());
      });
      // ignore: avoid_print
      print('COMET: $frames frames, started=$started');
      expect(started, isTrue);
    },
  );
}
