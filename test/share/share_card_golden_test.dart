// PRD-2.3 §6.1 golden images of the share cards (§4.2, §4.3, §4.5, §9.5,
// §12): Spotlight at levels 0 / 3 / 6 / 8 / 9 / 10 with different looks,
// 1- / 3- / 4-digit scores, the longest banner with a 16-character name, and
// the two new-player cards with two looks each.
//
// Update with: flutter test --update-goldens test/share/share_card_golden_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flappy_spikes/share/share_card.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';

Future<void> loadCardFonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  await Future.wait([lvdc.load(), opificio.load(), fredoka.load()]);
}

ShareCardData card({
  ShareCardKind kind = ShareCardKind.spotlight,
  int score = 47,
  int best = 132,
  int level = 3, // PRD-2.6 J5: progression is independent of best score.
  Look look = const Look(),
  String name = 'HiesemSurak',
  String banner = 'BEAT MY SCORE!',
}) => ShareCardData(
  kind: kind,
  progression: kind == ShareCardKind.spotlight,
  score: score,
  best: best,
  level: kind == ShareCardKind.spotlight ? level : 0,
  look: look,
  name: name,
  banner: banner,
  bannerId: 1,
  text: 'text',
  textId: 1,
);

Future<ui.Image> draw(ShareCardData data) async {
  final assets = await ShareCardAssets.load();
  final png = await renderShareCardPng(data, assets);
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// The golden cases (file name → card).
final Map<String, ShareCardData> goldens = {
  // §4.3 unranked (level 0), 1 digit.
  'spotlight_l0_1digit': card(
    level: 0,
    score: 7,
    best: 8,
    look: const Look(bird: 'sky', gear: 'shades'),
    name: 'SpikeDodger',
    banner: 'I DARE YOU!',
  ),
  // Level 3 Fledgling (the design's c1), 2 digits.
  'spotlight_l3': card(
    score: 47,
    best: 132,
    look: const Look(bird: 'mint', hat: 'party'),
  ),
  // Level 6 Falcon (c2), 3 digits.
  'spotlight_l6_3digit': card(
    level: 6,
    score: 118,
    best: 640,
    look: const Look(bird: 'classic', gear: 'shades', hat: 'cap'),
    name: 'RapidParrot411',
    banner: 'TRY TO BEAT ME!',
  ),
  // Level 8 Spike Ace (c5) with the longest banner and a 16-character name.
  'spotlight_l8_longest': card(
    level: 8,
    score: 87,
    best: 1240,
    look: const Look(bird: 'robo', hat: 'tophat'),
    name: 'WWWWWWWWWWWWWWWW',
    banner: 'THINK YOU CAN WIN?',
  ),
  // Level 9 Phoenix (c3).
  'spotlight_l9': card(
    level: 9,
    score: 263,
    best: 2150,
    look: const Look(bird: 'phoenix', gear: 'chain'),
    name: 'SpikeDodger',
    banner: 'I DARE YOU!',
  ),
  // Level 10 Legend (c4), 4 digits.
  'spotlight_l10_4digit': card(
    level: 10,
    score: 5320,
    best: 5320,
    look: const Look(bird: 'galaxy', hat: 'halo'),
    name: 'NightFlapper',
    banner: 'CAN YOU BEAT IT?',
  ),
  // §4.5 new-player cards, two looks each.
  'dodge_sky_shades': card(
    kind: ShareCardKind.dodge,
    look: const Look(bird: 'sky', gear: 'shades'),
    name: 'SpikeDodger',
    banner: 'THINK YOU CAN WIN?',
  ),
  'dodge_classic': card(
    kind: ShareCardKind.dodge,
    look: const Look(),
    name: 'RapidParrot411',
    banner: 'BEAT MY SCORE!',
  ),
  'flock_tangerine_crown': card(
    kind: ShareCardKind.flock,
    look: const Look(bird: 'tangerine', gear: 'shades', hat: 'crown'),
    name: 'GoldenWing',
    banner: 'CAN YOU BEAT IT?',
  ),
  'flock_grape_party': card(
    kind: ShareCardKind.flock,
    look: const Look(bird: 'grape', hat: 'party'),
    name: 'HiesemSurak',
    banner: 'TRY TO BEAT ME!',
  ),
};

class _RejectingComparator extends GoldenFileComparator {
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async =>
      throw FlutterError('S8-01 deliberate comparator rejection');

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async =>
      throw StateError('The negative control must never update a golden');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCardFonts);

  for (final MapEntry(key: name, value: data) in goldens.entries) {
    test('§6.1 golden $name', () async {
      final image = await draw(data);
      expect(image.width, 1080);
      expect(image.height, 1080);
      // S8-01: ui.Image matching uses binding.runAsync, which catches a
      // comparator FlutterError and returns null in a plain test(). Compare
      // PNG bytes directly so a mismatch reaches the test runner.
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await expectLater(
        png!.buffer.asUint8List(),
        matchesGoldenFile('goldens/$name.png'),
      );
      image.dispose();
    });
  }

  test('S8-01 a changed score actually rejects the golden', () async {
    final image = await draw(
      card(
        score: 8,
        best: 8,
        look: const Look(bird: 'sky', gear: 'shades'),
        name: 'SpikeDodger',
        banner: 'I DARE YOU!',
      ),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    // compareLists does not write failure images or rely on the widget
    // binding; pin that the negative control has different pixels.
    final reference = await File(
      'test/share/goldens/spotlight_l0_1digit.png',
    ).readAsBytes();
    final result = await GoldenFileComparator.compareLists(
      png!.buffer.asUint8List(),
      reference,
    );
    expect(result.passed, isFalse);
    result.dispose();
    final original = goldenFileComparator;
    final wasUpdating = autoUpdateGoldenFiles;
    try {
      autoUpdateGoldenFiles = false; // the negative control must compare
      goldenFileComparator = _RejectingComparator();
      await expectLater(
        () => expectLater(
          png.buffer.asUint8List(),
          matchesGoldenFile('goldens/spotlight_l0_1digit.png'),
        ),
        throwsA(isA<FlutterError>()),
      );
    } finally {
      goldenFileComparator = original;
      autoUpdateGoldenFiles = wasUpdating;
    }
  });

  test('§4.2 item 6 an empty username leaves out the name tag', () async {
    final withTag = await draw(card(name: 'HiesemSurak'));
    final without = await draw(card(name: ''));
    Future<Uint8List> rgba(ui.Image i) async => (await i.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    // The tag centre (430, 730) is white with a tag, the level plate
    // colour (level 3) without.
    int px(Uint8List b, int x, int y) => (y * 1080 + x) * 4;
    final a = await rgba(withTag), b = await rgba(without);
    final i = px(a, 300, 730);
    expect([a[i], a[i + 1], a[i + 2]], [255, 255, 255]);
    expect([b[i], b[i + 1], b[i + 2]], isNot([255, 255, 255]));
    withTag.dispose();
    without.dispose();
  });
}
