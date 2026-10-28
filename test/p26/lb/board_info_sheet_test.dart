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
      stepGame(game, .23);
      await flushAndMount(game);
      expect(board.infoSheet, isNull);
      board.infoButton.onPressed();
      await flushAndMount(game);
      expect(board.infoSheet, isNotNull);
      board.infoSheet!.close();
      stepGame(game, .23);
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

  FlameTester<FlappySpikesGame>(
    () {
      SharedPreferences.setMockInitialValues({});
      return FlappySpikesGame(worldHeight: 320 * 4 / 3, soundEnabled: false);
    },
    gameSize: Vector2(320, 320 * 4 / 3),
    pumpWidget: (widget, t) async {
      t.view.physicalSize = const ui.Size(320, 427);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(widget);
    },
  ).testGameWidget(
    'O59 tablet margins are dimmed and dismiss the guide',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, t) async {
      game.homeScreen!.trophyButton.onPressed();
      await flushAndMount(game);
      await flushAndMount(game);
      final sheet = game.boardScreen!.infoSheet!;
      expect(game.extraWidth, greaterThan(0));
      expect(sheet.containsLocalPoint(Vector2(-10, 200)), isTrue);
      expect(sheet.containsLocalPoint(Vector2(330, 200)), isTrue);
      sheet.update(1);
      await t.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)..translate(game.extraWidth, 0);
        sheet.render(canvas);
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          (320 + game.extraWidth * 2).ceil(),
          568,
        );
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final rowWidth = image.width;
        int alpha(int x) => bytes[(50 * rowWidth + x) * 4 + 3];
        expect(alpha(0), greaterThan(200));
        expect(alpha(rowWidth - 1), greaterThan(200));
        image.dispose();
        picture.dispose();
      });
      await t.tapAt(const ui.Offset(5, 200));
      await t.pump();
      stepGame(game, .23);
      await flushAndMount(game);
      expect(game.boardScreen!.infoSheet, isNull);
      await t.pump(const Duration(seconds: 1));
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
    expect(closed, 0);
    sheet.update(.11);
    expect(closed, 0);
    sheet.update(.12);
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
      expect(rect.width / rect.height, closeTo(136 / 96, 0.0001));
      final top = rect.top.ceil(), bottom = rect.bottom.floor() - 1;
      final x = rect.center.dx.round();
      expect(pixel(x, top), [130, 130, 130, 255]);
      expect(pixel(x, bottom), [130, 130, 130, 255]);
      image.dispose();
      picture.dispose();
    });
  }
}
