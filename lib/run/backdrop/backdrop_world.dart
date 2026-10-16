import 'dart:ui';

import 'backdrop_ctx.dart';
import 'backdrop_math.dart';
import 'backdrop_palette.dart';
import 'backdrop_scene.dart';
import 'backdrop_tables.dart';
import 'ride_hook.dart';
import 'seams/seam.dart';

/// PRD-2.4 §3.3 the endless world (`world()`, `drawGroup()`, `vmove()` of
/// `docs/p24/endless_vertical.html`): which scene or seam is on screen at
/// world distance `cam`, drawn band by band.
class BackdropWorld implements SceneDrawer {
  BackdropWorld({List<BackdropScene>? scenes, List<Seam>? seams})
    : scenes = scenes ?? kScenes,
      seams = seams ?? kSeams;

  final List<BackdropScene> scenes;
  final List<Seam> seams;

  /// PRD-2.4 §3.5 (WP-R): per-band offsets while a ride hands over.
  BackdropRideHook? hook;

  final SeamFrame _s = SeamFrame();

  static const List<List<Band>> _single = [
    [Band.sky],
    [Band.far],
    [Band.mid],
    [Band.near],
  ];

  /// What is drawn at world distance `c.cam` (tests, debug).
  static ({int j, double d}) seamAt(double cam) {
    final j = jsRound(cam / kE);
    return (j: j, d: cam - j * kE);
  }

  /// The scene index (0–9) the world shows at [cam] outside a seam window,
  /// or the scene the camera is in during one (`d < 0` → the leaving one).
  static int sceneAt(double cam) {
    final (:j, :d) = seamAt(cam);
    if (j == 0) return 0; // the first loop has no Homecoming (see [paint])
    return modI(d < 0 ? j - 1 : j, kNST);
  }

  /// `world(V, cam, t, par)`: paints the world (no base fill, no colour
  /// filter; see `BackdropPainter`).
  void paint(Ctx c) {
    final (:j, :d) = seamAt(c.cam);
    // PRD-2.4 §3.3 / WP-W1 brief 5: in a run's first loop there is no
    // Homecoming: hoops 0–39 are pure Nest Canopy (the move treated as
    // finished, no leftovers from Space). From hoop 400 on it plays.
    if (j == 0) return group(c, 0, Band.layers);
    final seam = seams[modI(j - 1, kNST)];
    switch (seam) {
      case FloorSeam():
        if (d.abs() < kVWIN / 2 + kLinger) {
          return _vmove(c, j - 1, j, d, seam, j * kE);
        }
        return group(c, d < 0 ? j - 1 : j, Band.layers);
      case OlderSeam():
        if (d.abs() >= kVWIN / 2) {
          return group(c, d < 0 ? j - 1 : j, Band.layers);
        }
        seam.move(c, this, j - 1, j, smooth((d + kVWIN / 2) / kVWIN));
    }
  }

  /// `drawGroup(c, [env], …, bands, dy)`.
  @override
  void group(Ctx c, int env, List<Band> bands, [BandOffset? dy]) {
    final scene = scenes[modI(env, kNST)];
    for (final b in bands) {
      final y = dy == null ? 0.0 : dy(b);
      final o = hook?.bandOffset(b) ?? Offset.zero;
      c.save();
      if (y != 0 || o != Offset.zero) c.translate(o.dx, y + o.dy);
      c.env = env;
      c.save();
      scene.draw(c, b);
      c.restore();
      c.restore();
    }
  }

  /// `vmove(…)`: a floor move.
  void _vmove(Ctx c, int ga, int gb, double d, FloorSeam l, double sc) {
    final s = _s;
    final travel = l.travel + c.ext;
    final u = (d + kVWIN / 2) / kVWIN, q = smooth(u), dir = l.dir;
    s
      ..u = u
      ..q = q
      ..travel = travel
      ..dir = dir
      ..y = travel * q
      ..sc = sc
      ..cam = c.cam
      ..t = c.t
      ..a = ga
      ..b = gb;
    s.sT = l.yF + (dir > 0 ? s.oA(Band.near) : s.oB(Band.near));
    s.sB = s.sT + l.thickness;
    final fold = l.fold(s);
    // going down the leaving scene is above the floor, going up below it
    final upper = dir > 0 ? ga : gb, lower = dir > 0 ? gb : ga;
    final top = c.yTop;
    for (final b in Band.layers) {
      if (s.sB - 30 < kVH) {
        c.save();
        c.clipRect(c.xl, s.sB - 30, c.xr - c.xl, kVH + 400 + (s.sB < 0 ? -s.sB : 0));
        _scene(c, lower, gb, b, fold);
        c.restore();
      }
      if (s.sT + 30 > top) {
        c.save();
        c.clipRect(c.xl, top - 400, c.xr - c.xl, s.sT + 430 - top);
        _scene(c, upper, gb, b, fold);
        c.restore();
      }
      _piece(c, l, b);
    }
    if (s.sT < kVH + 10 && s.sB + l.hang > top - 10) {
      _withOffset(c, Band.near, () => l.slab(c, s));
    }
    _piece(c, l, Band.front);
  }

  void _scene(Ctx c, int env, int gb, Band b, double? fold) {
    final s = _s;
    final off = env == s.a ? s.oA(b) : s.oB(b);
    if (fold != null && env == gb) c.fold = fold;
    group(c, env, _single[b.index], (_) => off);
    c.fold = 1;
  }

  void _piece(Ctx c, FloorSeam l, Band b) =>
      _withOffset(c, b == Band.front ? Band.near : b, () => l.piece(c, _s, b));

  void _withOffset(Ctx c, Band b, void Function() fn) {
    final o = hook?.bandOffset(b) ?? Offset.zero;
    if (o == Offset.zero) return fn();
    c.save();
    c.translate(o.dx, o.dy);
    fn();
    c.restore();
  }
}

/// PRD-2.4 §3.3 / §3.4 paints one frame of the run background: the base
/// fill, the world at its distance, tall-screen anchoring (the 568 design
/// sits on the screen bottom) and the colour stage — one colour-filter
/// layer for the whole background, never per shape.
class BackdropPainter {
  BackdropPainter({BackdropWorld? world}) : world = world ?? BackdropWorld();

  final BackdropWorld world;
  final Ctx ctx = Ctx();
  final Paint _layer = Paint();
  final Paint _base = Paint()..color = const Color(0xFFF1F1F1);
  final Path _cover = Path();
  Color? _bg, _fg;
  ColorFilter? _filter;

  /// Paints the background into the rectangle 0, 0, 320, [viewHeight]:
  /// world distance [cam] (pt), run clock [t] (s), colour stage [bg] / [fg]
  /// (the game's current, crossfaded stage colours), faded to [opacity].
  void paint(
    Canvas canvas, {
    required double cam,
    required double t,
    required double viewHeight,
    required Color bg,
    required Color fg,
    double opacity = 1,
  }) {
    if (opacity <= 0) return;
    final screen = Rect.fromLTWH(0, 0, kVW, viewHeight);
    final identity = isIdentityPalette(bg, fg);
    if (!identity && (bg != _bg || fg != _fg)) {
      _bg = bg;
      _fg = fg;
      _filter = ColorFilter.matrix(palMatrix(bg, fg));
    }
    if (identity && opacity >= 1) {
      canvas.save();
    } else {
      _layer
        ..colorFilter = identity ? null : _filter
        ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0, 1));
      canvas.saveLayer(screen, _layer);
    }
    canvas.clipRect(screen);
    final hook = world.hook;
    if (hook != null) {
      _cover.reset();
      if (hook.cover(_cover, viewHeight)) {
        _cover
          ..addRect(screen)
          ..fillType = PathFillType.evenOdd;
        canvas.clipPath(_cover);
      }
    }
    canvas.drawRect(screen, _base);
    canvas.translate(0, viewHeight - kVH);
    final c = ctx
      ..canvas = canvas
      ..resetStyle()
      ..cam = cam
      ..t = t
      ..viewHeight = viewHeight
      ..yTop = kVH - viewHeight
      ..xl = 0
      ..xr = kVW;
    world.paint(c);
    canvas.restore();
  }
}
