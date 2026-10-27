import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flappy_spikes/components/levels/emblem_view.dart';
import 'package:flappy_spikes/levels/emblem_painter.dart';
import 'package:flappy_spikes/levels/level_track.dart';
import 'package:flappy_spikes/run/hud/fit_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../art/art_render.dart';
import '../../share/share_card_golden_test.dart' show loadCardFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCardFonts);

  test('J6 routes 32 slots, endless reuses 32, unranked has no image', () {
    expect(EmblemPainter.assetFor(0), isNull);
    final paths = {for (var i = 1; i <= 32; i++) EmblemPainter.assetFor(i)};
    expect(paths.length, 32);
    expect(EmblemPainter.assetFor(999), EmblemPainter.assetFor(32));
    expect(EmblemPainter.slotFor(-1), 0);
  });

  testWidgets('J13 every painted slot and locked variant has bounded ink', (
    tester,
  ) async {
    for (var level = 0; level <= 32; level++) {
      for (final grey in [false, true]) {
        final pixels = await capture(tester, 300, 300, (c) {
          c.translate(150, 150);
          EmblemPainter.paintTrack(c, level, t: 1, grey: grey);
        });
        expect(hasInk(pixels), isTrue, reason: '$level / grey $grey');
        for (var x = 0; x < 300; x++) {
          expect(pixel(pixels, 300, x, 0)[3], 0);
          expect(pixel(pixels, 300, x, 299)[3], 0);
          expect(pixel(pixels, 300, 0, x)[3], 0);
          expect(pixel(pixels, 300, 299, x)[3], 0);
        }
      }
    }
  });

  testWidgets('J6 idle thresholds, sweep, and reduced-motion pixels', (
    tester,
  ) async {
    Future<List<int>> frame(
      int level,
      double t, {
      bool still = false,
      bool shine = false,
    }) => capture(tester, 300, 300, (c) {
      c.translate(150, 150);
      EmblemPainter.paintTrack(
        c,
        level,
        t: t,
        shine: shine,
        reduceMotion: still,
      );
    });
    for (final level in [1, 10, 20, 21, 25, 26, 29, 31, 32, 999]) {
      final a = await frame(level, 3);
      final b = await frame(level, 3.5);
      expect(
        a,
        level < 21 ? orderedEquals(b) : isNot(orderedEquals(b)),
        reason: '$level',
      );
      expect(
        await frame(level, 1, still: true, shine: true),
        orderedEquals(await frame(level, 4, still: true, shine: true)),
      );
      expect(
        await frame(level, .9, shine: true),
        isNot(orderedEquals(await frame(level, .9))),
      );
    }
  });

  testWidgets('image route keeps the plate centre, overlays and grey filter', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 280, 280),
      ui.Paint()..color = const ui.Color(0xFF00FF00),
    );
    final picture = recorder.endRecording();
    late ui.Image image;
    await tester.runAsync(() async {
      image = await picture.toImage(280, 280);
    });
    picture.dispose();
    final requested = <int>[];
    final view = EmblemView(
      level: 999,
      artScale: 1,
      imageLoader: (slot) async {
        requested.add(slot);
        return image;
      },
    )..reduceMotion = true;
    await view.onLoad();
    expect(requested, [32]);
    Future<List<int>> frame() => capture(tester, 300, 300, (c) {
      c.translate(150, 150);
      view.render(c);
    });
    final color = await frame();
    expect(pixel(Uint8List.fromList(color), 300, 150, 150), [0, 255, 0, 255]);
    view.grey = true;
    final grey = await frame();
    final centre = pixel(Uint8List.fromList(grey), 300, 150, 150);
    expect(centre[0], centre[1]);
    expect(centre[1], centre[2]);
    expect(centre[3], closeTo(255 * .38, 1));
    expect(view.drewCached, isTrue);
    view.onRemove();
    image.dispose();
  });

  testWidgets('late PNG completion cannot replace a new unranked slot', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF00FF00), ui.BlendMode.src);
    final picture = recorder.endRecording();
    late ui.Image image;
    await tester.runAsync(() async {
      image = await picture.toImage(2, 2);
    });
    picture.dispose();
    final pending = Completer<ui.Image?>();
    final view = EmblemView(
      level: 32,
      artScale: 1,
      imageLoader: (_) => pending.future,
    );
    final loading = view.onLoad();
    await Future<void>.value();
    view.level = 0;
    pending.complete(image);
    await loading;
    final pixels = await capture(tester, 300, 300, (c) {
      c.translate(150, 150);
      view.render(c);
    });
    final expected = await capture(tester, 300, 300, (c) {
      c.translate(150, 150);
      EmblemPainter.paintTrack(c, 0);
    });
    expect(pixels, orderedEquals(expected));
    view.onRemove();
    image.dispose();
  });

  testWidgets('broken image source retains painted fallback', (tester) async {
    final view = EmblemView(
      level: 23,
      artScale: 1,
      imageLoader: (_) async => throw StateError('bad PNG'),
    )..reduceMotion = true;
    await view.onLoad();
    final actual = await capture(tester, 300, 300, (c) {
      c.translate(150, 150);
      view.render(c);
    });
    final fallback = await capture(tester, 300, 300, (c) {
      c.translate(150, 150);
      EmblemPainter.paintTrack(c, 23, reduceMotion: true);
    });
    expect(actual, orderedEquals(fallback));
    view.onRemove();
  });

  test('J7 long names reserve badge 999, and rank lines keep every glyph', () {
    final measure = measureName(fontFamily: 'Opificio Neue');
    final badge = measureName(fontFamily: 'Fredoka');
    for (final level in [19, 23, 24, 999]) {
      final name = trackLevelDef(level)!.name;
      final fitted = fitLevelName(
        name,
        level,
        202,
        20,
        measure,
        measureBadge: badge,
      );
      expect(fitted.name, name);
      expect(fitted.width, lessThanOrEqualTo(202.001));
      expect(fitted.badgeWidth, greaterThanOrEqualTo(badge('$level', 12) + 10));
      final rank = fitRankName(name, level, 292, 18, measure);
      expect(rank.text, '$name · LV $level');
      expect(measure(rank.text, rank.size), lessThanOrEqualTo(292.001));
      final versus = fitName(name, 116, 15, measure);
      expect(versus.cut, isFalse);
      expect(measure(versus.text, versus.size), lessThanOrEqualTo(116.001));
    }
  });
}
