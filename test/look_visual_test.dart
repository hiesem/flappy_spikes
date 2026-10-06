import 'dart:io';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/pipe_pair.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'menu_screenshot_test.dart' show loadFonts;

/// WP-D visual check: renders the home bird and the run bird with the classic
/// look and with a non-default look (robin + wind-up key + cowboy) to
/// `build/look_shots/*.png` (LOOKed at by the author), and asserts the pixels
/// that matter: the look is drawn where the 1.0 bird sat, and the run bird at
/// stage 5 is tinted exactly `Config.skinStageBlend` of the stage foreground
/// toward the body colours.
///
/// Every capture pins the bird first ([_pinBird] / the home bird's clock) so
/// the art frame, position and opacity are fixed; the widget's own ticks then
/// cannot change what is sampled.
const double _scale = 2; // device px per point
const String _outDir = 'build/look_shots';

/// The look items are owned but nothing is equipped: the games start on the
/// classic look and the tests equip the non-default look mid-flight.
const Map<String, Object> _ownedPrefs = {
  'ownedItems': ['bird:robin', 'gear:windup', 'hat:cowboy'],
};

Future<void> _equipLook(FlappySpikesGame game) async {
  await game.menu.items.equip(SkinLayer.bird, 'robin');
  await game.menu.items.equip(SkinLayer.gear, 'windup');
  await game.menu.items.equip(SkinLayer.hat, 'cowboy');
}

/// Renders the game at [_scale] and writes a PNG; returns the straight RGBA.
Future<Uint8List> _capture(FlappySpikesGame game, String name) async {
  final size = _canvasSize(game);
  // Resize right before rendering: the harness reverts earlier resizes.
  game.onGameResize(size);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.x, size.y),
    Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  final image = await rec.endRecording().toImage(
        size.x.toInt(),
        size.y.toInt(),
      );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final raw = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  final file = File('$_outDir/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png!.buffer.asUint8List());
  debugPrint('SHOT ${file.path}: ${png.lengthInBytes} bytes');
  expect(png.lengthInBytes, greaterThan(8000));
  return raw!.buffer.asUint8List();
}

Vector2 _canvasSize(FlappySpikesGame game) => Vector2(
      Config.worldWidth * _scale,
      (game.viewHeight * _scale).roundToDouble(),
    );

/// Straight-RGBA pixel at world point ([x], [y]) of a [_capture] buffer.
Color _pixel(Uint8List px, double x, double y) {
  final w = (Config.worldWidth * _scale).round();
  final i = ((y * _scale).round() * w + (x * _scale).round()) * 4;
  return Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]);
}

/// How many pixels differ inside world [rect], and the bounding box of the
/// differing pixels (null when none differ).
({int count, Rect? box}) _diffWithin(Uint8List a, Uint8List b, Rect rect) {
  final w = (Config.worldWidth * _scale).round();
  final x0 = (rect.left * _scale).floor(), x1 = (rect.right * _scale).ceil();
  final y0 = (rect.top * _scale).floor(), y1 = (rect.bottom * _scale).ceil();
  var count = 0;
  int? minX, minY, maxX, maxY;
  for (var py = y0; py < y1; py++) {
    for (var px = x0; px < x1; px++) {
      final i = (py * w + px) * 4;
      if (i < 0 || i + 3 >= a.length) continue;
      if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
        count++;
        minX = minX == null ? px : (px < minX ? px : minX);
        maxX = maxX == null ? px : (px > maxX ? px : maxX);
        minY = minY == null ? py : (py < minY ? py : minY);
        maxY = maxY == null ? py : (py > maxY ? py : maxY);
      }
    }
  }
  final box = count == 0
      ? null
      : Rect.fromLTRB(
          minX! / _scale,
          minY! / _scale,
          (maxX! + 1) / _scale,
          (maxY! + 1) / _scale,
        );
  return (count: count, box: box);
}

/// Fixes the run bird at its spawn point, upright, in the flap frame, fully
/// opaque, so every capture lines up pixel for pixel. The opacity is set
/// after the zero-dt update so the run's fade-in (driven by the widget's own
/// ticks) cannot leak into the sampled pixels.
void _pinBird(FlappySpikesGame game) {
  final bird = game.world.children.query<Bird>().single;
  bird.body
    ..gravityScale = Vector2.zero()
    ..linearVelocity.setZero()
    ..angularVelocity = 0
    ..setTransform(Vector2(Config.birdX, game.viewHeight / 2), 0);
  bird.lookComponent.playFlap(); // t = 0: the same wing frame every capture
  game.update(0);
  bird.setSpriteOpacity(1);
}

/// Fixes the home bird's clock like [_pinBird] does for the run bird.
void _pinHomeBird(FlappySpikesGame game) {
  game.homeScreen!.bird.lookComponent.playFlap();
  game.update(0);
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  FlameTester<FlappySpikesGame>(
    () => createTestGame(_ownedPrefs),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  ).testGameWidget(
    'home bird: classic and robin + wind-up + cowboy sit on the 1.0 rect',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      await tester.runAsync(() async {
        final rect = Config.homeBirdRectFor(game.viewHeight);
        final centre = rect.center;
        _pinHomeBird(game);
        final classic = await _capture(game, 'home_classic');
        final classicPixel = _pixel(classic, centre.dx, centre.dy);

        await _equipLook(game);
        await flushAndMount(game);
        expect(game.homeScreen!.bird.look.bird, 'robin');
        _pinHomeBird(game);
        final looked = await _capture(game, 'home_robin_windup_cowboy');
        final lookPixel = _pixel(looked, centre.dx, centre.dy);

        // Both draws put bird pixels on the rect centre (the 1.0 home bird
        // position) and the two looks differ there.
        expect(classicPixel.a, 1);
        expect(lookPixel.a, 1);
        expect(lookPixel, isNot(classicPixel));

        // The only difference between the two captures is the bird art, and
        // it all sits around the home-bird rect: the differing pixels are the
        // bird (body + hat + wind-up key) drawn at the 1.0 position.
        final region = Rect.fromCenter(center: centre, width: 90, height: 80);
        final diff = _diffWithin(classic, looked, region);
        expect(diff.count, greaterThan(2000));
        // The silhouette is centred on the rect (the hat and key overhang by
        // a few points, so allow a small offset).
        expect(diff.box!.center.dx, closeTo(centre.dx, 10));
        expect(diff.box!.center.dy, closeTo(centre.dy, 10));
      });
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createTestGame(_ownedPrefs),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  ).testGameWidget(
    'run bird: look at stage 0 and the 35 % stage blend at stage 5',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      await tester.runAsync(() async {
        game.onScreenTap(); // START
        await flushAndMount(game);
        stepGame(game, 0.6); // let the menu fade out
        _pinBird(game);
        final classic0 = await _capture(game, 'run_stage0_classic');

        await _equipLook(game);
        await flushAndMount(game);
        _pinBird(game);
        final look0 = await _capture(game, 'run_stage0_robin_windup_cowboy');

        // The run bird draws the equipped look at the 1.0 spawn point (the
        // only difference between the two captures is the bird art).
        final body = Offset(Config.birdX, game.viewHeight / 2);
        final region = Rect.fromCenter(center: body, width: 90, height: 80);
        final diff = _diffWithin(classic0, look0, region);
        expect(diff.count, greaterThan(2000));
        expect(diff.box!.center.dx, closeTo(body.dx, 10));
        expect(diff.box!.center.dy, closeTo(body.dy, 10));
        expect(
          _pixel(classic0, body.dx, body.dy),
          isNot(_pixel(look0, body.dx, body.dy)),
        );

        // Drive the game to stage 5 (score 5) and finish the crossfade.
        game.score = 4;
        game.onScoreSensor(PipePair(gapBottomY: 351));
        stepGame(game, 0.6);
        final bird = game.world.children.query<Bird>().single;
        expect(game.skinBlend, Config.skinStageBlend);
        expect(bird.lookComponent.blend, Config.skinStageBlend);
        expect(bird.lookComponent.blendColor, game.foregroundColor);
        expect(game.foregroundColor, kPalettes[5]!.foreground);
        _pinBird(game);
        await _capture(game, 'run_stage5_robin_windup_cowboy');

        // The same frame rendered twice — blend 0 and blend 0.35 — so the
        // only difference is the tint (no update in between). Every changed
        // pixel of the bird must be `off * (1 - blend) + foreground * blend`
        // on RGB with alpha kept: solving for the mixed-in colour recovers
        // the stage foreground exactly on the body pixels (anti-aliased edge
        // pixels mix in the background, so only the solid body counts).
        final pair = await _captureBlendPair(game);
        const blend = Config.skinStageBlend;
        final fg = kPalettes[5]!.foreground;
        final fgR = fg.r * 255, fgG = fg.g * 255, fgB = fg.b * 255;
        var changed = 0, tinted = 0;
        for (var i = 0; i < pair.off.length; i += 4) {
          if (pair.off[i] == pair.on[i] &&
              pair.off[i + 1] == pair.on[i + 1] &&
              pair.off[i + 2] == pair.on[i + 2]) {
            continue;
          }
          changed++;
          expect(pair.on[i + 3], pair.off[i + 3], reason: 'alpha must be kept');
          final implied = [
            (pair.on[i] - (1 - blend) * pair.off[i]) / blend,
            (pair.on[i + 1] - (1 - blend) * pair.off[i + 1]) / blend,
            (pair.on[i + 2] - (1 - blend) * pair.off[i + 2]) / blend,
          ];
          if ((implied[0] - fgR).abs() <= 2 &&
              (implied[1] - fgG).abs() <= 2 &&
              (implied[2] - fgB).abs() <= 2) {
            tinted++;
          }
        }
        expect(changed, greaterThan(1000), reason: 'the bird art changed');
        expect(tinted, greaterThan(1000), reason: 'solid body tinted by fg');
      });
    },
  );
}

/// Renders the current frame twice, with the run bird's blend forced to 0
/// then [Config.skinStageBlend], without an update in between, so the two
/// images share geometry, pose and background exactly.
Future<({Uint8List off, Uint8List on})> _captureBlendPair(
  FlappySpikesGame game,
) async {
  final bird = game.world.children.query<Bird>().single;
  final size = _canvasSize(game);
  game.onGameResize(size);
  final w = size.x.toInt(), h = size.y.toInt();
  ui.Picture record(double blend) {
    bird.lookComponent.blend = blend;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()..color = game.backgroundColor(),
    );
    game.render(canvas);
    return rec.endRecording();
  }

  final offPicture = record(0);
  final onPicture = record(Config.skinStageBlend);
  final offImage = await offPicture.toImage(w, h);
  final onImage = await onPicture.toImage(w, h);
  final off = (await offImage.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!
      .buffer
      .asUint8List();
  final on = (await onImage.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!
      .buffer
      .asUint8List();
  offImage.dispose();
  onImage.dispose();
  return (off: off, on: on);
}
