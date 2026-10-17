import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP-TAB shared harness: screen shapes, rendering the whole game at a
/// screen size and saving evidence PNGs (best-effort, outside git).

/// The evidence folder (outside git).
const String kTabEvidence =
    '/home/killerhis/Projects/flappyspikes/.worktrees/briefs13/evidence/tab';

/// The game's `worldHeight` (`320 × h / w`) of a [w]:[h] portrait screen.
double worldHeightFor(double w, double h) => 320 * h / w;

/// Screen shapes: name, aspect w, aspect h.
const List<(String, double, double)> kShapes = [
  ('3x4', 3, 4),
  ('4x5', 4, 5),
  ('2x3', 2, 3),
  ('phone', 9, 19.5),
];

/// The canvas (px) for a [w]:[h] screen, [scale] px per game point on the
/// longer fit.
Vector2 canvasFor(double w, double h, {double height = 1136}) =>
    Vector2((height * w / h).roundToDouble(), height);

/// Renders [g] at [size] (px) into an image (inside `tester.runAsync`).
Future<ui.Image> renderGame(FlappySpikesGame g, Vector2 size) async {
  g.onGameResize(size);
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.x, size.y),
    ui.Paint()..color = g.backgroundColor(),
  );
  g.render(canvas);
  return rec.endRecording().toImage(size.x.toInt(), size.y.toInt());
}

/// Saves [img] as evidence `<sub>/<name>.png` when the folder exists.
Future<void> saveTabEvidence(ui.Image img, String sub, String name) async {
  if (!Directory(kTabEvidence).existsSync()) return;
  final dir = Directory('$kTabEvidence/$sub');
  await dir.create(recursive: true);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  await File('${dir.path}/$name.png').writeAsBytes(bytes);
}

/// Renders and saves (best-effort) a shot of [g] at [size].
Future<void> shoot(
  WidgetTester tester,
  FlappySpikesGame g,
  Vector2 size,
  String sub,
  String name,
) async {
  await tester.runAsync(() async {
    final img = await renderGame(g, size);
    await saveTabEvidence(img, sub, name);
    img.dispose();
  });
}
