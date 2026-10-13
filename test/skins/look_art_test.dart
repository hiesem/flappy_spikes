import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP-B1 unit tests for the canvas art port (`lib/skins/art/`).

const int _w = 80, _h = 72; // 2x the art box with margin for hats/gear

/// Renders [draw] (origin at the image centre, 2x scale) to raw RGBA.
Future<Uint8List> _render(void Function(Canvas c) draw) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)
    ..translate(_w / 2, _h / 2 + 6)
    ..scale(1.5);
  draw(canvas);
  final image = await rec.endRecording().toImage(_w, _h);
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  return data!.buffer.asUint8List();
}

/// Alpha at art-box point [p] (art units, box origin top-left).
int _alphaAt(Uint8List px, Offset p) {
  final x = (_w / 2 + (p.dx - 22) * 1.5).round();
  final y = (_h / 2 + 6 + (p.dy - 18) * 1.5).round();
  return px[(y * _w + x) * 4 + 3];
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

  test('catalogue sizes match PRD section 5', () {
    expect(BirdArt.ids, hasLength(30));
    // PRD-2.3 §19: 29 each (+ None).
    expect(GearArt.ids, hasLength(29));
    expect(HatArt.ids, hasLength(29));
    expect(GearArt.ids, contains('windup'));
    expect(GearArt.ids, isNot(contains('buddy')));
    expect(BirdArt.ids.first, 'classic');
  });

  testWidgets('every bird paints an opaque body at the body centre', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final id in BirdArt.ids) {
        final px = await _render(
          (c) => LookPainter.paint(c, Look(bird: id), t: .7),
        );
        expect(
          _alphaAt(px, LookPainter.bodyCentre),
          greaterThan(200),
          reason: id,
        );
      }
    });
  });

  testWidgets('every gear and hat changes the mannequin and the bird', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bare = await _render(
        (c) => LookPainter.paintOnMannequin(c, SkinLayer.gear, kNoneId),
      );
      final bareHat = await _render(
        (c) => LookPainter.paintOnMannequin(c, SkinLayer.hat, kNoneId),
      );
      final bird = await _render(
        (c) => LookPainter.paint(c, const Look(bird: 'owl')),
      );
      for (final id in GearArt.ids) {
        final m = await _render(
          (c) => LookPainter.paintOnMannequin(c, SkinLayer.gear, id, t: .4),
        );
        expect(
          _diff(m, bare),
          greaterThan(10),
          reason: 'gear $id on mannequin',
        );
        final b = await _render(
          (c) => LookPainter.paint(c, Look(bird: 'owl', gear: id), t: .4),
        );
        expect(_diff(b, bird), greaterThan(10), reason: 'gear $id on owl');
      }
      for (final id in HatArt.ids) {
        final m = await _render(
          (c) => LookPainter.paintOnMannequin(c, SkinLayer.hat, id, t: .4),
        );
        expect(
          _diff(m, bareHat),
          greaterThan(10),
          reason: 'hat $id on mannequin',
        );
        final b = await _render(
          (c) => LookPainter.paint(c, Look(bird: 'owl', hat: id), t: .4),
        );
        expect(_diff(b, bird), greaterThan(10), reason: 'hat $id on owl');
      }
    });
  });

  testWidgets('unknown ids fall back to classic / no gear / no hat', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const unknown = Look(
        bird: 'nope',
        gear: 'buddy',
        hat: '???',
        hoop: 'x',
        trail: 'y',
      );
      final a = await _render((c) => LookPainter.paint(c, unknown, t: 2));
      final b = await _render((c) => LookPainter.paint(c, Look.defaults, t: 2));
      expect(_diff(a, b), 0);
      // Unknown items on the mannequin draw just the mannequin.
      final m = await _render(
        (c) => LookPainter.paintOnMannequin(c, SkinLayer.hat, 'nope'),
      );
      final none = await _render(
        (c) => LookPainter.paintOnMannequin(c, SkinLayer.hat, kNoneId),
      );
      expect(_diff(m, none), 0);
      expect(BirdArt.byId('nope').id, 'classic');
    });
  });

  testWidgets('dim renders the layer as one flat layer at that alpha', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const look = Look(bird: 'classic', hat: 'tophat');
      final half = await _render(
        (c) => LookPainter.paint(c, look, dim: {SkinLayer.bird: .5}),
      );
      // Body centre: one flat layer at 50 % (overlapping wing/body do not stack).
      expect(
        _alphaAt(half, LookPainter.bodyCentre),
        inInclusiveRange(120, 135),
      );
      expect(
        _alphaAt(half, const Offset(15, 13)),
        inInclusiveRange(120, 135),
      ); // wing over body
      // The hat (not dimmed) stays opaque.
      expect(_alphaAt(half, const Offset(23, -10)), 255);
      final gone = await _render(
        (c) => LookPainter.paint(c, look, dim: {SkinLayer.hat: 0}),
      );
      expect(_alphaAt(gone, const Offset(23, -10)), 0);
      final full = await _render(
        (c) => LookPainter.paint(c, look, dim: {SkinLayer.hat: 1}),
      );
      final plain = await _render((c) => LookPainter.paint(c, look));
      expect(_diff(full, plain), 0);
    });
  });

  testWidgets('dead pose differs from alive and draws the X eye', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final id in BirdArt.ids) {
        final alive = await _render(
          (c) => LookPainter.paint(c, Look(bird: id), t: 1),
        );
        final dead = await _render(
          (c) => LookPainter.paint(c, Look(bird: id), t: 1, dead: true),
        );
        if (id == 'zombie') continue; // already has the X eye
        expect(_diff(alive, dead), greaterThan(0), reason: id);
      }
      // Dead ignores flap (wing stays up).
      final d1 = await _render(
        (c) => LookPainter.paint(c, Look.defaults, t: 1, dead: true),
      );
      final d2 = await _render(
        (c) =>
            LookPainter.paint(c, Look.defaults, t: 1, dead: true, flap: true),
      );
      expect(_diff(d1, d2), 0);
    });
  });

  testWidgets('painting is deterministic (jetpack flame uses a hash of t)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const look = Look(bird: 'galaxy', gear: 'jetpack', hat: 'wizard');
      final a = await _render((c) => LookPainter.paint(c, look, t: 3.21));
      final b = await _render((c) => LookPainter.paint(c, look, t: 3.21));
      expect(_diff(a, b), 0);
      final later = await _render((c) => LookPainter.paint(c, look, t: 3.5));
      expect(_diff(a, later), greaterThan(0)); // animated
    });
  });

  testWidgets('paintNone draws a ring', (tester) async {
    await tester.runAsync(() async {
      final px = await _render((c) => LookPainter.paintNone(c, 10));
      expect(_alphaAt(px, const Offset(22, 8)), greaterThan(0));
    });
  });
}
