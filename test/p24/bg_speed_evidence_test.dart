import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_world.dart';
import 'package:flappy_spikes/run/debug/autopilot.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'backdrop_harness.dart';

/// 2026-10-19 WP-BG visual check (best-effort; only when the evidence
/// folder exists): frame strips of three run backgrounds at the same run
/// times at 1× (top row) and `Config.backgroundSpeedFactor` (bottom row),
/// and the game frames around a portal ride's return.
const String _dir = '/home/killerhis/Projects/flappyspikes/.worktrees/briefs15/evidence/bg';

/// The world speed of a cruising run (≈ 200 pt/s camera × 300/310).
const double _v = 194;

Future<void> _save(ui.Image img, String name) async {
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  await File('$_dir/$name.png').writeAsBytes(bytes);
}

Future<ui.Image> _sheet(List<List<ui.Image>> rows, double h) async {
  final cols = rows.first.length;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(ui.Rect.fromLTWH(0, 0, cols * 324.0, rows.length * (h + 4)),
      ui.Paint()..color = const ui.Color(0xFF000000));
  for (var r = 0; r < rows.length; r++) {
    for (var i = 0; i < rows[r].length; i++) {
      c.drawImage(rows[r][i], ui.Offset(i * 324.0, r * (h + 4)), ui.Paint());
    }
  }
  return rec.endRecording().toImage(cols * 324, (rows.length * (h + 4)).toInt());
}

void main() {
  final have = Directory(_dir).existsSync();

  // (name, world distance at time 0, scene index it must show)
  for (final (name, w0, scene) in [('forest_nest', 2000.0, 0), ('city', 29000.0, 2), ('underwater', 89200.0, 7)]) {
    test('strip $name: 1× vs ${Config.backgroundSpeedFactor}× at t 0…2 s', () async {
      expect(BackdropWorld.sceneAt(w0), scene);
      if (!have) return;
      const times = [0.0, .4, .8, 1.2, 1.6, 2.0];
      final rows = <List<ui.Image>>[];
      for (final speed in [1.0, Config.backgroundSpeedFactor]) {
        rows.add([
          for (final t in times)
            await renderBackdrop(cam: w0 + _v * t, t: 10 + t, speed: speed),
        ]);
      }
      await _save(await _sheet(rows, 568), 'strip_$name');
    });
  }

  for (final id in [RideId.cannon, RideId.sea]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        seed: 5,
        worldHeight: 568,
        prefs: {
          'firstRunHintSeen': true,
          'metElements': [for (final e in ElementId.values) e.storageId],
        },
      ),
      gameSize: Vector2(320, 568),
    ).testGameWidget(
      'ride return frames $id',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) async {
        if (!have) return;
        g.runDebug.god = true;
        final run = await startRun(g, startHoopIndex: 25, ride: id);
        for (var i = 0; i < 3; i++) {
          run.debugPass(perfect: true);
        }
        final f = run.features.whereType<PortalRideFeature>().single;
        final bot = Autopilot(run);
        final shots = <ui.Picture>[];
        var seen = false;
        var ret = -1;
        for (var i = 0; i < 60 * 60; i++) {
          if (f.ride != null) seen = true;
          if (f.ride == null && bot.shouldFlap()) g.onScreenTap();
          g.update(1 / 60);
          if (i % 10 == 0) await flushAndMount(g);
          if (seen && f.ride == null && ret < 0) ret = shots.length;
          g.onGameResize(Vector2(320, 568));
          final rec = ui.PictureRecorder();
          final c = ui.Canvas(rec);
          c.drawRect(const ui.Rect.fromLTWH(0, 0, 320, 568), ui.Paint()..color = g.backgroundColor());
          g.render(c);
          shots.add(rec.endRecording());
          // keep a window of frames only
          if (ret < 0 && shots.length > 12) shots.removeAt(0).dispose();
          if (ret >= 0 && shots.length >= ret + 12) break;
        }
        expect(ret, greaterThan(0));
        // every 2nd frame: 5 before the return frame, the return frame, 5 after
        final pick = [for (var k = ret - 10; k <= ret + 10; k += 2) k]
            .where((k) => k >= 0 && k < shots.length)
            .toList();
        await tester.runAsync(() async {
          final imgs = [for (final k in pick) await shots[k].toImage(320, 568)];
          final half = (imgs.length / 2).ceil();
          await _save(await _sheet([imgs.sublist(0, half), imgs.sublist(half)], 568), 'ride_return_${id.name}');
        });
      },
    );
  }
}
