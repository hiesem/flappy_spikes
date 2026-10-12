import 'dart:ui';

import '../../run_context.dart';
import '../hoop.dart';
import '../hoop_kind.dart';
import '../ring_painter.dart';

/// The normal hoop (PRD-2 §3.1, §5.1 M0 "clean vertical ring"): a vertical
/// ring standing in the flight path, drawn with master #3 ([RingPainter]) in
/// two layers — the back (right) half behind the bird, the front (left)
/// half over it. Colours: the equipped hoop skin (default pink `#EC008C` /
/// `#B0006B`), unless [Hoop.look] overrides them (tier gold, Big Hoops gold,
/// miss flash). Tilt and movement are modifiers (§3.10 / §3.11) carried by
/// the hoop itself. Rim ends bounce (§3.0.4); generic pass / miss / rim
/// handling lives in the run controller.
class NormalHoopKind extends HoopKind {
  @override
  HoopKindId get id => HoopKindId.normal;

  @override
  bool get usesTierLook => true;

  @override
  void buildVisual(Hoop h, RunContext c) {
    final skin = c.game.menu.items.look.hoop;
    h.paintBack = (canvas) =>
        paintRings(canvas, h, skin, front: false, t: c.s.runClock);
    h.front.paintFront = (canvas) =>
        paintRings(canvas, h, skin, front: true, t: c.s.runClock);
  }

  /// Paints one half of every ring of [h] in hoop-local coordinates (the
  /// hoop component already carries the position and tilt).
  /// PRD-2.2 §27.3 a reward ring whose reward was stripped (an activity
  /// started): the plain rings with the equipped skin, and its own look
  /// ([reward]: gift boxes, wheel, plasma) fading out on top over 0.2 s.
  static void paintStripped(
    Canvas canvas,
    Hoop h,
    RunContext c, {
    required bool front,
    required void Function() reward,
  }) {
    paintRings(
      canvas,
      h,
      c.game.menu.items.look.hoop,
      front: front,
      t: c.s.runClock,
    );
    final a = h.rewardAlpha;
    if (a <= 0) return;
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a));
    reward();
    canvas.restore();
  }

  static void paintRings(
    Canvas canvas,
    Hoop h,
    String skinId, {
    required bool front,
    double t = 0,
  }) {
    final look = h.look;
    for (final o in h.rings) {
      RingPainter.paintHalf(
        canvas,
        centre: Offset(0, o),
        opening: h.opening,
        front: front,
        skinId: skinId,
        colors: look.colors,
        strokeWidth: look.strokeWidth,
        dash: look.dash,
        glow: look.glow,
        glowBlur: look.glowBlur,
        opacity: look.opacity,
        t: t,
      );
    }
  }
}
