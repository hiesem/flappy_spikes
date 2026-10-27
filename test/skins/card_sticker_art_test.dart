import 'dart:ui' as ui;

import 'package:flappy_spikes/skins/art/card_sticker_art.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'p23_render.dart';

Future<ui.Image> _render(String id, double t, ui.Image coin) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..translate(80, 80);
  CardStickerArt.paint(canvas, id, t: t, coinImage: coin);
  final picture = recorder.endRecording();
  final result = await picture.toImage(160, 160);
  picture.dispose();
  return result;
}

Future<Uint8List> _pixels(String id, double t, ui.Image coin) async {
  final image = await _render(id, t, coin);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.Image coin;

  setUpAll(() async {
    for (final (family, asset) in [
      ('Fredoka', 'assets/fonts/Fredoka-SemiBold.ttf'),
      ('Opificio Neue', 'assets/fonts/Opificio_neue-regular.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
    final data = await rootBundle.load('assets/images/menu/coin.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    coin = (await codec.getNextFrame()).image;
    codec.dispose();
  });
  tearDownAll(() => coin.dispose());

  test(
    'every catalog sticker, including all three skill stickers, has art',
    () {
      expect(CardStickerArt.ids, kCardStickers.map((i) => i.id).toList());
      expect(CardStickerArt.ids.toSet(), hasLength(20));
      for (final item in kCardStickers) {
        expect(CardStickerArt.has(item.id), isTrue, reason: item.id);
      }
      expect(CardStickerArt.has(''), isFalse);
      expect(CardStickerArt.has('s_future'), isFalse);
    },
  );

  // F9d: one sheet for the kind, all 20 in catalog order at four phases.
  // The skill rows include impact/shards, the turning facets, and crown
  // landing/bowing. Reuse rule O98 leaves shared ray rendering to the host.
  testWidgets('all twenty stickers golden sheet, four game-clock phases', (
    tester,
  ) async {
    ui.Image? image;
    await tester.runAsync(() async {
      image = await renderGrid(
        [
          for (final t in [.18, .65, 1.65, 2.6])
            for (final item in kCardStickers)
              (c) {
                c.drawRect(
                  const Rect.fromLTWH(1, 1, 118, 126),
                  Paint()..color = const Color(0xFFE2E2E2),
                );
                c.save();
                c.translate(60, 64);
                CardStickerArt.paint(
                  c,
                  item.id,
                  t: t,
                  scale: .8,
                  coinImage: coin,
                );
                c.restore();
                final label = TextPainter(
                  text: TextSpan(
                    text: '${item.name}\nt=$t',
                    style: const TextStyle(
                      fontFamily: 'Opificio Neue',
                      fontSize: 9,
                      color: Color(0xFF5A0033),
                    ),
                  ),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                )..layout(maxWidth: 116);
                label.paint(c, Offset(60 - label.width / 2, 102));
                label.dispose();
              },
        ],
        w: 120,
        h: 128,
        cols: 10,
        scale: 2,
        background: const Color(0xFFF1F1F1),
      );
    });
    await expectLater(image!, matchesGoldenFile('goldens/card_stickers.png'));
    image!.dispose();
  });

  testWidgets('all animated stickers freeze at supplied time and resume', (
    tester,
  ) async {
    const animated = [
      's_heart',
      's_kaching',
      's_spiked',
      's_nailed',
      's_bye',
      's_hatch',
      's_zoom',
      's_hot',
      's_medal',
      's_piggy',
      's_disco',
      's_champ',
      's_fireworks',
      's_unstop',
      's_flawless',
      's_topflock',
    ];
    for (final id in animated) {
      late Uint8List before, frozen, resumed;
      await tester.runAsync(() async {
        before = await _pixels(id, .18, coin);
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() async {
        resumed = await _pixels(id, 1.65, coin);
        // Draw out of order: no shared state may advance a paused sticker.
        frozen = await _pixels(id, .18, coin);
      });
      expect(frozen, orderedEquals(before), reason: '$id frozen clock');
      // The shared classic bird itself has no idle cycle; Nailed It's
      // motion is its host's slap-on, so it can stay static here.
      if (id != 's_nailed') {
        expect(resumed, isNot(orderedEquals(before)), reason: '$id resumes');
      }
      expect(before.any((v) => v != 0), isTrue, reason: '$id has visible art');
    }
  });

  test('unknown slots are empty and canvas state is restored', () async {
    final blank = await _pixels('', 1, coin);
    expect(blank.every((v) => v == 0), isTrue);
    expect(await _pixels('s_future', 1, coin), orderedEquals(blank));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final count = canvas.getSaveCount();
    for (final id in CardStickerArt.ids) {
      CardStickerArt.paint(canvas, id, coinImage: coin);
      expect(canvas.getSaveCount(), count, reason: id);
    }
    recorder.endRecording().dispose();
  });

  test('shared rays receive the supplied clock, centre and scale', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final calls = <(Offset, double, double)>[];
    for (final id in ['s_champ', 's_flawless', 's_topflock', 's_gg']) {
      CardStickerArt.paint(
        canvas,
        id,
        t: 1.25,
        paintRays: (c, centre, radius, t) => calls.add((centre, radius, t)),
      );
    }
    expect(calls, [
      (Offset.zero, 46.0, 1.25),
      (const Offset(0, -12), 46.0, 1.25),
      (const Offset(0, -14), 46.0, 1.25),
    ]);
    recorder.endRecording().dispose();
  });

  test('widget adapter repaints only for changed inputs', () {
    final first = CardStickerPainter(id: 's_flawless', t: 2, coinImage: coin);
    expect(
      CardStickerPainter(
        id: 's_flawless',
        t: 2,
        coinImage: coin,
      ).shouldRepaint(first),
      isFalse,
    );
    expect(
      CardStickerPainter(
        id: 's_flawless',
        t: 3,
        coinImage: coin,
      ).shouldRepaint(first),
      isTrue,
    );
    expect(
      CardStickerPainter(
        id: 's_gg',
        t: 2,
        coinImage: coin,
      ).shouldRepaint(first),
      isTrue,
    );
  });
}
