// PRD-2.3 §12: the share card's logo bar. The pixels are pinned by the
// goldens in share_card_golden_test.dart; these tests pin the geometry the
// goldens are drawn with (the logo in the title's place, the two store
// badges in one slot, nothing stretched).
import 'dart:ui' show Size;

import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/share/share_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShareCardAssets img;
  setUpAll(() async => img = await ShareCardAssets.load());

  test('the logo takes the title\'s place: its lettering starts at the '
      'title\'s x (icon right + 28) and is centred on the icon', () {
    final l = ShareCardPainter.footerLayout(img);
    final k = l.logo.width / ShareCardPainter.logoSource.width;
    final ink = ShareCardPainter.logoInk;
    expect(ink.height * k, closeTo(ShareCardPainter.logoInkHeight, 1e-6));
    expect(l.logo.left + ink.left * k, closeTo(l.icon.right + 28, 1e-6));
    expect(
      l.logo.top + (ink.top + ink.height / 2) * k,
      closeTo(l.icon.center.dy, 1e-6),
    );
  });

  test('the logo keeps the home logo\'s aspect ratio (never stretched)', () {
    final l = ShareCardPainter.footerLayout(img);
    expect(l.logo.width / l.logo.height, closeTo(Config.homeLogoAspect, 1e-6));
  });

  test('the icon is 128 square at x 64, centred in the logo bar', () {
    final l = ShareCardPainter.footerLayout(img);
    expect(l.icon.size, const Size.square(128));
    expect(l.icon.left, 64);
    expect(
      l.icon.center.dy,
      ShareCardPainter.footY + ShareCardPainter.footHeight / 2,
    );
  });

  test('the Google Play badge keeps its size: 86 high, its own proportions, '
      'right edge 64 from the card edge', () {
    final l = ShareCardPainter.footerLayout(img);
    expect(l.googlePlay.height, closeTo(86, 1e-6));
    expect(
      l.googlePlay.width / l.googlePlay.height,
      closeTo(img.googlePlay.width / img.googlePlay.height, 1e-6),
    );
    expect(l.googlePlay.right, closeTo(ShareCardPainter.size - 64, 1e-6));
  });

  test('the App Store badge sits in the Google Play slot: centred under it, '
      'at its own proportions (not stretched)', () {
    final l = ShareCardPainter.footerLayout(img);
    expect(l.appStore.height, closeTo(86, 1e-6));
    expect(
      l.appStore.width / l.appStore.height,
      closeTo(img.appStore.width / img.appStore.height, 1e-6),
    );
    expect(l.appStore.center.dx, closeTo(l.googlePlay.center.dx, 1e-6));
    expect(l.appStore.width, lessThanOrEqualTo(l.googlePlay.width));
  });

  test('the two badges form one column, 14 apart, centred vertically in the '
      'logo bar', () {
    final l = ShareCardPainter.footerLayout(img);
    expect(l.appStore.top - l.googlePlay.bottom, closeTo(14, 1e-6));
    expect(
      (l.googlePlay.top + l.appStore.bottom) / 2,
      closeTo(ShareCardPainter.footY + ShareCardPainter.footHeight / 2, 1e-6),
    );
  });

  test('every rect stays inside the logo bar', () {
    final l = ShareCardPainter.footerLayout(img);
    for (final r in [l.icon, l.googlePlay, l.appStore]) {
      expect(r.top, greaterThanOrEqualTo(ShareCardPainter.footY));
      expect(r.bottom, lessThanOrEqualTo(ShareCardPainter.size));
    }
    expect(l.logo.top, greaterThanOrEqualTo(ShareCardPainter.footY));
    expect(l.logo.bottom, lessThanOrEqualTo(ShareCardPainter.size));
  });
}
