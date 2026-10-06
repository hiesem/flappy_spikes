import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flappy_spikes/components/look_component.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP-D unit tests for [LookComponent] (the vector replacement for the
/// PRD-1 sprite component).

const int _w = 96, _h = 88; // generous margins around the 44 x 36 art box
const double _scale = 1.5; // device px per art unit

/// Renders [component] with its art body centre at ([cx], [cy]) and returns
/// straight (unpremultiplied) RGBA.
Future<Uint8List> _render(LookComponent component, double cx, double cy) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  // render() draws the art box with its top-left at the canvas origin; move
  // it so the art body centre lands on (cx, cy).
  canvas.translate(
    cx - LookPainter.bodyCentre.dx * component.artScale,
    cy - LookPainter.bodyCentre.dy * component.artScale,
  );
  component.render(canvas);
  final image = await rec.endRecording().toImage(_w, _h);
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  return data!.buffer.asUint8List();
}

Color _pixelAt(Uint8List px, double cx, double cy) {
  final i = ((cy.round() * _w) + cx.round()) * 4;
  return Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]);
}

int _diff(Uint8List a, Uint8List b) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      n++;
    }
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('geometry', () {
    test('the art body centre is the default anchor', () {
      final c = LookComponent(
        look: Look.defaults,
        artScale: 2,
        position: Vector2(100, 50),
      );
      expect(LookComponent.bodyAnchor, const Anchor(21 / 44, 18 / 36));
      expect(c.anchor, LookComponent.bodyAnchor);
      // The component's box is the art box at the requested scale.
      expect(c.size.x, closeTo(LookPainter.boxWidth * 2, 1e-3));
      expect(c.size.y, closeTo(LookPainter.boxHeight * 2, 1e-3));
      expect(c.artScale, closeTo(2, 1e-3));
      // The art body centre lands on the component's position (and therefore
      // on the physics body centre when the parent places it there).
      final centre = c.absolutePositionOfAnchor(LookComponent.bodyAnchor);
      expect(centre.x, closeTo(100, 1e-3));
      expect(centre.y, closeTo(50, 1e-3));
    });

    test('artScale resizes the art box in place', () {
      final c = LookComponent(look: Look.defaults, artScale: 1);
      c.artScale = Config.lookScale;
      expect(c.size.x, closeTo(LookPainter.boxWidth * Config.lookScale, 1e-3));
      expect(c.size.y, closeTo(LookPainter.boxHeight * Config.lookScale, 1e-3));
    });
  });

  group('pose timing', () {
    test('idle alternates idle/flap every Config.idleFrameTime', () {
      final c = LookComponent(look: Look.defaults);
      expect(c.pose, LookPose.idle);
      expect(c.flapping, isFalse);
      c.update(Config.idleFrameTime - 0.01);
      expect(c.flapping, isFalse);
      c.update(0.02);
      expect(c.flapping, isTrue);
      c.update(Config.idleFrameTime);
      expect(c.flapping, isFalse);
    });

    test('playFlap shows flap then idle and returns to idle', () {
      final c = LookComponent(look: Look.defaults);
      c.playFlap();
      expect(c.pose, LookPose.flap);
      expect(c.flapping, isTrue);
      c.update(Config.flapFrameTime - 0.01);
      expect(c.pose, LookPose.flap);
      expect(c.flapping, isTrue);
      c.update(0.02); // past the flap frame, still in the flap pose
      expect(c.pose, LookPose.flap);
      expect(c.flapping, isFalse);
      c.update(Config.flapFrameTime);
      expect(c.pose, LookPose.idle);
      expect(c.time, 0);
    });

    test('paused freezes the idle clock and resumes where it stopped', () {
      final c = LookComponent(look: Look.defaults);
      c.update(0.7);
      final t = c.time;
      c.paused = true;
      c.update(5);
      expect(c.time, t, reason: 'the idle art pauses with the screen clock');
      c.paused = false;
      c.update(0.1);
      expect(c.time, closeTo(t + 0.1, 1e-9));
    });

    test('showDead freezes the clock in the dead pose', () {
      final c = LookComponent(look: Look.defaults);
      c.update(0.7);
      final frozen = c.time;
      c.showDead();
      expect(c.pose, LookPose.dead);
      expect(c.flapping, isFalse);
      c.update(5);
      expect(c.time, frozen, reason: 'the dead pose is a still frame');
      expect(c.pose, LookPose.dead);
    });
  });

  group('stage blend', () {
    test('blendMatrix mixes 35 % of the tint into every RGB channel', () {
      const tint = Color(0xFF102030);
      final m = LookComponent.blendMatrix(Config.skinStageBlend, tint);
      expect(m, hasLength(20));
      expect(m[0], closeTo(0.65, 1e-12));
      expect(m[4], closeTo(tint.r * 255 * Config.skinStageBlend, 1e-9));
      expect(m[6], closeTo(0.65, 1e-12));
      expect(m[9], closeTo(tint.g * 255 * Config.skinStageBlend, 1e-9));
      expect(m[12], closeTo(0.65, 1e-12));
      expect(m[14], closeTo(tint.b * 255 * Config.skinStageBlend, 1e-9));
      // Alpha is kept.
      expect(m.sublist(15), [0, 0, 0, 1, 0]);
    });

    testWidgets('apply 0.35 toward the stage foreground on RGB only', (
      tester,
    ) async {
      await tester.runAsync(() async {
        const tint = Color(0xFF3A7D44);
        final plain = LookComponent(look: Look.defaults, artScale: _scale);
        final blended = LookComponent(
          look: Look.defaults,
          artScale: _scale,
          blend: Config.skinStageBlend,
          blendColor: tint,
        );
        final a = await _render(plain, _w / 2, _h / 2);
        final b = await _render(blended, _w / 2, _h / 2);
        var checked = 0;
        for (var i = 0; i < a.length; i += 4) {
          if (a[i + 3] != 255) continue; // opaque body pixels only
          for (var k = 0; k < 3; k++) {
            final expected = a[i + k] * (1 - Config.skinStageBlend) +
                (k == 0
                        ? tint.r
                        : k == 1
                            ? tint.g
                            : tint.b) *
                    255 *
                    Config.skinStageBlend;
            expect(b[i + k], closeTo(expected, 2), reason: 'channel $k');
          }
          expect(b[i + 3], a[i + 3], reason: 'alpha must be kept');
          checked++;
        }
        expect(checked, greaterThan(500), reason: 'body pixels sampled');
        expect(b, isNot(a));
      });
    });
  });

  group('opacity and look swap', () {
    testWidgets('opacity 0 draws nothing, 0.5 halves the alpha', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final hidden = LookComponent(
          look: Look.defaults,
          artScale: _scale,
          opacity: 0,
        );
        final px = await _render(hidden, _w / 2, _h / 2);
        expect(px.every((b) => b == 0), isTrue);

        final half = LookComponent(
          look: Look.defaults,
          artScale: _scale,
          opacity: 0.5,
        );
        final px2 = await _render(half, _w / 2, _h / 2);
        final centre = _pixelAt(px2, _w / 2, _h / 2);
        expect(centre.a, inInclusiveRange(0.47, 0.53));
      });
    });

    testWidgets('swapping the look redraws the bird', (tester) async {
      await tester.runAsync(() async {
        final c = LookComponent(look: Look.defaults, artScale: _scale);
        final classic = await _render(c, _w / 2, _h / 2);
        c.look = const Look(bird: 'robin');
        final robin = await _render(c, _w / 2, _h / 2);
        expect(c.look.bird, 'robin');
        expect(_diff(classic, robin), greaterThan(200));
      });
    });
  });
}
