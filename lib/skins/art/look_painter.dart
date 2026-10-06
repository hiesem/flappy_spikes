import 'dart:ui';

import '../look.dart';
import 'bird_art.dart';
import 'gear_art.dart';
import 'hat_art.dart';

export 'bird_art.dart' show BirdArt, BirdShape, BirdSpec;
export 'gear_art.dart' show GearArt;
export 'hat_art.dart' show HatArt;
export 'shapes.dart' show artHash, octPath, paintHeart, paintStar, polyPath;

/// Paints a whole bird look (bird + gear + hat) with `dart:ui` Canvas — a 1:1
/// port of `drawLook` / `drawOnMannequin` / `drawNone` in
/// `design/menu_v2/skin_art.js`. Pure painting: no Flame, no game state, no
/// assets. Units are art units (the original 44 x 36 bird box); callers scale.
abstract final class LookPainter {
  /// Art box of one bird in art units (JS 44 x 36). The body square is 30x30
  /// at (6,3); body centre (21,18).
  static const double boxWidth = 44, boxHeight = 36;
  static const Offset bodyCentre = Offset(21, 18);

  static final Paint _layerPaint = Paint();

  /// Draws the whole look (gear back → bird body/face → gear front → hat)
  /// with the art-box CENTRE (22,18) at the canvas origin, in art units
  /// (caller scales/translates). [dim] = per-layer try-on opacity (0..1):
  /// that layer is rendered as ONE flat layer (saveLayer) at that alpha, no
  /// see-through overlaps inside it (JS `layer()`). A missing key or a value
  /// ≥ 1 draws the layer normally; ≤ 0 skips it.
  /// [dead]: dead pose — eye drawn as an X (like the zombie eye, white for
  /// dark birds), wing up, all idle animations frozen at t (caller passes a
  /// fixed t). Hoop and trail ids in [look] are ignored here.
  static void paint(
    Canvas canvas,
    Look look, {
    double t = 0,
    bool flap = false,
    Map<SkinLayer, double> dim = const {},
    bool dead = false,
  }) {
    final b = BirdArt.byId(look.bird);
    final s = b.shape;
    final gear = look.gear, hat = look.hat;
    final wing = flap && !dead;
    canvas.save();
    canvas.translate(-22, -18);
    final gearDim = dim[SkinLayer.gear];
    _layer(canvas, gearDim, () => paintGearBack(canvas, gear, s, t, wing));
    _layer(canvas, dim[SkinLayer.bird], () {
      paintBirdBody(canvas, b, t);
      paintBirdFace(canvas, b, t, wing, dead: dead);
    });
    _layer(
      canvas,
      gearDim,
      () => paintGearFront(canvas, gear, s, t, wing, dead: dead),
    );
    _layer(canvas, dim[SkinLayer.hat], () => paintHat(canvas, hat, s, t));
    canvas.restore();
  }

  /// Gear or hat item on the light-grey mannequin bird (shop tiles), centred
  /// like [paint]. Other layers (and `none`) draw just the mannequin.
  static void paintOnMannequin(
    Canvas canvas,
    SkinLayer layer,
    String id, {
    double t = 0,
    bool flap = false,
  }) {
    final m = BirdArt.mannequin;
    final s = m.shape;
    canvas.save();
    canvas.translate(-22, -18);
    if (layer == SkinLayer.gear) paintGearBack(canvas, id, s, t, flap);
    paintBirdBody(canvas, m, t);
    paintBirdFace(canvas, m, t, flap);
    if (layer == SkinLayer.gear) {
      paintGearFront(canvas, id, s, t, flap);
    } else if (layer == SkinLayer.hat) {
      paintHat(canvas, id, s, t);
    }
    canvas.restore();
  }

  static final Paint _none = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0xFFC8C8C8);

  /// Grey circle-slash "none" icon of radius r centred at the origin.
  static void paintNone(Canvas canvas, double r) {
    final p = _none..strokeWidth = r * .16;
    canvas.drawCircle(Offset.zero, r, p);
    canvas.drawLine(Offset(-r * .7, r * .7), Offset(r * .7, -r * .7), p);
  }

  static void _layer(Canvas canvas, double? dim, void Function() draw) {
    if (dim == null || dim >= 1) {
      draw();
      return;
    }
    if (dim <= 0) return;
    canvas.saveLayer(null, _layerPaint..color = Color.fromRGBO(0, 0, 0, dim));
    draw();
    canvas.restore();
  }
}
