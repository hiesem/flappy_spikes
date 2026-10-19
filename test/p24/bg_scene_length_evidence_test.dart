import 'dart:io';
import 'dart:ui' as ui;

import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_tables.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_world.dart';
import 'package:flappy_spikes/run/backdrop/seams/seam.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'backdrop_harness.dart';

/// 20-hoop scenes (owner 2026-10-19, 2.4.0+38) visual evidence: contact
/// sheets of the background across consecutive seams, written to the
/// run's evidence folder (outside git; skipped where it does not exist).
const String _out = '/home/killerhis/Projects/flappyspikes/.worktrees/briefs16/evidence/bg';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final f = FontLoader('Fredoka')..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
    await f.load();
  });
  final enabled = Directory(_out).existsSync();

  Future<void> sheet(String name, List<double> cams, {int cols = 10, double scale = .5, double h = 568}) async {
    final w = (kVW * scale).round(), hh = (h * scale).round();
    final rows = (cams.length / cols).ceil();
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, (w + 4) * cols.toDouble(), (hh + 4) * rows.toDouble()),
        ui.Paint()..color = const ui.Color(0xFF000000));
    for (var i = 0; i < cams.length; i++) {
      final img = await renderBackdrop(cam: cams[i], viewHeight: h, scale: scale, t: 3 + cams[i] / 200);
      canvas.drawImage(img, ui.Offset((i % cols) * (w + 4.0), (i ~/ cols) * (hh + 4.0)), ui.Paint());
      img.dispose();
    }
    final pic = rec.endRecording();
    final out = await pic.toImage((w + 4) * cols, (hh + 4) * rows);
    pic.dispose();
    final png = (await out.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    out.dispose();
    File('$_out/$name.png').writeAsBytesSync(png);
  }

  double reach(int k) => kSeams[(k - 1) % kNST] is FloorSeam ? kVWIN / 2 + kLinger : kVWIN / 2;

  test('every hoop from hoop 10 to hoop 110 (seams 1–5 on hoops 20, 40, 60, 80, 100)', () async {
    if (!enabled) return;
    await sheet('sequence_hoops_10_110', [for (var hp = 10; hp <= 110; hp++) hp * kPerHoop], cols: 10, scale: .4);
  }, timeout: const Timeout(Duration(minutes: 5)));

  for (final k in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
    test('seam $k: before its range, the window, after its range', () async {
      if (!enabled) return;
      final r = reach(k);
      final ds = <double>[
        -kE / 2, -r - 1, -kVWIN / 2, -kVWIN / 3, -kVWIN / 6, 0, kVWIN / 6, kVWIN / 3, kVWIN / 2,
        (kVWIN / 2 + r) / 2, r - 1, r + 1, kE / 2 - 1,
      ];
      // loop 2 (the Homecoming plays from hoop 200)
      final base = k * kE + (k == 10 ? 0 : kTotal);
      await sheet('seam${k.toString().padLeft(2, '0')}_hoop${(base / kPerHoop).round()}',
          [for (final d in ds) base + d], cols: ds.length, scale: .5);
      await sheet('seam${k.toString().padLeft(2, '0')}_730', [for (final d in ds) base + d],
          cols: ds.length, scale: .4, h: 730);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }

  test('WP-TAB 3:4 seam 5 at −kVWIN/4 (the Desk sky sample)', () async {
    if (!enabled) return;
    const e = 106.0;
    final p = BackdropPainter();
    p.basePaint.color = const ui.Color(0xFFFF00FF);
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec)..translate(e, 0);
    p.paint(canvas, cam: 5 * kE - kVWIN / 4, t: 3, viewHeight: 568,
        bg: const ui.Color(0xFFF1F1F1), fg: const ui.Color(0xFF828282), left: -e);
    final img = await rec.endRecording().toImage((kVW + e).round(), 568);
    final png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    File('$_out/tab_seam5_q25_568.png').writeAsBytesSync(png);
  });
}
