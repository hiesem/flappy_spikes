import 'dart:math' as math;
import 'dart:ui';

import '../../../../components/ui/mystery_box.dart';
import '../../../config/pair_config.dart';
import '../../../director/plans.dart' show PairReward;
import '../ring_arcs.dart';

/// The §5.20 gift box and its reward icons. The box itself is drawn only by
/// the 2.6 O99 master ([MysteryBox.paintPair]); this class keeps the run's
/// reward-coloured parameters and the icon art.
abstract final class GiftBox {
  static final Paint _p = Paint();

  /// The approved box look for [r]: the pair keeps the shield / comet /
  /// coins / score / FEVER reward colours, with no label (the gift tag
  /// carries the word), and the master's 44 pt size and white ribbon.
  static MysteryBoxLook look(PairReward r) {
    final st = PairConfig.style(r);
    return MysteryBoxLook.colours(st.main, st.dark, label: null);
  }

  /// The box centred at the origin (≈ 44 pt). [lid] false = the lid has
  /// flown off. Drawing is delegated to [MysteryBox.paintPair]; the caller
  /// owns the bob / tilt transform and the tag's skip fade.
  static void paint(Canvas c, PairReward r, {bool lid = true}) {
    MysteryBox.paintPair(
      c,
      main: PairConfig.style(r).main,
      dark: PairConfig.style(r).dark,
      size: PairConfig.boxHalf * 2 * PairConfig.boxScale,
      lid: lid,
    );
  }

  /// The lid with the ribbon and the bow. Used by the fly-away bit in
  /// `PairState.pick`; it is the same master lid, not a second drawing. The
  /// caller has already applied [PairConfig.boxScale], so the master draws
  /// at the same size as [paint].
  static void paintLid(Canvas c, PairReward r) {
    MysteryBox.paint(
      c,
      look(r),
      size: PairConfig.boxHalf * 2,
      drawBody: false,
      lid: const MysteryBoxLid.closed(),
    );
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
