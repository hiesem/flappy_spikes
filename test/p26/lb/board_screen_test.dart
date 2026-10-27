import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/leaderboard/board_row.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/leaderboard/lb_models.dart';
import 'package:flappy_spikes/leaderboard/lb_service.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../helpers.dart';

class _BoardService extends NoopLeaderboardService {
  _BoardService(this.result);
  final LbGetBoardResult result;
  @override
  Future<LbGetBoardResult?> getBoard({
    LbBoardTab tab = LbBoardTab.today,
  }) async => result;
}

class _Services extends GameServices {
  int achievements = 0;
  @override
  Future<ShowAchievementsResult> showAchievements() async {
    achievements++;
    return ShowAchievementsResult.opened;
  }
}

void main() {
  final rows = List.generate(
    12,
    (i) => LbBoardRow(
      rid: '$i',
      rank: i + 1,
      name: 'Bird $i',
      look: Look.defaults,
      points: 100 - i,
      best: 999,
    ),
  );
  final today = LbBoardPayload(
    tab: LbBoardTab.today,
    rows: rows,
    me: rows[11],
    group: LbBoardGroup(
      bracket: 0,
      start: DateTime.now().toUtc(),
      end: DateTime.now().toUtc().add(const Duration(hours: 3)),
    ),
  );
  final best = LbBoardPayload(
    tab: LbBoardTab.best,
    rows: rows,
    me: rows[11],
    approximate: true,
  );
  final services = _Services();
  final tester = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({});
    return FlappySpikesGame(
      soundEnabled: false,
      services: services,
      leaderboard: _BoardService(LbGetBoardResult(today: today, best: best)),
    );
  }, gameSize: Vector2(320, 568));
  tester.testGameWidget(
    'O62–O64: tabs, podium, pin and native achievements handoff',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      game.homeScreen!.trophyButton.onPressed();
      await flushAndMount(game);
      await flushAndMount(game);
      final board = game.boardScreen!;
      expect(board.tab, LbBoardTab.today);
      expect(board.tabs, hasLength(3));
      expect(board.tabLabels.map((e) => e.text), [
        'TODAY',
        'BEST RUN',
        'ACHIEVEMENTS',
      ]);
      expect(board.podium!.today, isTrue);
      expect(board.showPinned, isTrue);
      expect(board.pinnedRow!.own, isTrue);
      board.scroll.offset = board.scroll.maxOffset;
      expect(board.showPinned, isFalse);
      board.scroll.offset = 0;
      expect(board.scroll.content.children.query<BoardRow>().length, 9);
      board.tabs[1].onPressed();
      await flushAndMount(game);
      await flushAndMount(game);
      expect(board.tab, LbBoardTab.best);
      expect(board.podium!.today, isFalse);
      expect(board.pinnedRow!.approximate, isTrue);
      board.tabs[2].onPressed();
      await flushAndMount(game);
      expect(services.achievements, 1);
      expect(board.tab, LbBoardTab.best);
      game.closeBoard();
      await flushAndMount(game);
      expect(game.boardScreen, isNull);
    },
  );
  final empty = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({});
    return FlappySpikesGame(
      soundEnabled: false,
      leaderboard: _BoardService(
        const LbGetBoardResult(
          today: LbBoardPayload(tab: LbBoardTab.today, rows: []),
          best: LbBoardPayload(tab: LbBoardTab.best, rows: []),
        ),
      ),
    );
  }, gameSize: Vector2(320, 568));
  empty.testGameWidget(
    'O67 no group PLAY starts a run',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      game.homeScreen!.trophyButton.onPressed();
      await flushAndMount(game);
      await flushAndMount(game);
      final board = game.boardScreen!;
      expect(board.podium!.rows, isEmpty);
      expect(board.playButton, isNotNull);
      board.playButton!.onPressed();
      await flushAndMount(game);
      await flushAndMount(game);
      expect(game.boardScreen, isNull);
      expect(game.state, GameState.playing);
    },
  );
}
