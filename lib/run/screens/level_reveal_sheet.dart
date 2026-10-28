import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../../components/home/menu_primitives.dart';
import '../../components/skins/item_art.dart';
import '../../components/skins/item_tile.dart';
import '../../components/ui/mystery_box.dart';
import '../../components/ui/confetti.dart';
import '../../components/ui/p1_popup.dart';
import '../../game/config.dart';
import '../../game/sound.dart';
import '../effects/particle_pool.dart';
import '../effects/shock_ring.dart';
import '../../skins/catalog.dart';
import '../../skins/look.dart';
import '../../skins/art/look_painter.dart';
import '../../skins/art/hat_art.dart';
import '../../skins/art/hoop_painter.dart';
import '../../skins/art/trail.dart';

/// The results-page level reward. The pending record remains durable until a
/// choice is made, so removing the page during the animation loses nothing.
class LevelRevealSheet extends P1Popup {
  LevelRevealSheet({
    required this.item,
    required this.onFinished,
    this.extraCoins = 0,
  }) : super(onDismiss: () {}, priority: 100);

  final SkinItem? item;
  final int extraCoins;
  final void Function(bool equipped) onFinished;
  double elapsed = 0;
  double? equipAt;
  bool choosing = false;
  bool revealed = false;
  bool _secondBurst = false;
  bool _burst = false;
  bool _equipBurst = false;
  late final MysteryBoxComponent box;
  late final PositionComponent details;
  late final _EquipPreview _preview;
  late final Look originalLook;
  late final MenuText equippedLabel;
  final ItemArtCache art = ItemArtCache();
  final ParticlePool particles = ParticlePool();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final scale = ((game.viewHeight - 250) / 360).clamp(.65, 1.0);
    card.scale.setAll(scale);
    card.position.setValues(
      (320 - card.width * scale) / 2,
      (game.viewHeight * .38).clamp(0.0, game.viewHeight - cardHeight * scale),
    );
  }

  @override
  Future<void> buildCard(PositionComponent card) async {
    cardHeight = 310;
    final rarity = item?.rarity ?? Rarity.common;
    box = MysteryBoxComponent(
      look: MysteryBoxLook.colours(
        rarity.color,
        Color.lerp(rarity.color, const Color(0xFF000000), .3)!,
      ),
      boxSize: 80,
      position: Vector2(Config.p1PopupWidth / 2, 85),
      animation: const MysteryBoxAnimation(),
    );
    card.add(box);
    card.add(particles);
    card.add(
      _SkipSurface(() {
        if (!revealed) elapsed = 1.95;
      }, size: Vector2(Config.p1PopupWidth, cardHeight)),
    );
    details = PositionComponent();
    card.add(details);
    if (item != null) {
      details.add(
        ItemTile(
          item: item!,
          rect: Rect.fromLTWH((Config.p1PopupWidth - 92) / 2, 18, 92, 92),
          state: () => const ItemTileState(
            owned: true,
            equipped: false,
            tryingOn: false,
            isNew: false,
          ),
          onPressed: () {},
          art: art,
          cardColor: () => game.stageBackground,
          tint: () => Config.uiAccent,
          reduceMotion: () => game.reduceMotion,
        ),
      );
      details.add(
        MenuText(
          item!.name.toUpperCase(),
          fontSize: 18,
          color: Config.uiAccent,
          position: Vector2(Config.p1PopupWidth / 2, 115),
          anchor: Anchor.topCenter,
        ),
      );
      details.add(
        MenuText(
          '${rarity.label} · ${item!.layer.key.toUpperCase()}',
          fontSize: 12,
          color: rarity.color,
          position: Vector2(Config.p1PopupWidth / 2, 142),
          anchor: Anchor.topCenter,
        ),
      );
      details.add(
        MenuText(
          'NEW ITEM · ADDED TO YOUR ${item!.layer.tabLabel}',
          fontSize: 10,
          color: Config.menuPlum,
          position: Vector2(Config.p1PopupWidth / 2, 163),
          anchor: Anchor.topCenter,
        ),
      );
    } else {
      details.add(
        MenuText(
          extraCoins > 0
              ? 'ALL ITEMS OWNED · +${formatCoins(extraCoins)} INSTEAD'
              : 'YOUR REWARD',
          fontSize: 10,
          color: Config.uiAccent,
          position: Vector2(Config.p1PopupWidth / 2, 115),
          anchor: Anchor.topCenter,
        ),
      );
    }
    originalLook = game.menu.items.look;
    _preview = _EquipPreview(
      item: item,
      original: originalLook,
      position: Vector2(Config.p1PopupWidth / 2, 205),
    );
    details.add(_preview);
    equippedLabel = MenuText(
      '',
      fontSize: 12,
      color: Config.uiAccent,
      position: Vector2(Config.p1PopupWidth / 2, 225),
      anchor: Anchor.topCenter,
    );
    details.add(equippedLabel);
    void button(String text, double x, void Function() action) {
      details.add(
        MenuButton(
          position: Vector2(x, 260),
          size: Vector2(100, 36),
          color: Config.menuPink,
          isActive: () => revealed && !choosing,
          onPressed: action,
          children: [
            MenuText(
              text,
              fontSize: 14,
              color: const Color(0xFFFFFFFF),
              position: Vector2(50, 18),
              anchor: Anchor.center,
            ),
          ],
        ),
      );
    }

    if (item != null) button('EQUIP', 28, () => unawaited(choose(true)));
    button(
      'LATER',
      item == null
          ? (Config.p1PopupWidth - 100) / 2
          : Config.p1PopupWidth - 128,
      () => unawaited(choose(false)),
    );
    details.scale.setAll(0);
  }

  Future<void> choose(bool equip) async {
    if (!revealed || choosing) return;
    choosing = true;
    await game.menu.levels.payPending();
    if (equip && item != null) {
      await game.menu.items.equip(item!.layer, item!.id);
      for (final child in details.children.whereType<PositionComponent>()) {
        if (child != _preview && child != equippedLabel) child.scale.setZero();
      }
      _preview.start(game.menu.items.look);
      equipAt = elapsed;
    } else {
      onFinished(false);
      removeFromParent();
    }
  }

  void _sparkles(Color color, int count) {
    for (var i = 0; i < count; i++) {
      final angle = i * 2 * math.pi / count;
      particles.spawn(
        shape: ParticleShape.twinkle,
        x: Config.p1PopupWidth / 2,
        y: 85,
        vx: math.cos(angle) * 100,
        vy: math.sin(angle) * 100,
        w: 9,
        color: color,
        life: .8,
      );
    }
  }

  @override
  void render(Canvas canvas) {} // The results sheet leaves the score card visible.

  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    if (!revealed) elapsed = 1.95;
  }

  @override
  void update(double dt) {
    super.update(dt);
    elapsed += dt;
    if (!_burst && elapsed >= 1.25) {
      _burst = true;
      if (!game.reduceMotion) {
        _sparkles(
          item?.rarity?.color ?? Rarity.common.color,
          12 + (item?.rarity?.index ?? 0) * 5,
        );
        card.add(
          ConfettiBurst.burst(
            origin: Offset(Config.p1PopupWidth / 2, 85),
            count: 12 + (item?.rarity?.index ?? 0) * 5,
            stars: true,
          ),
        );
      }
      game.sound.play(
        item?.rarity == Rarity.legendary ? Sfx.lvUpBig : Sfx.lvClaim,
      );
    }
    if (item?.rarity == Rarity.legendary && !_secondBurst && elapsed >= 1.5) {
      _secondBurst = true;
      if (!game.reduceMotion) {
        _sparkles(const Color(0xFFFFD85A), 24);
        card.add(
          ShockRing().play(
            Offset(Config.p1PopupWidth / 2, 85),
            rx: 18,
            color: const Color(0xFFFFD85A),
            length: .6,
            scaleTo: 5,
          ),
        );
        card.add(
          ConfettiBurst.burst(
            origin: Offset(Config.p1PopupWidth / 2, 85),
            count: 16,
            stars: true,
          ),
        );
      }
    }
    if (!revealed && elapsed >= 1.95) {
      revealed = true;
      box.removeFromParent();
      details.scale.setAll(1);
    }
    if (!_burst && !game.reduceMotion) {
      final drop = (elapsed / .3).clamp(0.0, 1.0);
      box.position.y = 85 - 120 * (1 - drop) * (1 - drop);
    }
    final start = equipAt;
    if (start != null) {
      if (!_equipBurst && elapsed - start >= .4) {
        _equipBurst = true;
        if (!game.reduceMotion &&
            (item?.layer == SkinLayer.bird || item?.layer == SkinLayer.gear)) {
          for (var i = 0; i < 8; i++) {
            final a = i * math.pi / 4;
            particles.spawn(
              shape: ParticleShape.circle,
              x: Config.p1PopupWidth / 2,
              y: 205,
              vx: math.cos(a) * 55,
              vy: math.sin(a) * 55,
              w: 13,
              color: const Color(0xFFFFFFFF),
              life: .35,
              scale1: 0,
            );
          }
        }
      }
      if (elapsed - start >= .6) equippedLabel.text = 'EQUIPPED ✓';
      if (elapsed - start >= 1.6) {
        equipAt = null;
        onFinished(true);
        removeFromParent();
      }
    }
  }
}

/// Reuses the wardrobe painters while giving each layer its own equip motion.
class _EquipPreview extends PositionComponent {
  _EquipPreview({required this.item, required this.original, super.position})
    : trail = item?.layer == SkinLayer.trail
          ? TrailEmitter(item!.id, lookPainter: paintLookForTrail)
          : null;
  final SkinItem? item;
  final Look original;
  final TrailEmitter? trail;
  Look? equipped;
  double time = 0;
  void start(Look look) {
    equipped = look;
    time = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (equipped == null) return;
    time += dt;
    if (time >= .25) trail?.emit(const Offset(12, 0), dt, k: 1.3);
    trail?.step(dt);
  }

  @override
  void render(Canvas canvas) {
    final it = item;
    final look = equipped;
    if (look == null || it == null) return;
    canvas.save();
    if (it.layer == SkinLayer.trail) trail?.paint(canvas, k: 1.3);
    if (it.layer == SkinLayer.hoop) {
      HoopPainter.paintHalf(canvas, it.id, Offset.zero, 42, time, front: false);
      final u = ((time - .2) / .9).clamp(0.0, 1.0);
      canvas.translate(-65 + 100 * u, 0);
    }
    canvas.scale(1.4);
    if (it.layer == SkinLayer.hat && time < .6) {
      LookPainter.paint(
        canvas,
        original.withItem(SkinLayer.hat, kNoneId),
        t: time,
      );
      final u = ((time - .25) / .35).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(-22, -18 - 60 * (1 - u));
      if (u > 0) {
        paintHat(canvas, it.id, BirdArt.byId(original.bird).shape, time);
      }
      canvas.restore();
    } else {
      final shown =
          (it.layer == SkinLayer.bird || it.layer == SkinLayer.gear) &&
              time < .5
          ? original
          : look;
      LookPainter.paint(canvas, shown, t: time, flap: true);
    }
    canvas.restore();
    if (it.layer == SkinLayer.hoop) {
      HoopPainter.paintHalf(canvas, it.id, Offset.zero, 42, time, front: true);
    }
  }
}

class _SkipSurface extends PositionComponent with TapCallbacks {
  _SkipSurface(this.skip, {super.size}) : super(priority: -1);
  final void Function() skip;
  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    skip();
  }
}
