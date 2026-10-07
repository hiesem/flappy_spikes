import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../menu/powerup_slot.dart';
import '../menu/wallet.dart';
import '../services/ads_service.dart';
import '../services/iap_service.dart';
import '../skins/catalog.dart';
import 'home/menu_primitives.dart';

/// One debug action: a label (re-read after every tap, so it can show the
/// current mode) and what it does.
class DebugAction {
  DebugAction(this.label, this.run);

  final String Function() label;
  final Future<void> Function() run;
}

/// Developer panel (debug builds and the Linux desktop target only; see
/// [FlappySpikesGame.debugAvailable]): a dim over the home screen with a
/// column of text buttons for menu-state testing. Opened by long-pressing
/// the home title or the `D` key; closed by its CLOSE row, Esc or a tap on
/// the dim.
class DebugPanel extends PositionComponent
    with HasGameReference<FlappySpikesGame>, TapCallbacks {
  DebugPanel({required this.onClose}) : super(priority: 900);

  final void Function() onClose;

  static const Color _dim = Color(0xD914141E); // rgba(20,20,30,.85)
  static const Color _text = Color(0xFFFFFFFF);

  late final List<DebugAction> actions;
  final List<MenuText> _labels = [];

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(Config.worldWidth, game.viewHeight);
    actions = _buildActions();
    final top = Config.debugPanelTopFor(game.viewHeight);
    add(
      MenuText(
        'DEBUG',
        fontSize: 20,
        color: Config.menuGold,
        letterSpacingEm: 0.14,
        position: top,
        anchor: Anchor.topCenter,
      ),
    );
    for (final (i, action) in actions.indexed) {
      final y = top.y + (i + 1) * Config.debugRowHeight + 6;
      final label = MenuText(
        action.label(),
        fontSize: 16,
        color: _text,
        anchor: Anchor.center,
        position: Vector2(Config.worldWidth / 2, Config.debugRowHeight / 2),
      );
      _labels.add(label);
      add(
        MenuButton(
          position: Vector2(Config.homeMargin, y),
          size: Vector2(
            Config.worldWidth - 2 * Config.homeMargin,
            Config.debugRowHeight - 2,
          ),
          color: const Color(0x33FFFFFF),
          onPressed: () => _run(i),
          children: [label],
        ),
      );
    }
  }

  Future<void> _run(int index) async {
    await actions[index].run();
    for (final (i, action) in actions.indexed) {
      _labels[i].text = action.label();
    }
  }

  List<DebugAction> _buildActions() {
    final menu = game.menu;
    final ads = game.monetization.ads;
    final iap = game.monetization.iap;
    return [
      DebugAction(
        () => '+1000 coins (${menu.wallet.balance})',
        () => menu.wallet.add(1000, CoinSource.debug),
      ),
      DebugAction(() => 'Reset menu state', () async {
        await menu.items.resetAll();
        menu.slot.debugForce = null;
        game.refreshHome();
        game.showToast('Menu state reset');
      }),
      DebugAction(() => 'Next day (offset ${menu.storage.debugDayOffset})', () {
        return menu.storage.saveDebugDayOffset(menu.storage.debugDayOffset + 1);
      }),
      DebugAction(() => 'Slot: force BIG HOOPS', () async {
        menu.slot.debugForce = Powerup.bigHoops;
        menu.slot.rollForArrival();
      }),
      DebugAction(() => 'Slot: force SHIELD', () async {
        menu.slot.debugForce = Powerup.shield;
        menu.slot.rollForArrival();
      }),
      DebugAction(() => 'Slot: random (re-roll)', () async {
        menu.slot.debugForce = null;
        menu.slot.rollForArrival();
      }),
      if (ads is FakeRewardedAds)
        DebugAction(() => 'Ads: ${ads.mode.name}', () async {
          ads.mode = FakeAdMode
              .values[(ads.mode.index + 1) % FakeAdMode.values.length];
        }),
      if (game.monetization.isFake && iap is FakeIapService)
        DebugAction(() => 'IAP: ${iap.mode.name}', () async {
          iap.mode = FakeIapMode
              .values[(iap.mode.index + 1) % FakeIapMode.values.length];
        }),
      DebugAction(
        () => 'LEVEL UP (best ${menu.storage.bestScore}, '
            'lv ${menu.levels.level})',
        () async {
          // PRD-home-v3 Q-H1 interim: the popup shows on the next home.
          await menu.levels.debugForceLevelUp();
          final pending = menu.levels.pendingLevelUp;
          game.showToast(
            pending == null
                ? 'No level-up pending'
                : 'Level up to ${pending.def.name} (+${pending.reward})',
          );
        },
      ),
      DebugAction(
        () => 'ALL ITEMS (${menu.items.ownedCount}/$kCollectibleTotal)',
        () async {
          await menu.items.grantAll();
          game.refreshHome();
          game.showToast('All items granted');
        },
      ),
      DebugAction(() => 'Close', () async => onClose()),
    ];
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = _dim);
  }

  /// Taps on the dim close the panel; the buttons consume their own taps.
  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
  }

  @override
  void onTapUp(TapUpEvent event) => onClose();
}
