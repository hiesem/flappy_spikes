import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/hud_config.dart';
import 'package:flappy_spikes/run/config/versus_config.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../run/shots/versus_shots_test.dart' as shots show rival, shot;

const _url = 'https://firebasestorage.example/v0/b/x/o/avatars%2Fu.jpg';
const _green = ui.Color(0xFF00FF00);

/// The game rendered at 1 px per point (RGBA).
Future<(ByteData, int)> _pixels(FlappySpikesGame g) async {
  await _render(g); // warm-up frame (lazily built art caches)
  return _render(g);
}

Future<(ByteData, int)> _render(FlappySpikesGame g) async {
  final w = 320, h = g.viewHeight.round();
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = g.backgroundColor(),
  );
  g.render(c);
  final im = await rec.endRecording().toImage(w, h);
  final data = (await im.toByteData())!;
  im.dispose();
  return (data, w);
}

/// How many pixels of [r] pass [test] (r, g, b in 0..255).
int _count(
  (ByteData, int) px,
  ui.Rect r,
  bool Function(int r, int g, int b) test,
) {
  final (d, w) = px;
  var n = 0;
  for (var y = r.top.ceil(); y < r.bottom.floor(); y++) {
    for (var x = r.left.ceil(); x < r.right.floor(); x++) {
      final i = (y * w + x) * 4;
      if (test(d.getUint8(i), d.getUint8(i + 1), d.getUint8(i + 2))) n++;
    }
  }
  return n;
}

/// The solid test picture.
bool _isGreen(int r, int g, int b) => g > 200 && r < 60 && b < 60;

/// The sky bird's blue (also under the plate's fading lock flash).
bool _isSky(int r, int g, int b) => b > 200 && b - r > 80;

Future<ui.Image> _solid(ui.Color c) async {
  final rec = ui.PictureRecorder();
  ui.Canvas(
    rec,
  ).drawRect(const ui.Rect.fromLTWH(0, 0, 8, 8), ui.Paint()..color = c);
  return rec.endRecording().toImage(8, 8);
}

OpponentRun _opp({String avatar = ''}) {
  final r = shots.rival(
    name: 'Pond',
    score: 12,
    look: const Look(bird: 'sky', hat: 'cap'),
  );
  return OpponentRun(
    uid: r.uid,
    name: r.name,
    score: r.score,
    best: r.best,
    level: r.level,
    look: r.look,
    timeline: r.timeline,
    runId: r.runId,
    avatarUrl: avatar,
  );
}

/// PRD-2.3 §21.3 / §21.5 the opponent's square: their picture from the URL,
/// else (no URL, or the load fails) their own bird in their look; the grey
/// person icon never.
void main() {
  setUpAll(() async {
    final opificio = FontLoader('Opificio Neue')
      ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
    final fredoka = FontLoader('Fredoka')
      ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
    await Future.wait([opificio.load(), fredoka.load()]);
  });
  for (final h in [568.0, 711.0]) {
    final tag = h.round();
    for (final (label, avatar, picture) in [
      ('a URL shows the picture', _url, true),
      ('no URL shows their bird', '', false),
      (
        'a failed load shows their bird',
        'https://nowhere.example/x.jpg',
        false,
      ),
    ]) {
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(
          worldHeight: h,
          prefs: {'bestScore': 640},
          versus: FakeVersusService(pool: [_opp(avatar: avatar)]),
        ),
        gameSize: Vector2(320, h),
      ).testGameWidget(
        '§21.5 $label (intro and HUD, $tag)',
        setUp: (g, _) async {
          await g.ready();
          await preloadImages(g);
        },
        verify: (g, tester) async {
          if (picture) {
            final im = (await tester.runAsync(() => _solid(_green)))!;
            g.avatars.images.add(_url, im);
          }
          g.onScreenTap();
          await flushAndMount(g);
          final intro = g.versusIntro!;
          for (var i = 0; i < 600 && intro.time < intro.lockAt + .8; i++) {
            g.update(1 / 60);
            await Future<void>.value();
          }
          final plate = intro.oppPlate;
          final topLeft = plate.absoluteTopLeftPosition;
          const s = VersusConfig.plateSlot;
          final sq = ui.Rect.fromLTWH(
            topLeft.x + 2,
            topLeft.y + 2,
            s - 4,
            s - 4,
          );
          await tester.runAsync(
            () => shots.shot(
              g,
              1.5,
              's21_avatar_${picture ? 'pic' : 'bird'}_intro_$tag',
            ),
          );
          g.onGameResize(Vector2(320, h));
          var px = (await tester.runAsync(() => _pixels(g)))!;
          final area = sq.width * sq.height;
          if (picture) {
            expect(_count(px, sq, _isGreen), greaterThan(area * .5));
          } else {
            expect(_count(px, sq, _isGreen), 0);
            expect(
              _count(px, sq, _isSky),
              greaterThan(area * .1),
              reason: 'their sky bird fills the square',
            );
          }
          await finishVersusIntro(g);
          for (var i = 0; i < 40; i++) {
            g.update(1 / 60);
          }
          await flushAndMount(g);
          const rowH = HudConfig.rowHeight;
          final themAv = ui.Rect.fromLTWH(
            HudConfig.themLeft + HudConfig.boxWidth - rowH + 2,
            HudConfig.rowTop + 2,
            rowH - 4,
            rowH - 4,
          );
          px = (await tester.runAsync(() => _pixels(g)))!;
          final a2 = themAv.width * themAv.height;
          if (picture) {
            expect(_count(px, themAv, _isGreen), greaterThan(a2 * .5));
          } else {
            expect(_count(px, themAv, _isGreen), 0);
            expect(_count(px, themAv, _isSky), greaterThan(a2 * .1));
          }
          await tester.runAsync(
            () => shots.shot(
              g,
              1.5,
              's21_avatar_${picture ? 'pic' : 'bird'}_hud_$tag',
            ),
          );
        },
      );
    }
  }
}
