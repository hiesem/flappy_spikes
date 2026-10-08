import 'dart:ui';

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../../../game/config.dart';
import '../../../config/pair_config.dart';
import '../../../director/plans.dart' show PairReward;
import 'gift_box.dart';

/// The §5.20 gift tag (mock `TH.gift.label`): a white luggage tag (notched
/// left end with a punched hole), 2 pt outline in the reward's dark shade,
/// the reward icon + word (Opificio 14 pt, dark shade). It hangs on a thin
/// string from the top of the top ring / the bottom of the bottom ring,
/// ≈ 30 pt out, tilted −3° and swaying ±3° — never in the gap or the
/// opening.
abstract final class GiftTag {
  static final Map<PairReward, TextPainter> _text = {};

  static TextPainter _label(PairReward r) => _text.putIfAbsent(r, () {
    final st = PairConfig.style(r);
    return TextPainter(
      text: TextSpan(
        text: st.tag,
        style: TextStyle(
          fontFamily: Config.uiFont,
          fontSize: PairConfig.tagFont,
          color: st.dark,
        ),
      ),
      textDirection: p.TextDirection.ltr,
    )..layout();
  });

  /// The tag's width (pt): the word + 40.
  static double width(PairReward r) => _label(r).width + 40;

  /// Paints the tag hanging from [anchor] (the ring's top / bottom point,
  /// ring-local) [above] or below it; [sway] in radians.
  static void paint(
    Canvas c,
    PairReward r,
    Offset anchor, {
    required bool above,
    double sway = 0,
  }) {
    final st = PairConfig.style(r);
    final w = width(r);
    final y = anchor.dy + (above ? -PairConfig.tagOut : PairConfig.tagOut);
    c.drawLine(
      anchor,
      Offset(anchor.dx - w / 2 + 10, y),
      Paint()
        ..strokeWidth = 1.4
        ..color = st.dark,
    );
    c.save();
    c.translate(anchor.dx, y);
    c.rotate(PairConfig.tagTilt + sway);
    final shape = Path()
      ..moveTo(-w / 2, -6)
      ..lineTo(-w / 2 + 8, -14)
      ..lineTo(w / 2, -14)
      ..lineTo(w / 2, 14)
      ..lineTo(-w / 2 + 8, 14)
      ..lineTo(-w / 2, 6)
      ..close();
    c.drawPath(shape, Paint()..color = const Color(0xFFFFFFFF));
    c.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = PairConfig.tagOutline
        ..strokeJoin = StrokeJoin.round
        ..color = st.dark,
    );
    c.drawCircle(Offset(-w / 2 + 7, 0), 2.2, Paint()..color = st.dark);
    GiftBox.icon(c, r, Offset(-w / 2 + 22, 0), 8);
    final tp = _label(r);
    tp.paint(c, Offset(-w / 2 + 33, 1 - tp.height / 2));
    c.restore();
  }
}
