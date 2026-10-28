import 'dart:io';
import 'dart:ui' show Color;
import 'package:flame/components.dart';
import 'package:flappy_spikes/components/leaderboard/podium.dart';
import 'package:flappy_spikes/components/leaderboard/board_screen.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
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
  final List<(String, Map<String, Object>?)> events = [];
  @override
  void logEvent(String name, [Map<String, Object>? parameters]) =>
      events.add((name, parameters));
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
      expect(board.podium!.markerRanks, [1, 2, 3]);
      expect(
        BoardPodium(rows, today: true, ownId: rows.first.rid).displayedText,
        contains('YOU'),
      );
      final texts = [
        ...board.podium!.displayedText,
        ...board.scroll.content.children.query<BoardRow>().expand(
          (r) => r.displayedText,
        ),
        ...board.pinnedRow!.displayedText,
        ...board.content.whereType<MenuText>().map((t) => t.text),
      ];
      for (final text in texts) {
        expect(text.toUpperCase(), isNot(contains('BEST'))); // O62
        for (final forbidden in ['PLAY GAMES', 'GAME CENTER', 'REPORT', '%']) {
          expect(text.toUpperCase(), isNot(contains(forbidden))); // O54/O64
        }
      }
      expect(board.pinnedRow!.displayedText, contains('YOU'));
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
      expect(board.podium!.markerRanks, isEmpty);
      expect(board.pinnedRow!.approximate, isTrue);
      board.tabs[2].onPressed();
      expect(board.tabs[2].color, const Color(0xffec008c));
      await flushAndMount(game);
      expect(services.achievements, 1);
      await board.refresh();
      final opened = services.events
          .where((event) => event.$1 == 'lb_board_open')
          .toList();
      expect(opened, hasLength(1));
      expect(opened.single.$2!['source'], 'home');
      expect(opened.single.$2!.containsKey('real_count'), isFalse);
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
      expect(
        board.content.whereType<MenuText>().map((e) => e.text),
        contains(
          'Fly one run and you join up to 49 players\nwith a best score close to yours. Your group\nthen runs for 24 hours.',
        ),
      );
      board.playButton!.onPressed();
      await flushAndMount(game);
      await flushAndMount(game);
      expect(game.boardScreen, isNull);
      expect(game.state, GameState.playing);
    },
  );
  test('approved time tags, timer and approximate rank', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    expect(lastRunTag(now), 'JUST NOW');
    expect(lastRunTag(now - 12 * 60000), '12 M AGO');
    expect(lastRunTag(now - 3 * 3600000), '3 H AGO');
    expect(lastRunTag(now - 2 * 86400000), '2 D AGO');
    expect(formatBoardTime(10799), '02:59:59');
    expect(formatBoardRank(1284, approximate: true), '#~1\u20092xx');
  });
  test('O54 and O64: no box in rows and no native-board UI caller', () {
    final row = File(
      'lib/components/leaderboard/board_row.dart',
    ).readAsStringSync();
    expect(row, isNot(contains('MysteryBox')));
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(
        RegExp(r'game\.showLeaderboard\s*\(').hasMatch(source),
        isFalse,
        reason: file.path,
      );
    }
  });
}
