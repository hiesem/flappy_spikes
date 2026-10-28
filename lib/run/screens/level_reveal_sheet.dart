import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

// region P26-G6c
import '../../components/levels/tabs/album_reveal_art.dart';
// endregion
import '../../components/home/menu_primitives.dart';
import '../../components/skins/item_art.dart';
import '../../components/skins/item_tile.dart';
import '../../components/ui/mystery_box.dart';
import '../../components/ui/confetti.dart';
import '../../components/ui/p1_popup.dart';
import '../../game/config.dart';
// region P26-J5
import '../../game/flappy_game.dart';
// endregion
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
    // region P26-G6c
    this.payReward,
    this.album = false,
    // endregion
  }) : super(onDismiss: () {}, priority: 100);

  final SkinItem? item;
  final int extraCoins;
  // region P26-G6c
  final Future<void> Function()? payReward;
  final bool album;
  // endregion
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
    // region P26-G6c
    final albumOffset = album ? 75.0 : 0.0;
    cardHeight = 310 + albumOffset;
    if (album) {
      card.add(AlbumRevealArt(reduceMotion: () => game.reduceMotion));
      card.addAll([
        MenuText('ALBUM COMPLETE!', fontSize: 19, color: Config.uiAccent,
          anchor: Anchor.topCenter, position: Vector2(Config.p1PopupWidth / 2, 5)),
        MenuText('ALL 8 PICTURES', fontSize: 10, color: Config.menuPlum,
          anchor: Anchor.topCenter, position: Vector2(Config.p1PopupWidth / 2, 30)),
      ]);
    }
    // endregion
    // region P26-G6c
    final rarity = item?.rarity ?? (album ? Rarity.epic : Rarity.common);
    // endregion
    box = MysteryBoxComponent(
      look: MysteryBoxLook.colours(
        rarity.color,
        Color.lerp(rarity.color, const Color(0xFF000000), .3)!,
      ),
      boxSize: 80,
      // region P26-G6c
      position: Vector2(Config.p1PopupWidth / 2, 85 + albumOffset),
      // endregion
      animation: const MysteryBoxAnimation(),
    );
    card.add(box);
    card.add(particles);
    card.add(
      _SkipSurface(() {
        if (!revealed) elapsed = 1.95;
      }, size: Vector2(Config.p1PopupWidth, cardHeight)),
    );
    // region P26-G6c
    details = PositionComponent(position: Vector2(0, albumOffset));
    // endregion
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
          // region P26-G6c
          position: Vector2(Config.p1PopupWidth / 2, album ? 142 : 115),
          // endregion
          anchor: Anchor.topCenter,
        ),
      );
      details.add(
        MenuText(
          // region P26-G6c
          album ? rarity.label : '${rarity.label} · ${item!.layer.key.toUpperCase()}',
          // endregion
          fontSize: 12,
          color: rarity.color,
          // region P26-G6c
          position: Vector2(Config.p1PopupWidth / 2, album ? 115 : 142),
          // endregion
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
    // region P26-G6c
    if (payReward != null) {
      await payReward!();
    } else {
      await game.menu.levels.payPending();
    }
    // endregion
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
        // region P26-G6c
        y: album ? 160 : 85,
        // endregion
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
            // region P26-G6c
            origin: Offset(Config.p1PopupWidth / 2, album ? 160 : 85),
            // endregion
            count: 12 + (item?.rarity?.index ?? 0) * 5,
            stars: true,
          ),
        );
      }
      // region P26-G6c
      game.sound.play(
        album ? Sfx.lvClaim : (item?.rarity == Rarity.legendary ? Sfx.lvUpBig : Sfx.lvClaim),
      );
      // endregion
    }
    if (item?.rarity == Rarity.legendary && !_secondBurst && elapsed >= 1.5) {
      _secondBurst = true;
      if (!game.reduceMotion) {
        _sparkles(const Color(0xFFFFD85A), 24);
        card.add(
          ShockRing().play(
            // region P26-G6c
            Offset(Config.p1PopupWidth / 2, album ? 160 : 85),
            // endregion
            rx: 18,
            color: const Color(0xFFFFD85A),
            length: .6,
            scaleTo: 5,
          ),
        );
        card.add(
          ConfettiBurst.burst(
            // region P26-G6c
            origin: Offset(Config.p1PopupWidth / 2, album ? 160 : 85),
            // endregion
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
      // region P26-G6c
      box.position.y = (album ? 160 : 85) - 120 * (1 - drop) * (1 - drop);
      // endregion
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

// region P26-J5
/// Sequential Home catch-up. Choices stay in memory until all boxes have been
/// seen; a kill before the final choice leaves every durable roll pending.
class LevelCatchUpSheet extends PositionComponent
    with HasGameReference<FlappySpikesGame> {
  LevelCatchUpSheet({required this.rewards, required this.onFinished});

  final List<Map<String, Object?>> rewards;
  final void Function() onFinished;
  final List<SkinItem> _equips = [];
  int index = 0;
  late LevelRevealSheet current;
  bool _finishing = false;
  String get title =>
      rewards.length == 1 ? 'LEVEL REWARD' : '${rewards.length} LEVEL REWARDS';
  String get levels => rewards.map((row) => 'LV ${row['lvl']}').join(' · ');

  /// Back skips the current box without closing or paying the sequence.
  void skipReveal() {
    if (!current.isMounted || current.revealed || current.choosing) return;
    current.elapsed = 1.95;
    current.update(0);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _showCurrent();
  }

  void _showCurrent() {
    final row = rewards[index];
    final item = allItems.where((it) => it.key == row['item']).firstOrNull;
    current = _CatchUpItemSheet(
      item: item,
      extraCoins: row['extraCoins'] as int,
      title: title,
      levels: levels,
      onChoice: (equip) async {
        if (equip && item != null) _equips.add(item);
        if (index + 1 < rewards.length) {
          index++;
          _showCurrent();
          return;
        }
        if (_finishing) return;
        _finishing = true;
        await game.menu.levels.payPending();
        for (final item in _equips) {
          await game.menu.items.equip(item.layer, item.id);
        }
        onFinished();
      },
    );
    add(current);
  }
}

class _CatchUpItemSheet extends LevelRevealSheet {
  _CatchUpItemSheet({
    required super.item,
    required super.extraCoins,
    required this.title,
    required this.levels,
    required this.onChoice,
  }) : super(onFinished: (_) {});
  final String title;
  final String levels;
  final Future<void> Function(bool) onChoice;

  @override
  Future<void> buildCard(PositionComponent card) async {
    await super.buildCard(card);
    for (final entry in [
      (title, -54.0, 15.0, const Color(0xFFFFFFFF)),
      (
        'Here is the reward from your last run!',
        -34.0,
        10.0,
        const Color(0xFFFFFFFF),
      ),
      (levels, -18.0, 10.0, const Color(0xFFFFFFFF)),
    ]) {
      card.add(
        MenuText(
          entry.$1,
          fontSize: entry.$3,
          color: entry.$4,
          position: Vector2(Config.p1PopupWidth / 2, entry.$2),
          anchor: Anchor.topCenter,
        ),
      );
    }
  }

  @override
  Future<void> choose(bool equip) async {
    if (!revealed || choosing) return;
    choosing = true;
    // A preview can use the prospective look without granting the item yet.
    if (equip && item != null) {
      for (final child in details.children.whereType<PositionComponent>()) {
        if (child != _preview && child != equippedLabel) child.scale.setZero();
      }
      _preview.start(originalLook.withItem(item!.layer, item!.id));
      equipAt = elapsed;
    } else {
      removeFromParent();
      await onChoice(false);
    }
  }

  @override
  void update(double dt) {
    final start = equipAt;
    // Intercept the normal completion, which would pay this one sheet.
    if (start != null && elapsed + dt - start >= 1.6) {
      equipAt = null;
      removeFromParent();
      unawaited(onChoice(true));
      return;
    }
    super.update(dt);
  }
}
// endregion
