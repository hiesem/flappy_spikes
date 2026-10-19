import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../achievements/achievement_catalog.dart'; // P231-E
import '../game/config.dart';
import '../game/flappy_game.dart';
import '../menu/powerup_slot.dart';
import '../menu/wallet.dart';
import '../run/debug/force_menu.dart';
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

  /// The current page's actions (the main page, or a page of the §3.0.8
  /// force menu).
  late List<DebugAction> actions;
  final List<MenuText> _labels = [];
  final List<Component> _rows = [];

  /// null = the main page; else the force-menu page index.
  int? _forcePage;

  /// PRD-2.3 §13.3: the MUSIC LOG page is up.
  bool _musicPage = false;

  /// PRD-2.3.1 §12.3 null = not on the ACHIEVEMENTS page; else its page.
  int? _achPage;

  /// The open page (main / RUN DEBUG page / MUSIC LOG / ACHIEVEMENTS).
  (int?, bool, int?) get _page => (_forcePage, _musicPage, _achPage);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(Config.worldWidth, game.viewHeight);
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
    _rebuild();
  }

  /// Rows that fit between the title and the bottom strip.
  int get _rowsPerPage {
    final top = Config.debugPanelTopFor(game.viewHeight).y;
    return ((game.viewHeight - top - Config.spikeHeight - 16) /
                Config.debugRowHeight)
            .floor() -
        1;
  }

  void _rebuild() {
    for (final r in _rows) {
      r.removeFromParent();
    }
    _rows.clear();
    _labels.clear();
    actions = _achPage != null
        ? _achievementActions()
        : _musicPage
        ? _musicActions()
        : _forcePage == null
        ? _buildActions()
        : _forceActions();
    final top = Config.debugPanelTopFor(game.viewHeight);
    for (final (i, action) in actions.indexed) {
      final y = top.y + (i + 1) * Config.debugRowHeight + 6;
      final label = MenuText(
        action.label(),
        fontSize: 16,
        color: _text,
        anchor: Anchor.center,
        position: Vector2(Config.worldWidth / 2, Config.debugRowHeight / 2),
      );
      // Long lines (the versus search line) shrink to the row.
      label.fitWidth(action.label(), _labelWidth);
      _labels.add(label);
      final row = MenuButton(
        position: Vector2(Config.homeMargin, y),
        size: Vector2(
          Config.worldWidth - 2 * Config.homeMargin,
          Config.debugRowHeight - 2,
        ),
        color: const Color(0x33FFFFFF),
        onPressed: () => _run(i),
        children: [label],
      );
      _rows.add(row);
      add(row);
    }
  }

  /// Presses row [index] (the button path; tests).
  Future<void> press(int index) => _run(index);

  Future<void> _run(int index) async {
    final page = _page;
    await actions[index].run();
    if (page != _page || _musicPage) {
      _rebuild();
      return;
    }
    for (final (i, action) in actions.indexed) {
      _labels[i].fitWidth(action.label(), _labelWidth);
    }
  }

  static const double _labelWidth =
      Config.worldWidth - 2 * Config.homeMargin - 8;

  /// One page of the §3.0.8 force menu plus page navigation.
  List<DebugAction> _forceActions() {
    final all = ForceMenu.actions(game);
    final per = (_rowsPerPage - 2).clamp(4, 40);
    final pages = (all.length / per).ceil();
    final page = (_forcePage ?? 0).clamp(0, pages - 1);
    return [
      ...all.skip(page * per).take(per),
      DebugAction(() => 'Page ${page + 1}/$pages  >', () async {
        _forcePage = (page + 1) % pages;
      }),
      DebugAction(() => '< Back', () async => _forcePage = null),
    ];
  }

  /// PRD-2.3 §13.3: the newest music diagnostic log entries (the whole
  /// log is in logcat, tag FS-Music); any row re-reads it.
  List<DebugAction> _musicActions() {
    final entries = game.sound.musicLog.entries;
    final rows = (_rowsPerPage - 1).clamp(4, 40);
    final shown = entries.reversed.take(rows).toList();
    return [
      for (final e in shown)
        DebugAction(() => '${e.event} ${e.flags} ${e.player}', () async {}),
      if (shown.isEmpty)
        DebugAction(() => '(no music events yet)', () async {}),
      DebugAction(() => '< Back', () async => _musicPage = false),
    ];
  }

  /// PRD-2.3.1 §12.3 "Achievements: sync now", "Achievements: reset
  /// local" and "Achievements: unlock…" (one row per achievement, paged).
  List<DebugAction> _achievementActions() {
    final ach = game.achievements;
    final per = (_rowsPerPage - 4).clamp(3, 48);
    final all = AchievementId.values;
    final pages = (all.length / per).ceil();
    final page = (_achPage ?? 0).clamp(0, pages - 1);
    final shown = all.skip(page * per).take(per);
    return [
      DebugAction(() => 'Achievements: sync now', () async {
        await ach.syncAll();
        game.showToast('Achievements synced');
      }),
      DebugAction(
        () => 'Achievements: reset local (${game.storage.achUnlocked.length})',
        () async {
          await ach.resetLocal();
          game.showToast('Local achievements reset');
        },
      ),
      for (final id in shown)
        DebugAction(
          () => '${ach.isUnlocked(id) ? '✓' : 'Unlock'} ${id.title}',
          () async {
            ach.unlock(id);
            await ach.flush();
            game.showAchievementToasts();
          },
        ),
      DebugAction(
        () => 'More… (${page + 1}/$pages)',
        () async => _achPage = (page + 1) % pages,
      ),
      DebugAction(() => '< Back', () async => _achPage = null),
    ];
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
        () =>
            'LEVEL UP (best ${menu.storage.bestScore}, '
            'lv ${menu.levels.level})',
        () async {
          // PRD-home-v3 Q-H1 interim: raise the best to the next level,
          // then show the LEVEL UP popup right away over home (elsewhere
          // it shows on the next home).
          await menu.levels.debugForceLevelUp();
          final pending = menu.levels.pendingLevelUp;
          if (pending == null) {
            game.showToast('No level-up pending');
            return;
          }
          onClose();
          game.openLevelUpPopup();
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
      // Owner 2026-10-14 (2.3.0 (19)): switch an owned No Ads off again on
      // this phone (testing ads after a test purchase; refund + revoke the
      // order in Play first, or the next sync / restore turns it back on).
      DebugAction(
        () => menu.noAds ? 'No Ads: ON (tap = off)' : 'No Ads: off',
        () async {
          if (!menu.noAds) return;
          await menu.setNoAds(false);
          game.refreshHome();
          game.showToast('No Ads off on this phone');
        },
      ),
      DebugAction(() => 'NO-ADS POPUP: force', () async {
        // Bypasses the PRD-menu-v4 §8 schedule (no bookkeeping either).
        onClose();
        game.openNoAdsPopup(reason: 'forced');
      }),
      // PRD-2.2 §4: "Versus: last search <reason> / <reads> reads /
      // opponent <uid-prefix>" (debug builds only, like the whole panel);
      // a tap re-reads it.
      DebugAction(() => game.versus.lastSearch.debugLine, () async {}),
      // 2.3.0 (18) gameplay tuning: the current / last run (was on the
      // TUNING page, removed with the remote tuning in audit 17).
      DebugAction(() => game.runStats?.economyLine ?? 'Run: -', () async {}),
      DebugAction(() => game.runStats?.funLine ?? 'Specials -', () async {}),
      // PRD-2.3 §13.3: the music diagnostic log.
      DebugAction(() => 'MUSIC LOG >', () async => _musicPage = true),
      // PRD-2.3.1 §12.3 the achievements debug rows.
      DebugAction(() => 'ACHIEVEMENTS >', () async => _achPage = 0),
      // §3.0.8 debug force menu (PRD-2, WP-0b).
      DebugAction(() => 'RUN DEBUG >', () async => _forcePage = 0),
      DebugAction(() => 'Close', () async => onClose()),
    ];
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      bleedRectFor(this, size.y),
      Paint()..color = _dim,
    ); // WP-TAB
  }

  /// Taps on the dim close the panel; the buttons consume their own taps.
  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
  }

  @override
  void onTapUp(TapUpEvent event) => onClose();
}
