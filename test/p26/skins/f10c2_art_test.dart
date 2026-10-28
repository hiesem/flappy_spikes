import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flappy_spikes/skins/art/bird_art.dart';
import 'package:flappy_spikes/skins/art/skill_art_v26_part2.dart';

Future<Uint8List> render(
  String id,
  double time, {
  bool back = false,
  String shape = 'sq',
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..translate(48, 48);
  f10c2Painters[id]!(canvas, BirdShape.of(shape), time, back);
  final picture = recorder.endRecording();
  final image = await picture.toImage(120, 120);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the seven approved items are exposed', () {
    expect(f10c2Painters.keys.toSet(), {
      'jackpot',
      'magpie',
      'prism',
      'daynight',
      'goggles',
      'hoopchain',
      'peacock',
    });
  });
  test('each item paints and responds to the game clock', () async {
    for (final id in f10c2Painters.keys) {
      final back = id == 'goggles' || id == 'peacock';
      final first = await render(id, .2, back: back);
      final second = await render(id, 1.4, back: back);
      expect(first.any((x) => x != 0), isTrue, reason: id);
      expect(first, isNot(orderedEquals(second)), reason: id);
    }
  });
  test('gear anchors follow every bird shape', () async {
    expect(BirdShape.shapes.length, 10);
    for (final shape in BirdShape.shapes.values) {
      final goggles = await render('goggles', 0, shape: shape.kind);
      final x = (48 + shape.eye.dx).floor(), y = (48 + shape.eye.dy).floor();
      final pixel = (y * 120 + x) * 4;
      expect(goggles.sublist(pixel, pixel + 4), [
        0x4d,
        0xd0,
        0xe1,
        0xff,
      ], reason: '${shape.kind} lens centre');
      final edge = shape.hasBl ? shape.bl : shape.l;
      bool hasColorNear(Uint8List bytes, double x, double y, List<int> rgb) {
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            final px = (48 + x).round() + dx, py = (48 + y).round() + dy;
            final i = (py * 120 + px) * 4;
            final alpha = bytes[i + 3];
            if (alpha > 32 &&
                (bytes[i] - rgb[0] * alpha / 255).abs() < 5 &&
                (bytes[i + 1] - rgb[1] * alpha / 255).abs() < 5 &&
                (bytes[i + 2] - rgb[2] * alpha / 255).abs() < 5) {
              return true;
            }
          }
        }
        return false;
      }

      expect(
        hasColorNear(goggles, edge + 2, shape.neck - .5, [0xe5, 0x39, 0x35]),
        isTrue,
        reason: '${shape.kind} scarf at neck',
      );
      final chain = await render('hoopchain', 0, shape: shape.kind);
      final start = edge + (shape.r - edge) * 13 / 30;
      expect(
        hasColorNear(chain, start, shape.neck - 6.4, [0xc9, 0x8a, 0x00]),
        isTrue,
        reason: '${shape.kind} chain at neck',
      );
      final fan = await render('peacock', 0, shape: shape.kind, back: true);
      expect(
        hasColorNear(fan, edge + 2, shape.neck - 11, [0x00, 0x79, 0x6b]),
        isTrue,
        reason: '${shape.kind} fan root at back',
      );
      for (final id in ['goggles', 'hoopchain', 'peacock']) {
        final front = await render(id, .3, shape: shape.kind);
        expect(
          front.any((v) => v != 0),
          isTrue,
          reason: '${shape.kind} $id front',
        );
        if (id != 'hoopchain') {
          final back = await render(id, .3, shape: shape.kind, back: true);
          expect(
            back.any((v) => v != 0),
            isTrue,
            reason: '${shape.kind} $id back',
          );
        }
      }
    }
  });
  test('approved colours appear in rendered item art', () async {
    bool contains(Uint8List data, int r, int g, int b) {
      for (var i = 0; i < data.length; i += 4) {
        if (data[i] == r &&
            data[i + 1] == g &&
            data[i + 2] == b &&
            data[i + 3] == 255) {
          return true;
        }
      }
      return false;
    }

    final jackpot = await render('jackpot', 0);
    expect(contains(jackpot, 0xe5, 0x39, 0x35), isTrue);
    expect(contains(jackpot, 0xff, 0xb5, 0x29), isTrue);
    final magpie = await render('magpie', 0);
    expect(contains(magpie, 0x1c, 0x1c, 0x1c), isTrue);
    expect(contains(magpie, 0xfa, 0xfa, 0xfa), isTrue);
    final sky = await render('daynight', 0);
    expect(contains(sky, 0x4f, 0xc3, 0xf7), isTrue);
    expect(contains(sky, 0xff, 0xb5, 0x29), isTrue);
    final goggles = await render('goggles', 0);
    expect(contains(goggles, 0x4d, 0xd0, 0xe1), isTrue);
    expect(contains(goggles, 0xe5, 0x39, 0x35), isTrue);
  });
  test('bird face specs use the shared face painter colours', () {
    final shape = BirdShape.of('sq');
    expect(f10c2BirdFace('magpie', shape, 0).bk, const ui.Color(0xff3a3a3a));
    expect(f10c2BirdFace('prism', shape, 0).bk, const ui.Color(0xff8fd3f4));
    expect(f10c2BirdFace('daynight', shape, 0).bk, const ui.Color(0xffffb529));
    expect(
      f10c2BirdFace('magpie', shape, 0).d,
      isNot(f10c2BirdFace('magpie', shape, 1).d),
    );
  });
  test('fan and scarf back layers paint separately', () async {
    for (final id in ['prism', 'goggles', 'peacock']) {
      expect(
        (await render(id, .5, back: true)).any((x) => x != 0),
        isTrue,
        reason: id,
      );
    }
    for (final id in ['jackpot', 'magpie', 'daynight', 'hoopchain']) {
      expect(
        (await render(id, .5, back: true)).every((x) => x == 0),
        isTrue,
        reason: id,
      );
    }
  });
}
