import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../skins/art/look_painter.dart';
import '../skins/art/skill_art_v26_part2.dart';
import '../skins/catalog.dart';
import '../skins/look.dart';

/// PRD 2.4 WP-AV (design C "Sticker", `avatar_design/src.html`): the ONE
/// master painter of every player picture (VS intro plates, the versus HUD
/// bar, the results card; your own and the opponent's). No photo is ever
/// read or shown: the avatar is the player's own bird with its gear and
/// hat ([LookPainter], the game's skin art), tilted 16° nose-up, cut out
/// like a sticker with a thick white edge (~4.5 % of the size) and a soft
/// shadow, on a 9-point star blob (rotated 10°) in a light tint of the
/// bird's colour. Animated items are frozen at [frozenT].
///
/// Static: each (bird, gear, hat, pixel size) is rendered ONCE into an
/// image ([image]) and kept in a small LRU cache; frames only blit it.
class StickerAvatars {
  StickerAvatars({double Function()? pixelsPerPoint, this.maxCached = 16})
    : _pixelsPerPoint = pixelsPerPoint ?? (() => 3);

  final double Function() _pixelsPerPoint;

  /// Cached images at most (the own avatar at 3–4 sizes plus a few
  /// opponents); the least recently drawn one is disposed first.
  final int maxCached;

  final Map<String, ui.Image> _cache = {};

  /// How many images were rendered (tests: "rendered once").
  @visibleForTesting
  int renders = 0;

  /// Cache keys, least recently used first (tests).
  @visibleForTesting
  List<String> get cachedKeys => List.unmodifiable(_cache.keys);

  /// The moment animated items are frozen at (the design's `t = .6`).
  static const double frozenT = .6;

  /// The star blob: 9 points, outer / inner radius as a share of the size,
  /// turned 10°.
  static const int starPoints = 9;
  static const double starOuter = .41, starInner = .33;
  static const double starTurnDeg = 10;

  /// The bird's tilt, nose up.
  static const double tiltDeg = 16;

  /// The white sticker edge, share of the size (at least 2 device px).
  static const double edge = .045;

  /// The look box: 1.12 × the size over 84 art units, the bird's centre
  /// at (42, 47) of it (the design's `lookCanvas`).
  static const double lookBox = 1.12;

  /// Shadow: 28 % black, blur .05 × the size (canvas `shadowBlur` = 2σ),
  /// .035 × the size down (screen space).
  static const double shadowAlpha = .28;
  static const double shadowBlur = .05, shadowDrop = .035;

  /// Pixels per world point now (≥ 1, finite).
  double get pixelRatio {
    var r = 0.0;
    try {
      r = _pixelsPerPoint();
    } catch (_) {}
    if (!r.isFinite || r <= 0) r = 3;
    return r.clamp(1, 8).toDouble();
  }

  /// The per-layer catalogue fallback (an unknown id, e.g. a newer item on
  /// an older phone, becomes the layer's default: Classic bird, no gear,
  /// no hat). Hoop and trail are not part of the avatar.
  static Look normalise(Look look) {
    String pick(SkinLayer layer) {
      final id = look.idFor(layer);
      return itemById(layer, id) == null ? defaultItemId(layer) : id;
    }

    return Look(
      bird: pick(SkinLayer.bird),
      gear: pick(SkinLayer.gear),
      hat: pick(SkinLayer.hat),
    );
  }

  /// The light tint of the star blob: the bird's colour mixed 72 % to
  /// white (rainbow: #FF5252; snow / ghost: #90A4AE), as `palette()`.
  static ui.Color tintOf(String bird) {
    final c = switch (bird) {
      'rainbow' => const ui.Color(0xFFFF5252),
      'snow' || 'ghost' => const ui.Color(0xFF90A4AE),
      'magpie' || 'prism' || 'daynight' => f10c2BirdFace(bird, BirdArt.byId('classic').shape, frozenT).c,
      _ => BirdArt.byId(bird).c,
    };
    return ui.Color.lerp(
      c.withValues(alpha: 1),
      const ui.Color(0xFFFFFFFF),
      .72,
    )!;
  }

  static String _key(Look l, int px) => '${l.bird}|${l.gear}|${l.hat}|$px';

  /// The sticker of [look] for a [side]-point square, rendered once at
  /// [pixelRatio] and cached.
  ui.Image image(Look look, double side) {
    final l = normalise(look);
    final px = (side * pixelRatio).round().clamp(8, 1024);
    final key = _key(l, px);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // most recent last
      return hit;
    }
    final im = render(l, px);
    renders++;
    _cache[key] = im;
    while (_cache.length > maxCached) {
      final old = _cache.keys.first;
      _cache.remove(old)?.dispose();
    }
    return im;
  }

  /// Paints [look]'s sticker into [r] (a square), facing left when
  /// [mirror] (the opponent's side), at [opacity].
  void paint(
    ui.Canvas canvas,
    ui.Rect r,
    Look look, {
    bool mirror = false,
    double opacity = 1,
  }) {
    if (opacity <= 0 || r.isEmpty) return;
    final side = math.min(r.width, r.height);
    final im = image(look, side);
    final src = ui.Rect.fromLTWH(
      0,
      0,
      im.width.toDouble(),
      im.height.toDouble(),
    );
    final dst = ui.Rect.fromCenter(center: r.center, width: side, height: side);
    final p = ui.Paint()
      ..filterQuality = ui.FilterQuality.medium
      ..color = ui.Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));
    if (!mirror) {
      canvas.drawImageRect(im, src, dst, p);
      return;
    }
    canvas.save();
    canvas.translate(dst.center.dx, 0);
    canvas.scale(-1, 1);
    canvas.translate(-dst.center.dx, 0);
    canvas.drawImageRect(im, src, dst, p);
    canvas.restore();
  }

  /// Renders the sticker of [look] (already [normalise]d) as a [px] × [px]
  /// image. Pure painting (the design's `DESIGNS[2].draw`).
  static ui.Image render(Look look, int px) {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    paintSticker(canvas, look, px.toDouble());
    final picture = rec.endRecording();
    try {
      return picture.toImageSync(px, px);
    } finally {
      picture.dispose();
    }
  }

  /// Paints the sticker into the square (0, 0, [s], [s]).
  static void paintSticker(ui.Canvas canvas, Look look, double s) {
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTWH(0, 0, s, s));
    canvas.translate(s / 2, s / 2);
    // The star blob in the bird's light tint.
    canvas.save();
    canvas.rotate(starTurnDeg * math.pi / 180);
    final star = ui.Path();
    for (var i = 0; i < starPoints * 2; i++) {
      final a = i / (starPoints * 2) * 2 * math.pi;
      final rr = s * (i.isOdd ? starInner : starOuter);
      final p = ui.Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawPath(star, ui.Paint()..color = tintOf(look.bird));
    canvas.restore();

    // The bird: art units k = 1.12 s / 84; its centre (42, 47) of the box
    // drawn at (−.56 s, −.6 s).
    final k = s * lookBox / 84;
    final centre = ui.Offset(-s * .56 + 42 * k, -s * .6 + 47 * k);
    final r = math.max(s * edge, 2.0);
    final tilt = -tiltDeg * math.pi / 180;
    final bounds = ui.Rect.fromCircle(center: ui.Offset.zero, radius: s);

    void look0() {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.scale(k);
      LookPainter.paint(canvas, look, t: frozenT);
      canvas.restore();
    }

    // The look stamped around itself (the outline's silhouette).
    void stamps() {
      for (var i = 0; i < 20; i++) {
        final a = i / 20 * 2 * math.pi;
        canvas.save();
        canvas.translate(math.cos(a) * r, math.sin(a) * r);
        look0();
        canvas.restore();
      }
    }

    // Soft shadow (straight down in screen space, like a canvas shadow).
    canvas.save();
    canvas.translate(0, s * shadowDrop);
    canvas.rotate(tilt);
    canvas.saveLayer(
      bounds,
      ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: s * shadowBlur / 2,
          sigmaY: s * shadowBlur / 2,
        )
        ..colorFilter = ui.ColorFilter.mode(
          ui.Color.fromRGBO(0, 0, 0, shadowAlpha),
          ui.BlendMode.srcIn,
        ),
    );
    stamps();
    look0();
    canvas.restore();
    canvas.restore();

    // The white sticker edge, then the look on top.
    canvas.save();
    canvas.rotate(tilt);
    canvas.saveLayer(
      bounds,
      ui.Paint()
        ..colorFilter = const ui.ColorFilter.mode(
          ui.Color(0xFFFFFFFF),
          ui.BlendMode.srcIn,
        ),
    );
    stamps();
    canvas.restore();
    look0();
    canvas.restore();
    canvas.restore();
  }

  /// Drops every cached image.
  void clear() {
    for (final im in _cache.values) {
      im.dispose();
    }
    _cache.clear();
  }
}
