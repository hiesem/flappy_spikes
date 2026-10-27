import 'dart:async';
import 'dart:ui';
import 'package:flame/components.dart';
import '../../game/config.dart';
import '../../leaderboard/lb_models.dart';
import '../home/menu_primitives.dart';
import '../menu_screen_chrome.dart';
import 'board_row.dart';
import 'podium.dart';

/// Our daily and all-time boards; achievements hands off without changing tab.
class BoardScreen extends MenuScreen {
  BoardScreen({required super.onBack}) : super(title: 'LEADERBOARD');
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
  @override
  Rect scrollViewportFor(double viewHeight) =>
      Rect.fromLTRB(0, 330, 320, viewHeight - 70);
  @override
  Future<void> buildContent() async {
    titleText.position = Vector2(160, 58);
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
      position: Vector2(160, 94),
      anchor: Anchor.center,
    );
    add(timer);
    unawaited(refresh());
  }

  void _styleTabs() {
    for (var i = 0; i < tabs.length; i++) {
      final selected = i == (tab == LbBoardTab.today ? 0 : 1);
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
    game.services.track('lb_board_open', {
      'source': 'home',
      'tab': selected.name,
      'rank': opened?.me?.rank ?? 0,
      'real_count': -1,
    });
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
      final label = MenuText(
        result == null
            ? 'LEADERBOARD UNAVAILABLE'
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
          'Fly one run to join players with a best score\nclose to yours. Your group runs for 24 hours.',
          fontSize: 11,
          color: const Color(0xff7a0044),
          position: Vector2(160, 410),
          anchor: Anchor.topCenter,
        );
        add(explanation);
        content.add(explanation);
        final play = MenuButton(
          position: Vector2(88, 450),
          size: Vector2(144, 44),
          color: Config.menuPink,
          isActive: isActive,
          onPressed: () {
            unawaited(game.playFromBoard());
          },
          children: [
            MenuText(
              'PLAY',
              fontSize: 22,
              color: const Color(0xffffffff),
              position: Vector2(72, 22),
              anchor: Anchor.center,
            ),
          ],
        );
        playButton = play;
        add(play);
        content.add(play);
      }
      scroll.contentBottom = 330;
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
        position: Vector2(14, game.viewHeight - 115),
        priority: 10,
      );
      add(pinnedRow!);
      content.add(pinnedRow!);
    }
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

  @override
  void update(double dt) {
    super.update(dt);
    if (!built) return;
    if (!game.liveMotionPaused && !game.reduceMotion) _time += dt;
    podium?.time = _time;
    for (final view in content.whereType<BoardRow>()) {
      view.time = _time;
    }
    final end = tab == LbBoardTab.today ? data?.today.group?.end : null;
    final seconds = end?.difference(DateTime.now()).inSeconds.clamp(0, 86400);
    timer.text = tab == LbBoardTab.best
        ? 'ALL PLAYERS · ALL TIME'
        : seconds == null
        ? 'STARTS WITH YOUR NEXT RUN'
        : '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m ${seconds % 60}s';
    pinnedRow?.visible = showPinned;
  }
}
