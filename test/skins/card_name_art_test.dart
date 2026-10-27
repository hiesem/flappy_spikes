import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/card_name_art.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> renderName(
  String id,
  double t, {
  String text = 'Flappy',
}) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  CardNameArt.paint(
    c,
    id,
    text,
    t: t,
    center: const Offset(120, 40),
    fontSize: 24,
    maxWidth: 190,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(240, 80);
  picture.dispose();
  return image;
}

Future<List<int>> pixels(ui.Image image) async =>
    (await image.toByteData())!.buffer.asUint8List();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Fredoka')
      ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
    await loader.load();
  });

  test('F9f all name layouts and glyphs are reused as only time changes', () {
    CardNameArt.debugClearLayoutCache();
    for (final id in CardNameArt.ids) {
      void paint(double t, {double size = 24, double room = 86}) {
        final recorder = ui.PictureRecorder();
        CardNameArt.paint(
          Canvas(recorder),
          id,
          'Wrené👩‍🚀888',
          t: t,
          fontSize: size,
          maxWidth: room,
          cacheLayout: true,
        );
        recorder.endRecording().dispose();
      }

      paint(.05);
      final first = CardNameArt.debugLayoutCount;
      for (final t in [.1, .4, 1.3, 2.75, 4.1]) {
        paint(t);
        expect(
          CardNameArt.debugLayoutCount,
          first,
          reason: '$id must reuse fitting, fill, outline and grapheme layouts',
        );
      }
      paint(.4, room: 60);
      expect(
        CardNameArt.debugLayoutCount,
        greaterThan(first),
        reason: 'a changed width must refit the name',
      );
      final resized = CardNameArt.debugLayoutCount;
      paint(.8, room: 60);
      expect(CardNameArt.debugLayoutCount, resized);
      paint(.4, size: 30, room: 60);
      expect(
        CardNameArt.debugLayoutCount,
        greaterThan(resized),
        reason: 'a changed font size must use its own layout',
      );
    }
  });

  testWidgets('F9f cached versus names retain the native art at three phases', (
    tester,
  ) async {
    await tester.runAsync(() async {
      Future<List<int>> render(String id, double t, bool cached) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 160, 60),
          Paint()..color = const Color(0xFFFFFFFF),
        );
        CardNameArt.paint(
          canvas,
          id,
          'SparklySparrow888',
          t: t,
          center: const Offset(80, 30),
          fontSize: 14,
          maxWidth: 86,
          cacheLayout: cached,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(160, 60);
        final data = (await image.toByteData())!.buffer.asUint8List().toList();
        image.dispose();
        picture.dispose();
        return data;
      }

      for (final id in CardNameArt.ids) {
        for (final t in [.05, 1.3, 2.75]) {
          final native = await render(id, t, false);
          final cached = await render(id, t, true);
          var error = 0;
          for (var i = 0; i < native.length; i++) {
            error += (native[i] - cached[i]).abs();
          }
          expect(
            error / native.length,
            lessThan(.15),
            reason: '$id at $t: cache must preserve the styled name art',
          );
        }
      }
    });
  });

  test('all 20 catalogue names have exactly one painter', () {
    expect(CardNameArt.ids, kCardNames.map((item) => item.id).toList());
    expect(CardNameArt.ids.toSet(), hasLength(20));
  });

  testWidgets('all 20 names: approved art sheet, three clock phases', (
    tester,
  ) async {
    ui.Image? sheet;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      c.drawRect(
        const Rect.fromLTWH(0, 0, 1000, 700),
        Paint()..color = const Color(0xFFFCD9EE),
      );
      for (var i = 0; i < kCardNames.length; i++) {
        final x = (i % 4) * 250.0, y = (i ~/ 4) * 140.0;
        c.drawRect(
          Rect.fromLTWH(x + 2, y + 2, 246, 136),
          Paint()..color = const Color(0xFFFFFFFF),
        );
        final label = TextPainter(
          text: TextSpan(
            text: kCardNames[i].name,
            style: const TextStyle(
              fontFamily: 'Fredoka',
              fontSize: 12,
              color: Color(0xFF4A0029),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(c, Offset(x + 8, y + 5));
        label.dispose();
        for (var j = 0; j < 3; j++) {
          CardNameArt.paint(
            c,
            kCardNames[i].id,
            'Flappy',
            t: [0.05, 1.3, 2.75][j],
            fontSize: 22,
            center: Offset(x + 125, y + 44 + j * 36),
          );
        }
      }
      final picture = recorder.endRecording();
      sheet = await picture.toImage(1000, 700);
      picture.dispose();
    });
    await expectLater(sheet!, matchesGoldenFile('goldens/card_names.png'));
    sheet!.dispose();
  });

  const animated = [
    'n_rainbow',
    'n_gold',
    'n_flappy',
    'n_glitch',
    'n_fire',
    'n_stardust',
    'n_sky',
    'n_thunder',
    'n_marquee',
  ];
  for (final id in animated) {
    testWidgets('$id freezes at the supplied game time and advances with it', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final a = await renderName(id, .05);
        final paused = await renderName(id, .05);
        final next = await renderName(id, id == 'n_flappy' ? .4 : 2.75);
        expect(await pixels(paused), await pixels(a));
        expect(await pixels(next), isNot(await pixels(a)));
        a.dispose();
        paused.dispose();
        next.dispose();
      });
    });
  }

  testWidgets(
    'Thunderstruck strikes again at 2.3 seconds, between strikes stays yellow',
    (tester) async {
      await tester.runAsync(() async {
        for (final time in [.05, 2.35]) {
          final image = await renderName('n_thunder', time);
          final data = await pixels(image);
          var white = 0;
          for (var i = 0; i < data.length; i += 4) {
            if (data[i] > 245 &&
                data[i + 1] > 245 &&
                data[i + 2] > 245 &&
                data[i + 3] > 200) {
              white++;
            }
          }
          expect(white, greaterThan(100));
          image.dispose();
        }
        final between = await renderName('n_thunder', 1.3);
        final data = await pixels(between);
        var yellow = 0, violet = 0;
        for (var i = 0; i < data.length; i += 4) {
          if (data[i] > 200 &&
              data[i + 1] > 150 &&
              data[i + 2] < 140 &&
              data[i + 3] > 200) {
            yellow++;
          }
          if (data[i + 2] > data[i + 1] + 20 &&
              data[i + 2] > data[i] + 10 &&
              data[i + 3] > 150) {
            violet++;
          }
        }
        expect(yellow, greaterThan(100));
        expect(violet, greaterThan(100));
        between.dispose();
      });
    },
  );

  testWidgets(
    'ShaderMask widget renders the same gradients as the canvas master',
    (tester) async {
      for (final id in [
        'n_sunset',
        'n_gold',
        'n_fire',
        'n_stardust',
        'n_sky',
        'n_thunder',
        'n_marquee',
      ]) {
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: CardNameStyle(
                  id: id,
                  text: 'Flappy',
                  t: 1.3,
                  fontSize: 24,
                ),
              ),
            ),
          ),
        );
        expect(find.byType(ShaderMask), findsOneWidget);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final widgetImage = await boundary.toImage();
          final recorder = ui.PictureRecorder();
          final c = Canvas(recorder);
          CardNameArt.paint(
            c,
            id,
            'Flappy',
            t: 1.3,
            fontSize: 24,
            center: Offset(boundary.size.width / 2, boundary.size.height / 2),
          );
          final picture = recorder.endRecording();
          final canvasImage = await picture.toImage(
            widgetImage.width,
            widgetImage.height,
          );
          // GPU masking can round a channel differently; allow <= 2 / 255.
          final a = await pixels(widgetImage), b = await pixels(canvasImage);
          var maxDifference = 0;
          for (var i = 0; i < a.length; i++) {
            final difference = (a[i] - b[i]).abs();
            if (difference > maxDifference) maxDifference = difference;
          }
          expect(maxDifference, lessThanOrEqualTo(2), reason: id);
          picture.dispose();
          widgetImage.dispose();
          canvasImage.dispose();
        });
      }
    },
  );

  testWidgets('empty, unknown, narrow and Unicode names are safe', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final text in ['', 'É🦅e\u0301', 'A very long player name']) {
        for (final id in [...CardNameArt.ids, 'unknown', '']) {
          final image = await renderName(id, 1.3, text: text);
          expect(image.width, 240);
          image.dispose();
        }
      }
      final unknown = await renderName('unknown', 0);
      final plain = await renderName('', 0);
      expect(await pixels(unknown), await pixels(plain));
      unknown.dispose();
      plain.dispose();
    });
  });
}
