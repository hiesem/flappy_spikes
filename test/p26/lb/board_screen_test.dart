import 'dart:io';
import 'dart:ui' show Color, ImageByteFormat, PictureRecorder, Canvas;
import 'package:flame/components.dart';
import 'package:flappy_spikes/components/leaderboard/podium.dart';
import 'package:flappy_spikes/components/leaderboard/board_screen.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/leaderboard/board_row.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
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
      final sounds = <Sfx>[];
      game.sound.onPlay = sounds.add;
      game.state = GameState.playing;
      game.closeBoard();
      expect(game.boardScreen, same(board));
      expect(sounds, isEmpty);
      game.state = GameState.start;
      game.closeBoard();
      expect(sounds, [Sfx.click]);
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
      // PRD 2.6 §1204: dismiss the first-open guide before using the board.
      board.infoSheet!.close();
      await flushAndMount(game);
      expect(board.podium!.rows, isEmpty);
      expect(board.playButton, isNotNull);
      final panel = board.content.whereType<RectangleComponent>().single;
      expect(panel.position, Vector2(14, 352));
      expect(panel.size, Vector2(292, 196));
      expect(panel.paint.color, const Color(0xffffffff));
      expect(board.playButton!.position, Vector2(88, 484));
      expect(board.playButton!.children.query<MenuIcon>(), hasLength(1));
      final body = board.content.whereType<MenuText>().singleWhere(
        (t) => t.text.startsWith('Fly one run'),
      );
      expect(body.fontSize, 12.5);
      final sounds = <Sfx>[];
      game.sound.onPlay = sounds.add;
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
      expect(sounds, isNot(contains(Sfx.click)));
    },
  );
  final offline = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({});
    return FlappySpikesGame(soundEnabled: false);
  }, gameSize: Vector2(320, 568));
  offline.testGameWidget(
    'offline state hides the timer chip',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      game.homeScreen!.trophyButton.onPressed();
      await flushAndMount(game);
      await flushAndMount(game);
      game.update(.01);
      final board = game.boardScreen!;
      expect(board.timerChip.visible, isFalse);
      expect(board.timer.text, isEmpty);
      expect(
        board.content.whereType<MenuText>().map((t) => t.text),
        contains('Check your connection and try again.'),
      );
    },
  );
  test('empty podium paints the three metal top strips', () async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    BoardPodium(const [], today: false).render(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage(320, 179);
    final bytes = (await image.toByteData(
      format: ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    List<int> pixel(int x, int y) {
      final i = (y * 320 + x) * 4;
      return bytes.sublist(i, i + 4);
    }

    // Each strip has its tier's lighter top, above the darker plinth body.
    expect(pixel(15, 82), isNot(pixel(15, 86)));
    expect(pixel(115, 64), isNot(pixel(115, 68)));
    expect(pixel(215, 90), isNot(pixel(215, 94)));
    image.dispose();
    picture.dispose();
  });
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
