import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/effects/spike_teeth.dart';
import 'package:flappy_spikes/run/hoops/motion/hoop_motion.dart';
import 'package:flappy_spikes/run/hoops/motion/motion_guide.dart';
import 'package:flappy_spikes/run/hoops/ring_painter.dart';
import 'package:flappy_spikes/run/pickups/heart_pickup.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP-1b screenshot check (ARCH §7.1): angled rings (§5.11,
/// `design/menu_v2/rings_angled.png`) and moving rings with their guides
/// (§5.12, `moving_1..4.png`), drawn with the shared masters (strips #1,
/// ring #3, bird #4, `DashedPathPainter`) at the mock scale 1.5 (480 wide),
/// at 711 and 568 pt. Written to `build/shots/run/rings/` for a look next to
/// the mocks; nothing is asserted beyond "rendered".
const String outDir = 'build/shots/run/rings';
const double k = 1.5;
const Color bg = Color(0xFFF1F1F1);
const Color fg = Color(0xFF828282);
const double opening = 92;

Future<void> _write(String name, double h, void Function(Canvas c) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(k);
  canvas.drawRect(Rect.fromLTWH(0, 0, 320, h), Paint()..color = bg);
  SpikeTeethPainter.paint(canvas, width: 320, color: fg);
  canvas.save();
  canvas.translate(0, h);
  canvas.scale(1, -1);
  SpikeTeethPainter.paint(canvas, width: 320, color: fg);
  canvas.restore();
  draw(canvas);
  final image = await recorder.endRecording().toImage(
    (320 * k).round(),
    (h * k).round(),
  );
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  final file = File('$outDir/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  debugPrint('SHOT ${file.path}');
  expect(bytes.length, greaterThan(1000));
}

void _bird(Canvas c, Offset p) {
  c.save();
  c.translate(p.dx, p.dy);
  c.scale(Config.lookScale);
  c.translate(1, 0);
  LookPainter.paint(c, Look.defaults, t: .3);
  c.restore();
}

/// A ring at [home] with [spec] posed at run time [t] (+ [tiltDeg]); its
/// guide under it. Returns the ring's centre and angle.
(Offset, double) _moving(
  Canvas c,
  Offset home,
  MotionSpec? spec, {
  double t = 0,
  double tiltDeg = 0,
}) {
  var centre = home;
  var angle = tiltDeg * math.pi / 180;
  if (spec != null) {
    final m = HoopMotion.fromSpec(spec)..poseAt(t);
    centre = home + Offset(m.offset.x, m.offset.y);
    angle += m.angleOffset;
    c.save();
    c.translate(home.dx, home.dy);
    MotionGuidePainter.paint(
      c,
      spec,
      opening: opening,
      color: fg,
      ring: Offset(m.offset.x, m.offset.y),
    );
    c.restore();
  }
  return (centre, angle);
}

/// Back halves, the bird, front halves (master #3 around the bird).
void _scene(Canvas c, List<(Offset, double)> rings, Offset bird) {
  for (final (p, a) in rings) {
    RingPainter.paintHalf(
      c,
      centre: p,
      opening: opening,
      front: false,
      tilt: a,
    );
  }
  _bird(c, bird);
  for (final (p, a) in rings) {
    RingPainter.paintHalf(c, centre: p, opening: opening, front: true, tilt: a);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final h in [711.0, 568.0]) {
    final mid = h / 2;
    final tag = h.toInt();

    testWidgets('§5.11 angled rings (rings_angled.png) @$tag', (tester) async {
      await tester.runAsync(() async {
        await _write('5_11_angled_$tag', h, (c) {
          final a = _moving(c, Offset(47, mid - 55), null, tiltDeg: 30);
          final b = _moving(c, Offset(280, mid + 40), null, tiltDeg: -20);
          _scene(c, [a, b], Offset(RunConfig.birdX, mid - 10));
        });
        // Every tilt step of §3.10.
        await _write('5_11_tilt_steps_$tag', h, (c) {
          final steps = [-20.0, -10.0, 0.0, 15.0, 30.0, 45.0];
          final rings = [
            for (var i = 0; i < steps.length; i++)
              _moving(c, Offset(30 + i * 52, mid), null, tiltDeg: steps[i]),
          ];
          _scene(c, rings, Offset(RunConfig.birdX, mid + 160));
        });
      });
    });

    testWidgets('§5.12 moving rings with guides (moving_1..4.png) @$tag', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // moving_1: a horizontal slide with the bird passing through.
        await _write('5_12_m1_horizontal_$tag', h, (c) {
          final r = _moving(
            c,
            Offset(82, mid),
            const MotionSpec(
              type: MotionType.horizontal,
              axisDeg: 90,
              halfTravel: 60,
              speed: 34,
              phase: .12,
            ),
          );
          _scene(c, [r], Offset(RunConfig.birdX, mid));
        });
        // moving_2: a diagonal (↘) slide just ahead of the bird.
        await _write('5_12_m2_diagonal_$tag', h, (c) {
          final r = _moving(
            c,
            Offset(175, mid + 10),
            const MotionSpec(
              type: MotionType.diagonal,
              axisDeg: 52,
              halfTravel: 60,
              speed: 34,
              phase: .1,
            ),
          );
          _scene(c, [r], Offset(RunConfig.birdX + 10, mid - 25));
        });
        // moving_3: an orbit (clockwise arrows).
        await _write('5_12_m3_orbit_$tag', h, (c) {
          final r = _moving(
            c,
            Offset(243, mid),
            const MotionSpec(
              type: MotionType.orbit,
              rx: RunConfig.orbitRx,
              ry: RunConfig.orbitRy,
              omega: RunConfig.orbitOmega,
            ),
            t: .4,
          );
          _scene(c, [r], Offset(RunConfig.birdX + 10, mid));
        });
        // moving_4: a vertical rail and a diagonal (↗) slide.
        await _write('5_12_m4_rail_diagonal_$tag', h, (c) {
          final a = _moving(
            c,
            Offset(210, mid + 40),
            const MotionSpec(
              type: MotionType.rail,
              axisDeg: -12,
              halfTravel: 50,
              speed: 34,
              phase: .6,
            ),
          );
          final b = _moving(
            c,
            Offset(-20, mid - 60),
            const MotionSpec(
              type: MotionType.diagonal,
              axisDeg: -52,
              halfTravel: 60,
              speed: 34,
              phase: .3,
            ),
          );
          _scene(c, [a, b], Offset(RunConfig.birdX + 10, mid));
        });
        // The swing (rope from above the top spikes) and the rock.
        await _write('5_12_swing_rock_$tag', h, (c) {
          final swing = _moving(
            c,
            Offset(110, mid + 60),
            MotionSpec(
              type: MotionType.swing,
              amplitudeDeg: 15,
              period: 1.8,
              rope:
                  mid + 60 - RunConfig.stripHeight + RunConfig.swingPivotAbove,
              phase: .9,
            ),
          );
          final rock = _moving(
            c,
            Offset(260, mid - 80),
            const MotionSpec(
              type: MotionType.rock,
              amplitudeDeg: 15,
              period: 3,
              phase: 1,
            ),
            tiltDeg: 15,
          );
          _scene(c, [swing, rock], Offset(RunConfig.birdX, mid - 140));
        });
        // The heart pickup (WP-2a, §5.2) mid-gap.
        await _write('3_3_heart_$tag', h, (c) {
          final heart = HeartPickup(
            GapItemPlan(kind: ElementId.heart, trackX: 160, y: mid - 40),
          );
          c.save();
          c.translate(160 - heart.size.x / 2, mid - 40 - heart.size.y / 2);
          heart.render(c);
          c.restore();
          _scene(c, [
            (Offset(5, mid), 0.0),
            (Offset(315, mid - 80), 0.0),
          ], Offset(RunConfig.birdX, mid));
        });
      });
    });
  }
}
