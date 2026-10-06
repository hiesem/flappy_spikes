import 'dart:io';
import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contact-sheet generator for the WP-B1 canvas art port. Renders every bird,
/// every gear/hat on the mannequin and on each bird shape, try-on dim, the
/// dead pose and animation frames to `build/art_check/*.png` at 4x, for a
/// side-by-side visual check against `design/menu_v2/skin_catalog.png`.
/// The PNGs are build output and are not committed.

const double _scale = 4; // device px per art unit
const double _cellW = 64, _cellH = 56; // art units per cell
const int _cols = 10;
const _tileBg = Color(0xFFE2E2E2);
const _sheetBg = Color(0xFFF1F1F1);

typedef _Cell = void Function(Canvas canvas);

Future<void> _sheet(String name, List<_Cell?> cells) async {
  final rows = (cells.length / _cols).ceil();
  final w = (_cols * _cellW * _scale).round();
  final h = (rows * _cellH * _scale).round();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = _sheetBg,
  );
  canvas.scale(_scale);
  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    if (cell == null) continue;
    final x = (i % _cols) * _cellW, y = (i ~/ _cols) * _cellH;
    canvas.drawRect(
      Rect.fromLTWH(x + 1, y + 1, _cellW - 2, _cellH - 2),
      Paint()..color = _tileBg,
    );
    canvas.save();
    canvas.translate(x + _cellW / 2, y + _cellH / 2 + 4);
    cell(canvas);
    canvas.restore();
  }
  final image = await rec.endRecording().toImage(w, h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File('build/art_check/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

List<_Cell?> _padRow(List<_Cell?> cells) => [
  ...cells,
  for (var i = cells.length % _cols; i != 0 && i < _cols; i++) null,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('art contact sheets render to build/art_check', (tester) async {
    const t = 1.3;
    // 1: catalogue (birds, gear on mannequin, hats on mannequin).
    final catalogue = <_Cell?>[
      for (final id in BirdArt.ids)
        (c) => LookPainter.paint(c, Look(bird: id), t: t),
      ..._padRow([
        (c) => LookPainter.paintNone(c, 12),
        for (final id in GearArt.ids)
          (c) => LookPainter.paintOnMannequin(c, SkinLayer.gear, id, t: t),
      ]),
      (c) => LookPainter.paintNone(c, 12),
      for (final id in HatArt.ids)
        (c) => LookPainter.paintOnMannequin(c, SkinLayer.hat, id, t: t),
    ];
    // One bird per shape for the anchor checks.
    const shapeBirds = [
      'classic',
      'robin',
      'toucan',
      'chick',
      'penguin',
      'owl',
      'puffer',
      'ghost',
      'pixel',
      'galaxy',
    ];
    final gearOnShapes = <_Cell?>[
      for (final g in GearArt.ids)
        for (final b in shapeBirds)
          (c) => LookPainter.paint(
            c,
            Look(bird: b, gear: g),
            t: t,
          ),
    ];
    final hatsOnShapes = <_Cell?>[
      for (final h in HatArt.ids)
        for (final b in shapeBirds)
          (c) => LookPainter.paint(
            c,
            Look(bird: b, hat: h),
            t: t,
          ),
    ];
    // States: flap, dead pose, try-on dim per layer, animation frames.
    const full = Look(bird: 'phoenix', gear: 'jetpack', hat: 'crown');
    final states = <_Cell?>[
      for (final id in BirdArt.ids)
        (c) => LookPainter.paint(c, Look(bird: id), t: t, flap: true),
      for (final id in BirdArt.ids)
        (c) => LookPainter.paint(
          c,
          Look(bird: id, gear: id == 'classic' ? 'mask' : kNoneId),
          t: t,
          dead: true,
        ),
      ..._padRow([
        (c) => LookPainter.paint(c, full, t: t),
        for (final layer in [SkinLayer.bird, SkinLayer.gear, SkinLayer.hat])
          (c) => LookPainter.paint(c, full, t: t, dim: {layer: .4}),
        (c) => LookPainter.paint(
          c,
          const Look(bird: 'ghost', gear: 'scarf', hat: 'wizard'),
          t: t,
          dim: {SkinLayer.gear: .4},
        ),
        (c) => LookPainter.paint(
          c,
          const Look(bird: 'robo', gear: 'carpet', hat: 'halo'),
          t: t,
          dead: true,
        ),
      ]),
      for (var f = 0; f < 10; f++)
        (c) => LookPainter.paint(
          c,
          const Look(bird: 'rainbow', gear: 'windup', hat: 'prop'),
          t: f * .1,
        ),
      for (var f = 0; f < 10; f++)
        (c) => LookPainter.paint(
          c,
          const Look(bird: 'golden', gear: 'sneakers', hat: 'band'),
          t: f * .25,
          flap: f.isOdd,
        ),
    ];

    await tester.runAsync(() async {
      await _sheet('catalogue', catalogue);
      await _sheet('gear_on_shapes', gearOnShapes);
      await _sheet('hats_on_shapes', hatsOnShapes);
      await _sheet('states', states);
    });
    expect(File('build/art_check/catalogue.png').existsSync(), isTrue);
  });
}
