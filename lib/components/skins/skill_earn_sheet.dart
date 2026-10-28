import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../../game/config.dart';
import '../../skins/catalog.dart';
import '../../skins/look.dart';
import '../home/menu_primitives.dart';
import '../ui/p1_popup.dart';
import 'item_art.dart';
import 'preview_stage.dart';
import 'shop_widgets.dart';

/// PRD 2.6 F10 / O88: every locked skill item uses the secret copy.
class SkillEarnSheet extends P1Popup {
  SkillEarnSheet({required this.item, required this.art, this.cardArt})
    : super(onDismiss: () {}, priority: 100);

  final SkinItem item;
  final ItemArtCache art;
  final ShopCardArt? cardArt;
  double time = 0;
  void close() {
    active = false;
    removeFromParent();
  }

  @override
  Future<void> buildCard(PositionComponent card) async {
    cardHeight = 300;
    card.add(_SkillArt(item, art, cardArt, () => time));
    void line(String text, double y, double size, Color color) {
      card.add(
        MenuText(
          text,
          fontSize: size,
          color: color,
          position: Vector2(Config.p1PopupWidth / 2, y),
          anchor: Anchor.topCenter,
        ),
      );
    }

    line('HOW TO EARN', 12, 16, Config.menuPlum);
    line('LEGENDARY · SKILL ONLY · NEVER SOLD', 144, 9, Config.menuPlum);
    line('? A SECRET ACHIEVEMENT ?', 174, 12, Config.menuPlum);
    line('Keep racing to find out.', 195, 11, Config.menuPlum);
    line('ACHIEVEMENT: ? ? ?', 218, 10, Config.menuPlum);
    card.add(
      MenuButton(
        position: Vector2((Config.p1PopupWidth - 120) / 2, 250),
        size: Vector2(120, 36),
        color: Config.menuGold,
        onPressed: close,
        children: [
          MenuText(
            'GOT IT',
            fontSize: 14,
            color: Config.menuPlum,
            position: Vector2(60, 18),
            anchor: Anchor.center,
          ),
        ],
      ),
    );
    card.add(
      _CloseSurface(close)..size = Vector2(Config.p1PopupWidth, cardHeight),
    );
  }

  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    close();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!game.reduceMotion) time += dt;
  }
}

class _CloseSurface extends PositionComponent with TapCallbacks {
  _CloseSurface(this.close) : super(priority: -1);
  final void Function() close;
  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    close();
  }
}

class _SkillArt extends PositionComponent {
  _SkillArt(this.item, this.art, this.cardArt, this.time);
  final SkinItem item;
  final ItemArtCache art;
  final ShopCardArt? cardArt;
  final double Function() time;
  @override
  void render(Canvas canvas) {
    final centre = Offset(Config.p1PopupWidth / 2, 90);
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(0, 35, Config.p1PopupWidth, 105));
    PreviewStage.paintRays(canvas, centre, 95, time(), opacity: .35);
    canvas.translate(centre.dx, centre.dy);
    if (item.layer == SkinLayer.card && cardArt != null) {
      cardArt!.paint(canvas, item, time());
    } else {
      canvas.translate(-ItemArt.w / 2, -ItemArt.h / 2);
      ItemArt.paint(
        canvas,
        item,
        t: time(),
        emitter: item.layer == SkinLayer.trail ? art.emitterFor(item) : null,
      );
    }
    canvas.restore();
  }
}
