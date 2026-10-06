import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/hoop_painter.dart';
import 'package:flappy_spikes/skins/art/trail.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import 'art_render.dart';

/// Renders every hoop and every trail to `build/art_check/` for eyeballing
/// against `design/menu_v2/skin_catalog.png`, `skinshop_hoops.png` and
/// `skinshop_trails.png` (the PNGs themselves are not committed).
///
/// `flutter test test/art/art_check_generator_test.dart`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const outDir = 'build/art_check';
  const cell = 96.0;

  /// Emits for [seconds] so a trail shows a steady-state stream.
  void prime(
    TrailEmitter e,
    double seconds,
    ui.Offset head, {
    double k = 1,
    double vx = -140,
  }) {
    const dt = 1 / 60;
    var elapsed = 0.0;
    while (elapsed < seconds - 1e-9) {
      e.emit(head, dt, k: k, vx: vx);
      e.step(dt);
      elapsed += dt;
    }
  }

  testWidgets('hoops.png: every hoop as the shop-grid tile', (tester) async {
    await writeMontage(
      tester,
      '$outDir/hoops.png',
      count: HoopPainter.ids.length,
      columns: 5,
      cellWidth: cell,
      cellHeight: cell,
      scale: 3.5,
      drawCell: (canvas, i) {
        HoopPainter.paintHoopTile(
          canvas,
          HoopPainter.ids[i],
          const ui.Offset(cell / 2, cell / 2),
          68 * .34,
          1,
        );
      },
    );
  });

  testWidgets('hoops_anim.png: animated hoops over four t values', (
    tester,
  ) async {
    const animated = ['neon', 'lava', 'ice', 'rainbow', 'galaxy', 'blackhole'];
    await writeMontage(
      tester,
      '$outDir/hoops_anim.png',
      count: animated.length * 4,
      columns: 4,
      cellWidth: cell,
      cellHeight: cell,
      scale: 3,
      drawCell: (canvas, i) {
        HoopPainter.paintHoopTile(
          canvas,
          animated[i ~/ 4],
          const ui.Offset(cell / 2, cell / 2),
          68 * .34,
          (i % 4) * .45,
        );
      },
    );
  });

  testWidgets('hoops_halves.png: back / front / both halves per hoop', (
    tester,
  ) async {
    await writeMontage(
      tester,
      '$outDir/hoops_halves.png',
      count: HoopPainter.ids.length * 3,
      columns: 3,
      cellWidth: 80,
      cellHeight: 80,
      scale: 3,
      drawCell: (canvas, i) {
        final id = HoopPainter.ids[i ~/ 3];
        final centre = const ui.Offset(40, 40);
        switch (i % 3) {
          case 0:
            HoopPainter.paintHalf(
              canvas,
              id,
              centre,
              26,
              .35,
              front: false,
              lineWidth: 7,
            );
          case 1:
            HoopPainter.paintHalf(
              canvas,
              id,
              centre,
              26,
              .35,
              front: true,
              lineWidth: 7,
            );
          case 2:
            HoopPainter.paintHalf(
              canvas,
              id,
              centre,
              26,
              .35,
              front: false,
              lineWidth: 7,
            );
            HoopPainter.paintHalf(
              canvas,
              id,
              centre,
              26,
              .35,
              front: true,
              lineWidth: 7,
            );
        }
      },
    );
  });

  testWidgets('trails.png: every trail as the shop-grid tile', (tester) async {
    await writeMontage(
      tester,
      '$outDir/trails.png',
      count: TrailEmitter.ids.length,
      columns: 5,
      cellWidth: cell,
      cellHeight: cell,
      scale: 3.5,
      drawCell: (canvas, i) {
        final id = TrailEmitter.ids[i];
        final e = TrailEmitter(
          id,
          random: math.Random(1),
          lookPainter: stubLook,
        )..look = Look.defaults;
        final orb = ui.Offset(cell / 2 + 84 * .74 - 42, cell / 2);
        prime(e, id == 'echo' ? 2 : 1, orb, k: TrailEmitter.tileScale, vx: -90);
        TrailEmitter.paintTrailTile(canvas, e, orb, 0, 1);
      },
    );
  });

  testWidgets('trails_detail.png: full trails behind the bird head', (
    tester,
  ) async {
    const width = 260.0;
    const height = 80.0;
    await writeMontage(
      tester,
      '$outDir/trails_detail.png',
      count: TrailEmitter.ids.length,
      columns: 1,
      cellWidth: width,
      cellHeight: height,
      scale: 3,
      drawCell: (canvas, i) {
        final id = TrailEmitter.ids[i];
        final e = TrailEmitter(
          id,
          random: math.Random(7),
          lookPainter: stubLook,
        )..look = Look.defaults;
        final head = ui.Offset(width * .78, height / 2);
        prime(e, id == 'echo' ? 2 : 1, head);
        e.paint(canvas);
        canvas.save();
        canvas.translate(head.dx, head.dy);
        stubLook(canvas, Look.defaults, 1, false);
        canvas.restore();
      },
    );
  });
}
