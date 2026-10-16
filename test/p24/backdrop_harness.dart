import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_world.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.4 §4 shared harness for the background tests (WP-W1; WP-W2 / W3
/// call it for their scenes and seams): render the background at a world
/// distance to an image, compare two frames, save evidence PNGs.

/// The evidence folder (outside git); null when it does not exist (CI).
const String kBackdropEvidence =
    '/home/killerhis/Projects/flappyspikes/.worktrees/briefs11/evidence';

/// Renders the background at world distance [cam] (prototype `cam`), run
/// clock [t], on a 320 × [viewHeight] view, at [scale] px per pt.
Future<ui.Image> renderBackdrop({
  required double cam,
  double t = 3,
  double viewHeight = 568,
  double scale = 1,
  ui.Color bg = const ui.Color(0xFFF1F1F1),
  ui.Color fg = const ui.Color(0xFF828282),
  BackdropPainter? painter,
}) async {
  final p = painter ?? BackdropPainter();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(scale);
  p.paint(canvas, cam: cam, t: t, viewHeight: viewHeight, bg: bg, fg: fg);
  final pic = recorder.endRecording();
  final img = await pic.toImage((kVW * scale).round(), (viewHeight * scale).round());
  pic.dispose();
  return img;
}

/// The raw RGBA bytes of [img].
Future<Uint8List> rgbaOf(ui.Image img) async =>
    (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

/// Pixels whose largest channel difference exceeds [threshold].
int diffPixels(Uint8List a, Uint8List b, {int threshold = 40}) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    var d = 0;
    for (var k = 0; k < 3; k++) {
      final x = (a[i + k] - b[i + k]).abs();
      if (x > d) d = x;
    }
    if (d > threshold) n++;
  }
  return n;
}

/// PRD-2.4 §4 test 9: the frames at [cam] and [cam] + 1 pt (same clock)
/// differ in at most [maxFraction] of the pixels (a 1-pt step moves the
/// ground 0.34 pt; a pop or a jump changes whole shapes).
Future<int> frameJump(double cam, {double viewHeight = 568, double t = 3}) async {
  final a = await renderBackdrop(cam: cam, viewHeight: viewHeight, t: t);
  final b = await renderBackdrop(cam: cam + 1, viewHeight: viewHeight, t: t);
  final n = diffPixels(await rgbaOf(a), await rgbaOf(b));
  a.dispose();
  b.dispose();
  return n;
}

/// Expects no jump between [cam] and [cam] + 1 (see [frameJump]).
Future<void> expectNoJump(
  double cam, {
  double viewHeight = 568,
  double maxFraction = .01,
  String? label,
}) async {
  final n = await frameJump(cam, viewHeight: viewHeight);
  final limit = (kVW * viewHeight * maxFraction).round();
  expect(n, lessThanOrEqualTo(limit),
      reason: '${label ?? ''} jump at cam $cam (view $viewHeight): $n px changed');
}

/// Saves [img] as a PNG into the evidence folder [sub]/[name].png (only when
/// the folder exists: best-effort, as the other evidence tests).
Future<void> saveEvidence(ui.Image img, String sub, String name) async {
  final dir = Directory('$kBackdropEvidence/$sub');
  if (!Directory(kBackdropEvidence).existsSync()) return;
  await dir.create(recursive: true);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  await File('${dir.path}/$name.png').writeAsBytes(bytes);
}
