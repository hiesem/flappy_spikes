import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

/// The approved 2.6 mystery box (PRD O99; approved style A in
/// `docs/p26/design/levels_v26/item_reveal.html`). This is the only place
/// that draws a 2.6 box: the level item reveal, the gold bonus chest, the
/// gold / silver / bronze leaderboard gifts, Star Road mystery tiles and the
/// in-run paired-hoops gift all pass colour, size, label and lid phase here.
enum MysteryBoxTier {
  gold(
    main: Color(0xFFFFB529),
    dark: Color(0xFFC98A00),
    ink: Color(0xFF7A0044),
  ),
  silver(
    main: Color(0xFFC3CDD3),
    dark: Color(0xFF7F8C94),
    ink: Color(0xFF7A0044),
  ),
  bronze(
    main: Color(0xFFDB8B4C),
    dark: Color(0xFF9C5A2A),
    ink: Color(0xFF7A0044),
  ),
  pink(
    main: Color(0xFFEC008C),
    dark: Color(0xFFB0006B),
    ink: Color(0xFF7A0044),
  );

  const MysteryBoxTier({
    required this.main,
    required this.dark,
    required this.ink,
  });

  final Color main, dark, ink;
}

/// The colours and ribbon of a mystery box. The lid uses the main / dark
/// split, exactly as style A does; the label tint defaults to the ribbon.
class MysteryBoxLook {
  const MysteryBoxLook({
    required this.main,
    required this.dark,
    this.ribbon = const Color(0xFFFFFFFF),
    this.label = '?',
    this.labelColor = const Color(0xFFFFFFFF),
  });

  factory MysteryBoxLook.tier(MysteryBoxTier tier, {String? label = '?'}) =>
      MysteryBoxLook(main: tier.main, dark: tier.dark, label: label);

  /// The locked level row's grey box (`levels_screen.html`:
  /// `GREY={c:'#BDBDBD',d:'#9C9C9C'}`); it keeps the single `?` mark of
  /// `boxSVG(GREY, null)`.
  static const MysteryBoxLook levelBox = MysteryBoxLook(
    main: Color(0xFFBDBDBD),
    dark: Color(0xFF9C9C9C),
    label: '?',
  );

  /// The approved style A common/rare/... palette uses the rarity's own main
  /// and dark colours; the lid keeps the main/dark split and the ribbon is
  /// white at 90 %.
  factory MysteryBoxLook.colours(
    Color main,
    Color dark, {
    String? label = '?',
    Color ribbon = const Color(0xFFFFFFFF),
    Color? labelColor,
  }) => MysteryBoxLook(
    main: main,
    dark: dark,
    ribbon: ribbon,
    label: label,
    labelColor: labelColor ?? ribbon,
  );

  final Color main, dark;
  final Color ribbon;

  /// `'?'` in style A; null requests the label-less level tile / pair box.
  final String? label;
  final Color labelColor;
}

/// Lid timing from the approved style A page. Closed is the resting box;
/// shake is the warning phase; lid-off is the opening phase. The actual
/// 0.5 s flying-lid clip is [MysteryBoxAnimation.lidOff] at `u` 0..1.
enum MysteryBoxPhase { closed, shake, lidOff }

/// The box's lid state at one moment. [shake] is 0..1 across the warning
/// phase, while [revealTime] is the separate elapsed style-A clock that drives
/// the sine frequencies; [lift] / [angle] / [drop] are the style A lid
/// transform at [lidOff] progress [u].
class MysteryBoxLid {
  const MysteryBoxLid.closed()
    : phase = MysteryBoxPhase.closed,
      shake = 0,
      revealTime = 0,
      u = 0;

  const MysteryBoxLid.shake(this.shake, {required this.revealTime})
    : phase = MysteryBoxPhase.shake,
      u = 0;

  const MysteryBoxLid.off(this.u)
    : phase = MysteryBoxPhase.lidOff,
      shake = 0,
      revealTime = 0;

  final MysteryBoxPhase phase;
  final double shake;
  final double revealTime;
  final double u;

  bool get isOff => phase == MysteryBoxPhase.lidOff;

  /// Style A lid offset in box units: `translate(lu*60, -150lu + 40lu²)`
  /// and `rotate(lu*80°)` (the design's 80 px = 80° at the box scale).
  double get lift => 60 * u;
  double get drop => -150 * u + 40 * u * u;
  double get angle => u * 80 * math.pi / 180;

  /// Warning wobble: `sin(revealTime × 42) × (2 + 12 × shake²)` degrees,
  /// exactly as style A drives frequency from elapsed reveal time and
  /// amplitude from normalized shake progress.
  double get wobble => phase == MysteryBoxPhase.shake
      ? math.sin(revealTime * 42) * (2 + shake * shake * 12) * math.pi / 180
      : 0;

  /// Style A's small upward hop during the shake:
  /// `abs(sin(revealTime × 21)) × (-3 - 6 × shake)` box units.
  double get hop => phase == MysteryBoxPhase.shake
      ? -math.sin(revealTime * 21).abs() * (3 + shake * 6)
      : 0;
}

/// The deterministic animation envelope for a reveal: [at] returns the lid
/// state for elapsed seconds, with [shakeFrom] / [shakeLength] for the warning
/// and [lidOffFrom] / [lidOffLength] for the 0.5 s lid clip. The in-run pair
/// box keeps its own bob / tilt and passes only the lid phase; screens that
/// show the whole sequence pass elapsed seconds.
class MysteryBoxAnimation {
  const MysteryBoxAnimation({
    this.shakeFrom = .3,
    this.shakeLength = .75,
    this.lidOffFrom = 1.05,
    this.lidOffLength = .5,
  });

  final double shakeFrom, shakeLength, lidOffFrom, lidOffLength;

  MysteryBoxLid at(double elapsed) {
    if (elapsed < shakeFrom) return const MysteryBoxLid.closed();
    if (elapsed < lidOffFrom) {
      final u = ((elapsed - shakeFrom) / shakeLength).clamp(0.0, 1.0);
      return MysteryBoxLid.shake(u, revealTime: elapsed);
    }
    final u = ((elapsed - lidOffFrom) / lidOffLength).clamp(0.0, 1.0);
    return MysteryBoxLid.off(u);
  }
}

/// The only 2.6 box drawing. Coordinates are style A's art units: the body
/// is x −40..40, y −10..42 and the lid x −46..46, y −24..−8. The caller
/// chooses the point size; [paint] maps art units through [size] / 80.
abstract final class MysteryBox {
  /// Style A body / lid bounds (art units), used by tests and layout.
  static const Rect bodyBounds = Rect.fromLTRB(-40, -10, 40, 42);
  static const Rect lidBounds = Rect.fromLTRB(-46, -24, 46, -8);

  /// Style A's 80 unit reference: the tile and the pair box both scale from
  /// it. `size` is the box's width in pt.
  static const double referenceSize = 80;

  static final Paint _fill = Paint()..isAntiAlias = true;

  static void _rect(Canvas c, Rect r, Color color) {
    c.drawRect(r, _fill..color = color);
  }

  static void _poly(Canvas c, List<Offset> pts, Color color) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    c.drawPath(path..close(), _fill..color = color);
  }

  /// The body in art units: main fill, dark right third, ribbon, top bevel
  /// and the two `?` marks. [label] null = a label-less box.
  static void _body(Canvas c, MysteryBoxLook look) {
    const body = bodyBounds;
    _rect(c, body, look.main);
    _rect(c, const Rect.fromLTRB(18, -10, 40, 42), look.dark);
    _rect(
      c,
      const Rect.fromLTRB(-8, -10, 8, 42),
      look.ribbon.withValues(alpha: look.ribbon.a * .9),
    );
    _poly(c, const [
      Offset(-40, -10),
      Offset(40, -10),
      Offset(40, -4),
      Offset(-40, -4),
    ], const Color(0x2E000000));
    final label = look.label;
    if (label != null && label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w600,
            fontSize: label.length > 1 ? 22 : 30,
            color: look.labelColor.withValues(alpha: look.labelColor.a * .95),
          ),
        ),
        textDirection: p.TextDirection.ltr,
      )..layout();
      final baseline = tp.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      tp.paint(c, Offset(-14 - tp.width / 2, 30 - baseline));
      if (label.length == 1) {
        final side = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontFamily: 'Fredoka',
              fontWeight: FontWeight.w600,
              fontSize: 22,
              color: look.labelColor.withValues(alpha: .55),
            ),
          ),
          textDirection: p.TextDirection.ltr,
        )..layout();
        final sideBaseline = side.computeDistanceToActualBaseline(
          TextBaseline.alphabetic,
        );
        side.paint(c, Offset(30 - side.width / 2, 30 - sideBaseline));
      }
    }
  }

  /// The lid in art units, with style A's white bow. [lid] null = closed.
  static void _lid(Canvas c, MysteryBoxLook look, MysteryBoxLid? lid) {
    c.save();
    if (lid != null && lid.phase == MysteryBoxPhase.lidOff) {
      c.translate(lid.lift, lid.drop);
      c.rotate(lid.angle);
    }
    _rect(c, lidBounds, look.main);
    _rect(c, const Rect.fromLTRB(22, -24, 46, -8), look.dark);
    _rect(c, const Rect.fromLTRB(-9, -24, 9, -8), look.ribbon);
    _poly(c, const [
      Offset(-2, -24),
      Offset(-20, -40),
      Offset(-24, -30),
      Offset(-8, -24),
    ], look.ribbon);
    _poly(c, const [
      Offset(2, -24),
      Offset(20, -40),
      Offset(24, -30),
      Offset(8, -24),
    ], look.ribbon);
    _poly(c, const [
      Offset(-2, -24),
      Offset(-20, -40),
      Offset(-16, -28),
    ], const Color(0x1F000000));
    c.restore();
  }

  /// Draws the box centred at the canvas origin. [size] is the style A 80
  /// reference width (the pair box passes its 44.4 pt equivalent). [lid]
  /// null = the default closed pose; [drawBody] false draws only the lid
  /// (the pair's flying-lid bit), and the normal reveal order is body, lid.
  static void paint(
    Canvas c,
    MysteryBoxLook look, {
    required double size,
    MysteryBoxLid? lid,
    bool drawBody = true,
    bool drawLid = true,
  }) {
    if (size <= 0 || (!drawBody && !drawLid)) return;
    final k = size / referenceSize;
    c.save();
    c.scale(k);
    if (lid != null && lid.phase == MysteryBoxPhase.shake) {
      c.translate(0, lid.hop);
      c.rotate(lid.wobble);
    }
    if (drawBody) _body(c, look);
    if (drawLid) _lid(c, look, lid);
    c.restore();
  }

  /// The pair box's 44 pt drawing: the approved master at [PairConfig.boxHalf]
  /// × [PairConfig.boxScale] without a label (the reward tag carries the
  /// word). Kept here so no second box path exists in the run.
  static void paintPair(
    Canvas c, {
    required Color main,
    required Color dark,
    required double size,
    bool lid = true,
    MysteryBoxLid? lidState,
  }) => paint(
    c,
    MysteryBoxLook.colours(main, dark, label: null),
    size: size,
    drawLid: lid,
    lid: lidState ?? const MysteryBoxLid.closed(),
  );

  /// A standalone widget-style drawable for the level tile and popups.
  static void paintTile(
    Canvas c,
    MysteryBoxTier tier, {
    double size = 56,
    String? label = '?',
    MysteryBoxLid lid = const MysteryBoxLid.closed(),
  }) => paint(
    c,
    MysteryBoxLook.tier(tier, label: label),
    size: size,
    lid: lid,
  );
}

/// A component wrapper for the master (level tile, chest, leaderboard gifts,
/// Star Road tiles). It never owns box geometry; [look], [size] and [lid]
/// are the only parameters. [animation] steps a deterministic reveal when
/// [elapsed] is advanced.
class MysteryBoxComponent extends PositionComponent {
  MysteryBoxComponent({
    required this.look,
    required this.boxSize,
    this.lid = const MysteryBoxLid.closed(),
    this.animation,
    super.position,
    super.priority,
  });

  final MysteryBoxLook look;
  final double boxSize;
  MysteryBoxLid lid;
  final MysteryBoxAnimation? animation;
  double elapsed = 0;

  @override
  void update(double dt) {
    super.update(dt);
    elapsed += dt;
    final anim = animation;
    if (anim != null) lid = anim.at(elapsed);
  }

  @override
  void render(Canvas canvas) =>
      MysteryBox.paint(canvas, look, size: boxSize, lid: lid);
}
