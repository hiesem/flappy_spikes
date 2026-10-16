import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';

import '../helpers.dart';
import 'backdrop_harness.dart';

/// PRD-2.4 §3 WP-W1 visual check in the game: the run with the new
/// background under today's game (evidence/wpW1/game, best-effort).
void main() {
  for (final (h, start) in [(568.0, 36), (730.0, 36), (568.0, 0), (730.0, 0)]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {
          'firstRunHintSeen': true,
          'metElements': [for (final e in ElementId.values) e.storageId],
        },
        worldHeight: h,
      ),
      gameSize: Vector2(320, h),
    ).testGameWidget(
      'game shot hoop $start @${h.round()}',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) async {
        g.runDebug.god = true;
        await startRun(g, startHoopIndex: start);
        await flyUntil(g, (r) => r.state.runClock > 4 || r.state.ride != null);
        if (!Directory(kBackdropEvidence).existsSync()) return;
        await tester.runAsync(() async {
          final size = Vector2(640, h * 2);
          g.onGameResize(size);
          final rec = ui.PictureRecorder();
          final canvas = ui.Canvas(rec);
          canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.x, size.y), ui.Paint()..color = g.backgroundColor());
          g.render(canvas);
          final img = await rec.endRecording().toImage(size.x.toInt(), size.y.toInt());
          await saveEvidence(img, 'wpW1/game', 'run_hoop${start}_${h.round()}');
        });
      },
    );
  }
}
