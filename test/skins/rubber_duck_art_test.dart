import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP-J2: bird #16 is a bath-toy rubber duck with its own `rduck` shape.
/// Renders a check sheet to `build/art_check/rubber_duck.png` (duck vs
/// chick, flap / dead / blink, all hats, all gear) and checks the anchors.

const double _scale = 4;
const double _cellW = 64, _cellH = 56;
const int _cols = 8;

typedef _Cell = void Function(Canvas canvas);

Future<void> _sheet(String name, List<_Cell?> cells) async {
  final rows = (cells.length / _cols).ceil();
  final w = (_cols * _cellW * _scale).round();
  final h = (rows * _cellH * _scale).round();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFFF1F1F1),
  );
  canvas.scale(_scale);
  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    if (cell == null) continue;
    final x = (i % _cols) * _cellW, y = (i ~/ _cols) * _cellH;
    canvas.drawRect(
      Rect.fromLTWH(x + 1, y + 1, _cellW - 2, _cellH - 2),
      Paint()..color = const Color(0xFFE2E2E2),
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

const int _w = 96, _h = 96;

Future<Uint8List> _render(void Function(Canvas c) draw) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)
    ..translate(_w / 2, _h / 2 + 8)
    ..scale(1.5);
  draw(canvas);
  final image = await rec.endRecording().toImage(_w, _h);
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  return data!.buffer.asUint8List();
}

int _diff(Uint8List a, Uint8List b) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      n++;
    }
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('duck is the Rubber duck: Rare, 750, own rduck shape', () {
    final item = itemById(SkinLayer.bird, 'duck')!;
    expect(item.name, 'Rubber duck');
    expect(item.rarity, Rarity.rare);
    expect(item.price, 750);
    final duck = BirdArt.byId('duck');
    expect(duck.shape.kind, 'rduck');
    expect(duck.c, const Color(0xFFFFD600));
    expect(duck.d, const Color(0xFFF9A825));
    expect(duck.bk, const Color(0xFFFF5722));
    expect(duck.shape, isNot(BirdArt.byId('chick').shape));
  });

  test('rubber duck anchors sit inside the 44 x 36 art box and the body', () {
    final s = BirdShape.of('rduck');
    final box = const Rect.fromLTWH(0, 0, 44, 36);
    final body = s.body.getBounds();
    expect(box.contains(body.topLeft), isTrue);
    expect(body.right, lessThanOrEqualTo(44));
    expect(body.bottom, lessThanOrEqualTo(36));
    expect(s.body.contains(s.eye), isTrue);
    for (final v in [s.top, s.neck, s.bot]) {
      expect(v, inInclusiveRange(0, 36));
    }
    for (final v in [s.l, s.r, s.hx, s.bl]) {
      expect(v, inInclusiveRange(0, 44));
    }
    expect(s.top, body.top);
    expect(s.bot, body.bottom);
    // Hat anchor on the head bump, body anchors left of the head.
    expect(s.body.contains(Offset(s.hx, s.top + 1)), isTrue);
    expect(s.bl, lessThan(s.l));
    expect(s.l, lessThan(s.hx));
    expect(s.hx, lessThan(s.r));
    // Wing inside the body.
    expect(s.body.contains(Offset(s.wing[0] + 1, s.wing[1] - 1)), isTrue);
    // The bill is wider than every other beak.
    double width(List<double> pts) {
      final xs = [for (var i = 0; i < pts.length; i += 2) pts[i]];
      return xs.reduce((a, b) => a > b ? a : b) -
          xs.reduce((a, b) => a < b ? a : b);
    }

    for (final other in BirdShape.shapes.values) {
      if (other.kind == 'rduck') continue;
      expect(width(s.beak), greaterThan(width(other.beak)), reason: other.kind);
    }
  });

  testWidgets('rubber duck paints, differs from the chick, wears all gear '
      'and hats', (tester) async {
    await tester.runAsync(() async {
      final duck = await _render(
        (c) => LookPainter.paint(c, const Look(bird: 'duck'), t: .4),
      );
      final chick = await _render(
        (c) => LookPainter.paint(c, const Look(bird: 'chick'), t: .4),
      );
      expect(_diff(duck, chick), greaterThan(800));
      for (final id in GearArt.ids) {
        final g = await _render(
          (c) => LookPainter.paint(c, Look(bird: 'duck', gear: id), t: .4),
        );
        expect(_diff(g, duck), greaterThan(10), reason: 'gear $id');
      }
      for (final id in HatArt.ids) {
        final h = await _render(
          (c) => LookPainter.paint(c, Look(bird: 'duck', hat: id), t: .4),
        );
        expect(_diff(h, duck), greaterThan(10), reason: 'hat $id');
      }
      final dead = await _render(
        (c) =>
            LookPainter.paint(c, const Look(bird: 'duck'), t: .4, dead: true),
      );
      expect(_diff(dead, duck), greaterThan(0));
    });
  });

  testWidgets('rubber duck check sheet renders to build/art_check', (
    tester,
  ) async {
    const t = 1.3;
    const duck = Look(bird: 'duck');
    const chick = Look(bird: 'chick');
    final cells = <_Cell?>[
      (c) => LookPainter.paint(c, duck, t: t),
      (c) => LookPainter.paint(c, chick, t: t),
      (c) => LookPainter.paint(c, duck, t: t, flap: true),
      (c) => LookPainter.paint(c, chick, t: t, flap: true),
      (c) => LookPainter.paint(c, duck, t: t, dead: true),
      (c) => LookPainter.paint(c, chick, t: t, dead: true),
      (c) => LookPainter.paint(c, duck, t: t, blink: true),
      (c) => LookPainter.paint(c, duck, t: t, dim: {SkinLayer.bird: .42}),
      for (final h in HatArt.ids)
        (c) => LookPainter.paint(
          c,
          Look(bird: 'duck', hat: h),
          t: t,
        ),
      null,
      null,
      for (final g in GearArt.ids)
        (c) => LookPainter.paint(
          c,
          Look(bird: 'duck', gear: g),
          t: t,
        ),
      null,
      null,
      (c) => LookPainter.paint(
        c,
        const Look(bird: 'duck', gear: 'shades', hat: 'pirate'),
        t: t,
      ),
      (c) => LookPainter.paint(
        c,
        const Look(bird: 'duck', gear: 'scarf', hat: 'beanie'),
        t: t,
        flap: true,
      ),
      (c) => LookPainter.paint(
        c,
        const Look(bird: 'duck', gear: 'jetpack', hat: 'crown'),
        t: t,
      ),
      (c) => LookPainter.paint(
        c,
        const Look(bird: 'duck', gear: 'mask', hat: 'cap'),
        t: t,
        dead: true,
      ),
    ];
    await tester.runAsync(() => _sheet('rubber_duck', cells));
    expect(File('build/art_check/rubber_duck.png').existsSync(), isTrue);
  });
}
