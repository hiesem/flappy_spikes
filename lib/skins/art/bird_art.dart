import 'dart:math' as math;
import 'dart:ui';

import 'shapes.dart';

/// Port of the bird half of `design/menu_v2/skin_art.js`: the per-shape
/// anchors (`SH`), the 30-bird art catalogue (`BIRDS`) and `birdBody` /
/// `birdFace`. Coordinates are in the 44 x 36 bird box.

/// One bird body shape with the anchors gear and hats attach to (JS `SH`).
class BirdShape {
  BirdShape._({
    required this.kind,
    required this.eye,
    required this.beak,
    required this.tail,
    required this.wing,
    required this.top,
    required this.neck,
    required this.bot,
    required this.l,
    required this.r,
    required this.hx,
    required Path Function() body,
    this.px = false,
    double? bl,
  }) : _bodyBuilder = body,
       hasBl = bl != null,
       bl = bl ?? l;

  /// JS shape key (`sq`, `round`, `tall`, `chick`, `peng`, `owl`, `puff`,
  /// `ghost`, `pixel`, `rduck`).
  final String kind;

  /// Eye centre.
  final Offset eye;

  /// Beak / tail polygons as flat coordinate lists.
  final List<double> beak, tail;

  /// Wing `[w0, wy, w1]`.
  final List<double> wing;

  /// Head top, neck line, bottom edge, left (back) and right edge, hat x.
  final double top, neck, bot, l, r, hx;

  /// Back edge of the lower body (wind-up key); [l] unless the head sits
  /// well forward of the body (the rubber duck: JS `bl`).
  final double bl;

  /// Whether the shape sets its own [bl] (JS `s.bl != null`: the rubber
  /// duck). The PRD-2.3 §19 gear uses it to anchor at the stern.
  final bool hasBl;

  /// Pixel-art shape (blocky wing).
  final bool px;

  final Path Function() _bodyBuilder;

  /// Body outline (cached).
  late final Path body = _bodyBuilder();

  /// Tail polygon (cached).
  late final Path tailPath = polyPath(tail);

  /// Default beak polygon (cached).
  late final Path beakPath = polyPath(beak);

  /// Wing up (idle) and wing down (flap) polygons (cached).
  late final Path wingUp = polyPath([
    wing[0], wing[1] - 8, wing[2], wing[1], wing[0], wing[1], //
  ]);
  late final Path wingDown = polyPath([
    wing[0], wing[1], wing[2], wing[1], wing[0], wing[1] + 9, //
  ]);

  /// Shape by JS key; unknown keys fall back to the square.
  static BirdShape of(String kind) => shapes[kind] ?? shapes['sq']!;

  static final Map<String, BirdShape> shapes = {
    'sq': BirdShape._(
      kind: 'sq',
      body: () => Path()..addRect(const Rect.fromLTWH(6, 3, 30, 30)),
      eye: const Offset(28, 12),
      beak: [36, 14, 44, 20, 36, 26],
      tail: [0, 8, 9, 14, 0, 20],
      wing: [12, 17, 24],
      top: 3,
      neck: 27,
      bot: 33,
      l: 6,
      r: 36,
      hx: 23,
    ),
    'round': BirdShape._(
      kind: 'round',
      body: () => octPath(5, 2, 32, 32, 8),
      eye: const Offset(28, 11),
      beak: [35, 13, 44, 19, 35, 25],
      tail: [0, 10, 9, 15, 0, 21],
      wing: [11, 19, 23],
      top: 2,
      neck: 27,
      bot: 34,
      l: 5,
      r: 37,
      hx: 23,
    ),
    'tall': BirdShape._(
      kind: 'tall',
      body: () => Path()..addRect(const Rect.fromLTWH(6, 3, 30, 30)),
      eye: const Offset(27, 9),
      beak: [36, 5, 47, 9, 44, 20, 36, 20],
      tail: [0, 8, 9, 14, 0, 20],
      wing: [12, 19, 24],
      top: 3,
      neck: 24,
      bot: 33,
      l: 6,
      r: 36,
      hx: 21,
    ),
    'chick': BirdShape._(
      kind: 'chick',
      body: () => octPath(7, 6, 28, 28, 7),
      eye: const Offset(27, 15),
      beak: [34, 17, 42, 21, 34, 25],
      tail: [3, 15, 11, 19, 3, 23],
      wing: [12, 22, 22],
      top: 6,
      neck: 29,
      bot: 34,
      l: 7,
      r: 35,
      hx: 22,
    ),
    'peng': BirdShape._(
      kind: 'peng',
      body: () => octPath(7, 1, 28, 34, 7),
      eye: const Offset(27, 9),
      beak: [33, 10, 41, 13, 33, 16],
      tail: [3, 24, 11, 27, 3, 31],
      wing: [11, 17, 20],
      top: 1,
      neck: 19,
      bot: 35,
      l: 7,
      r: 35,
      hx: 22,
    ),
    'owl': BirdShape._(
      kind: 'owl',
      body: () => Path()..addRect(const Rect.fromLTWH(6, 5, 30, 28)),
      eye: const Offset(27, 14),
      beak: [35, 13, 41, 17, 35, 21],
      tail: [0, 10, 9, 15, 0, 20],
      wing: [12, 19, 24],
      top: 5,
      neck: 28,
      bot: 33,
      l: 6,
      r: 36,
      hx: 21,
    ),
    'puff': BirdShape._(
      kind: 'puff',
      body: () => octPath(8, 5, 26, 26, 7),
      eye: const Offset(27, 13),
      beak: [33, 15, 41, 19, 33, 23],
      tail: [0, 10, 9, 15, 0, 21],
      wing: [12, 19, 22],
      top: 1,
      neck: 27,
      bot: 35,
      l: 4,
      r: 38,
      hx: 21,
    ),
    'ghost': BirdShape._(
      kind: 'ghost',
      body: _ghostBody,
      eye: const Offset(27, 13),
      beak: [36, 15, 43, 19, 36, 23],
      tail: [1, 12, 8, 16, 1, 20],
      wing: [12, 19, 23],
      top: 2,
      neck: 27,
      bot: 33,
      l: 6,
      r: 36,
      hx: 22,
    ),
    // Bath-toy rubber duck: a rounded-geometric head bump forward over a
    // wide boat-shaped body whose back rises into an upturned tail. [l] is
    // the head's back (head-level gear), [bl] the boat's stern.
    'rduck': BirdShape._(
      kind: 'rduck',
      body: () => polyPath(_rduckBody),
      eye: const Offset(30, 8),
      beak: [33, 10, 43, 10, 46, 12.5, 43, 14.5, 45, 16.5, 42, 18, 33, 18],
      tail: [6, 22, 10, 22, 8, 25], // inside the body: the tail is the body's
      wing: [12, 25, 26],
      top: 1,
      neck: 19,
      bot: 34,
      l: 18,
      r: 36,
      hx: 27,
      bl: 4,
    ),
    'pixel': BirdShape._(
      kind: 'pixel',
      body: _pixelBody,
      eye: const Offset(28, 12),
      beak: [37, 14, 41, 14, 41, 18, 45, 18, 45, 22, 37, 22],
      tail: [0, 10, 5, 10, 5, 14, 9, 14, 9, 18, 0, 18],
      wing: [13, 18, 25],
      top: 2,
      neck: 28,
      bot: 34,
      l: 5,
      r: 37,
      hx: 21,
      px: true,
    ),
  };

  static const List<double> _rduckBody = [
    23, 1, 31, 1, 36, 6, 36, 13, 34, 17, 39, 21, 39, 27, 33, 34, //
    11, 34, 5, 29, 3, 21, 1, 8, 6, 11, 11, 18, 18, 18, 18, 6,
  ];

  static Path _ghostBody() {
    final p = Path()
      ..moveTo(6, 33)
      ..lineTo(6, 17)
      ..arcTo(
        Rect.fromCircle(center: const Offset(21, 17), radius: 15),
        math.pi,
        math.pi,
        false,
      )
      ..lineTo(36, 33);
    for (var i = 0; i < 5; i++) {
      final x = 36.0 - i * 6;
      p
        ..quadraticBezierTo(x - 1.5, 28, x - 3, 31)
        ..quadraticBezierTo(x - 4.5, 35, x - 6, 33);
    }
    return p..close();
  }

  static Path _pixelBody() {
    const rows = [
      [3, 5], [1, 7], [0, 8], [0, 8], [0, 8], [0, 8], [1, 7], [3, 5], //
    ];
    final p = Path();
    for (var j = 0; j < rows.length; j++) {
      final a = rows[j][0], b = rows[j][1];
      p.addRect(Rect.fromLTWH(5.0 + a * 4, 2.0 + j * 4, (b - a) * 4.0, 4));
    }
    return p;
  }
}

/// Art description of one bird (JS `BIRDS` entry minus shop data).
class BirdSpec {
  BirdSpec(
    this.id,
    String shape, {
    required this.c,
    required this.d,
    this.bk,
    this.ey,
    this.belly,
    this.beak,
    this.pat,
  }) : shape = BirdShape.of(shape);

  final String id;
  final BirdShape shape;

  /// Body colour and darker shade.
  final Color c, d;

  /// Beak colour (default gold), eye colour (default white), belly colour.
  final Color? bk, ey, belly;

  /// Special beak (`toucan`, `hook`).
  final String? beak;

  /// Body pattern (`stripes`, `camo`, `dots`, `zebra`, `bee`, `robo`,
  /// `zombie`, `ice`, `lava`, `galaxy`, `gold`, `rainbow`, `phoenix`).
  final String? pat;

  /// Belly patch, per shape (cached).
  late final Path? bellyPath = belly == null
      ? null
      : switch (shape.kind) {
          'peng' => octPath(18, 14, 15, 19, 5),
          'tall' => polyPath([24, 15, 36, 15, 36, 28, 28, 26]),
          'owl' => polyPath([14, 33, 14, 24, 22, 19, 30, 24, 30, 33]),
          _ => octPath(shape.r - 19, shape.bot - 15, 18, 18, 6),
        };

  /// Pattern geometry that never changes (cached).
  late final Path? patternPath = switch (pat) {
    'zebra' => _stripes(
      -2,
      6,
      (i) => [i * 8, 0, i * 8 + 4, 0, i * 8 + 18, 36, i * 8 + 14, 36],
    ),
    'stripes' => _stripes(
      -3,
      7,
      (i) => [i * 7, 36, i * 7 + 3, 36, i * 7 + 21, 0, i * 7 + 18, 0],
    ),
    _ => null,
  };

  static Path _stripes(int from, int to, List<double> Function(double) quad) {
    final p = Path();
    for (var i = from; i < to; i++) {
      addPoly(p, quad(i.toDouble()));
    }
    return p;
  }

  /// Light body (white, yellow): the PRD-2 white dead X would vanish, so it
  /// is drawn dark there.
  late final bool isLight = c.computeLuminance() > 0.6;
}

/// The 30 birds of the catalogue, in grid order, plus the shop mannequin.
abstract final class BirdArt {
  static final List<BirdSpec> all = [
    BirdSpec('classic', 'sq', c: artPink, d: const Color(0xFFC2185B)),
    BirdSpec(
      'sky',
      'sq',
      c: const Color(0xFF29B6F6),
      d: const Color(0xFF0277BD),
    ),
    BirdSpec(
      'lime',
      'sq',
      c: const Color(0xFF7CB342),
      d: const Color(0xFF33691E),
    ),
    BirdSpec(
      'grape',
      'sq',
      c: const Color(0xFF8E24AA),
      d: const Color(0xFF4A148C),
    ),
    BirdSpec(
      'tangerine',
      'sq',
      c: const Color(0xFFFF7A1A),
      d: const Color(0xFFC43E00),
    ),
    BirdSpec(
      'mint',
      'sq',
      c: const Color(0xFF3DDBB0),
      d: const Color(0xFF00897B),
    ),
    BirdSpec(
      'lemon',
      'sq',
      c: const Color(0xFFFFE03A),
      d: const Color(0xFFF29100),
      bk: const Color(0xFFFF5722),
      pat: 'stripes',
    ),
    BirdSpec(
      'slate',
      'sq',
      c: const Color(0xFF7C8B6E),
      d: const Color(0xFF4B5842),
      pat: 'camo',
    ),
    BirdSpec(
      'coral',
      'sq',
      c: const Color(0xFFFF6F61),
      d: const Color(0xFFC62828),
      pat: 'dots',
    ),
    BirdSpec(
      'snow',
      'sq',
      c: const Color(0xFFFAFAFA),
      d: const Color(0xFFB0BEC5),
      ey: const Color(0xFF37474F),
    ),
    BirdSpec(
      'robin',
      'round',
      c: const Color(0xFF8D6E63),
      d: const Color(0xFF5D4037),
      belly: const Color(0xFFFF7043),
    ),
    BirdSpec(
      'toucan',
      'tall',
      c: const Color(0xFF263238),
      d: const Color(0xFF000000),
      belly: const Color(0xFFFFF59D),
      beak: 'toucan',
    ),
    BirdSpec(
      'chick',
      'chick',
      c: const Color(0xFFFFD54F),
      d: const Color(0xFFFFA000),
      bk: const Color(0xFFFF7A1A),
    ),
    BirdSpec(
      'penguin',
      'peng',
      c: const Color(0xFF263238),
      d: const Color(0xFF101518),
      belly: const Color(0xFFFFFFFF),
    ),
    BirdSpec(
      'owl',
      'owl',
      c: const Color(0xFFA1887F),
      d: const Color(0xFF6D4C41),
      belly: const Color(0xFFD7CCC8),
    ),
    BirdSpec(
      'duck',
      'rduck',
      c: const Color(0xFFFFD600),
      d: const Color(0xFFF9A825),
      bk: const Color(0xFFFF5722),
      ey: const Color(0xFF212121),
    ),
    BirdSpec(
      'flamingo',
      'round',
      c: const Color(0xFFF48FB1),
      d: const Color(0xFFEC407A),
      beak: 'hook',
    ),
    BirdSpec(
      'puffer',
      'puff',
      c: const Color(0xFFFFCA28),
      d: const Color(0xFFF57F17),
      bk: const Color(0xFFFF7043),
    ),
    BirdSpec(
      'zebra',
      'sq',
      c: const Color(0xFFFAFAFA),
      d: const Color(0xFF212121),
      pat: 'zebra',
    ),
    BirdSpec(
      'buzz',
      'round',
      c: const Color(0xFFFFC107),
      d: const Color(0xFF212121),
      pat: 'bee',
      bk: const Color(0xFF212121),
    ),
    BirdSpec(
      'robo',
      'sq',
      c: const Color(0xFFB0BEC5),
      d: const Color(0xFF607D8B),
      pat: 'robo',
      bk: const Color(0xFF78909C),
    ),
    BirdSpec(
      'zombie',
      'sq',
      c: const Color(0xFF8BC34A),
      d: const Color(0xFF4E7A27),
      pat: 'zombie',
    ),
    BirdSpec(
      'ghost',
      'ghost',
      c: const Color(0xFFECEFF1),
      d: const Color(0xFFB0BEC5),
      ey: const Color(0xFF263238),
    ),
    BirdSpec('pixel', 'pixel', c: artPink, d: artPlum),
    BirdSpec(
      'frost',
      'sq',
      c: const Color(0xFFB3E5FC),
      d: const Color(0xFF4FC3F7),
      pat: 'ice',
    ),
    BirdSpec(
      'magma',
      'sq',
      c: const Color(0xFF3E2723),
      d: const Color(0xFF1B0F0C),
      pat: 'lava',
      bk: const Color(0xFFFF6D00),
    ),
    BirdSpec(
      'galaxy',
      'round',
      c: const Color(0xFF2A1260),
      d: const Color(0xFF120634),
      pat: 'galaxy',
    ),
    BirdSpec(
      'golden',
      'sq',
      c: const Color(0xFFFFC629),
      d: const Color(0xFFC98A00),
      pat: 'gold',
      bk: const Color(0xFFFFFFFF),
    ),
    BirdSpec(
      'rainbow',
      'sq',
      c: const Color(0xFFFF4444),
      d: const Color(0xFFFFFFFF),
      pat: 'rainbow',
    ),
    BirdSpec(
      'phoenix',
      'round',
      c: const Color(0xFFFF5722),
      d: const Color(0xFFBF360C),
      pat: 'phoenix',
    ),
  ];

  /// All bird ids in grid order.
  static final List<String> ids = [for (final b in all) b.id];

  // region P26-POL3
  static final Map<String, BirdSpec> _byId = {
    for (final b in all) b.id: b,
    'magpie': BirdSpec('magpie', 'sq', c: const Color(0xFF1C1C1C), d: const Color(0xFF2673B8)),
    'prism': BirdSpec('prism', 'sq', c: const Color(0xFFEAF8FF), d: const Color(0xFF6EB9E4)),
    'daynight': BirdSpec('daynight', 'sq', c: const Color(0xFF4FC3F7), d: const Color(0xFF364675)),
  };
  // endregion

  /// Bird by id; unknown ids fall back to `classic` (JS `byId`).
  static BirdSpec byId(String id) => _byId[id] ?? all.first;

  /// Light-grey bird gear and hats are shown on in shop tiles.
  static final BirdSpec mannequin = BirdSpec(
    'mannequin',
    'sq',
    c: const Color(0xFFDCDCDC),
    d: const Color(0xFFC4C4C4),
    bk: const Color(0xFFCFCFCF),
    ey: const Color(0xFFFFFFFF),
  );
}

// ---- static paths / shaders -------------------------------------------------

final Path _owlEars = polyPath([7, 1, 13, 6, 7, 8])
  ..addPath(polyPath([35, 1, 29, 6, 35, 8]), Offset.zero);

final Path _puffSpikes = () {
  final p = Path();
  for (var i = 0; i < 14; i++) {
    final a = i / 14 * tau + .2, c = math.cos(a), sn = math.sin(a);
    addPoly(p, [
      21 + c * 11 - sn * 2.6, 18 + sn * 11 + c * 2.6, //
      21 + c * 17, 18 + sn * 17,
      21 + c * 11 + sn * 2.6, 18 + sn * 11 - c * 2.6,
    ]);
  }
  return p;
}();

final Path _chickTuft = polyPath([19, 7, 17, 0, 22, 6, 24, 1, 24, 7]);

final Path _owlFeathers = () {
  final p = Path();
  for (final (x, y) in const [
    (18.0, 25.0),
    (24.0, 25.0),
    (21.0, 29.0),
    (27.0, 29.0),
  ]) {
    addPoly(p, [x - 2, y, x, y + 2, x + 2, y]);
  }
  return p;
}();

const _camo = [
  (6.0, 3.0, 10.0, 6.0, Color(0xFF4B5842)),
  (20.0, 6.0, 12.0, 5.0, Color(0xFFA3AE87)),
  (8.0, 14.0, 8.0, 8.0, Color(0xFFA3AE87)),
  (24.0, 14.0, 12.0, 7.0, Color(0xFF4B5842)),
  (14.0, 22.0, 10.0, 6.0, Color(0xFF5E6B4F)),
  (28.0, 25.0, 8.0, 8.0, Color(0xFFA3AE87)),
  (6.0, 27.0, 8.0, 6.0, Color(0xFF4B5842)),
  (16.0, 9.0, 4.0, 4.0, Color(0xFF3A4433)),
];

final Path _roboLines = Path()
  ..addRect(const Rect.fromLTWH(9, 6, 24, 24))
  ..moveTo(6, 18)
  ..lineTo(36, 18);

final Path _zombieStitches = () {
  final p = Path()
    ..moveTo(12, 8)
    ..lineTo(22, 26);
  for (var i = 0; i < 4; i++) {
    final u = i / 3, x = 12 + u * 10, y = 8 + u * 18;
    p
      ..moveTo(x - 2.2, y + 1.2)
      ..lineTo(x + 2.2, y - 1.2);
  }
  return p;
}();

final Path _iceLight = polyPath([6, 3, 20, 3, 6, 17]);
final Path _iceShade = polyPath([36, 12, 36, 33, 18, 33]);
final Path _iceCrack = Path()
  ..moveTo(6, 24)
  ..lineTo(20, 10)
  ..lineTo(36, 22);

final Path _lavaCracks = Path()
  ..moveTo(6, 10)
  ..lineTo(14, 14)
  ..lineTo(12, 22)
  ..lineTo(20, 27)
  ..lineTo(18, 33)
  ..moveTo(14, 14)
  ..lineTo(24, 12)
  ..lineTo(30, 4)
  ..moveTo(20, 27)
  ..lineTo(36, 25);

final Shader _galaxyFill = Gradient.radial(
  const Offset(21, 18),
  18,
  const [Color(0xFF6A3DE8), Color(0xFF2A1260), Color(0xFF120634)],
  const [0, .6, 1],
  TileMode.clamp,
  null,
  const Offset(18, 14),
  2,
);
final Shader _goldFill = Gradient.linear(
  const Offset(6, 3),
  const Offset(36, 33),
  const [Color(0xFFFFE082), Color(0xFFFFC629), Color(0xFFE69500)],
  const [0, .5, 1],
);
final Shader _phoenixFill = Gradient.linear(
  const Offset(0, 34),
  const Offset(0, 2),
  const [Color(0xFFD84315), Color(0xFFFF7043), Color(0xFFFFCA28)],
  const [0, .6, 1],
);
final Shader _iceFill = Gradient.linear(
  const Offset(6, 3),
  const Offset(36, 33),
  const [Color(0xFFE1F5FE), Color(0xFF81D4FA)],
);
final Shader _toucanBeak = Gradient.linear(
  const Offset(32, 0),
  const Offset(45, 0),
  const [Color(0xFFFFEB3B), Color(0xFFFF9800), Color(0xFFE53935)],
  const [0, .7, 1],
);
final Path _toucanTip = polyPath([42, 7, 47, 9, 45.8, 14, 42, 14]);
final Path _toucanShade = polyPath([36, 14, 45.3, 14, 44, 20, 36, 20]);
final Path _hookWhite = polyPath([35, 13, 42, 15, 44, 20, 35, 21]);
final Path _hookTip = polyPath([42, 15, 44, 20, 42, 23, 39, 19]);

/// Rubber duck: the sailor-hat band round the head bump and the one glossy
/// highlight on the body (both clipped to the body).
const Color _rduckBand = Color(0xFF1E88E5);
final Path _rduckGloss = polyPath([20, 10, 23, 7, 25, 7, 22, 12]);

const _rainbow = [
  Color(0xFFFF3B30), Color(0xFFFF9500), Color(0xFFFFCC00), //
  Color(0xFF34C759), Color(0xFF00A2FF), Color(0xFFAF52DE),
];
const _phoenixCrest = [Color(0xFFFFB529), Color(0xFFFF7043), Color(0xFFFFEB3B)];

/// Scratch path for per-frame geometry (reset before every use).
final Path _scratch = Path();
Path _poly(List<double> pts) => addPoly(_scratch..reset(), pts);

/// Behind-the-body parts, body fill and pattern (JS `birdBody`).
void paintBirdBody(Canvas c, BirdSpec b, double t) {
  final s = b.shape;
  if (s.kind == 'owl') c.drawPath(_owlEars, fillPaint(b.d));
  if (s.kind == 'puff') c.drawPath(_puffSpikes, fillPaint(b.d));
  if (b.pat == 'phoenix') {
    for (var i = 0; i < 3; i++) {
      final f = math.sin(t * 9 + i * 2) * 1.5;
      c.drawPath(
        _poly([14.0 + i * 5, 5, 11 + i * 6 + f, -6 + i * 1.5, 19.0 + i * 5, 4]),
        fillPaint(_phoenixCrest[i]),
      );
    }
    c.drawPath(
      _poly([
        6, 14, -6 + math.sin(t * 8) * 2, 9, -2, 16, //
        -8, 21 + math.sin(t * 7) * 2, 6, 22,
      ]),
      fillPaint(_phoenixCrest[2]),
    );
  } else {
    c.drawPath(s.tailPath, fillPaint(b.d));
  }
  if (b.pat == 'robo') {
    c.drawLine(
      const Offset(18, 3),
      const Offset(18, -4),
      strokePaint(const Color(0xFF607D8B), 1.5),
    );
    circ(
      c,
      18,
      -5,
      2.2,
      math.sin(t * 6) > 0 ? const Color(0xFFFF1744) : const Color(0xFFB71C1C),
    );
  }
  if (s.kind == 'chick') c.drawPath(_chickTuft, fillPaint(b.d));

  // body fill
  c.save();
  final body = s.body;
  final shader = switch (b.pat) {
    'galaxy' => _galaxyFill,
    'gold' => _goldFill,
    'phoenix' => _phoenixFill,
    'ice' => _iceFill,
    _ => null,
  };
  if (shader != null) {
    c.drawPath(body, shaderPaint(shader));
  } else {
    c.drawPath(
      body,
      fillPaint(s.kind == 'ghost' ? b.c.withValues(alpha: .88) : b.c),
    );
  }
  c.clipPath(body);
  final belly = b.bellyPath;
  if (belly != null) {
    c.drawPath(belly, fillPaint(b.belly!));
    if (s.kind == 'owl') c.drawPath(_owlFeathers, fillPaint(b.d));
  }
  if (s.kind == 'rduck') {
    fillRect(c, 17, 2.6, 20, 3.2, _rduckBand);
    c.drawPath(_rduckGloss, fillPaint(const Color(0xFFFFFFFF)));
  }
  switch (b.pat) {
    case 'zebra' || 'stripes':
      c.drawPath(b.patternPath!, fillPaint(b.d));
    case 'camo':
      for (final (x, y, w, h, col) in _camo) {
        fillRect(c, x, y, w, h, col);
      }
    case 'dots':
      for (var j = 0; j < 5; j++) {
        for (var i = 0; i < 5; i++) {
          if ((i + j).isEven) {
            fillRect(
              c,
              7 + i * 6.4,
              4 + j * 6.4,
              3.2,
              3.2,
              const Color(0xFFFFFFFF),
            );
          }
        }
      }
    case 'bee':
      fillRect(c, 12, 0, 4.5, 36, b.d);
      fillRect(c, 21, 0, 4.5, 36, b.d);
    case 'robo':
      c.drawPath(_roboLines, strokePaint(const Color(0xFF78909C), 1));
      for (final (x, y) in const [
        (9.0, 6.0),
        (33.0, 6.0),
        (9.0, 30.0),
        (33.0, 30.0),
      ]) {
        circ(c, x, y, 1.2, const Color(0xFF546E7A));
      }
      fillRect(c, 13, 21, 10, 6, const Color(0xFF90A4AE));
    case 'zombie':
      fillRect(c, 8, 20, 9, 8, const Color(0xFF689F38));
      fillRect(c, 22, 5, 6, 4, const Color(0xFF689F38));
      c.drawPath(_zombieStitches, strokePaint(const Color(0xFF33691E), 1.2));
    case 'ice':
      c.drawPath(
        _iceLight,
        fillPaint(const Color.fromRGBO(255, 255, 255, .55)),
      );
      c.drawPath(_iceShade, fillPaint(const Color.fromRGBO(2, 136, 209, .18)));
      c.drawPath(
        _iceCrack,
        strokePaint(const Color.fromRGBO(255, 255, 255, .8), .8),
      );
    case 'lava':
      final g = .6 + .4 * math.sin(t * 4);
      c.drawPath(
        _lavaCracks,
        strokePaint(
          Color.fromRGBO(255, (110 + 80 * g).truncate(), 0, .7 + .3 * g),
          1.6,
        ),
      );
    case 'galaxy':
      for (var i = 0; i < 14; i++) {
        final x = 6 + artHash(i) * 30, y = 3 + artHash(i + 40) * 30;
        final tw = .4 + .6 * math.sin(t * 2 + i * 1.7).abs();
        circ(
          c,
          x,
          y,
          .5 + artHash(i + 9) * 1.1 * tw,
          Color.fromRGBO(255, 255, 255, tw),
        );
      }
    case 'gold':
      final u = ((t * .45) % 1.6) * 60 - 30;
      c.drawPath(
        _poly([u, 0, u + 7, 0, u - 8, 36, u - 15, 36]),
        fillPaint(const Color.fromRGBO(255, 255, 255, .65)),
      );
    case 'rainbow':
      final shift = (t * 4).floor();
      final dy = (t * 20) % 5;
      for (var i = -1; i < 7; i++) {
        fillRect(c, 0, 3 + i * 5 + dy, 44, 5.2, _rainbow[(i + shift) % 6]);
      }
  }
  c.restore();
}

/// Wing, eye and beak (JS `birdFace`). [dead] draws the eye as an X;
/// [blink] draws it closed: a short horizontal bar in the eye colour
/// (`build55.py`: the eye square is covered and a 4 x 1 bar drawn 0.6
/// below its centre).
void paintBirdFace(
  Canvas c,
  BirdSpec b,
  double t,
  bool flap, {
  bool dead = false,
  bool blink = false,
}) {
  final s = b.shape;
  // wing
  final wc = switch (b.pat) {
    'rainbow' => const Color(0xFFFFFFFF),
    'gold' => const Color(0xFFE69500),
    'galaxy' => const Color(0xFF6A3DE8),
    'phoenix' => const Color(0xFFFFEB3B),
    _ => b.d,
  };
  final w0 = s.wing[0], wy = s.wing[1];
  if (s.px) {
    if (flap) {
      fillRect(c, w0, wy, 12, 4, wc);
      fillRect(c, w0, wy + 4, 4, 4, wc);
    } else {
      fillRect(c, w0, wy - 4, 4, 4, wc);
      fillRect(c, w0, wy - 1, 12, 4, wc);
    }
  } else {
    c.drawPath(flap ? s.wingDown : s.wingUp, fillPaint(wc));
  }
  // eye
  final ex = s.eye.dx, ey = s.eye.dy;
  if (blink && !dead && b.pat != 'zombie') {
    _paintClosedEye(c, b, ex, ey);
  } else if (s.kind == 'owl') {
    fillRect(c, ex - 5, ey - 5, 10, 10, const Color(0xFFFFFFFF));
    if (dead) {
      paintDeadX(c, ex, ey, const Color(0xFF212121));
    } else {
      fillRect(c, ex - 1, ey - 2.5, 5, 5, const Color(0xFF212121));
      fillRect(c, ex + 1.5, ey - 2, 1.5, 1.5, const Color(0xFFFFFFFF));
    }
    c.drawPath(
      _poly([ex - 7, ey - 8, ex + 6, ey - 6, ex + 6, ey - 5, ex - 7, ey - 5]),
      fillPaint(b.d),
    );
  } else if (dead) {
    paintDeadX(
      c,
      ex,
      ey,
      b.isLight ? const Color(0xFF212121) : const Color(0xFFFFFFFF),
    );
  } else if (b.pat == 'robo') {
    fillRect(c, ex - 4, ey - 3, 9, 6, const Color(0xFF212121));
    fillRect(
      c,
      ex - 1,
      ey - 1.5,
      4,
      3,
      math.sin(t * 3) > -.8 ? const Color(0xFFFF1744) : const Color(0xFF7F0000),
    );
  } else if (b.pat == 'zombie') {
    paintDeadEye(c, ex, ey, const Color(0xFF212121));
  } else if (s.kind == 'ghost') {
    c.drawOval(
      Rect.fromCenter(center: Offset(ex, ey), width: 4, height: 6.4),
      fillPaint(b.ey!),
    );
  } else {
    fillRect(c, ex - 2, ey - 2, 4, 4, b.ey ?? const Color(0xFFFFFFFF));
    if (b.c == const Color(0xFFFAFAFA) ||
        b.c == const Color(0xFFFFE03A) ||
        b.pat == 'ice') {
      fillRect(c, ex - 1, ey - 1, 3, 3, const Color(0xFF37474F));
    }
  }
  // beak
  switch (b.beak) {
    case 'toucan':
      c.drawPath(s.beakPath, shaderPaint(_toucanBeak));
      c.drawPath(_toucanTip, fillPaint(const Color(0xFF212121)));
      c.drawPath(_toucanShade, fillPaint(const Color.fromRGBO(0, 0, 0, .25)));
    case 'hook':
      c.drawPath(_hookWhite, fillPaint(const Color(0xFFFFFFFF)));
      c.drawPath(_hookTip, fillPaint(const Color(0xFF212121)));
    default:
      c.drawPath(s.beakPath, fillPaint(b.bk ?? artGold));
  }
}

/// Closed eye of the idle blink: a 4 x 1 bar 0.6 below the eye centre in
/// the colour the open eye's lid line would have (the white eye square /
/// the owl's pupil / the ghost's eye colour / the robo visor).
void _paintClosedEye(Canvas c, BirdSpec b, double ex, double ey) {
  if (b.shape.kind == 'owl') {
    fillRect(c, ex - 5, ey - 5, 10, 10, const Color(0xFFFFFFFF));
    fillRect(c, ex - 2, ey + .6, 6, 1, const Color(0xFF212121));
    c.drawPath(
      _poly([ex - 7, ey - 8, ex + 6, ey - 6, ex + 6, ey - 5, ex - 7, ey - 5]),
      fillPaint(b.d),
    );
    return;
  }
  final color = b.pat == 'robo'
      ? const Color(0xFF212121)
      : b.shape.kind == 'ghost'
      ? b.ey!
      : b.ey ?? const Color(0xFFFFFFFF);
  fillRect(c, ex - 2, ey + .6, 4, 1, color);
}

/// X eye (the zombie eye; also the dead pose) centred at ([ex], [ey]).
void paintDeadEye(Canvas c, double ex, double ey, Color color) {
  final p = strokePaint(color, 1.5);
  c.drawLine(Offset(ex - 2.5, ey - 2.5), Offset(ex + 2.5, ey + 2.5), p);
  c.drawLine(Offset(ex + 2.5, ey - 2.5), Offset(ex - 2.5, ey + 2.5), p);
}

/// The PRD-2 §3.0.9 #6 dead-bird X (miss-flash mock, `build85.py`): a 6 x 6
/// X with a 2 pt line centred on the eye, replacing it.
void paintDeadX(Canvas c, double ex, double ey, Color color) {
  final p = strokePaint(color, 2);
  c.drawLine(Offset(ex - 3, ey - 3), Offset(ex + 3, ey + 3), p);
  c.drawLine(Offset(ex + 3, ey - 3), Offset(ex - 3, ey + 3), p);
}
