import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../config/feather_config.dart';
import '../effects/coin_icon.dart';
import '../effects/easing.dart';
import '../effects/gold_sticker.dart';
import '../effects/particle_pool.dart';
import '../effects/shock_ring.dart';
import '../run_controller.dart';
import 'banner_layer.dart';
import 'collect_slot.dart';
import 'run_hud.dart';

/// The run HUD's collect layer (PRD-2 §3.15 / §3.16, ARCH §1.10): the one
/// shared [CollectSlot] (feather tray / puzzle pill, one at a time, Q37 /
/// Q42), the screen-space particle pool for the fetch trails, landing
/// sparkles and confetti, and the gold rings ([ShockRing]). Lives in the
/// [RunHud] (viewport, real time); a death clears it with the other HUD
/// parts and [ensureFor] builds a new one after a revive. The text parts are
/// drawn in the run's banner layer instead (PRD-2.2 §12.1 / §12.2), behind
/// the gameplay: the stickers ("BONUS UNLOCKED!", "PICTURE COMPLETE") and the
/// puzzle's collect text ("n/4", "+N") through [labels] in [bannerLayer].
/// Owner 2026-10-20 (2.5.0 47): the rest is drawn there too ([view]): the
/// slot (feather tray / puzzle pill), the trails, sparkles, confetti and
/// rings sit behind the hoops, bird and pickups, over the score circle. The
/// layer itself stays in the HUD for its clock and life cycle.
class CollectLayer extends PositionComponent
    with HasGameReference<FlappySpikesGame> {
  CollectLayer(this.run, this.bannerLayer)
    : super(priority: CollectConfig.priority);

  final RunController run;

  /// The run's banner layer, where the stickers and the collect text are
  /// drawn.
  final RunBannerLayer bannerLayer;

  /// The banner-layer part of this layer's collect text (see [CollectLabels]).
  late final CollectLabels labels = CollectLabels(this);

  /// Draws this layer's slot and effects in the banner layer, under
  /// [labels] (see [CollectView]).
  late final CollectView view = CollectView(this);

  static final Expando<CollectLayer> _layers = Expando('CollectLayer');

  /// The collect layer of [run]'s HUD, created on first use.
  static CollectLayer ensureFor(RunController run) {
    final hud = RunHud.ensureFor(run);
    final existing = _layers[hud];
    if (existing != null && !existing.isRemoving && !existing.isRemoved) {
      return existing;
    }
    final layer = CollectLayer(run, hud.bannerLayer);
    _layers[hud] = layer;
    hud.add(layer);
    return layer;
  }

  /// The layer of [run]'s HUD, if one is up.
  static CollectLayer? of(RunController run) {
    final hud = RunHud.of(run);
    if (hud == null) return null;
    final l = _layers[hud];
    if (l == null || l.isRemoving || l.isRemoved) return null;
    return l;
  }

  /// The shared slot at (160, [CollectConfig.slotY]). It does not wait for
  /// the banner band: the slot sits under it (see [CollectConfig.slotY]).
  final CollectSlot slot = CollectSlot(
    centre: Vector2(CollectConfig.slotX, CollectConfig.slotY),
  );

  /// Screen-space pool (fetch trails, sparkles, confetti).
  final ParticlePool pool = ParticlePool(priority: 2);

  static final EffectPool<ShockRing> _rings = ShockRing.newPool();

  /// The coin sprite (master #14), once loaded.
  Image? coin;

  Color get fg => game.foregroundColor;
  Color get bg => game.stageBackground;

  /// The stage foreground at [p] over the background (the mocks' `mix`).
  Color mix(double p) => Color.lerp(bg, fg, p)!;

  @override
  Future<void> onLoad() async {
    add(slot);
    add(pool);
    bannerLayer.add(view);
    bannerLayer.add(labels);
    try {
      coin = await CoinIcon.load(game.images);
    } catch (_) {
      coin = null;
    }
  }

  /// The labels leave the banner layer with this layer (PRD-2.2 §12.4); the
  /// slot's items drop their stickers in the slot's own removal.
  @override
  void onRemove() {
    view.removeFromParent();
    labels.removeFromParent();
    super.onRemove();
  }

  /// Nothing in the HUD: [view] draws this layer in the banner layer.
  @override
  void renderTree(Canvas canvas) {}

  /// This layer's own drawing (slot, pool, rings), for [view].
  void paintTree(Canvas canvas) => super.renderTree(canvas);

  /// A gold ring growing [from] → [to] pt (stroke [stroke], [length] s).
  void ring(
    Offset at, {
    required double from,
    required double to,
    double stroke = 2.5,
    double length = .4,
    Color color = const Color(0xFFFFB529),
  }) {
    add(
      _rings.obtain().play(
        at,
        rx: to,
        color: color,
        length: length,
        scaleFrom: from / to,
        scaleTo: 1,
        strokeFrom: stroke,
      )..priority = 3,
    );
  }

  /// §5.14 / §5.15 landing sparkles: 6 at 60° steps, 110 pt/s.
  void sparkles(Offset at) {
    for (var i = 0; i < 6; i++) {
      final a = i * 1.047 + .3;
      pool.spawn(
        shape: ParticleShape.twinkle,
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * 110,
        vy: math.sin(a) * 110,
        w: 14,
        color: i.isOdd ? const Color(0xFFFFFFFF) : FeatherConfig.paleGold,
        life: .45,
        spin: 4,
        damp: 2.45,
      );
    }
  }

  /// §5.14 / §5.15 confetti: [n] squares flying up from [at].
  void confetti(Offset at, int n, math.Random r) {
    const cols = [
      Color(0xFFEC008C),
      Color(0xFFFFB529),
      Color(0xFFFCD9EE),
      Color(0xFFFF4FB7),
    ];
    for (var i = 0; i < n; i++) {
      final a = -math.pi * (.05 + .9 * r.nextDouble());
      final v = 150 + r.nextDouble() * 180;
      pool.spawn(
        x: at.dx,
        y: at.dy,
        vx: math.cos(a) * v,
        vy: math.sin(a) * v,
        w: 5 + r.nextDouble() * 5,
        color: cols[i % 4],
        life: .7 + r.nextDouble() * .4,
        gravity: 620,
        spin: (r.nextDouble() * 2 - 1) * 10,
        fadePow: 2,
        drag: 2.4,
      );
    }
  }

  /// The slot's centre on screen now (with its fade slide).
  Offset get slotCentre {
    final item = slot.current;
    final dy = item == null
        ? 0.0
        : CollectSlot.offsetFor(slot.alphaAt(item, slot.time));
    return Offset(slot.position.x, slot.position.y + dy);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final item = slot.current;
    if (item is CollectTimeline) item.advance(this, slot.time);
  }
}

/// Owner 2026-10-20 (2.5.0 47): the [CollectLayer]'s slot and effects, drawn
/// in the run's banner layer (behind the gameplay, over the score circle),
/// under the [CollectLabels]. The layer keeps its HUD clock; this only draws.
class CollectView extends PositionComponent {
  CollectView(this.layer) : super(priority: 1);

  final CollectLayer layer;

  @override
  void render(Canvas canvas) => layer.paintTree(canvas);
}

/// The part of a [CollectLayer] that lives in the run's banner layer (PRD-2.2
/// §12.1): the collect text of the item on the slot (its `paintBanner`),
/// drawn behind the gameplay. It is drawn at the slot's centre and fade (the
/// same place as the item in the HUD), on the slot's clock, so its timing is
/// the pill's and it does not follow the run's Hourglass or pause.
class CollectLabels extends PositionComponent {
  CollectLabels(this.layer) : super(priority: 2);

  final CollectLayer layer;

  @override
  void render(Canvas canvas) {
    final slot = layer.slot;
    final item = slot.current;
    if (item is! CollectTimeline) return;
    final t = slot.time;
    final alpha = slot.alphaAt(item, t);
    if (alpha <= 0) return;
    canvas.save();
    canvas.translate(
      slot.position.x,
      slot.position.y + CollectSlot.offsetFor(alpha),
    );
    item.paintBanner(canvas, alpha, t);
    canvas.restore();
  }
}

/// A [CollectSlotItem] with its own timeline of one-shot cues (sounds,
/// rings, sparkles, stickers) driven by the slot's clock.
abstract class CollectTimeline implements CollectSlotItem {
  double _prev = -1;

  /// Called every frame while shown, with the slot time.
  void advance(CollectLayer layer, double t) {
    final prev = _prev;
    _prev = t;
    cues(layer, prev, t);
  }

  /// Fire the cues whose time lies in (prev, t].
  void cues(CollectLayer layer, double prev, double t);

  /// PRD-2.2 §12.1: the item's collect text, drawn by the run's banner layer
  /// ([CollectLabels]) at the slot's centre with the item's [alpha] and slot
  /// time [t]. Nothing by default: an item without text draws none there.
  void paintBanner(Canvas canvas, double alpha, double t) {}

  static bool crossed(double prev, double t, double at) =>
      prev < at && t >= at;

  /// §5.14 / §5.15 slot punch: up to ×(1 + [amp]) over [length] s.
  static double punch(double t, double? at, double amp, double length) {
    if (at == null) return 1;
    final u = t - at;
    if (u < 0 || u >= length) return 1;
    return 1 + amp * math.sin(math.pi * u / length) * math.exp(-u * 3);
  }

  final List<GoldSticker> _stickers = [];

  /// Pops a collect sticker ([GoldSticker.collect]) at [at] (screen
  /// coordinates) in the run's banner layer (PRD-2.2 §12.2); it fades with
  /// the item.
  void sticker(CollectLayer layer, String text, Offset at) {
    final s = GoldSticker.collect(text, position: Vector2(at.dx, at.dy))
      ..priority = 1;
    _stickers.add(s);
    layer.bannerLayer.add(s);
  }

  void fadeStickers(double alpha) {
    for (final s in _stickers) {
      s.opacity = alpha;
    }
  }

  @override
  void onGone() => _dropStickers();

  /// The slot was torn down with the item on it (PRD-2.2 §12.4): its
  /// stickers go too, so a death leaves none behind.
  @override
  void onDiscard() => _dropStickers();

  void _dropStickers() {
    for (final s in _stickers) {
      s.removeFromParent();
    }
    _stickers.clear();
  }
}

/// One-line Opificio text, cached per string (collect HUD).
class CollectText {
  static final Map<(String, double, int), TextPainter> _cache = {};

  /// PRD-2.2 §33.4 item 6: drops the cached painters and frees their
  /// native paragraphs.
  static void clearCache() {
    for (final painter in _cache.values) {
      painter.dispose();
    }
    _cache.clear();
  }

  /// Cached painters (tests).
  static int get cachedCount => _cache.length;

  static TextPainter of(String s, double size, Color c, {double spacing = 0}) {
    if (_cache.length > 400) clearCache();
    return _cache.putIfAbsent(
        (s, size, c.toARGB32() ^ spacing.hashCode),
        () => TextPainter(
          text: TextSpan(
            text: s,
            style: TextStyle(
              fontFamily: Config.uiFont,
              fontSize: size,
              letterSpacing: spacing,
              color: c,
              height: 1,
            ),
          ),
          textDirection: p.TextDirection.ltr,
        )..layout(),
      );
  }

  static double eob(double u) => Ease.outBack(u.clamp(0.0, 1.0));
}
