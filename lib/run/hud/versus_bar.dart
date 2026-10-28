import 'dart:ui';

import 'package:flame/components.dart';

import '../config/hud_config.dart';
import '../config/versus_config.dart';
import 'name_chip.dart';
// region P26-F9f
import '../../skins/art/card_frame_art.dart';
import '../../skins/look.dart';
// endregion
import 'run_hud.dart';

/// §5.7 the versus bar (x 60 → 260): two 90 × 38 boxes at x 60 (you: pink,
/// dark-pink avatar square on the outside, soft-pink score) and x 170 (the
/// opponent: stage foreground, darker avatar square on the outside, score
/// in the stage background colour), "VS" between them, name chips below.
/// The opponent box flashes a 3 pt gold outline whenever their score
/// rises. Only added when the run has an opponent (solo: no bar).
///
/// The opponent's score replays their recorded timeline on `runClock`
/// ([OpponentRun.scoreAt]): it stops with the run in pause, the revive
/// offer and the phoenix and slows with the Hourglass (§3.13). Once their
/// timeline has ended ([out], WP-5b) their score stays final and their box
/// (and name chip) is drawn dimmed ([VersusConfig.outOpacity]).
class VersusBar extends PositionComponent {
  // region P26-F9f
  VersusBar(this.hud) : super(position: Vector2.zero()) {
    // Resolve the lazy chips during setup, before the first HUD render.
    you;
    them;
  }
  // endregion

  final RunHud hud;

  /// §5.7 / §3.13 the own name: the generated nickname (WP-AV).
  // region P26-F9f
  late final NameChip you = NameChip(
    hud.game.myVersusName,
    HudConfig.youLeft,
    style: hud.game.menu.items.look.cardIdFor(CardKind.name),
  );
  // endregion
  late final NameChip them = NameChip(
    hud.run.setup.opponent?.name ?? '',
    HudConfig.themLeft,
    // region P26-F9f
    style: hud.run.setup.opponent?.look.cardIdFor(CardKind.name) ?? '',
    // endregion
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

  // region WP-5b — the opponent goes "out" at the end of their timeline
  /// §3.13 their recorded run is over at my runClock.
  bool get out =>
      hud.run.setup.opponent?.outAt(hud.run.state.runClock) ?? false;
  // endregion WP-5b

  /// Seconds of gold outline flash left (tests).
  double get flash => _flash;

  @override
  void update(double dt) {
    super.update(dt);
    final s = theirScore;
    if (s > _lastThem) _flash = HudConfig.flashLength;
    _lastThem = s;
    // region P26-F9f
    if (_flash > 0) _flash = (_flash - dt).clamp(0.0, 1.0);
    // endregion
  }

  // region P26-F9f
  final Paint _frameAlpha = Paint();

  static Path _clip(bool mine) {
    const top = HudConfig.rowTop, h = HudConfig.rowHeight;
    final avatar = Rect.fromLTWH(
      mine ? HudConfig.youLeft : HudConfig.themLeft + HudConfig.boxWidth - h,
      top,
      h,
      h,
    );
    final score = mine
        ? Rect.fromLTRB(
            avatar.right,
            top,
            HudConfig.youLeft + HudConfig.boxWidth,
            top + h,
          )
        : Rect.fromLTRB(HudConfig.themLeft, top, avatar.left, top + h);
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(avatar.inflate(CardFrameArt.outset(avatar.width))),
      Path()..addRect(score),
    );
  }

  static final Path _youClip = _clip(true), _themClip = _clip(false);

  double get cardTime => hud.game.reduceMotion ? 0 : hud.run.state.runClock;

  void _frame(
    Canvas canvas,
    Rect avatar,
    Look look,
    double opacity, {
    required bool back,
  }) {
    final id = look.cardIdFor(CardKind.frame);
    if (id.isEmpty || opacity <= 0) return;
    final layered = opacity < 1;
    if (layered) {
      canvas.saveLayer(
        null,
        _frameAlpha..color = Color.fromRGBO(255, 255, 255, opacity),
      );
    } else {
      canvas.save();
    }
    // O82: the score box covers ornaments, also while the whole row fades.
    canvas.clipPath(avatar.left == HudConfig.youLeft ? _youClip : _themClip);
    canvas.translate(avatar.center.dx, avatar.center.dy);
    if (back) {
      CardFrameArt.paintBack(canvas, id, size: avatar.width, t: cardTime);
    } else {
      CardFrameArt.paintFront(canvas, id, size: avatar.width, t: cardTime);
    }
    canvas.restore();
  }
  // endregion

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
    // region P26-F9f
    _frame(canvas, youAv, g.menu.items.look, a, back: true);
    // endregion
    _box(canvas, youAv, HudConfig.youAvatar, a);
    // WP-AV your sticker avatar (your bird, gear and hat).
    g.avatars.paint(canvas, youAv, g.menu.items.look, opacity: a);
    _score(
      canvas,
      '$myScore',
      Rect.fromLTRB(youAv.right, top, youBox.right, top + h).center,
      HudConfig.soft,
      a,
    );
    // Opponent: avatar outside (right); dimmed once they are out (WP-5b).
    final ta = out ? a * VersusConfig.outOpacity : a;
    final themBox = Rect.fromLTWH(HudConfig.themLeft, top, w, h);
    _box(canvas, themBox, fg, ta);
    final themAv = Rect.fromLTWH(themBox.right - h, top, h, h);
    // region P26-F9f
    final oppLook = hud.run.setup.opponent?.look ?? Look.defaults;
    _frame(canvas, themAv, oppLook, ta, back: true);
    // endregion
    _box(
      canvas,
      themAv,
      Color.lerp(const Color(0xFF000000), fg, HudConfig.themAvatarMix)!,
      ta,
    );
    // WP-AV their sticker avatar from their look (never a photo, never
    // the grey person icon), facing left.
    final opp = hud.run.setup.opponent;
    if (opp != null) {
      g.avatars.paint(canvas, themAv, opp.look, mirror: true, opacity: ta);
    }
    _score(
      canvas,
      '$theirScore',
      Rect.fromLTRB(themBox.left, top, themAv.left, top + h).center,
      bg,
      ta,
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
    // region P26-F9f
    you.render(canvas, a, t: cardTime);
    them.render(canvas, ta, t: cardTime);
    _frame(canvas, youAv, g.menu.items.look, a, back: false);
    _frame(canvas, themAv, oppLook, ta, back: false);
    // endregion
  }

  void _box(Canvas canvas, Rect r, Color c, double a) {
    _p.color = c.withValues(alpha: c.a * a);
    canvas.drawRect(r, _p);
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
