// PRD-2.3 §12: the share card's logo bar. The pixels are pinned by the
// goldens in share_card_golden_test.dart; these tests pin the geometry the
// goldens are drawn with: the logo in the title's place, the two store
// badges at one common width, each at its own artwork proportions, inside
// the bar with equal top and bottom margins.
import 'dart:ui' show Size;

import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/share/share_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShareCardAssets img;
  setUpAll(() async => img = await ShareCardAssets.load());

  const barTop = ShareCardPainter.footY;
  const barMid = ShareCardPainter.footY + ShareCardPainter.footHeight / 2;

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
    expect(l.icon.center.dy, barMid);
  });

  test('both store badges have one common width', () {
    final l = ShareCardPainter.footerLayout(img);
    expect(l.googlePlay.width, closeTo(ShareCardPainter.badgeWidth, 1e-6));
    expect(l.appStore.width, closeTo(ShareCardPainter.badgeWidth, 1e-6));
    expect(l.appStore.width, closeTo(l.googlePlay.width, 1e-6));
  });

  test('each badge keeps its artwork proportions within 0.5 % (no stretching)',
      () {
    final l = ShareCardPainter.footerLayout(img);
    final pairs = [(l.googlePlay, img.googlePlay), (l.appStore, img.appStore)];
    for (final (rect, artwork) in pairs) {
      final ratio = rect.width / rect.height;
      expect(
        ratio / (artwork.width / artwork.height),
        closeTo(1, 0.005),
      );
    }
  });

  test('both badges share one vertical axis, at the right margin of 64 px',
      () {
    final l = ShareCardPainter.footerLayout(img);
    expect(l.appStore.center.dx, closeTo(l.googlePlay.center.dx, 1e-6));
    expect(l.appStore.left, closeTo(l.googlePlay.left, 1e-6));
    expect(l.googlePlay.right, closeTo(ShareCardPainter.size - 64, 1e-6));
  });

  test('the gap between the two badges is at least 14 px', () {
    final l = ShareCardPainter.footerLayout(img);
    final gap = l.appStore.top - l.googlePlay.bottom;
    expect(gap, closeTo(ShareCardPainter.badgeGap, 1e-6));
    expect(gap, greaterThanOrEqualTo(14));
  });

  test('the badge column is centred in the logo bar: equal top and bottom '
      'margins, both at least 8 px', () {
    final l = ShareCardPainter.footerLayout(img);
    final topMargin = l.googlePlay.top - barTop;
    final bottomMargin = ShareCardPainter.size - l.appStore.bottom;
    expect(topMargin, closeTo(bottomMargin, 1e-6));
    expect((l.googlePlay.top + l.appStore.bottom) / 2, closeTo(barMid, 1e-6));
    expect(topMargin, greaterThanOrEqualTo(8));
  });

  test('every rect stays inside the logo bar', () {
    final l = ShareCardPainter.footerLayout(img);
    for (final r in [l.icon, l.logo, l.googlePlay, l.appStore]) {
      expect(r.top, greaterThanOrEqualTo(barTop));
      expect(r.bottom, lessThanOrEqualTo(ShareCardPainter.size));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(ShareCardPainter.size));
    }
  });
}
