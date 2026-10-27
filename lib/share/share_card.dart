import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../components/levels/emblem_view.dart';
import '../levels/emblem_painter.dart';
import '../levels/level_track.dart';
import '../levels/levels.dart';
import '../run/hud/fit_name.dart';
import '../skins/art/look_painter.dart';
import '../skins/look.dart';

/// Which card a share draws (PRD-2.3 §4): the Spotlight score card, or one
/// of the two new-player invite cards (`n3` Dodge the spikes, `n4` Pick your
/// bird). [analytics] is the §2.1 `card` parameter.
enum ShareCardKind {
  spotlight('spotlight'),
  dodge('dodge'),
  flock('flock');

  const ShareCardKind(this.analytics);

  final String analytics;
}

/// Everything one share needs (PRD-2.3 §4.1, §4.6): the card's content plus
/// the picked share text and the analytics ids. Built only from the
/// sharer's own data, never an opponent's.
class ShareCardData {
  const ShareCardData({
    required this.kind,
    required this.score,
    required this.best,
    required this.level,
    required this.look,
    required this.name,
    required this.banner,
    required this.bannerId,
    required this.text,
    required this.textId,
    this.progression = false,
  });

  final ShareCardKind kind;

  /// The points on the sticker (Spotlight only).
  final int score;

  /// The stored best after the run is counted (Spotlight only).
  final int best;

  /// The stored player level (WP-L): the emblem and the card colours
  /// (0 = unranked).
  final int level;

  // region P26-J7
  /// J2 opts migrated callers into the cumulative track, including slots
  /// 1–10. Legacy score-rank callers keep their established artwork until
  /// that migration; levels above ten unambiguously belong to the track.
  final bool progression;
  bool get usesProgression => progression || level > 10;
  // endregion

  /// The equipped look (bird, gear, hat are drawn).
  final Look look;

  /// The username; empty = no name tag (§4.2 item 6).
  final String name;

  /// The §3.2 banner text and its 1-based id.
  final String banner;
  final int bannerId;

  /// The share-sheet text (§3.1 or §3.3) and its 1-based id.
  final String text;
  final int textId;

  /// §2.1 analytics parameters (`share_score` adds `score`, `invite` adds
  /// `card`).
  Map<String, Object> get analytics => {
    'text_id': textId,
    'banner_id': bannerId,
    'level': level,
  };

  @override
  String toString() =>
      'ShareCardData(${kind.analytics}, score $score, best $best, level '
      '$level, $look, "$name", "$banner" #$bannerId, text #$textId)';
}

/// The bundled images the cards use (§4.3: nothing is downloaded).
class ShareCardAssets {
  ShareCardAssets({
    required this.spikes,
    required this.icon,
    required this.logo,
    required this.googlePlay,
    required this.appStore,
    required this.coin,
  });

  final ui.Image spikes;
  final ui.Image icon;
  final ui.Image logo;
  final ui.Image googlePlay;
  final ui.Image appStore;
  final ui.Image coin;

  static const String spikesAsset = 'assets/images/ground_spikes.png';
  static const String iconAsset = 'assets/images/app_icon.png';
  static const String logoAsset = 'assets/images/menu/logo.png';
  static const String googlePlayAsset =
      'assets/images/share/badge_google_play.png';
  static const String appStoreAsset = 'assets/images/share/badge_app_store.png';
  static const String coinAsset = 'assets/images/menu/coin.png';

  static Future<ShareCardAssets>? _cached;

  /// Decodes the images once per app run (they are small; the 1024 icon is
  /// decoded at 256 and the logo at 544, twice their sizes on the card).
  static Future<ShareCardAssets> load([AssetBundle? bundle]) {
    final b = bundle ?? rootBundle;
    return _cached ??= _load(b).catchError((Object e) {
      _cached = null;
      throw e;
    });
  }

  static Future<ShareCardAssets> _load(AssetBundle b) async {
    Future<ui.Image> decode(String key, {int? width}) async {
      final data = await b.load(key);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        targetWidth: width,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    }

    final images = await Future.wait([
      decode(spikesAsset),
      decode(iconAsset, width: 256),
      decode(logoAsset, width: 544),
      decode(googlePlayAsset),
      decode(appStoreAsset),
      decode(coinAsset),
    ]);
    return ShareCardAssets(
      spikes: images[0],
      icon: images[1],
      logo: images[2],
      googlePlay: images[3],
      appStore: images[4],
      coin: images[5],
    );
  }
}

/// Draws the 1080 x 1080 share cards with `dart:ui` (PRD-2.3 §4): a port of
/// `spotlight()` / `newcomer()` in `design/share_v23/share_card.html` (the
/// file wins on positions). Pure painting: no Flame, no game state. Every
/// shared part (rays, sticker, banner, name tag, spike strips, logo bar) has
/// one master here; the emblem and the birds are [EmblemPainter] and
/// [LookPainter].
abstract final class ShareCardPainter {
  /// Canvas edge (px).
  static const double size = 1080;

  static const Color pink = Color(0xFFEC008C);
  static const Color plum = Color(0xFF7A0044);
  static const Color gold = Color(0xFFFFB529);
  static const Color white = Color(0xFFFFFFFF);
  static const Color grey = Color(0xFF828282);
  static const Color greyBg = Color(0xFFF1F1F1);
  static const Color legendBest = Color(0xFFFFE082);

  static const double spikeHeight = 74;
  static const double footHeight = 200;
  static const double footY = size - footHeight;

  /// The store badges on the logo bar (px): one common width, each at its
  /// own artwork proportions (so the two heights differ), and the gap
  /// between them.
  static const double badgeWidth = 256;
  static const double badgeGap = 16;

  /// The logo's lettering on the card (px): the opaque part of
  /// `logo.png` ([logoInk] of [logoSource]) is this tall.
  static const double logoInkHeight = 128;
  static const Rect logoInk = Rect.fromLTWH(30, 10, 537, 295);
  static const Size logoSource = Size(600, 352);

  /// Centre of the emblem / centre art and of the rays.
  static const Offset centre = Offset(430, 470);

  // region P26-J7
  /// Below the name tag (bottom 766), above the bottom spikes (top 806).
  static const Rect rankLine = Rect.fromLTWH(130, 770, 600, 30);
  // endregion

  static const String _score = 'LVDC Common2';
  static const String _display = 'Opificio Neue';
  static const String _body = 'Fredoka';

  /// Paints [data] on [canvas] (0,0 top left, 1080 x 1080).
  static void paint(
    Canvas canvas,
    ShareCardData data,
    ShareCardAssets img, {
    ui.Image? emblem,
  }) {
    switch (data.kind) {
      case ShareCardKind.spotlight:
        _spotlight(canvas, data, img, emblem: emblem);
      case ShareCardKind.dodge:
        _newcomer(
          canvas,
          data,
          img,
          bg: const Color(0xFFE5F2F9),
          ink: const Color(0xFF667B84),
          art: () => _dodgeArt(canvas, data.look, img),
        );
      case ShareCardKind.flock:
        _newcomer(
          canvas,
          data,
          img,
          bg: const Color(0xFFF9EDE6),
          ink: const Color(0xFF806A62),
          art: () => _flockArt(canvas, data.look),
        );
    }
  }

  // --- the cards ------------------------------------------------------------

  static void _spotlight(
    Canvas c,
    ShareCardData d,
    ShareCardAssets img, {
    ui.Image? emblem,
  }) {
    // region P26-J7
    final def = trackLevelDef(d.level);
    final track = d.usesProgression ? def : null;
    // endregion
    // §4.3 unranked: the post-run grey palette.
    final bg = track?.plate ?? def?.plate ?? greyBg;
    final rayColor = track?.rim ?? def?.rim ?? grey;
    final rayAlpha = def == null && track == null
        ? .15
        : (d.level == 10 ? .22 : .28);
    final ink = track?.accent ?? def?.accent ?? grey;
    final bestColor = d.level == 10 ? legendBest : ink;
    c.drawRect(const Rect.fromLTWH(0, 0, size, size), Paint()..color = bg);
    _rays(c, rayColor, rayAlpha);
    // Emblem with the equipped bird on the plate (as the Levels screen).
    c.save();
    c.translate(centre.dx, centre.dy);
    c.scale(2.55);
    // region P26-J7
    if (!d.usesProgression) {
      EmblemPainter.paint(c, d.level, t: 0, shine: false);
    } else {
      EmblemPainter.paintTrack(
        c,
        d.level,
        shine: false,
        reduceMotion: true,
        image: emblem,
      );
    }
    // endregion
    c.translate(0, -2);
    c.scale(1.4);
    LookPainter.paint(c, d.look);
    c.restore();
    _sticker(c, pink, (r) {
      final s = '${d.score}';
      final want = s.length > 2 ? r * .9 : r * 1.15;
      _text(
        c,
        s,
        0,
        -r * .1,
        family: _score,
        size: want,
        color: white,
        maxWidth: r * 2 * .8,
      );
      _text(c, 'POINTS', 0, r * .58, size: r * .2, color: white, spacing: 6);
    });
    _banner(c, d.banner);
    // region P26-J7
    if (d.usesProgression && track != null) {
      final rank = fitRankName(
        track.name,
        d.level,
        rankLine.width,
        rankLine.height,
        measureName(fontFamily: _display),
      );
      _text(
        c,
        rank.text,
        rankLine.center.dx,
        rankLine.center.dy,
        size: rank.size,
        color: d.level >= 26 ? white : ink,
      );
    }
    // endregion
    _nameTag(c, d.name);
    _text(
      c,
      'BEST ${d.best}',
      820,
      560,
      family: _body,
      size: 36,
      color: bestColor,
    );
    _frame(c, ink, img);
  }

  static void _newcomer(
    Canvas c,
    ShareCardData d,
    ShareCardAssets img, {
    required Color bg,
    required Color ink,
    required void Function() art,
  }) {
    c.drawRect(const Rect.fromLTWH(0, 0, size, size), Paint()..color = bg);
    _rays(c, ink, .12);
    art();
    _sticker(c, gold, (r) {
      _text(c, 'FREE', 0, -r * .1, family: _score, size: r * .56, color: white);
      _text(c, 'TO PLAY', 0, r * .5, size: r * .22, color: plum, spacing: 6);
    });
    _banner(c, d.banner);
    _nameTag(c, d.name);
    _frame(c, ink, img);
  }

  /// `n3` Dodge the spikes: two spike blocks, a dashed flap path with two
  /// coins, and the player's bird (wings up).
  static void _dodgeArt(Canvas c, Look look, ShareCardAssets img) {
    const ink = Color(0xFF667B84);
    final fill = Paint()..color = ink;
    void teeth(double x, double y, bool up, int n, double s) {
      for (var i = 0; i < n; i++) {
        final tx = x + i * s;
        c.drawPath(
          Path()
            ..moveTo(tx, y)
            ..lineTo(tx + s / 2, y + (up ? -s * .9 : s * .9))
            ..lineTo(tx + s, y)
            ..close(),
          fill,
        );
      }
    }

    c.drawRect(const Rect.fromLTWH(150, 230, 132, 70), fill);
    teeth(150, 300, false, 3, 44);
    c.drawRect(const Rect.fromLTWH(470, 640, 132, 70), fill);
    teeth(470, 640, true, 3, 44);
    // The dashed flap path.
    final path = Path()
      ..moveTo(110, 560)
      ..cubicTo(200, 420, 260, 420, 330, 470)
      ..cubicTo(390, 515, 430, 520, 470, 470);
    final dash = Paint()
      ..color = pink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 22 + 18) {
        c.drawPath(
          metric.extractPath(at, math.min(at + 22, metric.length)),
          dash,
        );
      }
    }
    c.save();
    c.translate(520, 430);
    c.rotate(-.25);
    c.scale(4.2);
    LookPainter.paint(c, Look(bird: look.bird, gear: look.gear, hat: look.hat), flap: true);
    c.restore();
    _coin(c, img, 214, 420, 56);
    _coin(c, img, 330, 470, 56);
  }

  /// The three small birds of `n4` (§4.5: they stay as designed).
  static const List<(Look, double, double, double)> flockBirds = [
    (Look(bird: 'penguin', hat: 'beanie'), 230, 330, 2.8),
    (Look(bird: 'duck', hat: 'tophat'), 225, 610, 2.8),
    (Look(bird: 'zombie', gear: 'patch'), 640, 610, 2.6),
  ];

  /// `n4` Pick your bird: three fixed birds, the player's look big in the
  /// middle, two sparkle stars.
  static void _flockArt(Canvas c, Look look) {
    void bird(Look l, double x, double y, double s) {
      c.save();
      c.translate(x, y);
      c.scale(s);
      LookPainter.paint(c, Look(bird: l.bird, gear: l.gear, hat: l.hat));
      c.restore();
    }

    for (final (l, x, y, s) in flockBirds) {
      bird(l, x, y, s);
    }
    bird(look, 440, 470, 4.6);
    paintStar(c, 600, 300, 18, gold, rot: .3);
    paintStar(c, 330, 230, 12, pink, rot: .2);
  }

  // --- shared parts (one master each) ---------------------------------------

  /// 16 wedges from the card centre, alternating filled and empty.
  static void _rays(Canvas c, Color color, double alpha) {
    const n = 16;
    final paint = Paint()..color = color.withValues(alpha: alpha);
    final path = Path();
    final rect = Rect.fromCircle(center: centre, radius: 1400);
    for (var i = 0; i < n; i++) {
      path
        ..moveTo(centre.dx, centre.dy)
        ..arcTo(rect, i * 2 * math.pi / n, math.pi / n, false)
        ..close();
    }
    c.drawPath(path, paint);
  }

  /// The tilted round sticker (score or FREE TO PLAY): plum shadow, white
  /// ring, [fill] disc of radius 130; [content] draws in sticker space.
  static void _sticker(
    Canvas c,
    Color fill,
    void Function(double r) content,
  ) {
    const r = 130.0;
    c.save();
    c.translate(820, 360);
    c.rotate(.14);
    c.drawCircle(const Offset(8, 10), r + 12, Paint()..color = plum);
    c.drawCircle(Offset.zero, r + 12, Paint()..color = white);
    c.drawCircle(Offset.zero, r, Paint()..color = fill);
    content(r);
    c.restore();
  }

  /// The tilted pink banner with a hard plum shadow; the text shrinks to
  /// fit 600 - 64.
  static void _banner(Canvas c, String text) {
    const w = 600.0, h = 92.0;
    c.save();
    c.translate(430, 160);
    c.rotate(-.06);
    c.drawRect(
      const Rect.fromLTWH(-w / 2 + 10, -h / 2 + 10, w, h),
      Paint()..color = plum,
    );
    c.drawRect(
      const Rect.fromLTWH(-w / 2, -h / 2, w, h),
      Paint()..color = pink,
    );
    _text(
      c,
      text,
      0,
      3,
      family: _body,
      size: 54,
      color: white,
      spacing: 2,
      maxWidth: w - 64,
    );
    c.restore();
  }

  /// The white name tag; left out when [name] is empty (§4.2 item 6).
  static void _nameTag(Canvas c, String name) {
    if (name.trim().isEmpty) return;
    c.save();
    c.translate(430, 730);
    c.rotate(-.02);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-210, -36, 420, 72),
        const Radius.circular(36),
      ),
      Paint()..color = white,
    );
    // PRD-2.3 §21.2 the one name rule: shrink to 70 %, then "…".
    final f = fitName(
      name,
      380,
      40,
      measureName(fontFamily: _body, fontWeight: FontWeight.w600),
    );
    _text(c, f.text, 0, 2, family: _body, size: f.size, color: plum);
    c.restore();
  }

  /// Both spike strips and the logo bar.
  static void _frame(Canvas c, Color spikeColor, ShareCardAssets img) {
    _spikes(c, true, 0, spikeColor, img.spikes);
    _spikes(c, false, footY, spikeColor, img.spikes);
    _footer(c, img);
  }

  /// `ground_spikes.png` scaled to 74 high, tiled across the width and
  /// tinted (the game's flat-sprite tint). Top: y..y+74, teeth down;
  /// bottom: y-74..y, teeth up.
  static void _spikes(
    Canvas c,
    bool top,
    double y,
    Color color,
    ui.Image sprite,
  ) {
    const h = spikeHeight;
    final w = (sprite.width * h / sprite.height).roundToDouble();
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
    final src = Rect.fromLTWH(
      0,
      0,
      sprite.width.toDouble(),
      sprite.height.toDouble(),
    );
    c.save();
    if (top) {
      c.translate(0, y + h);
      c.scale(1, -1);
    } else {
      c.translate(0, y - h);
    }
    for (var x = 0.0; x < size; x += w) {
      c.drawImageRect(sprite, src, Rect.fromLTWH(x, 0, w, h), paint);
    }
    c.restore();
  }

  /// The white logo bar flush with the bottom edge: app icon, the logo in
  /// the title's place, and both store badges (geometry: [footerLayout]).
  static void _footer(Canvas c, ShareCardAssets img) {
    const y0 = footY, h = footHeight;
    final l = footerLayout(img);
    c.drawRect(const Rect.fromLTWH(0, y0, size, h), Paint()..color = white);
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(l.icon, const Radius.circular(30)));
    _image(c, img.icon, l.icon);
    c.restore();
    _image(c, img.logo, l.logo);
    _image(c, img.googlePlay, l.googlePlay);
    _image(c, img.appStore, l.appStore);
  }

  /// The logo bar's rects in canvas px (shared by the painter and the tests).
  ///
  /// The icon is 128 at x 64, centred vertically. The logo's lettering
  /// ([logoInk]) starts at the old title's x (220) and is centred on the
  /// icon, at its own aspect ratio. The two store badges share one width
  /// ([badgeWidth]) and so one vertical axis; their column's right edge is
  /// 64 from the card edge, [badgeGap] lies between them, and the column is
  /// centred vertically in the bar (equal top and bottom margins). Each
  /// badge's height follows its own artwork, so nothing is stretched.
  static ({Rect icon, Rect logo, Rect googlePlay, Rect appStore}) footerLayout(
    ShareCardAssets img,
  ) {
    const y0 = footY, h = footHeight;
    const iconSize = 128.0, margin = 64.0, titleGap = 28.0;
    final iconRect = Rect.fromLTWH(
      margin,
      y0 + (h - iconSize) / 2,
      iconSize,
      iconSize,
    );
    // The logo: [logoInkHeight] of lettering, scaled from logo.png's pixels.
    final k = logoInkHeight / logoInk.height;
    final logoRect = Rect.fromLTWH(
      margin + iconSize + titleGap - logoInk.left * k,
      y0 + h / 2 - (logoInk.top + logoInk.height / 2) * k,
      logoSource.width * k,
      logoSource.height * k,
    );
    // The badges: one width; each height follows its own artwork.
    final gpHeight = badgeWidth * img.googlePlay.height / img.googlePlay.width;
    final asHeight = badgeWidth * img.appStore.height / img.appStore.width;
    final left = size - margin - badgeWidth;
    final top = y0 + (h - (gpHeight + badgeGap + asHeight)) / 2;
    return (
      icon: iconRect,
      logo: logoRect,
      googlePlay: Rect.fromLTWH(left, top, badgeWidth, gpHeight),
      appStore: Rect.fromLTWH(
        left,
        top + gpHeight + badgeGap,
        badgeWidth,
        asHeight,
      ),
    );
  }

  static void _coin(Canvas c, ShareCardAssets img, double x, double y, double s) =>
      _image(c, img.coin, Rect.fromLTWH(x - s / 2, y - s / 2, s, s));

  static void _image(Canvas c, ui.Image image, Rect dst) => c.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    dst,
    Paint()..filterQuality = FilterQuality.high,
  );

  /// Canvas-style text: [align] at x, the em box centred on [y] (the JS
  /// `textBaseline = 'middle'`). [spacing] is the letter spacing; with
  /// [maxWidth] the size shrinks until the text fits.
  static void _text(
    Canvas c,
    String text,
    double x,
    double y, {
    String family = _display,
    required double size,
    required Color color,
    TextAlign align = TextAlign.center,
    double spacing = 0,
    double? maxWidth,
  }) {
    TextPainter layout(double s) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: family,
          fontSize: s,
          fontWeight: family == _body ? FontWeight.w600 : FontWeight.w400,
          letterSpacing: spacing,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    var tp = layout(size);
    if (maxWidth != null && tp.width > maxWidth) {
      final s = size * maxWidth / tp.width;
      tp.dispose();
      tp = layout(s);
    }
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final descent = tp.height - ascent;
    final fontSize = tp.text!.style!.fontSize!;
    final baseline =
        y + fontSize * (ascent - descent) / (2 * (ascent + descent));
    final left = switch (align) {
      TextAlign.left || TextAlign.start => x,
      TextAlign.right || TextAlign.end => x - tp.width,
      _ => x - tp.width / 2,
    };
    tp.paint(c, Offset(left, baseline - ascent));
    tp.dispose();
  }
}

/// Draws [data] off-screen at 1080 x 1080 and encodes it as PNG (§2.0 step
/// 2). The image is freed as soon as it is encoded (2.2 §33.4).
Future<Uint8List> renderShareCardPng(
  ShareCardData data,
  ShareCardAssets assets,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // region P26-J7
  final emblem = data.kind == ShareCardKind.spotlight && data.usesProgression
      ? await EmblemView.loadImageForLevel(data.level)
      : null;
  ShareCardPainter.paint(canvas, data, assets, emblem: emblem);
  // endregion
  final picture = recorder.endRecording();
  final ui.Image image;
  try {
    image = await picture.toImage(
      ShareCardPainter.size.toInt(),
      ShareCardPainter.size.toInt(),
    );
  } finally {
    picture.dispose();
  }
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('PNG encoding failed');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
  }
}
