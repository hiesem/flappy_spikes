import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../game/config.dart';
import '../config/parts_config.dart';

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

  /// Band height: the text line plus the padding above and below.
  double get bandHeight => _text.height + 2 * PartsConfig.bannerPadding;

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
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a));
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, bandWidth, h), Paint()..color = color);
    final tp = _text;
    // Letter-spacing trails the last glyph; shift by half to stay centred.
    final spacing = fontSize * PartsConfig.bannerLetterSpacing;
    tp.paint(
      canvas,
      Offset((bandWidth - tp.width + spacing) / 2, PartsConfig.bannerPadding),
    );
    if (layer) canvas.restore();
    canvas.restore();
  }
}

/// Master #7 — the streak banner (PRD §3.0.9 #7, §3.4, §5.4
/// `screen_perfect4.html banner()`): the 10 tier names and colours of §3.4,
/// fixed font size per tier [28, 32, 34, 30, 32, 34, 34, 32, 34, 30],
/// duration 0.9 + 0.16 × min(tier, 6) s (1.06–1.86 s). Tiers above 10 stay
/// IMMORTAL ×10. Used by every perfect pass incl. comet, portal and rides.
class StreakBanner extends RunBanner {
  StreakBanner(int tier, {super.bandWidth})
    : tier = tier.clamp(1, names.length),
      super(lane: BannerLane.streak);

  static const List<String> names = [
    'PERFECT',
    'GREAT ×2',
    'AMAZING ×3',
    'INCREDIBLE ×4',
    'LEGENDARY ×5',
    'UNREAL ×6',
    'GODLIKE ×7',
    'MYTHIC ×8',
    'COSMIC ×9',
    'IMMORTAL ×10',
  ];

  static const List<Color> colors = [
    PartsConfig.pink,
    PartsConfig.lightPink,
    PartsConfig.gold,
    PartsConfig.deepPink,
    PartsConfig.plum,
    PartsConfig.gold,
    PartsConfig.lightPink,
    PartsConfig.pink,
    PartsConfig.deepPink,
    PartsConfig.plum,
  ];

  /// Displayed tier 1..10.
  final int tier;

  /// Duration for a tier (s).
  static double durationFor(int tier) =>
      PartsConfig.bannerBase +
      PartsConfig.bannerPerTier *
          math.min(math.max(tier, 1), PartsConfig.bannerTierCap);

  @override
  String get text => names[tier - 1];

  @override
  Color get color => colors[tier - 1];

  @override
  double get fontSize => PartsConfig.bannerFontSizes[tier - 1];

  @override
  double get duration => durationFor(tier);
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
}

/// Hosts the y-190 banner band (ARCH §1.10 master #7 host): lanes `streak`
/// (StreakBanner), `fever` (FeverBanner, WP-3c subclasses [RunBanner]) and
/// `element` (ElementBanner). A new banner **replaces** the one showing —
/// banners never stack. [busy] tells the [CollectSlot] queue to wait.
class BannerHost extends PositionComponent {
  BannerHost({super.priority});

  RunBanner? _current;

  /// The banner on screen, if any.
  RunBanner? get current => busy ? _current : null;

  /// True while a banner is on screen (or about to be mounted).
  bool get busy {
    final c = _current;
    return c != null && !c.done && !c.isRemoved && !c.isRemoving;
  }

  /// Shows [banner], replacing any banner on screen.
  T show<T extends RunBanner>(T banner) {
    final old = _current;
    if (old != null && !old.isRemoved) old.removeFromParent();
    _current = banner;
    add(banner);
    return banner;
  }

  /// Convenience: the streak banner for [tier].
  StreakBanner showStreak(int tier) => show(StreakBanner(tier));

  void clear() {
    final old = _current;
    if (old != null && !old.isRemoved) old.removeFromParent();
    _current = null;
  }
}
