import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../../progression/star_road.dart';
import '../../run/config/puzzle_config.dart';
import '../../run/effects/coin_icon.dart';
// region P26-POL4
import '../../run/effects/shock_ring.dart';
// endregion P26-POL4
import '../../run/effects/twinkle.dart';
import '../../run/pickups/feather_pickup.dart';
import '../../run/pickups/puzzle_piece_pickup.dart';
import '../../skins/look.dart' show Rarity;
import '../home/menu_primitives.dart';
import '../noads_celebration.dart' show NoAdsCelebrationRays;
import '../star_road/star_road_art.dart';
import '../star_road/star_road_card.dart' show starRoadRewardLabel;
import '../ui/confetti.dart';
import '../ui/live_effects.dart';
import '../ui/mystery_box.dart';
import '../ui/p1_popup.dart';

double _seg(double t, double start, double duration) =>
    ((t - start) / duration).clamp(0.0, 1.0);

double _easeOut(double u) => Curves.easeOutCubic.transform(u);

double _easeBack(double u) {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  return 1 + c3 * math.pow(u - 1, 3) + c1 * math.pow(u - 1, 2);
}

/// The Star Road Home popup (PRD-2.6 O37 / O75 / O91): a P1 card with the
/// approved tier badge, up to three waiting reward tiles and GO TO STAR ROAD.
/// The game owns the once-a-day selection policy and the road itself.
class StarRoadPopup extends P1Popup {
  StarRoadPopup({
    required this.road,
    required this.onGo,
    required super.onDismiss,
  }) : assert(road.claimable.isNotEmpty),
       claimable = List.unmodifiable(road.claimable);

  final StarRoad road;
  final void Function() onGo;

  /// The complete waiting list at the moment the popup opened (snapshot).
  final List<int> claimable;

  late final PositionComponent badge;
  late final MenuButton goButton;
  late final MenuButton closeButton;
  late final MenuText title;
  late final MenuText subtitle;
  late final MenuText line;
  late final _FadeGroup _titleGroup;
  late final _FadeGroup _subtitleGroup;
  late final _FadeGroup _lineGroup;
  late final _FadeGroup _goGroup;
  late final _FadeGroup _rayGroup;
  late final NoAdsCelebrationRays rays;
  // region P26-POL4
  late final _BadgeGlow _badgeGlow;
  // endregion P26-POL4
  late final PulseEffect goPulse;
  late final LightStreak goStreak;
  late final List<StarRoadPopupTile> tiles = [];

  double elapsed = 0;
  int _badgeTier = -1;
  bool _landed = false;
  bool _celebrated = false;
  final List<bool> _tileCues = [];

  List<int> get shownTiers => claimable.take(3).toList(growable: false);
  int get hiddenTiers => math.max(0, claimable.length - 3);

  // region P26-POL4
  /// The badge glow's current opacity (tests / O91). Zero before landing.
  double get badgeGlowOpacity => _badgeGlow.glowOpacity;
  // endregion P26-POL4

  String get titleText => claimable.length > 1
      ? 'TIERS ${claimable.first}\u2013${claimable.last} REACHED'
      : 'TIER ${claimable.first} REACHED';
  String get subtitleText => claimable.length > 1
      ? '${claimable.length} REWARDS ARE WAITING'
      : 'A REWARD IS WAITING';

  @override
  Future<void> buildCard(PositionComponent card) async {
    cardHeight = 364;
    final coin = await CoinIcon.load(game.images);
    final close = Sprite(await game.images.load('menu/close.png'));

    // approvals_v26/star_road_popup.html: the 128 pt header is pink (the P1
    // card's shared header band), so the pale STAR ROAD label and the gold
    // rays read against it instead of the cream card.
    card.add(
      RectangleComponent(
        size: Vector2(Config.p1PopupWidth, 128),
        paint: Paint()..color = Config.menuPink,
        priority: -30,
      ),
    );
    _rayGroup = _FadeGroup(size: Vector2(280, 128))..opacity = 0;
    rays = NoAdsCelebrationRays(
      rayCenter: const Offset(140, 53),
      motion: () => !game.reduceMotion && elapsed >= .25,
      size: Vector2(280, 128),
    );
    _rayGroup.priority = -20;
    _rayGroup.add(rays);
    card.add(_rayGroup);

    // region P26-POL4
    _badgeGlow = _BadgeGlow(this);
    card.add(_badgeGlow);
    // endregion P26-POL4

    badge = PositionComponent(
      position: Vector2(140, 53),
      size: Vector2.all(78),
      anchor: Anchor.center,
    );
    card.add(badge);

    card.add(
      MenuText(
        'STAR ROAD',
        fontSize: 12,
        color: Config.menuSoft,
        letterSpacingEm: .24,
        position: Vector2(140, 100),
        anchor: Anchor.topCenter,
      ),
    );

    title = MenuText(
      titleText,
      fontSize: 20,
      color: Config.menuPlum,
      letterSpacingEm: .06,
      position: Vector2(140, 14),
      anchor: Anchor.center,
    );
    _titleGroup = _FadeGroup(position: Vector2(0, 144), size: Vector2(280, 28))
      ..opacity = 0;
    _titleGroup.add(title);
    card.add(_titleGroup);

    subtitle = MenuText(
      subtitleText,
      fontSize: 10.5,
      color: const Color(0xFF8A8A8A),
      letterSpacingEm: .2,
      position: Vector2(140, 7.5),
      anchor: Anchor.center,
    );
    _subtitleGroup =
        _FadeGroup(position: Vector2(0, 172), size: Vector2(280, 15))
          ..opacity = 0;
    _subtitleGroup.add(subtitle);
    card.add(_subtitleGroup);

    final shown = shownTiers;
    final count = shown.length + (hiddenTiers > 0 ? 1 : 0);
    const tileWidth = 58.0;
    const gap = 10.0;
    final x0 = (280 - (count * tileWidth + (count - 1) * gap)) / 2;
    for (var i = 0; i < shown.length; i++) {
      final tile = StarRoadPopupTile(
        reward: starRoadReward(shown[i]),
        extra: null,
        index: i,
        coin: coin,
        appear: 1.05 + i * .14,
        position: Vector2(x0 + i * (tileWidth + gap) + tileWidth / 2, 229),
      );
      tiles.add(tile);
      card.add(tile);
    }
    if (hiddenTiers > 0) {
      final i = shown.length;
      final tile = StarRoadPopupTile(
        reward: null,
        extra: hiddenTiers,
        index: i,
        coin: coin,
        appear: 1.05 + i * .14,
        position: Vector2(x0 + i * (tileWidth + gap) + tileWidth / 2, 229),
      );
      tiles.add(tile);
      card.add(tile);
    }
    _tileCues.addAll(List.filled(tiles.length, false));

    line = MenuText(
      'They wait for you on the Star Road.',
      fontSize: 12.5,
      color: const Color(0xFF9A4D78),
      fontWeight: FontWeight.w600,
      position: Vector2(140, 9),
      anchor: Anchor.center,
    );
    _lineGroup = _FadeGroup(position: Vector2(0, 272), size: Vector2(280, 18))
      ..opacity = 0;
    _lineGroup.add(line);
    card.add(_lineGroup);

    goButton = MenuButton(
      position: Vector2(16, 298),
      size: Vector2(248, 50),
      color: Config.menuPink,
      onPressed: _pressGo,
      isActive: () => active && (game.reduceMotion || elapsed >= 1.55),
      children: [
        MenuText(
          'GO TO STAR ROAD',
          fontSize: 21,
          color: Config.menuSoft,
          position: Vector2(124, 25),
          anchor: Anchor.center,
        ),
      ],
    );
    goPulse = PulseEffect(
      goButton,
      amount: .025,
      glowColor: Config.menuGold.withValues(alpha: .2),
      glowBlur: 4,
    );
    goStreak = LightStreak(goButton);
    goButton.decorator
      ..addLast(goPulse)
      ..addLast(goStreak);
    _goGroup = _FadeGroup(size: Vector2(280, 364))..opacity = 0;
    _goGroup.add(goButton);
    card.add(_goGroup);

    closeButton = closeBox(close, onDismiss);
    card.add(closeButton);

    card.add(_BadgeFx(this));
  }

  void _setBadgeTier(int value) {
    if (_badgeTier == value) return;
    _badgeTier = value;
    for (final child in badge.children.whereType<StarRoadTierNode>().toList()) {
      badge.remove(child);
    }
    final node = StarRoadTierNode(
      tier: value,
      state: StarRoadNodeState.next,
      side: 74,
      labelSize: 16,
      labelColor: Config.menuPlum,
      position: Vector2(2, 2),
    );
    node.add(
      StarRoadStar(side: 50, position: Vector2(12, 12)),
    );
    badge.add(node);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    game.sound.play(Sfx.skDialog);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isLoaded) return;
    elapsed += dt;
    final t = elapsed;
    final still = game.reduceMotion;

    if (still) {
      cardPose.rest();
      _rayGroup.opacity = 1;
      rays.phase = 0;
      badge
        ..position = Vector2(140, 53)
        ..scale.setAll(1)
        ..angle = 0;
      _setBadgeTier(claimable.last);
      _titleGroup.opacity = 1;
      _subtitleGroup.opacity = 1;
      _lineGroup.opacity = 1;
      _goGroup.opacity = 1;
      goButton.position = Vector2(16, 298);
      goPulse.rest();
      goStreak.progress = null;
      for (final tile in tiles) {
        tile
          ..time = t
          ..opacity = 1
          ..scale.setAll(1);
      }
    } else {
      if (t < .62) _setBadgeTier(claimable.first - 1);
      final pu = _seg(t, 0, .24);
      cardPose.scale = pu < .6
          ? .82 + (1.04 - .82) * _easeOut(pu / .6)
          : 1.04 + (1 - 1.04) * ((pu - .6) / .4);

      final rayAlpha = _seg(t, .25, .4);
      _rayGroup.opacity = rayAlpha * (.88 + .12 * math.sin(t * 2.2));

      final b = _easeBack(_seg(t, .3, .32));
      final land = _seg(t, .62, .28);
      final squash = land > 0 && land < 1
          ? math.sin(land * math.pi) * (1 - land)
          : 0.0;
      final idle = t >= 1.95 ? 1.0 : _seg(t, .92, .4);
      badge
        ..position = Vector2(
          140,
          53 + (1 - b) * -40 + math.sin(t * 2.4) * 2 * idle,
        )
        ..scale = Vector2(
          (.4 + .6 * b) * (1 + .12 * squash),
          (.4 + .6 * b) * (1 - .1 * squash),
        )
        ..angle = math.sin(t * 1.7) * 2.5 * idle * math.pi / 180;

      if (t >= .62) _setBadgeTier(claimable.last);

      final titlePop = _seg(t, .8, .3);
      _titleGroup.opacity = _seg(t, .8, .1);
      title.scale.setAll(
        titlePop > 0 ? 1.35 + (1 - 1.35) * _easeBack(titlePop) : 1.35,
      );
      _subtitleGroup.opacity = _seg(t, .95, .25);
      _lineGroup.opacity = _seg(t, 1.4, .3);

      for (var i = 0; i < tiles.length; i++) {
        final tile = tiles[i];
        final u = _seg(t, tile.appear, .3);
        tile
          ..time = t
          ..opacity = u > 0 ? 1 : 0
          ..scale.setAll(_easeBack(u));
      }

      final goIn = _seg(t, 1.55, .3);
      _goGroup.opacity = goIn;
      goButton.position = Vector2(16, 298 + (1 - _easeOut(goIn)) * 16);
      // The shared pulse master (O91 "button breathes"); the design's
      // 1 + .025 sin(4t) becomes its 0..1 pulse value.
      goPulse.k = t >= 1.95 ? (1 - math.cos(t * 4)) / 2 : 0;
      if (t >= 1.95) {
        goStreak.at(t - 1.95);
      } else {
        goStreak.progress = null;
      }
    }

    if (!_landed && t >= .62) {
      _landed = true;
      game.sound.play(Sfx.lvUp);
      if (!still && !_celebrated) {
        _celebrated = true;
        _burst();
      }
    }
    for (var i = 0; i < tiles.length; i++) {
      if (!_tileCues[i] && t >= tiles[i].appear) {
        _tileCues[i] = true;
        game.sound.play(Sfx.vsPop);
      }
    }
  }

  void _burst() {
    // region P26-POL4
    card.add(
      ShockRing(priority: 2).play(
        const Offset(140, 53),
        rx: 22,
        color: const Color(0xFFFFFFFF),
        length: .45,
        scaleFrom: 1,
        scaleTo: 1,
        strokeFrom: 6,
        strokeTo: 1,
        grow: 62,
      ),
    );
    card.add(
      ShockRing(priority: 2).play(
        const Offset(140, 53),
        rx: 18,
        color: const Color(0xFFFFE082),
        length: .4,
        scaleFrom: 1,
        scaleTo: 1,
        strokeFrom: 6,
        strokeTo: 1,
        grow: 46,
      ),
    );
    // endregion P26-POL4
    card.add(
      ConfettiBurst.burst(
        origin: const Offset(140, 59),
        count: 46,
        speed: 240,
        up: 130,
        stars: true,
      ),
    );
    card.add(
      ConfettiBurst.burst(
        origin: const Offset(34, 6),
        count: 22,
        speed: 250,
        up: 60,
      ),
    );
    card.add(
      ConfettiBurst.burst(
        origin: const Offset(246, 6),
        count: 22,
        speed: 250,
        up: 60,
      ),
    );
  }

  void _pressGo() {
    if (!active || (!game.reduceMotion && elapsed < 1.55)) return;
    game.sound.play(Sfx.skTap);
    if (!game.reduceMotion) {
      // The popup is removed as soon as GO opens the road, so the puff lives
      // in the world (its coordinates already are world coordinates: the P1
      // popup sits at the origin).
      final p = position + card.position + goButton.position + Vector2(124, 25);
      game.world.add(
        ConfettiBurst.burst(
          origin: Offset(p.x, p.y),
          count: 16,
          speed: 150,
          up: 0,
          stars: true,
        ),
      );
    }
    onGo();
  }
}

class _FadeGroup extends PositionComponent with GroupOpacity {
  _FadeGroup({super.position, super.size});
}

// region P26-POL4
/// The white/gold radial glow behind the tier badge (mock `#pglow`). It is a
/// parameter of the popup's badge, drawn through one cached gradient shader.
class _BadgeGlow extends PositionComponent {
  _BadgeGlow(this.popup)
    : super(size: Vector2(280, 128), priority: -10);

  final StarRoadPopup popup;

  late final Shader _shader = Gradient.radial(
    const Offset(140, 53),
    80,
    const [
      Color(0xBFFFFFFF),
      Color(0x59FFE7A6),
      Color(0x00FFE7A6),
    ],
    const [0, .38, .7],
  );

  final Paint _paint = Paint();
  final Paint _layer = Paint();

  double get glowOpacity {
    if (popup.game.reduceMotion) return .35;
    final t = popup.elapsed;
    if (t < .62) return 0;
    final fade = (1 - _seg(t, .62, .5)).clamp(0.0, 1.0);
    return math.max(fade, .35 + .15 * math.sin(t * 2.6));
  }

  @override
  void render(Canvas canvas) {
    final opacity = glowOpacity;
    if (opacity <= 0) return;
    final rect = size.toRect();
    _paint.shader = _shader;
    _layer.color = Color.fromRGBO(
      255,
      255,
      255,
      opacity.clamp(0.0, 1.0).toDouble(),
    );
    canvas.saveLayer(rect, _layer);
    canvas.drawRect(rect, _paint);
    canvas.restore();
  }
}
// endregion P26-POL4

class _BadgeFx extends PositionComponent {
  _BadgeFx(this.popup) : super(size: Vector2(280, 128), priority: 2);

  final StarRoadPopup popup;

  static const _twinkles = <(double, double, double, double)>[
    (-62, 34, 5.5, 0),
    (66, 26, 4.5, 1.3),
    (-44, -2, 3.6, 2.1),
    (52, -8, 4, .7),
  ];

  @override
  void render(Canvas canvas) {
    if (popup.game.reduceMotion) return;
    final t = popup.elapsed;
    // region P26-POL4
    // The landing ring moved to the shared ShockRings in [_burst].
    // endregion P26-POL4
    if (t < .92) return;
    for (var i = 0; i < _twinkles.length; i++) {
      final (dx, dy, r, phase) = _twinkles[i];
      final ph = (t * .8 + phase) % 1.6;
      final u = ph < .8 ? math.sin(ph / .8 * math.pi) : 0.0;
      if (u <= 0) continue;
      final (scale, rotation, alpha) = Twinkle.curve(
        (ph / .8).clamp(0.0, 1.0),
      );
      Twinkle.paint(
        canvas,
        Offset(140 + dx, 53 + dy),
        r * 2.5 * scale,
        const Color(0xFFFFFFFF).withValues(alpha: alpha),
        rotation: rotation,
      );
    }
  }
}

class StarRoadPopupTile extends PositionComponent
    with GroupOpacity, HasGameReference<FlappySpikesGame> {
  StarRoadPopupTile({
    required this.reward,
    required this.extra,
    required this.index,
    required this.coin,
    required this.appear,
    super.position,
  }) : super(size: Vector2(58, 70), anchor: Anchor.center);

  final StarRoadReward? reward;
  final int? extra;
  final int index;
  final Image coin;
  final double appear;
  double time = 0;

  late final _RewardArt _art;

  Rarity? get rarity => switch (reward?.kind) {
    StarRoadRewardKind.rare => Rarity.rare,
    StarRoadRewardKind.epic => Rarity.epic,
    StarRoadRewardKind.legendary => Rarity.legendary,
    _ => null,
  };

  Color get border => switch (reward?.kind) {
    StarRoadRewardKind.coins => const Color(0xFFE5B04A),
    StarRoadRewardKind.feather || StarRoadRewardKind.piece => Config.menuGold,
    StarRoadRewardKind.rare ||
    StarRoadRewardKind.epic ||
    StarRoadRewardKind.legendary => rarity!.color,
    null => Config.menuGold,
  };

  Color get dark => switch (rarity) {
    Rarity.rare => const Color(0xFF0E6FA6),
    Rarity.epic => const Color(0xFF6A1A9C),
    Rarity.legendary => const Color(0xFFC98A00),
    _ => const Color(0xFFC98A00),
  };

  Color get background => rarity == null
      ? const Color(0xFFFFF8E6)
      : const Color(0xFFF4F4F4);

  String get label =>
      reward == null ? '+$extra' : starRoadRewardLabel(reward!);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _art = _RewardArt(
      reward: reward,
      extra: extra,
      coin: coin,
      position: Vector2(3, 0),
    );
    add(_art);
    add(_Shine(this, position: Vector2(3, 0)));
    add(
      MenuText(
        label,
        fontSize: 10,
        color: rarity == null ? const Color(0xFFC98A00) : dark,
        position: Vector2(29, 56),
        anchor: Anchor.topCenter,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    final box = _art.box;
    if (box == null) return;
    final ph = (time + index * .8) % 2.4;
    final wiggle = !game.reduceMotion && time >= 1.95 && ph < .5
        ? math.sin(ph * 28) * 6 * (1 - ph / .5)
        : 0.0;
    box.angle = wiggle * math.pi / 180;
  }

  @override
  void render(Canvas canvas) {
    const frame = Rect.fromLTWH(3, 0, 52, 52);
    canvas.drawRect(frame, Paint()..color = background);
    canvas.drawRect(
      const Rect.fromLTWH(3, 48, 52, 4),
      Paint()..color = dark,
    );
    canvas.drawRect(
      frame.deflate(1),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}

class _RewardArt extends PositionComponent {
  _RewardArt({
    required this.reward,
    required this.extra,
    required this.coin,
    super.position,
  }) : super(size: Vector2.all(52));

  final StarRoadReward? reward;
  final int? extra;
  final Image coin;
  MysteryBoxComponent? box;

  Rarity? get _rarity => switch (reward?.kind) {
    StarRoadRewardKind.rare => Rarity.rare,
    StarRoadRewardKind.epic => Rarity.epic,
    StarRoadRewardKind.legendary => Rarity.legendary,
    _ => null,
  };

  Color get _dark => switch (_rarity) {
    Rarity.rare => const Color(0xFF0E6FA6),
    Rarity.epic => const Color(0xFF6A1A9C),
    Rarity.legendary => const Color(0xFFC98A00),
    _ => const Color(0xFFC98A00),
  };

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final rarity = _rarity;
    if (rarity != null) {
      box = MysteryBoxComponent(
        look: MysteryBoxLook.colours(rarity.color, _dark, label: null),
        boxSize: 46,
        position: Vector2(26, 26),
      );
      add(box!);
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.clipRect(size.toRect());
    if (extra != null) {
      canvas.translate(26, 26);
      StarRoadStar.paint(canvas, 30);
    } else {
      switch (reward!.kind) {
        case StarRoadRewardKind.coins:
          CoinIcon.paint(canvas, coin, const Offset(26, 26), 32);
        case StarRoadRewardKind.feather:
          FeatherArt.paintAt(canvas, const Offset(26, 26), .85, 0);
        case StarRoadRewardKind.piece:
          canvas.save();
          canvas.translate(26, 26);
          canvas.scale(.85);
          PuzzleArt.paintPieceCentred(
            canvas,
            0,
            PuzzleConfig.themes.first,
          );
          canvas.restore();
        case StarRoadRewardKind.rare:
        case StarRoadRewardKind.epic:
        case StarRoadRewardKind.legendary:
          break;
      }
    }
    canvas.restore();
  }
}

/// The one-shot white shine sweep and the small sparkle each tile gets when
/// it pops in. It sits above the art (including the mystery-box child).
class _Shine extends PositionComponent {
  _Shine(this.tile, {super.position}) : super(size: Vector2.all(52));

  final StarRoadPopupTile tile;

  static final Paint _shine = Paint()
    ..color = const Color(0xA6FFFFFF);

  @override
  void render(Canvas canvas) {
    if (tile.game.reduceMotion) return;
    final u = _seg(tile.time, tile.appear + .25, .45);
    if (u > 0 && u < 1) {
      canvas.save();
      canvas.clipRect(size.toRect());
      canvas.translate(-30 + u * 100, -10);
      canvas.rotate(20 * math.pi / 180);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 16, 80), _shine);
      canvas.restore();
    }
    final k = (tile.time - (tile.appear + .08)) / .5;
    if (k <= 0 || k >= 1) return;
    final (scale, rotation, alpha) = Twinkle.curve(k);
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 + .4;
      Twinkle.paint(
        canvas,
        Offset(26 + math.cos(a) * 28, 26 + math.sin(a) * 28),
        12 * scale,
        const Color(0xFFFFE082).withValues(alpha: alpha),
        rotation: rotation,
      );
    }
  }
}
