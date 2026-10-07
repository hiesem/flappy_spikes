import 'dart:ui' as ui;

import 'package:flappy_spikes/levels/emblem_painter.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import '../art/art_render.dart';
import '../menu_screenshot_test.dart' show loadFonts;

/// WP-G visual check: renders the 11 emblems (+ the classic bird on top, at
/// bird scale 1.4 like the mock) to `build/emblem_check/` for eyeballing
/// against `design/menu_v2/levels_emblems.png` (the PNGs are not committed).
///
/// `flutter test test/levels/emblem_generator_test.dart`
///
/// The cells copy the mock gallery (build74.py): 200 x 190 pt cells on the
/// light-grey tile background, emblem scale .78 with the plate centre at
/// (100, 100), the rank name under it. The animation sheet shows levels 7-10
/// (the ones with idle animation) over four t values.
const String _outDir = 'build/emblem_check';
const double _cellWidth = 200;
const double _cellHeight = 190;
const double _emblemScale = .78;
const double _birdScale = 1.4;

const List<String> _labels = [
  'UNRANKED',
  'EGG · 10',
  'CHICK · 50',
  'FLEDGLING · 100',
  'FLAPPER · 200',
  'GLIDER · 400',
  'FALCON · 600',
  'HAWK · 800',
  'SPIKE ACE · 1 000',
  'PHOENIX · 2 000',
  'LEGEND · 5 000',
];

/// The emblem (scaled, plate centre at the cell centre) with the classic bird
/// on top, exactly like `paintEmb(..., bird=true)` in build74.py.
void _paintCell(
  ui.Canvas canvas,
  int level,
  double t, {
  bool grey = false,
  bool shine = true,
}) {
  canvas.save();
  canvas.translate(_cellWidth / 2, 100);
  canvas.scale(_emblemScale, _emblemScale);
  EmblemPainter.paint(canvas, level, t: t, shine: shine, grey: grey);
  canvas.save();
  if (grey) {
    // The mock's `ctx.filter` covers the bird too; the painter's grey mode is
    // the emblem's own filter, so the caller greys the look itself.
    canvas.saveLayer(null, _greyFilter);
    canvas.scale(_birdScale, _birdScale);
    LookPainter.paint(canvas, Look.defaults, t: t);
    canvas.restore();
  } else {
    canvas.scale(_birdScale, _birdScale);
    LookPainter.paint(canvas, Look.defaults, t: t);
  }
  canvas.restore();
  canvas.restore();
}

/// `grayscale(1) opacity(.38)`, the locked list rows.
final ui.Paint _greyFilter = ui.Paint()
  ..colorFilter = const ui.ColorFilter.matrix(<double>[
    .2126, .7152, .0722, 0, 0,
    .2126, .7152, .0722, 0, 0,
    .2126, .7152, .0722, 0, 0,
    0, 0, 0, .38, 0,
  ]);

/// The mock's mock-tile caption: 13 pt Opificio, .1 em, #828282, centred.
void _paintLabel(ui.Canvas canvas, String text) {
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontFamily: 'Opificio Neue',
            fontSize: 13,
            textAlign: ui.TextAlign.center,
          ),
        )
        ..pushStyle(
          ui.TextStyle(
            color: ui.Color(0xFF828282),
            fontFamily: 'Opificio Neue',
            fontSize: 13,
            letterSpacing: 1.3,
          ),
        )
        ..addText(text);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: _cellWidth));
  canvas.drawParagraph(paragraph, const ui.Offset(0, 170));
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  testWidgets('emblems.png: all 11 emblems with the bird on top', (
    tester,
  ) async {
    // t = 2.0: past the first sweep window, so every cell shows the emblem
    // itself (the sweep is verified in the animation sheet and the unit
    // tests).
    await writeMontage(
      tester,
      '$_outDir/emblems.png',
      count: 11,
      columns: 4,
      cellWidth: _cellWidth,
      cellHeight: _cellHeight,
      scale: 4,
      drawCell: (canvas, i) {
        _paintCell(canvas, i, 2);
        _paintLabel(canvas, _labels[i]);
      },
    );
  });

  testWidgets('emblems_anim.png: levels 7-10 over four t values', (
    tester,
  ) async {
    await writeMontage(
      tester,
      '$_outDir/emblems_anim.png',
      count: 4 * 4,
      columns: 4,
      cellWidth: _cellWidth,
      cellHeight: _cellHeight,
      scale: 4,
      drawCell: (canvas, i) {
        final level = 7 + i ~/ 4;
        final t = (i % 4) * .5;
        _paintCell(canvas, level, t);
        _paintLabel(canvas, '${_labels[level]}  t ${t.toStringAsFixed(1)}');
      },
    );
  });

  testWidgets('emblems_grey.png: locked list rows vs the current one', (
    tester,
  ) async {
    await writeMontage(
      tester,
      '$_outDir/emblems_grey.png',
      count: 4,
      columns: 2,
      cellWidth: _cellWidth,
      cellHeight: _cellHeight,
      scale: 4,
      drawCell: (canvas, i) {
        const level = 6;
        _paintCell(canvas, level, 2, grey: i.isOdd, shine: !i.isOdd);
        _paintLabel(canvas, i.isOdd ? 'GREY (LOCKED)' : 'COLOUR (CURRENT)');
      },
    );
  });
}
