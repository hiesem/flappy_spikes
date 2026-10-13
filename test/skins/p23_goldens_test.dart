import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flappy_spikes/components/skins/item_art.dart';
import 'package:flappy_spikes/run/hoops/ring_painter.dart';
import 'package:flappy_spikes/skins/art/gear_art_v23.dart';
import 'package:flappy_spikes/skins/art/hat_art_v23.dart';
import 'package:flappy_spikes/skins/art/hoop_art_v23.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/art/trail.dart';
import 'package:flappy_spikes/skins/art/trail_v23.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'p23_render.dart';

/// PRD-2.3 §19.6 goldens of the 60 new items (next to
/// `look_art_golden_test.dart`). Regenerate after an intended art change
/// with `flutter test --update-goldens test/skins/p23_goldens_test.dart`
/// and compare the PNGs in `test/skins/goldens/` with the approved page.
const double _t1 = 1.3, _t2 = 2.75;
const _bg = Color(0xFFFCD9EE);
const _tileBg = Color(0xFFFFFFFF);

void _cellBg(Canvas c, double w, double h, Color col) => c.drawRect(
  Rect.fromLTWH(1, 1, w - 2, h - 2),
  Paint()..color = col,
);

/// A tile cell: the real shop-grid art ([ItemArt]) in its 84 x 68 box.
void Function(Canvas) _tile(SkinItem item, double t, {TrailEmitter? e}) =>
    (c) {
      _cellBg(c, 90, 74, _tileBg);
      c.save();
      c.translate(3, 3);
      if (e != null) {
        for (var i = 0; i < 60; i++) {
          ItemArt.advanceTrail(e, i / 60, 1 / 60);
        }
        ItemArt.paint(c, item, t: 1, emitter: e);
      } else {
        ItemArt.paint(c, item, t: t);
      }
      c.restore();
    };

/// A look cell: [look] at 1.6 px per art unit, centred low (hats rise).
void Function(Canvas) _look(Look look, double t) => (c) {
  _cellBg(c, 90, 74, _bg);
  c.save();
  c.translate(45, 46);
  c.scale(1.4);
  LookPainter.paint(c, look, t: t);
  c.restore();
};

Future<void> _golden(
  WidgetTester tester,
  String name,
  List<void Function(Canvas)> cells, {
  int cols = 15,
  double w = 90,
  double h = 74,
}) async {
  ui.Image? image;
  await tester.runAsync(() async {
    image = await renderGrid(cells, w: w, h: h, cols: cols, scale: 2,
        background: const Color(0xFF7A0044));
  });
  await expectLater(image!, matchesGoldenFile('goldens/$name.png'));
  image!.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SkinItem item(SkinLayer l, String id) => itemById(l, id)!;

  for (final (name, t) in [('t1', _t1), ('t2', _t2)]) {
    testWidgets('hats: tile (mannequin) + Classic bird at $name', (tester) async {
      await _golden(tester, 'p23_hats_$name', [
        for (final id in HatArtV23.ids) _tile(item(SkinLayer.hat, id), t),
        for (final id in HatArtV23.ids)
          _look(Look(bird: 'classic', hat: id), t),
      ]);
    });

    testWidgets('gear: tile (mannequin) + Classic bird at $name', (tester) async {
      await _golden(tester, 'p23_gear_$name', [
        for (final id in GearArtV23.ids) _tile(item(SkinLayer.gear, id), t),
        for (final id in GearArtV23.ids)
          _look(Look(bird: 'classic', gear: id), t),
      ]);
    });

    testWidgets('hoops: tile ring + in-run back / front halves at $name',
        (tester) async {
      await _golden(tester, 'p23_hoops_$name', [
        for (final id in HoopArtV23.ids) _tile(item(SkinLayer.hoop, id), t),
        for (final id in HoopArtV23.ids)
          (c) {
            _cellBg(c, 90, 74, _bg);
            c.save();
            c.translate(45, 37);
            c.scale(.55);
            const centre = Offset.zero;
            RingPainter.paintHalf(c,
                centre: centre, opening: 92, front: false, skinId: id, t: t);
            c.save();
            c.scale(1.6);
            LookPainter.paint(c, const Look(bird: 'classic'), t: t);
            c.restore();
            RingPainter.paintHalf(c,
                centre: centre, opening: 92, front: true, skinId: id, t: t);
            c.restore();
          },
      ]);
    });
  }

  testWidgets('trails after a fixed number of seeded steps (tile + run)',
      (tester) async {
    await _golden(tester, 'p23_trails', [
      for (final id in TrailV23.ids)
        _tile(item(SkinLayer.trail, id), 1,
            e: TrailEmitter(id, random: math.Random(7))),
      for (final id in TrailV23.ids)
        (c) {
          _cellBg(c, 90, 74, _bg);
          c.save();
          c.scale(90 / 160);
          paintPortCell(c, SkinLayer.trail, id, _t1);
          c.restore();
        },
    ]);
  });

  for (final bird in ['penguin', 'duck', 'owl', 'pixel', 'ghost']) {
    testWidgets('every new hat and gear on the $bird', (tester) async {
      await _golden(tester, 'p23_shape_$bird', [
        for (final id in HatArtV23.ids) _look(Look(bird: bird, hat: id), _t1),
        for (final id in GearArtV23.ids)
          _look(Look(bird: bird, gear: id), _t1),
      ]);
    });
  }
}
