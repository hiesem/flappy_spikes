import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart';

import '../components/home/menu_primitives.dart' show menuTextStyle;
import '../game/config.dart';
import '../game/flappy_game.dart';
import 'achievement_catalog.dart';

/// PRD-2.3.1 §12.5 the "ACHIEVEMENT UNLOCKED" pill: slides down from the
/// top (below the top spikes), holds, slides back up, then takes the next
/// unlock of [queue] (one pill at a time). The pill holds the 52 pt icon,
/// "ACHIEVEMENT UNLOCKED" (Opificio 11 pt, `Config.uiAccent`), the name
/// (18 pt plum) and "+N" points. A tap dismisses the pill early. When more
/// than [Config.achToastMaxPills] are queued, the last pill reads "+N more".
class AchievementToast extends PositionComponent
    with HasGameReference<FlappySpikesGame>, TapCallbacks {
  AchievementToast({required this.queue, this.onDone})
    : super(
        position: Vector2(
          (Config.worldWidth - Config.achToastWidth) / 2,
          Config.achToastTop,
        ),
        size: Vector2(Config.achToastWidth, Config.achToastHeight),
        priority: 60,
      );

  /// The tracker's toast queue (consumed from the front).
  final List<AchievementId> queue;
  final void Function()? onDone;

  /// The pill on screen: an achievement, or null for a "+N more" pill.
  AchievementId? current;

  /// "+N more" count of the summary pill (0 = a normal pill).
  int more = 0;

  /// Pills shown so far in this batch.
  int shown = 0;

  double _t = 0;
  ui.Image? _icon;

  /// The texts of the pill on screen (tests).
  String get label => 'ACHIEVEMENT UNLOCKED';
  String get title => more > 0 ? '+$more MORE' : (current?.title ?? '');
  String get points => more > 0 ? '' : '+${current?.points ?? 0}';

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _next();
  }

  bool _next() {
    _t = 0;
    _icon = null;
    if (queue.isEmpty) {
      current = null;
      more = 0;
      return false;
    }
    if (shown == Config.achToastMaxPills - 1 && queue.length > 1) {
      // The 5th pill of a longer queue sums up the rest.
      more = queue.length;
      current = queue.first;
      queue.clear();
    } else {
      more = 0;
      current = queue.removeAt(0);
    }
    shown++;
    final id = current;
    if (id != null) _loadIcon(id);
    return true;
  }

  Future<void> _loadIcon(AchievementId id) async {
    try {
      final img = await game.images.load(id.asset);
      if (identical(current, id)) _icon = img;
    } catch (_) {
      // A missing icon draws the pill without it (never breaks the page).
    }
  }

  /// Seconds into the pill on screen.
  double get time => _t;

  /// The vertical slide: 0 = in place, 1 = fully above the screen.
  double get _hidden {
    const s = Config.achToastSlide;
    const d = Config.achToastDuration;
    if (_t < s) return 1 - Curves.easeOutCubic.transform(_t / s);
    if (_t > d - s) {
      return Curves.easeInCubic.transform(((_t - (d - s)) / s).clamp(0, 1));
    }
    return 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= Config.achToastDuration) _advance();
  }

  void _advance() {
    if (!_next()) {
      removeFromParent();
      onDone?.call();
    }
  }

  /// A tap dismisses the pill early (it slides out from where it is).
  /// A tap dismisses the pill and still reaches what lies under it (the
  /// shop's back button, the results page), so the pill never blocks a tap.
  @override
  void onTapDown(TapDownEvent event) {
    dismiss();
    event.continuePropagation = true;
  }

  /// Slides the pill out from where it is (a tap; tests).
  void dismiss() {
    const out = Config.achToastDuration - Config.achToastSlide;
    if (_t < out) _t = out;
  }

  @override
  bool containsLocalPoint(Vector2 point) =>
      _hidden < .5 && super.containsLocalPoint(point);

  @override
  void render(Canvas canvas) {
    final h = size.y;
    final w = size.x;
    final dy = -_hidden * (Config.achToastTop + h + 8);
    canvas.save();
    canvas.translate(0, dy);
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(Config.achToastRadius),
    );
    canvas.drawRRect(
      rr.shift(const Offset(0, 4)),
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawRRect(rr, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRRect(
      rr.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Config.uiAccent,
    );
    const pad = (Config.achToastHeight - Config.achToastIcon) / 2;
    final icon = _icon;
    const iconRect = Rect.fromLTWH(
      pad + 2,
      pad,
      Config.achToastIcon,
      Config.achToastIcon,
    );
    if (icon != null) {
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(iconRect, const Radius.circular(12)),
      );
      canvas.drawImageRect(
        icon,
        Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble()),
        iconRect,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(iconRect, const Radius.circular(12)),
        Paint()..color = const Color(0xFFFCD9EE),
      );
    }
    final textLeft = iconRect.right + 10;
    final pts = _text(points, Config.achToastPointsSize, Config.uiAccent, w);
    final textRight = w - 20 - (points.isEmpty ? 0 : pts.width + 8);
    final labelP = _text(
      label,
      Config.achToastLabelSize,
      Config.uiAccent,
      textRight - textLeft,
      spacing: .08,
    );
    final nameP = _text(
      title,
      Config.achToastNameSize,
      Config.achToastPlum,
      textRight - textLeft,
    );
    final block = labelP.height + 2 + nameP.height;
    final top = (h - block) / 2;
    labelP.paint(canvas, Offset(textLeft, top));
    nameP.paint(canvas, Offset(textLeft, top + labelP.height + 2));
    if (points.isNotEmpty) {
      pts.paint(canvas, Offset(w - 20 - pts.width, (h - pts.height) / 2));
    }
    canvas.restore();
  }

  TextPainter _text(
    String s,
    double size,
    Color color,
    double maxWidth, {
    double spacing = 0,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: s,
        style: menuTextStyle(
          fontSize: size,
          color: color,
          letterSpacingEm: spacing,
          lineHeight: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    p.layout(maxWidth: maxWidth < 1 ? 1 : maxWidth);
    return p;
  }
}
