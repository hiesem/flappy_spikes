import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../game/config.dart';
import '../config/parts_config.dart';
import '../config/streak_config.dart';
import '../../game/paints.dart';

/// Which kind of banner occupies the y-190 band (ARCH §1.10).
enum BannerLane { streak, fever, element }

/// A full-width banner at y 190 (master #7's frame): a coloured band with
/// white Opificio text, letter-spacing 0.1 em, padding 6 pt, scaling in
/// (scaleY 0 → 1 over the first 12 %), holding to 75 % and scaling out with
/// a fade. Subclasses choose the text, colour, font size and duration;
/// [BannerHost] shows one at a time.
abstract class RunBanner extends PositionComponent {
  RunBanner({required this.lane, this.bandWidth = 320})
    : super(position: Vector2(0, PartsConfig.bannerTop));

  final BannerLane lane;

  /// Band width (pt, the 320 pt playfield).
  final double bandWidth;

  String get text;
  Color get color;
  double get fontSize;

  /// Total time on screen (s).
  double get duration;

  double _t = 0;
  double get time => _t;
  bool get done => _t >= duration;

  TextPainter? _tp;
  TextPainter get _text => _tp ??= TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: Config.uiFont,
        fontSize: fontSize,
        letterSpacing: fontSize * PartsConfig.bannerLetterSpacing,
        color: const Color(0xFFFFFFFF),
      ),
    ),
    textDirection: p.TextDirection.ltr,
  )..layout();

  // region WP-3c — optional subtitle line (PRD-2 §5.21 / §5.23 / §5.24)
  /// A second, smaller line under the title ("all three rings · +3
  /// coins", "+3 coins", "lucky spin · coins"), or null.
  String? get subtitle => null;

  /// Subtitle font size (pt; the lab mocks' 13 px).
  static const double subtitleSize = 13;

  TextPainter? _sp;
  TextPainter? get _sub {
    final s = subtitle;
    if (s == null) return null;
    return _sp ??= TextPainter(
      text: TextSpan(
        text: s,
        style: const TextStyle(
          fontFamily: Config.uiFont,
          fontSize: subtitleSize,
          color: Color(0xFFFFFFFF),
        ),
      ),
      textDirection: p.TextDirection.ltr,
    )..layout();
  }
  // endregion WP-3c

  /// Band height: the text line plus the padding above and below.
  double get bandHeight =>
      _text.height +
      2 * PartsConfig.bannerPadding +
      (_sub == null ? 0 : _sub!.height);

  /// (scaleY, opacity) at [t] seconds: the §5.4 keyframes.
  (double, double) curveAt(double t) {
    final k = duration <= 0 ? 1.0 : (t / duration).clamp(0.0, 1.0);
    const kin = PartsConfig.bannerInShare, hold = PartsConfig.bannerHoldShare;
    if (k < kin) return (k / kin, 1);
    if (k <= hold) return (1, 1);
    final u = (k - hold) / (1 - hold);
    return (1 - u, 1 - u);
  }

  @override
  Future<void> onLoad() async {
    size = Vector2(bandWidth, bandHeight);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (done) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final (sy, a) = curveAt(_t);
    if (sy <= 0 || a <= 0) return;
    final h = bandHeight;
    canvas.save();
    canvas.translate(0, h / 2);
    canvas.scale(1, sy);
    canvas.translate(0, -h / 2);
    final layer = a < 1;
    if (layer) {
      canvas.saveLayer(null, layerPaint(a));
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, bandWidth, h), fillPaint(color));
    final tp = _text;
    // Letter-spacing trails the last glyph; shift by half to stay centred.
    final spacing = fontSize * PartsConfig.bannerLetterSpacing;
    tp.paint(
      canvas,
      Offset((bandWidth - tp.width + spacing) / 2, PartsConfig.bannerPadding),
    );
    final sub = _sub;
    if (sub != null) {
      sub.paint(
        canvas,
        Offset(
          (bandWidth - sub.width) / 2,
          PartsConfig.bannerPadding + tp.height,
        ),
      );
    }
    if (layer) canvas.restore();
    canvas.restore();
  }
}

/// Master #7 — the streak banner (PRD §3.0.9 #7, §3.4, §5.4
/// `screen_perfect4.html banner()`; names and colours PRD-2.2 §29,
/// `screen_streak_names.html`): the text and colour of perfect streak
/// [streak] (`StreakConfig.nameFor` / `colourFor`: 50 names, then FLAPPY
/// GOD ×n; 10 rotating colours), the font shrinking for long names
/// ([ElementBanner.autoSize]: min(34, 300 / (characters × 0.72))),
/// duration 0.9 + 0.16 × min(streak, 6) s (1.06–1.86 s). Used by every
/// perfect pass incl. comet, portal and rides.
class StreakBanner extends RunBanner {
  StreakBanner(int streak, {super.bandWidth})
    : streak = math.max(1, streak),
      super(lane: BannerLane.streak);

  /// The perfect streak shown (≥ 1; no cap).
  final int streak;

  /// The tier shown (streak capped at `StreakConfig.tierCap`; effects).
  int get tier => math.min(streak, StreakConfig.tierCap);

  /// Duration for a streak / tier (s).
  static double durationFor(int tier) =>
      PartsConfig.bannerBase +
      PartsConfig.bannerPerTier *
          math.min(math.max(tier, 1), PartsConfig.bannerTierCap);

  @override
  String get text => StreakConfig.nameFor(streak);

  @override
  Color get color => StreakConfig.colourFor(streak);

  @override
  double get fontSize => ElementBanner.autoSize(text);

  @override
  double get duration => durationFor(streak);
}

/// An element banner (TRAIN ×3, BULLSEYE!, LUCKY SPIN, PERFECT LINE,
/// HATCHED!, ×2 LOST, PIGGY BANK, JAR FULL!, powerup names, SAVED!,
/// LOCKED! …) in the same band and animation as the streak banner.
class ElementBanner extends RunBanner {
  ElementBanner(
    this.text, {
    this.color = PartsConfig.pink,
    double? fontSize,
    double? duration,
    super.bandWidth,
    super.lane = BannerLane.element,
    this.subtitle,
  }) : fontSize = fontSize ?? autoSize(text),
       duration = duration ?? 1.2;

  /// Auto size for free text: min(34, 300 / (len × 0.72)) (the 5.3 rule),
  /// so long names still fit the 320 pt band.
  static double autoSize(String text) =>
      math.min(34, (300 / (text.length * .72)).floorToDouble());

  @override
  final String text;
  @override
  final Color color;
  @override
  final double fontSize;
  @override
  final double duration;

  @override
  final String? subtitle;
}

/// Hosts the y-190 banner band (ARCH §1.10 master #7 host): lanes `streak`
/// (StreakBanner), `fever` (FeverBanner, WP-3c subclasses [RunBanner]) and
/// `element` (ElementBanner). A new banner **replaces** the one showing —
/// banners never stack. [busy] tells the [CollectSlot] queue to wait.
class BannerHost extends PositionComponent {
  BannerHost({super.priority});

  static final Expando<BannerHost> _hosts = Expando('BannerHost');

  /// The one banner host under [parent], created at [priority] the first
  /// time (WP-2b): the streak, FEVER and element banners all share it, so a
  /// new banner replaces the one showing instead of stacking. Safe to call
  /// several times in one frame (before the host is mounted).
  static BannerHost ensureIn(Component parent, {int priority = 18}) {
    final existing = _hosts[parent];
    if (existing != null && !existing.isRemoving && !existing.isRemoved) {
      return existing;
    }
    final host = BannerHost(priority: priority);
    _hosts[parent] = host;
    parent.add(host);
    return host;
  }

  RunBanner? _current;

  // region WP-G3 — banners inside a ride scene (PRD-2.2 §18.1)
  /// PRD-2.2 §18.1 while a portal ride runs, its scene layer draws this
  /// host (between the scene's backdrop and objects, at 50 %) through
  /// [renderInScene]; the host's own pass then draws nothing. Wherever the
  /// host lives (the HUD now, the background banner layer of §12 later),
  /// the same switch moves it into the scene.
  bool drawnByScene = false;

  @override
  void renderTree(Canvas canvas) {
    if (drawnByScene) return;
    super.renderTree(canvas);
  }

  /// PRD-2.2 §18.1 draws the banners (same place, same colours) at
  /// [opacity] for the ride scene's layer.
  void renderInScene(Canvas canvas, double opacity) {
    if (opacity <= 0 || children.isEmpty) return;
    final layer = opacity < 1;
    if (layer) {
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)),
      );
    }
    super.renderTree(canvas);
    if (layer) canvas.restore();
  }
  // endregion WP-G3

  /// The banner on screen, if any.
  RunBanner? get current => busy ? _current : null;

  /// True while a banner is on screen (or about to be mounted).
  bool get busy {
    final c = _current;
    return c != null && !c.done && !c.isRemoved && !c.isRemoving;
  }

  // region WP-3c — the FEVER lane (PRD-2 §3.19 / §5.18)
  /// The FEVER! banner shows **together with** the tier banner, above it
  /// (§3.19 "a big FEVER! banner (above the tier banner)"): banners of the
  /// [BannerLane.fever] lane use their own slot (a new FEVER! replaces the
  /// previous one); streak and element banners keep replacing each other.
  PositionComponent? _fever;

  /// The FEVER! banner on screen (tests).
  PositionComponent? get fever =>
      _fever != null && !_fever!.isRemoved && !_fever!.isRemoving
      ? _fever
      : null;

  /// Shows [banner] in the FEVER slot.
  T showFever<T extends PositionComponent>(T banner) {
    final old = _fever;
    if (old != null && !old.isRemoved) old.removeFromParent();
    _fever = banner;
    add(banner);
    return banner;
  }
  // endregion WP-3c

  /// Shows [banner], replacing any banner on screen.
  T show<T extends RunBanner>(T banner) {
    if (banner.lane == BannerLane.fever) return showFever(banner);
    final old = _current;
    if (old != null && !old.isRemoved) old.removeFromParent();
    _current = banner;
    add(banner);
    return banner;
  }

  /// Convenience: the streak banner for [tier].
  /// PRD-2.2 §29 the banner of perfect streak [streak] (not the tier).
  StreakBanner showStreak(int streak) => show(StreakBanner(streak));

  void clear() {
    final old = _current;
    if (old != null && !old.isRemoved) old.removeFromParent();
    _current = null;
    final f = _fever;
    if (f != null && !f.isRemoved) f.removeFromParent();
    _fever = null;
  }
}
