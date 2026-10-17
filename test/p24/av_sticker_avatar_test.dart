import 'dart:io';
import 'dart:ui' as ui;

import 'package:flappy_spikes/components/sticker_avatar.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

/// The design page's 10 example looks (`avatar_design/src.html` LOOKS; the
/// `n_` prefix of the 2.3 items dropped).
const List<Look> kDesignLooks = [
  Look(),
  Look(bird: 'penguin', gear: 'snorkel', hat: 'cap'),
  Look(bird: 'duck', gear: 'shades', hat: 'sprout'),
  Look(bird: 'owl', gear: 'monocle', hat: 'tophat'),
  Look(bird: 'chick', gear: 'bowtie', hat: 'party'),
  Look(bird: 'pixel', gear: 'backpack', hat: 'ufo'),
  Look(bird: 'ghost', gear: 'cape', hat: 'halo'),
  Look(bird: 'galaxy', gear: 'crystal', hat: 'crown'),
  Look(bird: 'phoenix', gear: 'jetpack', hat: 'planet'),
  Look(bird: 'golden', gear: 'chain', hat: 'sunburst'),
];

/// Evidence directory (outside git); falls back to build/ when absent.
String get _outDir {
  const ev =
      '/home/killerhis/Projects/flappyspikes/.worktrees/briefs13/evidence/av';
  if (Directory(
    '/home/killerhis/Projects/flappyspikes/.worktrees/briefs13',
  ).existsSync()) {
    return ev;
  }
  return 'build/shots/p24/av';
}

Future<void> _savePng(ui.Image im, String name) async {
  final data = (await im.toByteData(format: ui.ImageByteFormat.png))!;
  final f = File('$_outDir/$name.png')..createSync(recursive: true);
  f.writeAsBytesSync(data.buffer.asUint8List());
}

/// Alpha of the pixel at (x, y).
Future<List<int>> _rgba(ui.Image im, int x, int y) async {
  final d = (await im.toByteData())!;
  final i = (y * im.width + x) * 4;
  return [
    d.getUint8(i),
    d.getUint8(i + 1),
    d.getUint8(i + 2),
    d.getUint8(i + 3),
  ];
}

/// A sheet: the 10 looks at [s] on a light grey card, then [extra].
Future<ui.Image> _sheet(
  StickerAvatars av,
  List<(Look, double)> cells, {
  ui.Color bg = const ui.Color(0xFFF1F1F1),
}) async {
  const pad = 12.0;
  var w = pad, h = 0.0;
  for (final (_, s) in cells) {
    w += s + pad;
    if (s > h) h = s;
  }
  h += 2 * pad;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(ui.Rect.fromLTWH(0, 0, w, h), ui.Paint()..color = bg);
  var x = pad;
  for (final (look, s) in cells) {
    av.paint(c, ui.Rect.fromLTWH(x, h - pad - s, s, s), look);
    x += s + pad;
  }
  return rec.endRecording().toImage(w.ceil(), h.ceil());
}

void main() {
  test('AV sticker sheets (design C): 10 looks at 96, sizes 128/64/40/28, '
      'mirrored, on game backgrounds', () async {
    final av = StickerAvatars(pixelsPerPoint: () => 2);
    final row = await _sheet(av, [for (final l in kDesignLooks) (l, 96.0)]);
    await _savePng(row, 'av_looks_96_x2');
    final sizes = await _sheet(av, [
      for (final s in [128.0, 64.0, 40.0, 28.0]) (kDesignLooks[3], s),
      for (final s in [128.0, 64.0, 40.0, 28.0]) (kDesignLooks[7], s),
    ]);
    await _savePng(sizes, 'av_sizes_x2');
    final av1 = StickerAvatars(pixelsPerPoint: () => 1);
    final sizes1 = await _sheet(av1, [
      for (final s in [128.0, 64.0, 40.0, 28.0]) (kDesignLooks[3], s),
    ]);
    await _savePng(sizes1, 'av_sizes_x1');
    // On the pink square (own) and a dark stage square (opponent).
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.drawRect(
      const ui.Rect.fromLTWH(0, 0, 260, 64),
      ui.Paint()..color = const ui.Color(0xFFF1F1F1),
    );
    c.drawRect(
      const ui.Rect.fromLTWH(8, 8, 52, 52),
      ui.Paint()..color = const ui.Color(0xFFEC008C),
    );
    av.paint(c, const ui.Rect.fromLTWH(8, 8, 52, 52), kDesignLooks[0]);
    c.drawRect(
      const ui.Rect.fromLTWH(70, 8, 52, 52),
      ui.Paint()..color = const ui.Color(0xFF3A3A3A),
    );
    av.paint(
      c,
      const ui.Rect.fromLTWH(70, 8, 52, 52),
      kDesignLooks[7],
      mirror: true,
    );
    c.drawRect(
      const ui.Rect.fromLTWH(132, 8, 38, 38),
      ui.Paint()..color = const ui.Color(0xFFC40073),
    );
    av.paint(c, const ui.Rect.fromLTWH(132, 8, 38, 38), kDesignLooks[8]);
    c.drawRect(
      const ui.Rect.fromLTWH(180, 8, 38, 38),
      ui.Paint()..color = const ui.Color(0xFF555555),
    );
    av.paint(
      c,
      const ui.Rect.fromLTWH(180, 8, 38, 38),
      kDesignLooks[4],
      mirror: true,
    );
    await _savePng(
      await rec.endRecording().toImage(260, 64),
      'av_in_squares_x1',
    );
  });

  test('AV the sticker: transparent corners, white edge, tinted blob, '
      'the bird in the middle', () async {
    final av = StickerAvatars(pixelsPerPoint: () => 1);
    final im = av.image(const Look(bird: 'sky'), 128);
    expect(im.width, 128);
    expect(im.height, 128);
    expect((await _rgba(im, 1, 1))[3], 0, reason: 'corner stays clear');
    // The blob's outer ring (between the bird and the star tips) shows the
    // tint: sky mixed 72 % to white.
    final tint = StickerAvatars.tintOf('sky');
    final p = await _rgba(im, 64, 64 + 46);
    expect(p[3], 255);
    expect((p[2] - (tint.b * 255).round()).abs(), lessThan(12));
    // Some pure-white edge pixels exist.
    final d = (await im.toByteData())!;
    var white = 0, opaque = 0;
    for (var i = 0; i < d.lengthInBytes; i += 4) {
      if (d.getUint8(i + 3) == 255) opaque++;
      if (d.getUint8(i) > 250 &&
          d.getUint8(i + 1) > 250 &&
          d.getUint8(i + 2) > 250 &&
          d.getUint8(i + 3) > 250) {
        white++;
      }
    }
    expect(white, greaterThan(150));
    expect(opaque, greaterThan(128 * 128 * .35));
  });

  test('AV tint: bird colour 72 % to white; snow / ghost / rainbow '
      'special cases', () {
    expect(
      StickerAvatars.tintOf('rainbow'),
      ui.Color.lerp(
        const ui.Color(0xFFFF5252),
        const ui.Color(0xFFFFFFFF),
        .72,
      ),
    );
    final grey = ui.Color.lerp(
      const ui.Color(0xFF90A4AE),
      const ui.Color(0xFFFFFFFF),
      .72,
    );
    expect(StickerAvatars.tintOf('snow'), grey);
    expect(StickerAvatars.tintOf('ghost'), grey);
    expect(StickerAvatars.tintOf('sky'), isNot(grey));
  });

  test('AV cache: each (bird, gear, hat, size) is rendered once; hoop and '
      'trail do not matter; LRU bounded', () {
    final av = StickerAvatars(pixelsPerPoint: () => 2, maxCached: 3);
    const a = Look(bird: 'owl', gear: 'monocle', hat: 'tophat');
    final first = av.image(a, 40);
    for (var i = 0; i < 50; i++) {
      expect(av.image(a, 40), same(first));
      expect(
        av.image(
          const Look(
            bird: 'owl',
            gear: 'monocle',
            hat: 'tophat',
            hoop: 'neon',
            trail: 'laser',
          ),
          40,
        ),
        same(first),
      );
    }
    expect(av.renders, 1);
    av.image(a, 52);
    expect(av.renders, 2, reason: 'another size is another image');
    av.image(const Look(bird: 'sky'), 40);
    av.image(const Look(bird: 'lime'), 40);
    expect(av.cachedKeys.length, 3);
    expect(av.cachedKeys.first, isNot(contains('owl|monocle|tophat|80')));
    av.clear();
    expect(av.cachedKeys, isEmpty);
  });

  test('AV unknown ids fall back per layer to the default '
      '(classic bird, no gear, no hat)', () {
    expect(
      StickerAvatars.normalise(
        const Look(bird: 'future_bird', gear: 'shades', hat: 'zz9'),
      ),
      const Look(bird: 'classic', gear: 'shades', hat: kNoneId),
    );
    expect(
      StickerAvatars.normalise(
        const Look(bird: 'owl', gear: 'warp_drive', hat: 'crown'),
      ),
      const Look(bird: 'owl', gear: kNoneId, hat: 'crown'),
    );
    final av = StickerAvatars(pixelsPerPoint: () => 1);
    final a = av.image(const Look(bird: 'nope', gear: 'nope', hat: 'nope'), 40);
    expect(av.image(const Look(), 40), same(a));
    expect(av.renders, 1);
  });

  test('AV every catalogue bird, gear and hat renders', () {
    final av = StickerAvatars(pixelsPerPoint: () => 1, maxCached: 200);
    for (final b in kBirds) {
      av.image(Look(bird: b.id), 28);
    }
    for (final g in kGear) {
      av.image(Look(gear: g.id), 28);
    }
    for (final h in kHats) {
      av.image(Look(hat: h.id), 28);
    }
    expect(av.renders, kBirds.length + kGear.length + kHats.length - 2);
  });
}
