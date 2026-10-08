import 'dart:ui';

import 'package:flame/components.dart';

import '../config/hud_config.dart';
import 'name_chip.dart';
import 'run_hud.dart';

/// §5.7 the versus bar (x 60 → 260): two 90 × 38 boxes at x 60 (you: pink,
/// dark-pink avatar square on the outside, soft-pink score) and x 170 (the
/// opponent: stage foreground, darker avatar square on the outside, score
/// in the stage background colour), "VS" between them, name chips below.
/// The opponent box flashes a 3 pt gold outline whenever their score
/// rises. Only added when the run has an opponent (solo: no bar).
///
/// WP-2d placeholder: the opponent's score replays their recorded
/// timeline on `runClock` ([OpponentRun.scoreAt]); WP-5b (`VersusService`)
/// owns the live parts (avatars, out state, the duel).
class VersusBar extends PositionComponent {
  VersusBar(this.hud) : super(position: Vector2.zero());

  final RunHud hud;

  late final NameChip you = NameChip('You', HudConfig.youLeft);
  late final NameChip them = NameChip(
    hud.run.setup.opponent?.name ?? '',
    HudConfig.themLeft,
  );
  final HudText _vs = HudText(
    'VS',
    size: HudConfig.chipFont,
    color: HudConfig.plum,
    font: HudConfig.nameFont,
  );

  int _lastThem = 0;
  double _flash = 0;

  /// The opponent's score now (their timeline at my runClock).
  int get theirScore =>
      hud.run.setup.opponent?.scoreAt(hud.run.state.runClock) ?? 0;

  int get myScore => hud.run.state.score;

  /// Seconds of gold outline flash left (tests).
  double get flash => _flash;

  @override
  void update(double dt) {
    super.update(dt);
    final s = theirScore;
    if (s > _lastThem) _flash = HudConfig.flashLength;
    _lastThem = s;
    if (_flash > 0) _flash = (_flash - dt).clamp(0.0, 1.0);
  }

  final Paint _p = Paint();
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void render(Canvas canvas) {
    final a = hud.rowOpacity;
    if (a <= 0) return;
    final g = hud.game;
    final fg = g.foregroundColor, bg = g.stageBackground;
    const top = HudConfig.rowTop, h = HudConfig.rowHeight;
    const w = HudConfig.boxWidth;
    // You: avatar outside (left).
    final youBox = Rect.fromLTWH(HudConfig.youLeft, top, w, h);
    _box(canvas, youBox, HudConfig.youBox, a);
    final youAv = Rect.fromLTWH(HudConfig.youLeft, top, h, h);
    _box(canvas, youAv, HudConfig.youAvatar, a);
    _avatar(canvas, youAv, HudConfig.soft, a);
    _score(
      canvas,
      '$myScore',
      Rect.fromLTRB(youAv.right, top, youBox.right, top + h).center,
      HudConfig.soft,
      a,
    );
    // Opponent: avatar outside (right).
    final themBox = Rect.fromLTWH(HudConfig.themLeft, top, w, h);
    _box(canvas, themBox, fg, a);
    final themAv = Rect.fromLTWH(themBox.right - h, top, h, h);
    _box(
      canvas,
      themAv,
      Color.lerp(const Color(0xFF000000), fg, HudConfig.themAvatarMix)!,
      a,
    );
    _avatar(canvas, themAv, bg, a);
    _score(
      canvas,
      '$theirScore',
      Rect.fromLTRB(themBox.left, top, themAv.left, top + h).center,
      bg,
      a,
    );
    if (_flash > 0) {
      _stroke
        ..strokeWidth = HudConfig.flashStroke
        ..color = HudConfig.gold.withValues(
          alpha: a * (_flash / HudConfig.flashLength),
        );
      canvas.drawRect(themBox.deflate(HudConfig.flashStroke / 2), _stroke);
    }
    _vs.paintCentred(
      canvas,
      Offset(HudConfig.vsLeft + HudConfig.vsWidth / 2, top + h / 2),
      opacity: a,
    );
    you.render(canvas, a);
    them.render(canvas, a);
  }

  void _box(Canvas canvas, Rect r, Color c, double a) {
    _p.color = c.withValues(alpha: c.a * a);
    canvas.drawRect(r, _p);
  }

  /// The mock's person glyph (head r 4.5 at (12, 8), shoulders from y 22)
  /// at 25 pt in [r].
  void _avatar(Canvas canvas, Rect r, Color c, double a) {
    final k = 25 / 24;
    final o = r.center - Offset(12 * k, 12 * k);
    _p.color = c.withValues(alpha: c.a * a);
    canvas.drawCircle(o + Offset(12 * k, 8 * k), 4.5 * k, _p);
    canvas.drawPath(
      Path()
        ..moveTo(o.dx + 3 * k, o.dy + 22 * k)
        ..arcToPoint(
          Offset(o.dx + 21 * k, o.dy + 22 * k),
          radius: Radius.circular(9 * k),
        )
        ..close(),
      _p,
    );
  }

  final Map<String, HudText> _scores = {};

  void _score(Canvas canvas, String s, Offset c, Color col, double a) {
    final t = _scores.putIfAbsent(
      s,
      () => HudText(s, size: HudConfig.scoreSize, color: col),
    );
    if (_scores.length > 40) _scores.clear();
    t.paintCentred(canvas, c, opacity: a, colorOverride: col);
  }
}
