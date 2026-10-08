import 'dart:math' as math;
import 'dart:ui';

import '../../../config/pair_config.dart';
import '../../../director/plans.dart' show PairReward;
import '../ring_arcs.dart';

/// The §5.20 gift box and the reward icons (mock `TH.gift.back` and
/// `icon()` of `build65.py`): flat, hard edges like the square bird.
abstract final class GiftBox {
  static final Paint _p = Paint();

  /// The box centred at the origin (≈ 44 pt): body in the main colour with
  /// the right half dark, a slightly wider lid in the light shade (right
  /// half main), a white ribbon cross and a white bow; [lid] false = the
  /// lid has flown off.
  static void paint(Canvas c, PairReward r, {bool lid = true}) {
    final st = PairConfig.style(r);
    const s = PairConfig.boxHalf;
    c.save();
    c.scale(PairConfig.boxScale);
    c.drawRect(
      const Rect.fromLTWH(-s, -s + 4, s * 2, s * 2 - 4),
      _p..color = st.main,
    );
    c.drawRect(
      const Rect.fromLTWH(0, -s + 4, s, s * 2 - 4),
      _p..color = st.dark,
    );
    _p.color = const Color(0xFFFFFFFF);
    c.drawRect(const Rect.fromLTWH(-3, -s + 4, 6, s * 2 - 4), _p);
    c.drawRect(const Rect.fromLTWH(-s, 2, s * 2, 5), _p);
    if (lid) paintLid(c, r);
    c.restore();
  }

  /// The lid with the ribbon and the bow (box-local, before the ×1.45).
  static void paintLid(Canvas c, PairReward r) {
    final st = PairConfig.style(r);
    const s = PairConfig.boxHalf;
    c.drawRect(
      const Rect.fromLTWH(-s - 2, -s - 2, s * 2 + 4, 7),
      _p..color = st.light,
    );
    c.drawRect(const Rect.fromLTWH(0, -s - 2, s + 2, 7), _p..color = st.main);
    _p.color = const Color(0xFFFFFFFF);
    c.drawRect(const Rect.fromLTWH(-3, -s - 2, 6, 7), _p);
    RingArcs.poly(c, const [
      Offset(0, -s - 2),
      Offset(-11, -s - 11),
      Offset(-9, -s - 1),
    ], const Color(0xFFFFFFFF));
    RingArcs.poly(c, const [
      Offset(0, -s - 2),
      Offset(11, -s - 11),
      Offset(9, -s - 1),
    ], const Color(0xFFFFFFFF));
    c.drawRect(const Rect.fromLTWH(-3, -s - 5, 6, 5), _p);
  }

  /// §5.20 the reward icon at [at], [size] pt (12 = the mock's unit).
  static void icon(Canvas c, PairReward r, Offset at, double size) {
    final st = PairConfig.style(r);
    c.save();
    c.translate(at.dx, at.dy);
    c.scale(size / 12);
    switch (r) {
      case PairReward.shield:
        final shield = Path()
          ..moveTo(0, -12)
          ..lineTo(10, -8)
          ..quadraticBezierTo(10, 6, 0, 12)
          ..quadraticBezierTo(-10, 6, -10, -8)
          ..close();
        c.drawPath(shield, _p..color = st.main);
        final side = Path()
          ..moveTo(0, -12)
          ..lineTo(10, -8)
          ..quadraticBezierTo(10, 6, 0, 12)
          ..close();
        c.drawPath(side, _p..color = const Color(0x59FFFFFF));
        c.drawPath(
          Path()
            ..moveTo(-5, 0)
            ..lineTo(-1, 4)
            ..lineTo(6, -4),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFFFFFFFF),
        );
      case PairReward.comet:
        RingArcs.poly(c, const [
          Offset(-2, -6),
          Offset(-14, -13),
          Offset(-6, -2),
        ], const Color(0xFFFFD54A));
        RingArcs.poly(c, const [
          Offset(-3, 4),
          Offset(-16, 2),
          Offset(-6, -2),
        ], const Color(0xFFFFB529));
        c.drawCircle(const Offset(3, 0), 8, _p..color = st.main);
        c.drawCircle(
          const Offset(5, -2),
          3.4,
          _p..color = const Color(0xFFFFE0B2),
        );
      case PairReward.coins:
        for (final o in const [Offset(-5, 4), Offset(5, 4), Offset(0, -4)]) {
          c.drawCircle(o, 7, _p..color = const Color(0xFFFFB529));
          c.drawCircle(
            o,
            4.3,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8
              ..color = const Color(0xFFFFFFFF),
          );
        }
      case PairReward.score:
        _p.color = const Color(0xFFFFB529);
        c.drawPath(
          Path()
            ..moveTo(-9, -11)
            ..lineTo(9, -11)
            ..quadraticBezierTo(9, 3, 0, 4)
            ..quadraticBezierTo(-9, 3, -9, -11),
          _p,
        );
        c.drawRect(const Rect.fromLTWH(-2, 3, 4, 5), _p);
        c.drawRect(const Rect.fromLTWH(-7, 8, 14, 4), _p);
        final handle = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = const Color(0xFFFFB529);
        c.drawArc(
          Rect.fromCircle(center: const Offset(-9, -6), radius: 4),
          math.pi * .5,
          math.pi,
          false,
          handle,
        );
        c.drawArc(
          Rect.fromCircle(center: const Offset(9, -6), radius: 4),
          -math.pi * .5,
          math.pi,
          false,
          handle,
        );
        RingArcs.star4(c, const Offset(0, -4), 4.5, const Color(0xFFFFFFFF));
      case PairReward.fever:
        c.drawPath(
          Path()
            ..moveTo(0, -13)
            ..quadraticBezierTo(12, 0, 8, 8)
            ..quadraticBezierTo(0, 15, -8, 8)
            ..quadraticBezierTo(-11, 0, 0, -13),
          _p..color = const Color(0xFFFF3B3B),
        );
        c.drawPath(
          Path()
            ..moveTo(0, -4)
            ..quadraticBezierTo(7, 4, 4, 8)
            ..quadraticBezierTo(0, 12, -4, 8)
            ..quadraticBezierTo(-6, 3, 0, -4),
          _p..color = const Color(0xFFFFB529),
        );
    }
    c.restore();
  }
}
