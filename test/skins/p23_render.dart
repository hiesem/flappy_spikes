import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/gear_art_v23.dart';
import 'package:flappy_spikes/skins/art/hat_art_v23.dart';
import 'package:flappy_spikes/skins/art/hoop_art_v23.dart';
import 'package:flappy_spikes/skins/art/hoop_painter.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/art/trail.dart';
import 'package:flappy_spikes/skins/art/trail_v23.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/painting.dart';

/// Shared renderers of the PRD-2.3 §19.6 goldens and the port check.

/// The 60 new items in page order (H1–H15, G1–G15, O1–O15, T1–T15).
final List<(SkinLayer, String)> p23Items = [
  for (final id in HatArtV23.ids) (SkinLayer.hat, id),
  for (final id in GearArtV23.ids) (SkinLayer.gear, id),
  for (final id in HoopArtV23.ids) (SkinLayer.hoop, id),
  for (final id in TrailV23.ids) (SkinLayer.trail, id),
];

/// One port-check cell (160 x 110 art px), exactly as
/// `tool/skins_port/harness.html` draws it: the item on the Classic bird,
/// the hoop around it, the trail behind it after 90 seeded 1/60 s steps.
void paintPortCell(Canvas c, SkinLayer layer, String id, double t) {
  c.drawRect(const Rect.fromLTWH(0, 0, 160, 110),
      Paint()..color = const Color(0xFFFCD9EE));
  c.save();
  c.clipRect(const Rect.fromLTWH(0, 0, 160, 110));
  switch (layer) {
    case SkinLayer.hat:
      c.translate(80, 72);
      c.scale(1.7);
      LookPainter.paint(c, Look(bird: 'classic', hat: id), t: t);
    case SkinLayer.gear:
      c.translate(84, 58);
      c.scale(1.7);
      LookPainter.paint(c, Look(bird: 'classic', gear: id), t: t);
    case SkinLayer.hoop:
      HoopPainter.paintHalf(c, id, const Offset(80, 55), 42, t, front: false);
      c.save();
      c.translate(80, 55);
      c.scale(1.2);
      LookPainter.paint(c, const Look(bird: 'classic'), t: t);
      c.restore();
      HoopPainter.paintHalf(c, id, const Offset(80, 55), 42, t, front: true);
    case SkinLayer.trail:
      const kk = 1.6, hx = 112.0, hy = 55.0;
      final e = TrailEmitter(id, random: math.Random(1));
      const head = Offset(hx - 14 * kk, hy);
      for (var i = 0; i < 90; i++) {
        e.emit(head, 1 / 60, k: kk, vx: -150);
        e.step(1 / 60);
      }
      e.paint(c, k: kk, head: head);
      c.save();
      c.translate(hx, hy);
      c.scale(kk);
      LookPainter.paint(c, const Look(bird: 'classic'), t: t);
      c.restore();
    case SkinLayer.bird:
      break;
  }
  c.restore();
}

/// Renders [cells] (each painted in a [w] x [h] art-unit box) into a grid
/// image at [scale] device px per unit.
Future<ui.Image> renderGrid(
  List<void Function(Canvas)> cells, {
  required double w,
  required double h,
  int cols = 4,
  double scale = 2,
  Color background = const Color(0xFFFFFFFF),
}) async {
  final rows = (cells.length / cols).ceil();
  final pw = (cols * w * scale).round(), ph = (rows * h * scale).round();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)
    ..drawRect(Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble()),
        Paint()..color = background)
    ..scale(scale);
  for (var i = 0; i < cells.length; i++) {
    canvas
      ..save()
      ..translate((i % cols) * w, (i ~/ cols) * h);
    cells[i](canvas);
    canvas.restore();
  }
  return rec.endRecording().toImage(pw, ph);
}

Future<void> writePng(ui.Image image, String path) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}
