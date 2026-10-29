import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fixed civil date used by the 2.6 golden screens. It is a Sunday midday,
/// so mission, streak, season and countdown labels all have stable values.
final DateTime kGoldenNow = DateTime(2026, 11, 1, 12);

DateTime goldenClock() => kGoldenNow;

Future<void> loadGoldenFonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  await Future.wait([lvdc.load(), opificio.load(), fredoka.load()]);
}

/// Renders the game exactly as the phone does at a 320 pt design width.
Future<ui.Image> goldenFrame(FlappySpikesGame game) async {
  final size = Vector2(320, game.viewHeight.roundToDouble());
  game.onGameResize(size);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.x, size.y),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  return recorder.endRecording().toImage(size.x.toInt(), size.y.toInt());
}

Future<void> expectGameGolden(
  WidgetTester tester,
  FlappySpikesGame game,
  String file,
) async {
  final image = await tester.runAsync(() => goldenFrame(game));
  await expectLater(image!, matchesGoldenFile(file));
  image.dispose();
}
