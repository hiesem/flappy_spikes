import 'dart:math' as math;
import 'dart:ui';

import '../skins/art/shapes.dart';
import 'levels.dart';

/// A cached static path with the single colour it is filled in.
class _Shape {
  const _Shape(this.path, this.color, {this.strokeWidth = 0});

  final Path path;
  final Color color;

  /// 0 = fill, > 0 = stroke of that width.
  final double strokeWidth;
}

/// The static plate outlines of a level: the rim (k = 1), the plate itself
/// (k = .84) and, for the shields 4-7, the inner hairline (k = .74).
class _Plate {
  const _Plate(this.outer, this.inner, this.outline);

  final Path outer;
  final Path inner;
  final Path? outline;
}

/// The 10 level emblems plus the unranked frame, drawn with `dart:ui` — a 1:1
/// port of `design/menu_v2/emblem_art.js` (which reuses the `skin_art.js`
/// helpers `oct` / `poly` / `circ` / `star` / `hash` / `TAU`, reimplemented in
/// `skins/art/shapes.dart`).
///
/// Units are the JS art units with the plate centre at the canvas origin: the
/// plate is ≈ 96 wide, wings reach ±113, the crown up to ≈ −100 and the ribbon
/// down to ≈ +72. The caller scales (home uses 0.936). Pure painting — no
/// Flame, no game state, no assets; the ribbon number uses the bundled
/// Opificio font.
///
/// Static geometry (plate outlines, ray wedges, spike rings, wings, laurel,
/// crown, ribbon) is cached per level; only the animated parts (pennants,
/// flames, stars, sweeps) are rebuilt per frame. The JS never calls
/// `Math.random()` — the galaxy twinkles come from `hash` and `t` — so
/// painting is deterministic.
abstract final class EmblemPainter {
  /// Number of ranked levels (1..10); 0 is the unranked frame.
  static const int maxLevel = 10;

  static const Color _steel = Color(0xFF6E7B83);
  static const Color _steelDark = Color(0xFF4D575D);
  static const Color _gold = Color(0xFFFFB529);
  static const Color _goldDark = Color(0xFFC98A00);
  static const Color _goldLight = Color(0xFFFFE082);
  static const Color _white = Color(0xFFFFFFFF);

  /// Level colours come from the shared [kLevels] table (PRD-home-v3 §4.2).
  static const List<LevelDef> _styles = kLevels;

  /// Feather count per level (`N` in `wings()`); levels 1-2 have none.
  static const Map<int, int> _wingCount = {
    3: 2,
    4: 3,
    5: 4,
    6: 4,
    7: 5,
    8: 5,
    9: 5,
    10: 6,
  };
  static const Map<int, double> _wingScale = {
    3: .72,
    4: .86,
    5: 1,
    6: 1.04,
    7: 1.1,
    8: 1.12,
    9: 1.18,
    10: 1.26,
  };
  static const List<Color> _rainbow = [
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF00A2FF),
    Color(0xFFAF52DE),
  ];

  /// Grayscale + 38 % alpha — the JS `ctx.filter='grayscale(1) opacity(.38)'`
  /// of the locked list rows, applied to the whole emblem in one layer.
  static final Paint _greyPaint = Paint()
    ..colorFilter = const ColorFilter.matrix(<double>[
      .2126, .7152, .0722, 0, 0,
      .2126, .7152, .0722, 0, 0,
      .2126, .7152, .0722, 0, 0,
      0, 0, 0, .38, 0,
    ]);

  static int _clamp(int level) =>
      level < 0 ? 0 : (level > maxLevel ? maxLevel : level);

  /// Draws the emblem of [level] (0 = unranked dashed frame, 1..10) with the
  /// plate centre at the canvas origin, in emblem art units (the JS units; the
  /// caller scales). [t] seconds drives every animation (pennants, phoenix
  /// flames, legend stars / rainbow ring / spike spin / gem sparkle, rays for
  /// 9-10, plate light sweep every 6.4 s). [shine]: false disables the sweep.
  /// [grey]: draw desaturated at 38 % opacity (locked list rows).
  static void paint(
    Canvas canvas,
    int level, {
    double t = 0,
    bool shine = true,
    bool grey = false,
  }) {
    final l = _clamp(level);
    if (!grey) {
      _draw(canvas, l, t, shine);
      return;
    }
    canvas.saveLayer(null, _greyPaint);
    _draw(canvas, l, t, shine);
    canvas.restore();
  }

  /// True when the emblem of [level] has idle animation besides the sweep
  /// (7..10: pennants, spike rings, flames, stars and rays).
  static bool animates(int level) => _clamp(level) >= 7;

  // --- the draw itself ------------------------------------------------------

  static void _draw(Canvas canvas, int level, double t, bool shine) {
    if (level == 0) {
      canvas.drawPath(_unrankedDash, strokePaint(const Color(0xFFCFCFCF), 4));
      canvas.drawPath(
        octPath(-48, -48, 96, 96, 26),
        fillPaint(const Color.fromRGBO(130, 130, 130, .07)),
      );
      // The unranked ribbon borrows the EGG colours (JS clamps
      // `LEVELS[max(0, L-1)]`).
      _ribbon(canvas, 0);
      return;
    }
    final lv = _styles[level - 1];

    // Back layer: rays (9-10), rainbow ring (10), pennants (7+), wings.
    if (level >= 9) {
      final alpha = level == 10 ? .32 : .24;
      canvas.save();
      canvas.rotate(t * .35);
      canvas.drawPath(_raysEven, fillPaint(Color.fromRGBO(255, 181, 41, alpha)));
      canvas.drawPath(_raysOdd, fillPaint(Color.fromRGBO(255, 224, 130, alpha)));
      canvas.restore();
    }
    if (level == 10) {
      final shift = (t * 3).floor();
      for (var i = 0; i < 6; i++) {
        canvas.drawCircle(
          Offset.zero,
          68 - i * 3,
          strokePaint(_rainbow[(i + shift) % 6], 3),
        );
      }
    }
    if (level >= 7) _flags(canvas, t, lv, level);
    if (level == 9) {
      _flameWings(canvas, t);
    } else if (level >= 3) {
      _paintShapes(canvas, _wingShapes(level));
    }
    if (level >= 8) {
      if (level == 10) {
        canvas.save();
        canvas.rotate(t * .15);
      }
      _paintShapes(canvas, _ringShapes(level));
      if (level == 10) canvas.restore();
    }
    if (level == 6 || level == 7) _paintShapes(canvas, _topSpikes(level));

    // Plate.
    final plate = _plateFor(level);
    canvas.drawPath(plate.outer, fillPaint(lv.rim));
    final shader = switch (level) { 9 => _phoenixPlate, 10 => _legendPlate, _ => null };
    canvas.drawPath(
      plate.inner,
      shader == null ? fillPaint(lv.plate) : shaderPaint(shader),
    );
    canvas.save();
    canvas.clipPath(plate.inner);
    if (level == 1) _paintShapes(canvas, _eggInner);
    if (level == 10) {
      // Galaxy twinkles.
      for (var i = 0; i < 16; i++) {
        final tw = .35 + .65 * math.sin(t * 2 + i * 1.7).abs();
        circ(
          canvas,
          -40 + artHash(i) * 80,
          -40 + artHash(i + 40) * 80,
          .6 + artHash(i + 9) * 1.5 * tw,
          Color.fromRGBO(255, 255, 255, tw),
        );
      }
    }
    if (shine) {
      final u = ((t % 6.4) / 6.4) / .28;
      if (u < 1) {
        final x = -110 + u * 220;
        canvas.drawPath(
          polyPath([x, -60, x + 22, -60, x - 8, 60, x - 30, 60]),
          fillPaint(const Color.fromRGBO(255, 255, 255, .38)),
        );
      }
    }
    canvas.restore();
    final outline = plate.outline;
    if (outline != null) {
      canvas.drawPath(
        outline,
        strokePaint(const Color.fromRGBO(255, 255, 255, .35), 1.4),
      );
    }

    // Front layer: chick tuft, laurel (5+), crown (8+), ribbon.
    if (level == 2) _paintShapes(canvas, _tuft);
    if (level >= 5) _paintShapes(canvas, _laurel(level));
    if (level == 9) {
      _flameCrown(canvas, t);
    } else if (level >= 8) {
      _paintShapes(canvas, _crown(level));
      if (level == 10) _crownSparkle(canvas, t);
    }
    _ribbon(canvas, level);
  }

  /// Draws a cached shape list with the shared (reused) paints.
  static void _paintShapes(Canvas canvas, List<_Shape> shapes) {
    for (final shape in shapes) {
      canvas.drawPath(
        shape.path,
        shape.strokeWidth > 0
            ? strokePaint(shape.color, shape.strokeWidth)
            : fillPaint(shape.color),
      );
    }
  }

  /// The two plate gradients of levels 9 and 10 (built once).
  static final Shader _phoenixPlate = Gradient.linear(
    const Offset(0, 46),
    const Offset(0, -46),
    const [Color(0xFFFFAB76), Color(0xFFFFE3B8)],
  );
  static final Shader _legendPlate = Gradient.radial(
    Offset.zero,
    52,
    const [Color(0xFF5B2DC8), Color(0xFF2A1260), Color(0xFF120634)],
    const <double>[0, .6, 1],
    TileMode.clamp,
    null,
    const Offset(-8, -10),
    4,
  );

  // --- geometry helpers -----------------------------------------------------

  /// `platePath(L, k)`: egg (1), shield (4-7) or octagon (everything else).
  static Path _platePath(int level, double k) {
    if (level == 1) return octPath(-38 * k, -50 * k, 76 * k, 98 * k, 24 * k);
    if (level >= 4 && level <= 7) {
      return polyPath([
        -46 * k, -38 * k,
        -38 * k, -46 * k,
        38 * k, -46 * k,
        46 * k, -38 * k,
        46 * k, 12 * k,
        0, 54 * k,
        -46 * k, 12 * k,
      ]);
    }
    return octPath(-48 * k, -48 * k, 96 * k, 96 * k, 26 * k);
  }

  static final Map<int, _Plate> _plates = {};

  static _Plate _plateFor(int level) => _plates.putIfAbsent(level, () {
    final shield = level >= 4 && level <= 7;
    return _Plate(
      _platePath(level, 1),
      _platePath(level, .84),
      shield ? _platePath(level, .74) : null,
    );
  });

  static final Path _unrankedDash = dashPath(
    octPath(-48, -48, 96, 96, 26),
    const [7.0, 5.0],
  );

  /// The 14 alpha wedges behind levels 9-10, split by fill colour parity
  /// (even indices gold, odd light gold), drawn under rotation.
  static final Path _raysEven = _buildRays(0);
  static final Path _raysOdd = _buildRays(1);

  static Path _buildRays(int parity) {
    final path = Path();
    final circle = Rect.fromCircle(center: Offset.zero, radius: 98);
    for (var i = parity; i < 14; i += 2) {
      path.moveTo(0, 0);
      path.arcTo(circle, i * tau / 14, .5 * tau / 14, false);
      path.close();
    }
    return path;
  }

  /// `bladePts(len, w, tipWob)`: one straight-edged feather pointing +x.
  static List<double> _bladePts(double len, double w, [double tipWob = 0]) => [
    0, -w / 2,
    len * .72, -w / 2,
    len + tipWob, 0,
    len * .72, w / 2,
    0, w / 2,
  ];

  /// `rot(pts, a, s, ox, oy)`: rotate by [a], then translate by (ox, oy).
  /// [s] scales the rotated x only — the JS flips x for the left wing but
  /// leaves the rotated y alone, so this is NOT a plain mirror; copy it
  /// exactly.
  static List<double> _rot(
    List<double> pts,
    double a,
    double s,
    double ox,
    double oy,
  ) {
    final c = math.cos(a), sn = math.sin(a);
    final out = List<double>.filled(pts.length, 0);
    for (var i = 0; i < pts.length; i += 2) {
      final x = pts[i], y = pts[i + 1];
      out[i] = ox + s * (x * c - y * sn);
      out[i + 1] = oy + (x * sn + y * c);
    }
    return out;
  }

  // --- levels 3-8 / 10 wings ------------------------------------------------

  static final Map<int, List<_Shape>> _wingCache = {};

  static List<_Shape> _wingShapes(int level) =>
      _wingCache.putIfAbsent(level, () {
        final lv = _styles[level - 1];
        final count = _wingCount[level]!;
        final scale = _wingScale[level]!;
        final denom = count - 1 == 0 ? 1 : count - 1;
        final shapes = <_Shape>[];
        for (final side in const <double>[-1, 1]) {
          for (var i = count - 1; i >= 0; i--) {
            final a = -.95 + i * (1.05 / denom);
            final len = (64 - i * 7) * scale;
            final w = (14 - i * .8) * scale;
            final ox = side * 32, oy = -14 + i * 9 * scale;
            final color = level == 10
                ? (i.isOdd ? _goldLight : _white)
                : (i.isOdd ? lv.accent : lv.rim);
            shapes.add(
              _Shape(
                polyPath(_rot(_bladePts(len, w), a, side, ox, oy)),
                color,
              ),
            );
            if (level >= 7) {
              shapes.add(
                _Shape(
                  polyPath(
                    _rot([
                      len * .18, -w / 2,
                      len * .72, -w / 2,
                      len * .86, -w * .18,
                      len * .18, -w * .18,
                    ], a, side, ox, oy),
                  ),
                  const Color.fromRGBO(255, 255, 255, .28),
                ),
              );
            }
          }
        }
        return shapes;
      });

  /// Level 9's flickering flame wings (rebuilt per frame).
  static void _flameWings(Canvas canvas, double t) {
    const count = 5;
    const scale = 1.18;
    for (final side in const <double>[-1, 1]) {
      for (var i = count - 1; i >= 0; i--) {
        final a = -.95 + i * (1.05 / (count - 1));
        final len = (64 - i * 7) * scale;
        final w = (14 - i * .8) * scale;
        final ox = side * 32, oy = -14 + i * 9 * scale;
        final f = math.sin(t * 9 + i * 1.7 + (side > 0 ? 1 : 0)) * 3.2;
        canvas.drawPath(
          polyPath(_rot(_bladePts(len + 4, w + 2, f), a, side, ox, oy)),
          fillPaint(i.isOdd ? const Color(0xFFFF7A1A) : _gold),
        );
        canvas.drawPath(
          polyPath(
            _rot(_bladePts(len * .62, w * .45, f * .5), a, side, ox + side * 6, oy),
          ),
          fillPaint(_goldLight),
        );
      }
    }
  }

  // --- spike ring (8-10) / top spikes (6-7) ---------------------------------

  static final Map<int, List<_Shape>> _ringCache = {};

  /// `spikeRing(n, 50, 15, ...)` cached as one path per colour; level 10's
  /// `spin` is applied by rotating the canvas around the ring.
  static List<_Shape> _ringShapes(int level) =>
      _ringCache.putIfAbsent(level, () {
        final n = level == 10 ? 16 : 12;
        final color = level == 8 ? _steel : _gold;
        final shade = level == 8 ? _steelDark : _goldDark;
        final main = Path(), darker = Path();
        for (var i = 0; i < n; i++) {
          final a = i / n * tau - math.pi / 2;
          final w = tau / n * .32;
          final c = math.cos(a), s = math.sin(a);
          final lx = math.cos(a - w) * 50, ly = math.sin(a - w) * 50;
          final rx = math.cos(a + w) * 50, ry = math.sin(a + w) * 50;
          addPoly(main, [lx, ly, c * 65, s * 65, rx, ry]);
          addPoly(darker, [lx, ly, c * 65, s * 65, c * 50, s * 50]);
        }
        return [_Shape(main, color), _Shape(darker, shade)];
      });

  /// Grey strip spikes standing on the plate top (levels 6-7).
  static final Map<int, List<_Shape>> _topSpikeCache = {};

  static List<_Shape> _topSpikes(int level) =>
      _topSpikeCache.putIfAbsent(level, () {
        final n = level == 6 ? 3 : 5;
        const len = 15.0;
        final span = n * 14.0;
        final shapes = <_Shape>[];
        for (var i = 0; i < n; i++) {
          final x = -span / 2 + 7 + i * 14;
          final h = len * (i == (n - 1) / 2 ? 1.25 : 1);
          shapes.add(
            _Shape(polyPath([x - 7, -40, x, -40 - h, x + 7, -40]), _steel),
          );
          shapes.add(
            _Shape(polyPath([x, -40 - h, x + 7, -40, x, -40]), _steelDark),
          );
        }
        return shapes;
      });

  // --- pennants (7+) --------------------------------------------------------

  static void _flags(Canvas canvas, double t, LevelDef lv, int level) {
    for (final side in const <double>[-1, 1]) {
      canvas.save();
      canvas.translate(side * 52, -50);
      canvas.rotate(side * .42);
      fillRect(canvas, -1.5, -34, 3, 40, _steelDark);
      circ(canvas, 0, -35, 2.6, _gold);
      double wv(int i) =>
          math.sin(t * 5 - i * 1.3 + (side > 0 ? 1.5 : 0)) * 2.4;
      final colors = level == 10 ? _rainbow : <Color>[lv.rim, lv.accent];
      canvas.scale(side, 1);
      canvas.drawPath(
        polyPath([1.5, -32, 24, -28 + wv(2), 1.5, -20]),
        fillPaint(colors[0]),
      );
      canvas.drawPath(
        polyPath([1.5, -26, 16, -25 + wv(1), 1.5, -20]),
        fillPaint(colors[1 % colors.length]),
      );
      if (level == 10) {
        paintStar(canvas, 10, -27 + wv(1), 2.6, _white, rot: t * 2);
      }
      canvas.restore();
    }
  }

  // --- laurel (5+) / crown (8+) ---------------------------------------------

  /// The two gold branches hugging the plate's lower half.
  static final Map<int, List<_Shape>> _laurelCache = {};

  static List<_Shape> _laurel(int level) =>
      _laurelCache.putIfAbsent(level, () {
        final n = level >= 8 ? 6 : 5;
        final c1 = level == 10 ? _goldLight : _gold;
        final c2 = level == 10 ? _gold : const Color(0xFFC98A00);
        final circle = Rect.fromCircle(center: const Offset(0, 4), radius: 56);
        final shapes = <_Shape>[];
        for (final side in const <double>[-1, 1]) {
          shapes.add(
            _Shape(
              Path()
                ..addArc(
                  circle,
                  side < 0 ? math.pi * .58 : math.pi * .42,
                  side < 0 ? math.pi * .40 : -math.pi * .40,
                ),
              c2,
              strokeWidth: 2,
            ),
          );
          for (var i = 0; i < n; i++) {
            final u = i / (n - 1);
            final a = side < 0
                ? math.pi * (.6 + u * .36)
                : math.pi * (.4 - u * .36);
            final cx = math.cos(a) * 56, cy = math.sin(a) * 56 + 4;
            // translate -> rotate -> rotate is one rotation about (cx, cy).
            final spin = a + (side < 0 ? -.5 : .5) + (side < 0 ? .9 : -.9);
            shapes.add(
              _Shape(
                polyPath(
                  _rot([0, -8, 3.6, 0, 0, 4, -3.6, 0], spin, 1, cx, cy),
                ),
                i.isOdd ? c2 : c1,
              ),
            );
          }
        }
        return shapes;
      });

  /// The static crown of levels 8 and 10 (level 9's flames animate).
  static final Map<int, List<_Shape>> _crownCache = {};

  static List<_Shape> _crown(int level) => _crownCache.putIfAbsent(level, () {
    final big = level == 10;
    final w = big ? 30.0 : 24.0, h = big ? 26.0 : 20.0;
    const y = -44.0;
    return [
      _Shape(
        polyPath([
          -w, y,
          -w, y - h * .75,
          -w * .5, y - h * .35,
          0, y - h,
          w * .5, y - h * .35,
          w, y - h * .75,
          w, y,
        ]),
        _gold,
      ),
      _Shape(
        polyPath([-w, y, -w, y - 5, w, y - 5, w, y]),
        const Color(0xFFE69500),
      ),
      _Shape(
        polyPath([
          -w, y - h * .75,
          -w * .5, y - h * .35,
          -w * .5, y - h * .2,
          -w, y - h * .55,
        ]),
        const Color.fromRGBO(255, 255, 255, .35),
      ),
      _Shape(
        octPath(-5, y - h * .62, 10, 10, 3),
        big ? const Color(0xFF7C4DFF) : const Color(0xFFE53935),
      ),
      // The two side jewels are circles; wrap them as tiny ring paths so they
      // share the cached-shape list (and its paints).
      _Shape(
        Path()
          ..addOval(Rect.fromCircle(center: Offset(-w * .62, y - 2.5), radius: 2.2)),
        const Color(0xFF1E88E5),
      ),
      _Shape(
        Path()
          ..addOval(Rect.fromCircle(center: Offset(w * .62, y - 2.5), radius: 2.2)),
        const Color(0xFF43A047),
      ),
      if (big)
        _Shape(
          polyPath([0, y - h - 14, 6, y - h - 5, 0, y - h + 2, -6, y - h - 5]),
          const Color(0xFF7C4DFF),
        ),
      if (big)
        _Shape(
          polyPath([0, y - h - 14, 6, y - h - 5, 0, y - h - 5]),
          const Color(0xFFB39DFF),
        ),
    ];
  });

  /// Level 9's flickering flame crown (rebuilt per frame).
  static void _flameCrown(Canvas canvas, double t) {
    const colors = [Color(0xFFFF7A1A), Color(0xFFFFB529), Color(0xFFFF7A1A)];
    for (var i = 0; i < 3; i++) {
      final f = math.sin(t * 10 + i * 2) * 2.5;
      final x = -14.0 + i * 14, h = i == 1 ? 30.0 : 22.0;
      canvas.drawPath(
        polyPath([x - 8, -44, x + f, -44 - h, x + 8, -44]),
        fillPaint(colors[i]),
      );
      canvas.drawPath(
        polyPath([x - 4, -44, x + f * .6, -44 - h * .55, x + 4, -44]),
        fillPaint(_goldLight),
      );
    }
  }

  /// Level 10's white sparkle skipped left-right across the crown.
  static void _crownSparkle(Canvas canvas, double t) {
    const w = 30.0, h = 26.0;
    final sp = (t * .7) % 2;
    if (sp >= 1) return;
    paintStar(canvas, -w + sp * 2 * w, -44 - h * .8, 3.4, _white, rot: t * 3);
  }

  /// The chick's head tuft (level 2).
  static final List<_Shape> _tuft = () {
    final lv = _styles[1];
    return [
      for (var i = 0; i < 3; i++)
        _Shape(
          polyPath([
            -8.0 + i * 8 - 4, -46,
            -8.0 + i * 8 + (i - 1) * 3, -58 - (i == 1 ? 4 : 0),
            -8.0 + i * 8 + 4, -46,
          ]),
          i == 1 ? lv.accent : lv.rim,
        ),
    ];
  }();

  /// The eggshell speckles and crack line (level 1, clipped to the plate).
  static final List<_Shape> _eggInner = () {
    final lv = _styles[0];
    final shapes = <_Shape>[];
    for (var i = 0; i < 9; i++) {
      shapes.add(
        _Shape(
          Path()
            ..addRect(
              Rect.fromLTWH(
                -28 + artHash(i) * 56,
                -38 + artHash(i + 20) * 76,
                3,
                3,
              ),
            ),
          lv.rim,
        ),
      );
    }
    final crack = Path()..moveTo(-40, -14);
    for (var i = 0; i <= 8; i++) {
      crack.lineTo(-40 + i * 10, i.isOdd ? -22 : -12);
    }
    shapes.add(_Shape(crack, lv.accent, strokeWidth: 2.4));
    return shapes;
  }();

  // --- ribbon (every level) -------------------------------------------------

  /// Ribbon bottom offset: 46 for the egg, 50 for the shields, else 44.
  static double _ribbonY(int level) =>
      level == 1 ? 46.0 : (level >= 4 && level <= 7 ? 50.0 : 44.0);

  static final Map<int, List<_Shape>> _ribbonCache = {};

  static List<_Shape> _ribbonShapes(int level) =>
      _ribbonCache.putIfAbsent(level, () {
        final lv = _styles[level == 0 ? 0 : level - 1];
        final c = level == 0 ? const Color(0xFFBDBDBD) : lv.accent;
        final y = _ribbonY(level);
        const shade = Color.fromRGBO(0, 0, 0, .25);
        return [
          _Shape(
            polyPath([
              -30, y + 2, -22, y + 2, -22, y + 16, -30, y + 16, -25, y + 9,
            ]),
            c,
          ),
          _Shape(
            polyPath([30, y + 2, 22, y + 2, 22, y + 16, 30, y + 16, 25, y + 9]),
            c,
          ),
          _Shape(polyPath([-22, y + 2, -18, y + 2, -22, y + 6]), shade),
          _Shape(polyPath([22, y + 2, 18, y + 2, 22, y + 6]), shade),
          _Shape(
            polyPath([-20, y - 2, 20, y - 2, 20, y + 12, -20, y + 12]),
            level == 0 ? const Color(0xFFCFCFCF) : lv.rim,
          ),
        ];
      });

  static void _ribbon(Canvas canvas, int level) {
    _paintShapes(canvas, _ribbonShapes(level));
    // The mock's `13px Opificio`, horizontal centre and `textBaseline:
    // middle` on (0, y + 5.5): centre the line box there.
    final y = _ribbonY(level);
    final text = _ribbonText(level);
    canvas.drawParagraph(text, Offset(-100, y + 5.5 - text.height / 2));
  }

  static final List<Paragraph?> _ribbonTexts = List<Paragraph?>.filled(
    maxLevel + 1,
    null,
  );

  static Paragraph _ribbonText(int level) =>
      _ribbonTexts[level] ??= _buildRibbonText(level);

  static Paragraph _buildRibbonText(int level) {
    final color = level == 0
        ? _white
        : (level == 8 || level == 1 || level == 2
              ? _styles[level - 1].accent
              : _white);
    final builder =
        ParagraphBuilder(
            ParagraphStyle(
              fontFamily: 'Opificio Neue',
              fontSize: 13,
              textAlign: TextAlign.center,
            ),
          )
          ..pushStyle(
            TextStyle(color: color, fontFamily: 'Opificio Neue', fontSize: 13),
          )
          ..addText(level == 0 ? '?' : '$level');
    final paragraph = builder.build()
      ..layout(const ParagraphConstraints(width: 200));
    return paragraph;
  }
}
