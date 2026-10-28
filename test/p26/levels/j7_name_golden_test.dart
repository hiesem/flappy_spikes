// J7: 320 pt evidence of the shared rank fitting seam, real Settings card,
// HUD name renderer, badge layout and real share painter. The three fitting
// specimens are not component integration goldens: J3/J8 own the real results
// rank line and versus plate goldens (J7 review round 2 decision).
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/levels/emblem_view.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/levels/level_track.dart';
import 'package:flappy_spikes/run/hud/fit_name.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/share/share_card.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import '../../menu_screenshot_test.dart' show loadFonts;
import '../../share/share_card_golden_test.dart' show loadCardFonts;

void text(
  ui.Canvas c,
  String s,
  double x,
  double y,
  double size, {
  String font = 'Opificio Neue',
  ui.Color color = const ui.Color(0xFF7A0044),
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontFamily: font, fontSize: size, color: color),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  tp.paint(c, ui.Offset(x, y));
  tp.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadFonts();
    await loadCardFonts();
  });
  for (final level in [19, 23, 24, 999]) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: 568),
      gameSize: Vector2(320, 568),
    ).testGameWidget(
      'J7 320pt ${trackLevelDef(level)!.name} $level',
      setUp: (g, tester) async {
        await g.ready();
        await preloadImages(g);
        await flushAndMount(g);
        g.storage.lvlIndex = level;
        g.openSettings();
        await flushAndMount(g);
        stepGame(g, .6);
        await flushAndMount(g);
      },
      verify: (g, tester) async {
        final card = g.world.children.query<SettingsPanel>().single.playerCard;
        final name = trackLevelDef(level)!.name;
        final measure = measureName(fontFamily: 'Opificio Neue');
        final rank = fitRankName(name, level, 292, 18, measure);
        final fitted = fitLevelName(
          name,
          level,
          202,
          20,
          measure,
          measureBadge: measureName(fontFamily: 'Fredoka'),
        );
        await tester.runAsync(() async {
          // J8 assets load asynchronously; capture the resolved emblem.
          await card.children.query<EmblemView>().single.imageReady;
          final assets = await ShareCardAssets.load();
          final recorder = ui.PictureRecorder();
          final c = ui.Canvas(recorder);
          c.drawColor(const ui.Color(0xFFF1F1F1), ui.BlendMode.src);
          text(c, 'RESULTS RANK LINE', 14, 8, 10);
          text(
            c,
            rank.text,
            (320 - measure(rank.text, rank.size)) / 2,
            26,
            rank.size,
          );
          text(c, 'SETTINGS PLAYER CARD', 14, 57, 10);
          c.save();
          c.translate(14 - card.x, 75 - card.y);
          card.renderTree(c);
          c.restore();
          text(c, 'VERSUS NAME BOX', 14, 155, 10);
          final picture = recordEmblem(
            level,
            look: const Look(),
            progression: true,
          );
          c.save();
          c.translate(45, 209);
          c.scale(.32);
          c.drawPicture(picture);
          c.restore();
          picture.dispose();
          c.drawRect(
            const ui.Rect.fromLTWH(90, 186, 130, 32),
            ui.Paint()..color = const ui.Color(0xFFFFFFFF),
          );
          final hud = HudText.name(
            name,
            maxWidth: 116,
            size: 15,
            color: const ui.Color(0xFF7A0044),
          );
          expect(hud.text, name);
          hud.paintCentred(c, const ui.Offset(155, 202));
          text(c, 'NAME + LEVEL BADGE', 14, 249, 10);
          const start = 14.0;
          text(c, name, start, 268, fitted.size);
          final badgeX = start + measure(name, fitted.size) + 6;
          c.drawRect(
            ui.Rect.fromLTWH(badgeX, 268, fitted.badgeWidth, 20),
            ui.Paint()..color = const ui.Color(0xFFEC008C),
          );
          text(
            c,
            '$level',
            badgeX + 5,
            270,
            12,
            font: 'Fredoka',
            color: const ui.Color(0xFFFFFFFF),
          );
          text(c, 'SHARE CARD', 14, 308, 10);
          c.save();
          c.translate(0, 326);
          c.scale(320 / 1080);
          c.clipRect(const ui.Rect.fromLTWH(0, 0, 1080, 1080));
          ShareCardPainter.paint(
            c,
            ShareCardData(
              kind: ShareCardKind.spotlight,
              score: 180,
              best: 640,
              level: level,
              progression: true,
              look: const Look(),
              name: 'Player999',
              banner: 'BEAT MY SCORE!',
              bannerId: 1,
              text: '',
              textId: 1,
            ),
            assets,
          );
          c.restore();
          final pic = recorder.endRecording();
          final image = await pic.toImage(320, 646);
          pic.dispose();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await expectLater(
            png!.buffer.asUint8List(),
            matchesGoldenFile('goldens/j7_names_$level.png'),
          );
        });
      },
    );
  }
}
