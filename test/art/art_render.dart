import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders [draw] into a [width] x [height] RGBA image. Must be called inside
/// `tester.runAsync` (real event loop needed for toImage/toByteData).
Future<Uint8List> renderRgba(
  int width,
  int height,
  void Function(ui.Canvas canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

/// [renderRgba] from a widget test, on the real event loop.
Future<Uint8List> capture(
  WidgetTester tester,
  int width,
  int height,
  void Function(ui.Canvas canvas) draw,
) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    bytes = await renderRgba(width, height, draw);
  });
  return bytes;
}

/// The RGBA pixel at ([x], [y]) as `[r, g, b, a]`.
List<int> pixel(Uint8List rgba, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return [rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]];
}

/// True when any pixel is not fully transparent.
bool hasInk(Uint8List rgba) => inkPixels(rgba) > 0;

/// Number of pixels that are not fully transparent.
int inkPixels(Uint8List rgba) {
  var count = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 0) count++;
  }
  return count;
}

/// Renders [count] cells into a `columns`-wide montage PNG (light-grey cells,
/// like the mock tiles) at [scale] x. Cells are drawn top-left relative to
/// their own `cellWidth` x `cellHeight` box.
Future<void> writeMontage(
  WidgetTester tester,
  String path, {
  required int count,
  required int columns,
  required double cellWidth,
  required double cellHeight,
  required void Function(ui.Canvas cell, int index) drawCell,
  double scale = 1,
}) async {
  final rows = (count + columns - 1) ~/ columns;
  final width = (cellWidth * columns * scale).round();
  final height = (cellHeight * rows * scale).round();
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFE2E2E2),
    );
    canvas.scale(scale);
    for (var i = 0; i < count; i++) {
      canvas.save();
      canvas.translate((i % columns) * cellWidth, (i ~/ columns) * cellHeight);
      drawCell(canvas, i);
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    expect(bytes.length, greaterThan(1000));
  });
}

/// The classic bird of `skin_art.js` (`sq` shape, pink), used as a stand-in
/// for the WP-B1 LookPainter so the Afterimage copies have something to stamp.
void stubLook(ui.Canvas canvas, Look look, double t, bool flap) {
  final pink = ui.Paint()..color = const ui.Color(0xFFEC008C);
  final dark = ui.Paint()..color = const ui.Color(0xFFC2185B);
  canvas.save();
  canvas.translate(-22, -18);
  canvas.drawPath(
    ui.Path()
      ..moveTo(0, 8)
      ..lineTo(9, 14)
      ..lineTo(0, 20)
      ..close(),
    dark,
  );
  canvas.drawRect(const ui.Rect.fromLTWH(6, 3, 30, 30), pink);
  canvas.drawPath(
    flap
        ? (ui.Path()
            ..moveTo(12, 17)
            ..lineTo(24, 17)
            ..lineTo(12, 26)
            ..close())
        : (ui.Path()
            ..moveTo(12, 9)
            ..lineTo(24, 17)
            ..lineTo(12, 17)
            ..close()),
    dark,
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(26, 10, 4, 4),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  canvas.drawPath(
    ui.Path()
      ..moveTo(36, 14)
      ..lineTo(44, 20)
      ..lineTo(36, 26)
      ..close(),
    ui.Paint()..color = const ui.Color(0xFFFFB529),
  );
  canvas.restore();
}
