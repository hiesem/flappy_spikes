import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/hat_art.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/art/shapes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../art/art_render.dart';

/// The headphones hat (H5, PRD-2.3 §19) seen from the side: one big cup over
/// the ear, a thick band arching over the crown, a thin white outline. Each
/// test paints the hat alone on every body shape and reads the pixels back.

/// Device px per art unit, and where art y = 0 sits in the image (the hat
/// rises above the head top).
const _k = 8.0;
const _oy = 14.0;

/// Image size: the 44 x 52 art units (x 0..44, y -14..38) at [_k].
const _pw = 44 * 8, _ph = 52 * 8;

Future<Uint8List> _hatOn(WidgetTester tester, BirdShape s) =>
    capture(tester, _pw, _ph, (c) {
      c.scale(_k);
      c.translate(0, _oy);
      paintHat(c, 'phones', s, 0);
    });

int _i(int x, int y) => (y * _pw + x) * 4;

bool _near(Uint8List p, int i, ui.Color col, [int tol = 36]) {
  final r = (col.r * 255).round(),
      g = (col.g * 255).round(),
      b = (col.b * 255).round();
  return (p[i] - r).abs() + (p[i + 1] - g).abs() + (p[i + 2] - b).abs() <= tol;
}

bool _opaque(Uint8List p, int x, int y) => p[_i(x, y) + 3] >= 250;

bool _cup(Uint8List p, int x, int y) =>
    _opaque(p, x, y) &&
    (_near(p, _i(x, y), artPlum) || _near(p, _i(x, y), artPink));

bool _band(Uint8List p, int x, int y) =>
    _opaque(p, x, y) &&
    (_near(p, _i(x, y), const ui.Color(0xFF37474F)) ||
        _near(p, _i(x, y), const ui.Color(0xFF90A4AE)));

bool _white(Uint8List p, int x, int y) {
  final i = _i(x, y);
  return p[i + 3] >= 250 && p[i] >= 245 && p[i + 1] >= 245 && p[i + 2] >= 245;
}

bool _ink(Uint8List p, int x, int y) => p[_i(x, y) + 3] >= 20;

/// One 4-connected blob of pixels matching a predicate.
class _Blob {
  int size = 0, minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;

  void add(int x, int y) {
    size++;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }

  double get cx => (minX + maxX + 1) / 2 / _k;
  double get cy => (minY + maxY + 1) / 2 / _k - _oy;
  double get width => (maxX + 1 - minX) / _k;
  double get height => (maxY + 1 - minY) / _k;
}

List<_Blob> _blobs(bool Function(int x, int y) on) {
  final seen = List<bool>.filled(_pw * _ph, false);
  final out = <_Blob>[];
  for (var y0 = 0; y0 < _ph; y0++) {
    for (var x0 = 0; x0 < _pw; x0++) {
      final s0 = y0 * _pw + x0;
      if (seen[s0] || !on(x0, y0)) continue;
      final b = _Blob();
      final stack = <int>[s0];
      seen[s0] = true;
      while (stack.isNotEmpty) {
        final s = stack.removeLast();
        final x = s % _pw, y = s ~/ _pw;
        b.add(x, y);
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= _pw || ny >= _ph) continue;
          final j = ny * _pw + nx;
          if (seen[j] || !on(nx, ny)) continue;
          seen[j] = true;
          stack.add(j);
        }
      }
      out.add(b);
    }
  }
  return out;
}

/// The eye box of [s] in art units (the owl's is a 10-unit box, the ghost's
/// a 4 x 6.4 oval; the rest are 4-unit squares).
(double, double, double, double) _eyeBox(BirdShape s) {
  final ex = s.eye.dx, ey = s.eye.dy;
  if (s.kind == 'owl') return (ex - 5, ey - 5, ex + 5, ey + 5);
  if (s.kind == 'ghost') return (ex - 2, ey - 3.2, ex + 2, ey + 3.2);
  return (ex - 2, ey - 2, ex + 2, ey + 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shapes = BirdShape.shapes.values.toList();

  testWidgets('one cup on every head shape, big and rounded', (tester) async {
    for (final s in shapes) {
      final rgba = await _hatOn(tester, s);
      final cups = _blobs(
        (x, y) => _cup(rgba, x, y),
      ).where((b) => b.size >= 30).toList();
      expect(cups, hasLength(1), reason: '${s.kind}: one cup, not two');
      final cup = cups.single;
      expect(cup.width, greaterThanOrEqualTo(9), reason: '${s.kind} cup width');
      expect(
        cup.height,
        greaterThanOrEqualTo(16),
        reason: '${s.kind} cup height',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('the cup sits over the ear: behind the eye, mid-head', (
    tester,
  ) async {
    for (final s in shapes) {
      final rgba = await _hatOn(tester, s);
      final cup = _blobs(
        (x, y) => _cup(rgba, x, y),
      ).where((b) => b.size >= 30).single;
      expect(
        cup.cx,
        inInclusiveRange(s.l + 3, s.hx + 1),
        reason: '${s.kind} cup x',
      );
      expect(
        cup.cy,
        inInclusiveRange(s.top + 3, s.bot - 3),
        reason: '${s.kind} cup y',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('the band is one arch over the crown, down to the forehead', (
    tester,
  ) async {
    for (final s in shapes) {
      final rgba = await _hatOn(tester, s);
      final bands = _blobs(
        (x, y) => _band(rgba, x, y),
      ).where((b) => b.size >= 30).toList();
      expect(bands, hasLength(1), reason: '${s.kind}: one band');
      final band = bands.single;
      // Its top is above the head top; its far end reaches the front.
      final top = band.cy - band.height / 2;
      expect(top, lessThan(s.top - 2), reason: '${s.kind} band arches over');
      expect(
        band.minX / _k,
        lessThan(s.hx),
        reason: '${s.kind} band starts at the back',
      );
      expect(
        band.maxX / _k,
        greaterThanOrEqualTo(s.r - 4),
        reason: '${s.kind} band reaches the forehead',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('no part of the hat covers the eye', (tester) async {
    for (final s in shapes) {
      final rgba = await _hatOn(tester, s);
      final (x0, y0, x1, y1) = _eyeBox(s);
      // A quarter unit inside the box is allowed (the antialiased edge).
      const m = .25;
      final over = <String>[];
      for (var y = 0; y < _ph; y++) {
        for (var x = 0; x < _pw; x++) {
          if (!_ink(rgba, x, y)) continue;
          final ax = (x + .5) / _k, ay = (y + .5) / _k - _oy;
          if (ax > x0 + m && ax < x1 - m && ay > y0 + m && ay < y1 - m) {
            over.add('($ax, $ay)');
          }
        }
      }
      expect(over, isEmpty, reason: '${s.kind}: hat over the eye at $over');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('a thin white outline runs round the cup and the band', (
    tester,
  ) async {
    for (final s in shapes) {
      final rgba = await _hatOn(tester, s);
      // Outline pixels: white and next to the outside (a neighbour that is
      // not fully opaque: the silhouette is antialiased).
      var outline = 0;
      for (var y = 1; y < _ph - 1; y++) {
        for (var x = 1; x < _pw - 1; x++) {
          if (!_white(rgba, x, y)) continue;
          if (!_opaque(rgba, x - 1, y) ||
              !_opaque(rgba, x + 1, y) ||
              !_opaque(rgba, x, y - 1) ||
              !_opaque(rgba, x, y + 1)) {
            outline++;
          }
        }
      }
      expect(outline, greaterThan(200), reason: '${s.kind}: outline');

      // Its width on the cup's left edge, across the middle row: 0.75 unit
      // (6 px). Rows are premultiplied, so a white pixel's green channel is
      // its coverage: sum it between the outside and the plum shell.
      final cup = _blobs(
        (x, y) => _cup(rgba, x, y),
      ).where((b) => b.size >= 30).single;
      final row = (cup.minY + cup.maxY + 1) ~/ 2;
      var x1 = 0;
      while (!_cup(rgba, x1, row)) {
        x1++;
      }
      var white = 0.0;
      for (var x = x1 - 12; x < x1; x++) {
        white += rgba[_i(x, row) + 1] / 255;
      }
      expect(
        white,
        inInclusiveRange(4.5, 7.5),
        reason: '${s.kind}: outline ${white.toStringAsFixed(2)} px',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('the hat stays on the head: sides, bottom and rise', (
    tester,
  ) async {
    var highest = 0.0;
    for (final s in shapes) {
      final rgba = await _hatOn(tester, s);
      var minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
      for (var y = 0; y < _ph; y++) {
        for (var x = 0; x < _pw; x++) {
          if (!_ink(rgba, x, y)) continue;
          final ax = (x + .5) / _k, ay = (y + .5) / _k - _oy;
          if (ax < minX) minX = ax;
          if (ax > maxX) maxX = ax;
          if (ay < minY) minY = ay;
          if (ay > maxY) maxY = ay;
        }
      }
      expect(minX, greaterThanOrEqualTo(s.l - 2), reason: '${s.kind} left');
      expect(maxX, lessThanOrEqualTo(s.r + 2), reason: '${s.kind} right');
      expect(maxY, lessThanOrEqualTo(s.bot), reason: '${s.kind} bottom');
      final rise = s.top - minY;
      if (rise > highest) highest = rise;
      expect(
        rise,
        lessThanOrEqualTo(LookPainter.hatRise['phones']! + .5),
        reason: '${s.kind}: the layout reserves the rise',
      );
    }
    // The layout table is measured, not a guess: it is the tallest shape.
    expect(
      LookPainter.hatRise['phones'],
      closeTo(highest, .5),
      reason: 'hatRise[phones] is the measured rise',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
