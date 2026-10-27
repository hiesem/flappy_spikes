import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flappy_spikes/skins/art/card_frame_art.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'p23_render.dart';

Future<ui.Image> _frame(
  String id,
  double size,
  double t, {
  bool avatar = false,
}) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder)
    ..scale(4)
    ..translate(64, 64);
  CardFrameArt.paintBack(c, id, size: size, t: t);
  if (avatar) {
    c.drawRect(
      Rect.fromCenter(center: Offset.zero, width: size, height: size),
      Paint()..color = const Color(0xFFF8BBD9),
    );
    c.save();
    c.scale(size / 44);
    LookPainter.paint(c, const Look(bird: 'classic'), t: 0);
    c.restore();
  }
  CardFrameArt.paintFront(c, id, size: size, t: t);
  final picture = recorder.endRecording();
  final result = await picture.toImage(512, 512);
  picture.dispose();
  return result;
}

Future<Uint8List> _pixels(String id, double size, double t) async {
  final image = await _frame(id, size, t);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader('Opificio Neue')
      ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
    await font.load();
  });

  test(
    'every catalog frame has one painter, including the three skill items',
    () {
      expect(CardFrameArt.ids, kCardFrames.map((e) => e.id).toList());
      expect(CardFrameArt.ids.toSet(), hasLength(20));
      expect(CardFrameArt.ids.skip(17), ['pecking', 'roost', 'prey']);
    },
  );

  testWidgets('all 20 frames: HUD and intro, two game-clock phases', (
    tester,
  ) async {
    ui.Image? sheet;
    await tester.runAsync(() async {
      sheet = await renderGrid(
        [
          for (final t in [0.08, 1.3])
            for (final size in [38.0, 52.0])
              for (final id in CardFrameArt.ids)
                (c) {
                  c.translate(48, 48);
                  CardFrameArt.paintBack(c, id, size: size, t: t);
                  c.drawRect(
                    Rect.fromCenter(
                      center: Offset.zero,
                      width: size,
                      height: size,
                    ),
                    Paint()..color = const Color(0xFFF8BBD9),
                  );
                  c.save();
                  c.scale(size / 44);
                  LookPainter.paint(c, const Look(bird: 'classic'), t: 0);
                  c.restore();
                  CardFrameArt.paintFront(c, id, size: size, t: t);
                },
        ],
        w: 96,
        h: 96,
        cols: 10,
        scale: 2,
        background: const Color(0xFFF1F1F1),
      );
    });
    await expectLater(sheet!, matchesGoldenFile('goldens/p26_card_frames.png'));
    sheet!.dispose();
  });

  testWidgets(
    'complete animated silhouettes fit within 7 pt without clipping',
    (tester) async {
      await tester.runAsync(() async {
        for (final size in [38.0, 52.0, 84.0]) {
          for (final id in CardFrameArt.ids) {
            for (final t in [0.0, .08, .2, .7, 1.3, 2.75, 4.9]) {
              final data = await _pixels(id, size, t);
              final limit = size / 2 + 7;
              var count = 0;
              var reach = 0.0;
              for (var y = 0; y < 512; y++) {
                for (var x = 0; x < 512; x++) {
                  if (data[(y * 512 + x) * 4 + 3] <= 16) continue;
                  count++;
                  reach = math.max(
                    reach,
                    math.max(
                      ((x + .5) / 4 - 64).abs(),
                      ((y + .5) / 4 - 64).abs(),
                    ),
                  );
                }
              }
              expect(
                reach,
                lessThanOrEqualTo(limit + .125),
                reason: '$id size=$size t=$t silhouette reach=$reach',
              );
              expect(count, greaterThan(0), reason: '$id must draw');
            }
          }
        }
      });
    },
  );

  testWidgets(
    'fixed run clock freezes art; advancing it animates every animated frame',
    (tester) async {
      await tester.runAsync(() async {
        for (final id in CardFrameArt.ids) {
          final frozen = await _pixels(id, 38, .08);
          await Future<void>.delayed(const Duration(milliseconds: 1));
          expect(await _pixels(id, 38, .08), frozen, reason: '$id paused');
          final later = await _pixels(id, 38, 1.3);
          if (CardFrameArt.animatedIds.contains(id)) {
            expect(later, isNot(frozen), reason: '$id must animate');
          } else {
            expect(later, frozen, reason: '$id static');
          }
        }
      });
    },
  );

  test('adapter repaints on host time changes only for animated art', () {
    for (final id in CardFrameArt.ids) {
      final old = CardFramePainter(id: id, avatarSize: 38, t: 0);
      expect(
        CardFramePainter(id: id, avatarSize: 38, t: 1).shouldRepaint(old),
        CardFrameArt.animatedIds.contains(id),
      );
      expect(
        CardFramePainter(id: id, avatarSize: 38, t: 0).shouldRepaint(old),
        false,
      );
      expect(
        CardFramePainter(id: id, avatarSize: 52, t: 0).shouldRepaint(old),
        true,
      );
      expect(
        CardFramePainter(id: id, avatarSize: 38, back: true).shouldRepaint(old),
        true,
      );
    }
  });

  testWidgets('empty and unknown ids are safe no-ops', (tester) async {
    await tester.runAsync(() async {
      for (final id in ['', 'none', 'future_frame']) {
        expect((await _pixels(id, 38, 0)).every((v) => v == 0), true);
      }
    });
  });
}
