import 'dart:async';
import 'dart:ui';
import 'package:flame/components.dart';
import '../../game/config.dart';
import '../../leaderboard/lb_models.dart';
import '../home/menu_primitives.dart';
import '../menu_screen_chrome.dart';
import 'board_row.dart';
import 'podium.dart';
// region P26-LB5
import 'board_info_sheet.dart';

// endregion

/// Our daily and all-time boards; achievements hands off without changing tab.
class BoardScreen extends MenuScreen {
  BoardScreen({required super.onBack, required this.source})
    : super(title: 'LEADERBOARD');
  final String source;
  LbBoardTab tab = LbBoardTab.today;
  LbGetBoardResult? data;
  final List<PositionComponent> content = [];
  final List<MenuButton> tabs = [];
  final List<MenuText> tabLabels = [];
  late MenuText timer;
  BoardRow? pinnedRow;
  BoardPodium? podium;
  MenuButton? playButton;
  int _generation = 0;
  double _time = 0;
  double _achievementFlash = 0;
  bool _loggedOpen = false;
  late final BoardTimerChip timerChip;
  late final BoardPinnedDivider pinnedDivider;
  // region P26-LB5
  BoardInfoSheet? infoSheet;
  late MenuButton infoButton;

  @override
  bool isActive() => super.isActive() && infoSheet == null;

  @override
  bool isBackActive() => super.isBackActive() && infoSheet == null;

  void openInfo() {
    if (!active || infoSheet != null) return;
    final sheet = BoardInfoSheet(
      height: game.viewHeight,
      playSound: game.sound.play,
      motion: () => !game.reduceMotion && !game.liveMotionPaused,
      onClose: closeInfo,
    );
    infoSheet = sheet;
    add(sheet);
    game.pushBack(_infoBack);
  }

  bool _infoBack() {
    infoSheet?.close();
    return true;
  }

  void closeInfo() {
    final sheet = infoSheet;
    if (sheet == null) return;
    infoSheet = null;
    game.popBack(_infoBack);
    sheet.removeFromParent();
  }

  @override
  void onRemove() {
    closeInfo();
    super.onRemove();
  }

  // endregion
  @override
  List<String> get contentImages => const ['menu/play.png'];
  @override
  Rect scrollViewportFor(double viewHeight) =>
      Rect.fromLTRB(0, 330, 320, viewHeight - 70);
  @override
  Future<void> buildContent() async {
    // region P26-FIX3
    // approvals_v26/leaderboard.html: the back / info boxes flank a 22 pt
    // title centred at y 70, so its line box clears the timer chip at 85.
    titleText
      ..fontSize = Config.boardTitleFontSize
      ..position = Vector2(160, Config.boardTitleCenterY)
      ..anchor = Anchor.center;
    // endregion P26-FIX3
    // region P26-LB5
    infoButton = MenuButton(
      position: Vector2(268, 58),
      size: Vector2.all(38),
      color: Config.menuPink,
      isActive: isActive,
      onPressed: openInfo,
      children: [
        MenuText(
          'i',
          fontSize: 25,
          color: const Color(0xffffffff),
          position: Vector2(19, 19),
          anchor: Anchor.center,
        ),
      ],
    );
    add(infoButton);
    if (source == 'home' && !game.storage.lbInfoSeen && active) {
      unawaited(game.storage.saveLbInfoSeen(true));
      openInfo();
    }
    // endregion
    for (var i = 0; i < 3; i++) {
      final x = [14.0, 98.0, 192.0][i], width = [82.0, 92.0, 114.0][i];
      final label = ['TODAY', 'BEST RUN', 'ACHIEVEMENTS'][i];
      final tabLabel = MenuText(
        label,
        fontSize: 11.5,
        color: Config.menuPink,
        position: Vector2(width / 2, 14),
        anchor: Anchor.center,
      );
      tabLabels.add(tabLabel);
      final button = MenuButton(
        position: Vector2(x, 110),
        size: Vector2(width, 28),
        isActive: isActive,
        onPressed: () {
          if (i == 2) {
            _achievementFlash = .4;
            _styleTabs();
            game.services.track('lb_achievements_tab', {
              'signed_in': game.services.achievementsReady,
            });
            unawaited(game.showAchievements());
          } else {
            final next = i == 0 ? LbBoardTab.today : LbBoardTab.best;
            if (next != tab) {
              tab = next;
              _styleTabs();
              unawaited(refresh());
            }
          }
        },
        children: [tabLabel],
      );
      tabs.add(button);
      add(button);
    }
    _styleTabs();
    timer = MenuText(
      '',
      fontSize: 10,
      color: Config.menuPink,
      position: Vector2(160, Config.boardTimerTextCenterY),
      anchor: Anchor.center,
    );
    timerChip = BoardTimerChip();
    add(timerChip);
    add(timer);
    pinnedDivider = BoardPinnedDivider(
      position: Vector2(0, Config.boardPinnedDividerYFor(game.viewHeight)),
      priority: 9,
    );
    add(pinnedDivider);
    unawaited(refresh());
  }

  // region P26-FIX3
  @override
  void onTint(Color color) {
    titleText.color = Config.menuPink;
  }
  // endregion P26-FIX3

  void _styleTabs() {
    for (var i = 0; i < tabs.length; i++) {
      final selected =
          i == (tab == LbBoardTab.today ? 0 : 1) ||
          (i == 2 && _achievementFlash > 0);
      tabs[i].color = selected ? Config.menuPink : const Color(0xffffd9ee);
      tabLabels[i].color = selected ? const Color(0xffffffff) : Config.menuPink;
    }
  }

  Future<void> refresh() async {
    final selected = tab, generation = ++_generation;
    final result = await game.leaderboard.getBoard(tab: selected);
    if (!active || generation != _generation) return;
    data = result;
    final opened = selected == LbBoardTab.today ? result?.today : result?.best;
    if (!_loggedOpen) {
      _loggedOpen = true;
      game.services.track('lb_board_open', {
        'source': source,
        'tab': selected.name,
        'rank': opened?.me?.rank ?? 0,
      });
    }
    for (final c in content) {
      c.removeFromParent();
    }
    content.clear();
    playButton = null;
    pinnedRow = null;
    podium = null;
    scroll.scrollTo(330, animate: false);
    final board = selected == LbBoardTab.today ? result?.today : result?.best;
    final isEmpty =
        board == null || (selected == LbBoardTab.today && board.group == null);
    if (isEmpty) {
      if (result != null) {
        podium = BoardPodium(const [], today: true);
        add(podium!);
        content.add(podium!);
      }
      if (result != null) {
        final panel = RectangleComponent(
          position: Vector2(14, 352),
          size: Vector2(292, 196),
          paint: Paint()..color = const Color(0xffffffff),
        );
        add(panel);
        content.add(panel);
      }
      final label = MenuText(
        result == null
            ? 'Check your connection and try again.'
            : 'YOUR GROUP STARTS\nWITH YOUR NEXT RUN',
        fontSize: 15,
        color: Config.menuPink,
        position: Vector2(160, 370),
        anchor: Anchor.topCenter,
      );
      add(label);
      content.add(label);
      if (result != null) {
        final explanation = MenuText(
          'Fly one run and you join up to 49 players\nwith a best score close to yours. Your group\nthen runs for 24 hours.',
          fontSize: 12.5,
          color: const Color(0xff7a0044),
          position: Vector2(160, 415),
          anchor: Anchor.topCenter,
        );
        add(explanation);
        content.add(explanation);
        final play = MenuButton(
          position: Vector2(88, 484),
          size: Vector2(144, 44),
          color: Config.menuPink,
          isActive: isActive,
          onPressed: () {
            unawaited(game.playFromBoard());
          },
          children: [
            MenuIcon(
              sprite('menu/play.png'),
              size: Vector2.all(24),
              position: Vector2(24, 10),
            ),
            MenuText(
              'PLAY',
              fontSize: 22,
              color: const Color(0xffffffff),
              position: Vector2(88, 22),
              anchor: Anchor.center,
            ),
          ],
        );
        playButton = play;
        add(play);
        content.add(play);
      }
      scroll.contentBottom = 330;
      _syncPinned();
      return;
    }
    podium = BoardPodium(
      board.rows,
      today: selected == LbBoardTab.today,
      ownId: board.me?.rid,
    );
    add(podium!);
    content.add(podium!);
    var y = 336.0;
    for (final row in board.rows.where((r) => r.rank > 3)) {
      final view = BoardRow(
        row,
        own: row.rid == board.me?.rid,
        position: Vector2(14, y),
      );
      scroll.content.add(view);
      content.add(view);
      y += 48;
    }
    scroll.contentBottom = y;
    if (board.me != null && board.me!.rank > 3) {
      pinnedRow = BoardRow(
        board.me!,
        own: true,
        approximate: board.approximate,
        position: Vector2(14, Config.boardPinnedRowTopFor(game.viewHeight)),
        priority: 10,
      );
      add(pinnedRow!);
      content.add(pinnedRow!);
    }
    _syncPinned();
  }

  bool get showPinned {
    final board = tab == LbBoardTab.today ? data?.today : data?.best;
    final me = board?.me;
    if (me == null || me.rank <= 3) return false;
    final index = board!.rows
        .where((r) => r.rank > 3)
        .toList()
        .indexWhere((r) => r.rid == me.rid);
    if (index < 0) return true;
    final y = 336 + index * 48 - scroll.offset;
    return y < scroll.viewport.top || y + 44 > scroll.viewport.bottom;
  }

  void _syncPinned() {
    final pinned = showPinned;
    pinnedRow?.visible = pinned;
    pinnedDivider.visible = pinned;
    scroll.clipBottom = pinned
        ? Config.boardPinnedDividerYFor(game.viewHeight)
        : null;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!built) return;
    if (_achievementFlash > 0) {
      _achievementFlash = (_achievementFlash - dt).clamp(0, .4);
      if (_achievementFlash == 0) _styleTabs();
    }
    if (!game.liveMotionPaused && !game.reduceMotion) _time += dt;
    podium?.time = _time;
    for (final view in content.whereType<BoardRow>()) {
      view.time = _time;
    }
    final end = tab == LbBoardTab.today ? data?.today.group?.end : null;
    final seconds = end?.difference(DateTime.now()).inSeconds.clamp(0, 86400);
    timerChip.visible = data != null;
    timer.text = data == null
        ? ''
        : tab == LbBoardTab.best
        ? 'ALL PLAYERS · ALL TIME'
        : seconds == null
        ? 'STARTS WITH YOUR NEXT RUN'
        : formatBoardTime(seconds);
    timer.color = seconds != null && tab == LbBoardTab.today
        ? const Color(0xff7a0044)
        : const Color(0xff888888);
    timerChip.stopwatch = seconds != null && tab == LbBoardTab.today;
    timer.fontSize = timerChip.stopwatch ? 13 : 9;
    timer.position.x = timerChip.stopwatch ? 166 : 160;
    timerChip.chipWidth = timerChip.stopwatch
        ? 112
        : (tab == LbBoardTab.best ? 150 : 180);
    _syncPinned();
  }
}

String formatBoardTime(int seconds) {
  final value = seconds.clamp(0, 86400);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value ~/ 3600)}:${two(value % 3600 ~/ 60)}:${two(value % 60)}';
}

/// The 2 pt rule between the clipped list and the pinned own row
/// (approvals_v26/leaderboard.html: `PIN_Y-6`, #E2E2E2).
class BoardPinnedDivider extends PositionComponent {
  BoardPinnedDivider({super.position, super.priority})
    : super(size: Vector2(Config.worldWidth, Config.boardPinnedDividerHeight));
  bool visible = false;
  final Paint _paint = Paint()..color = const Color(0xffe2e2e2);

  @override
  void render(Canvas canvas) {
    if (!visible) return;
    canvas.drawRect(size.toRect(), _paint);
  }
}

class BoardTimerChip extends PositionComponent {
  BoardTimerChip()
    : super(
        position: Vector2(160, Config.boardTimerChipCenterY),
        size: Vector2(180, 20),
        anchor: Anchor.center,
      );
  bool visible = false;
  bool stopwatch = false;
  double chipWidth = 180;
  @override
  void render(Canvas canvas) {
    if (!visible) return;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y / 2),
        width: chipWidth,
        height: 20,
      ),
      Paint()..color = const Color(0xffffffff),
    );
    if (stopwatch) {
      final x = size.x / 2 - chipWidth / 2 + 11;
      final ink = Paint()
        ..color = Config.menuPink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawCircle(Offset(x, 11), 5.3, ink);
      canvas.drawLine(Offset(x, 11), Offset(x, 7.5), ink);
      canvas.drawRect(
        Rect.fromLTWH(x - 2, 2, 4, 2),
        Paint()..color = Config.menuPink,
      );
    }
  }
}
