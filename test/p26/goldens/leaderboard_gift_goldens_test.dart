import 'dart:ui' show Color;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/leaderboard/lb_models.dart';
import 'package:flappy_spikes/leaderboard/lb_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';
import 'golden_helpers.dart';

class _BoardService extends NoopLeaderboardService {
  _BoardService(this.result);
  final LbGetBoardResult result;

  @override
  Future<LbGetBoardResult?> getBoard({
    LbBoardTab tab = LbBoardTab.today,
  }) async => result;
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadGoldenFonts();

  final rows = [
    for (var i = 0; i < 12; i++)
      LbBoardRow(
        rid: 'bird-$i',
        rank: i + 1,
        name: 'Bird ${i + 1}',
        look: Look.defaults,
        points: 480 - i * 27,
        playingNow: true,
      ),
  ];
  final today = LbBoardPayload(
    tab: LbBoardTab.today,
    rows: rows,
    me: rows.last,
    group: LbBoardGroup(
      bracket: 0,
      start: DateTime.utc(2026, 11, 1, 9),
      end: DateTime.utc(2026, 11, 1, 12),
    ),
  );
  final best = LbBoardPayload(
    tab: LbBoardTab.best,
    rows: rows,
    me: rows.last,
    approximate: true,
  );
  final result = LbGetBoardResult(today: today, best: best);

  for (final height in [568.0, 711.0]) {
    FlameTester<FlappySpikesGame>(() {
      SharedPreferences.setMockInitialValues({
        'gamesPlayed': 4,
        'bestScore': 185,
        'lastScore': 185,
        'firstSessionDone': true,
        'noAdsPopupLastMs': kGoldenNow.millisecondsSinceEpoch,
        'noAdsPopupClosedMs': kGoldenNow.millisecondsSinceEpoch,
      });
      return FlappySpikesGame(
        worldHeight: height,
        soundEnabled: false,
        clock: goldenClock,
        leaderboard: _BoardService(result),
      )..reduceMotionOverride = true;
    }, gameSize: Vector2(320, height)).testGameWidget(
      'Leaderboard today board with gift markers at ${height.round()}',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
        await game.storage.saveLbInfoSeen(true);
        stepGame(game, 1);
        game.openBoard();
        await flushAndMount(game);
        await flushAndMount(game);
        stepGame(game, .6);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        final board = game.boardScreen!;
        expect(board.tab, LbBoardTab.today);
        expect(board.data, isNotNull);
        expect(board.podium!.markerRanks, [1, 2, 3]);
        expect(board.pinnedRow, isNotNull);
        expect(board.infoSheet, isNull);
        // Freeze the wall-clock countdown after the final board update.
        board.timer
          ..text = '03:00:00'
          ..color = const Color(0xff7a0044)
          ..fontSize = 13
          ..position.x = 166;
        board.timerChip
          ..visible = true
          ..stopwatch = true
          ..chipWidth = 112;
        await expectGameGolden(
          tester,
          game,
          'goldens/leaderboard_today_${height.round()}.png',
        );
      },
    );
  }
}
