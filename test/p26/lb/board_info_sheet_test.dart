import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/leaderboard/board_info_sheet.dart';
import 'package:flappy_spikes/components/leaderboard/board_screen.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/services/obf_strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  final tester = FlameTester<FlappySpikesGame>(() {
    SharedPreferences.setMockInitialValues({});
    return FlappySpikesGame(soundEnabled: false);
  }, gameSize: Vector2(320, 568));

  tester.testGameWidget(
    'O60/O67 trophy first open persists, i reopens, results does not auto-open',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, _) async {
      final results = BoardScreen(onBack: () {}, source: 'results');
      game.world.add(results);
      await flushAndMount(game);
      await flushAndMount(game);
      expect(results.infoSheet, isNull);
      expect(game.storage.lbInfoSeen, isFalse);
      results.removeFromParent();
      await flushAndMount(game);
      game.homeScreen!.trophyButton.onPressed();
      await flushAndMount(game);
      await flushAndMount(game);
      final board = game.boardScreen!;
      expect(board.infoSheet, isNotNull);
      expect(game.storage.lbInfoSeen, isTrue);
      final prefs = await SharedPreferences.getInstance();
      // Reload proves the flag is persisted, not just cached in memory.
      expect(prefs.getBool(Obf.prefLbInfoSeen), isTrue);
      expect(board.isActive(), isFalse);
      board.infoSheet!.close();
      await flushAndMount(game);
      expect(board.infoSheet, isNull);
      board.infoButton.onPressed();
      await flushAndMount(game);
      expect(board.infoSheet, isNotNull);
      board.infoSheet!.close();
      await flushAndMount(game);
      game.closeBoard();
      await flushAndMount(game);
      await flushAndMount(game);
      game.homeScreen!.trophyButton.onPressed();
      await flushAndMount(game);
      await flushAndMount(game);
      expect(game.boardScreen!.infoSheet, isNull);
    },
  );

  test('O59 guide sounds and captions', () {
    final sounds = <Sfx>[];
    var closed = 0;
    final sheet = BoardInfoSheet(
      height: 711,
      playSound: sounds.add,
      onClose: () => closed++,
      motion: () => true,
    );
    sheet.update(3);
    expect(sounds, [Sfx.vsPop, Sfx.vsPop, Sfx.vsPop, Sfx.vsPop]);
    expect(BoardInfoSheet.captions, [
      'FLY AND SCORE',
      'TOP THE BOARD',
      'WIN GIFT BOXES',
      'BEAT THE RECORDS',
    ]);
    sheet.close();
    sheet.close();
    expect(closed, 1);
    expect(sounds.last, Sfx.skClose);
  });

  for (final height in [568.0, 711.0]) {
    test('O90 run picture strips meet both edges at height $height', () async {
      final sheet = BoardInfoSheet(
        height: height,
        playSound: (_) {},
        onClose: () {},
        motion: () => false,
      )..elapsed = 4;
      final recorder = ui.PictureRecorder();
      sheet.render(ui.Canvas(recorder));
      final picture = recorder.endRecording();
      final image = await picture.toImage(320, height.toInt());
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      List<int> pixel(int x, int y) {
        final at = (y * 320 + x) * 4;
        return bytes.sublist(at, at + 4);
      }

      final rect = sheet.runPictureRect;
      final top = rect.top.ceil(), bottom = rect.bottom.floor() - 1;
      expect(pixel(86, top), [130, 130, 130, 255]);
      expect(pixel(86, bottom), [130, 130, 130, 255]);
      image.dispose();
      picture.dispose();
    });
  }
}
