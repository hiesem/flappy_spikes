import 'dart:ui' show Rect;

import 'package:flame/components.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/capsule_config.dart';
import 'package:flappy_spikes/run/config/egg_config.dart';
import 'package:flappy_spikes/run/config/hud_config.dart';
import 'package:flappy_spikes/run/config/jar_config.dart';
import 'package:flappy_spikes/run/config/parts_config.dart';
import 'package:flappy_spikes/run/config/piggy_config.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/pickups/piggy_pickup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import '../../menu_screenshot_test.dart' show captureShot;

/// Fix P6 R1 S6-F03 (PRD-2 §5.26–§5.28, §3.0.9 #7): the collectables' HUD
/// badges sit between the name chips and the timer pill, clear of the
/// banner band, so "PIGGY BANK" / "FIREFLY JAR" / "HATCHED!" and every
/// streak banner never paint through the counters.

/// Text boxes are `height: 1` (HudText): the font size tall, centred.
Rect _text(double x, double cy, double size, double width) =>
    Rect.fromLTWH(x, cy - size / 2, width, size);

/// A piece of the pig art (art units, 1.4× at the HUD pig centre).
Rect _art(double l, double t, double r, double b) => Rect.fromLTRB(
  PiggyConfig.hudPigX + l * PiggyConfig.hudScale,
  PiggyConfig.hudPigY + t * PiggyConfig.hudScale,
  PiggyConfig.hudPigX + r * PiggyConfig.hudScale,
  PiggyConfig.hudPigY + b * PiggyConfig.hudScale,
);

/// The piggy badge's painted extent (pig body and ear; "20 / 20", the
/// bar, "20 missed").
List<Rect> get _piggy => [
  _art(-17, -10, 17, 12), // body, snout, legs, tail
  _art(-7, -15, 0, -7), // the ear
  _text(
    PiggyConfig.hudTextX,
    PiggyConfig.hudTextY,
    PiggyConfig.hudTextSize,
    70,
  ),
  Rect.fromLTWH(
    PiggyConfig.hudBarX,
    PiggyConfig.hudBarY,
    PiggyConfig.hudBarW,
    PiggyConfig.hudBarH,
  ),
  _text(
    PiggyConfig.hudBarX,
    PiggyConfig.hudMissedY,
    PiggyConfig.hudMissedSize,
    60,
  ),
];

/// The jar badge (jar −14…17 glass, lid from −20, at 0.95×; text; ✕ marks).
List<Rect> get _jar => [
  Rect.fromLTRB(
    JarConfig.hudJarX - JarConfig.lidW / 2 * JarConfig.hudJarScale,
    JarConfig.hudJarY + JarConfig.lidY * JarConfig.hudJarScale,
    JarConfig.hudJarX + JarConfig.lidW / 2 * JarConfig.hudJarScale,
    JarConfig.hudJarY + JarConfig.glassBottom * JarConfig.hudJarScale,
  ),
  _text(JarConfig.hudTextX, JarConfig.hudTextY, JarConfig.hudTextSize, 60),
  Rect.fromLTRB(
    JarConfig.markX - JarConfig.markSize - JarConfig.markWidth,
    JarConfig.markY - JarConfig.markSize - JarConfig.markWidth,
    JarConfig.markX +
        (JarConfig.maxEscapes - 1) * JarConfig.markStep +
        JarConfig.markSize +
        JarConfig.markWidth,
    JarConfig.markY + JarConfig.markSize + JarConfig.markWidth,
  ),
];

/// The egg's ×2 pill.
List<Rect> get _egg => [
  const Rect.fromLTWH(
    EggConfig.hudX,
    EggConfig.hudY,
    EggConfig.hudW,
    EggConfig.hudH,
  ),
];

Future<void> _fonts() async {
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  final fredoka = FontLoader('Fredoka')
    ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'));
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  await Future.wait([opificio.load(), fredoka.load(), lvdc.load()]);
}

void main() {
  setUpAll(_fonts);
  const pill = Rect.fromLTWH(
    CapsuleConfig.pillX,
    CapsuleConfig.pillY,
    CapsuleConfig.pillWidth,
    CapsuleConfig.pillHeight,
  );
  const chips = Rect.fromLTWH(
    HudConfig.youLeft,
    HudConfig.rowTop,
    HudConfig.themLeft + HudConfig.boxWidth - HudConfig.youLeft,
    RunConfig.hudBottom - HudConfig.rowTop,
  );
  const heart = Rect.fromLTWH(
    HudConfig.heartLeft,
    HudConfig.rowTop,
    HudConfig.rowHeight,
    HudConfig.rowHeight,
  );

  for (final (name, rects) in [
    ('§5.27 piggy', _piggy),
    ('§5.28 jar', _jar),
    ('§5.26 egg', _egg),
  ]) {
    test('$name HUD: above the banner band (y ${PartsConfig.bannerTop}), '
        'under the name chips, clear of the heart and the timer pill', () {
      for (final r in rects) {
        expect(
          r.bottom,
          lessThanOrEqualTo(PartsConfig.bannerTop),
          reason: '$r',
        );
        expect(r.overlaps(pill), isFalse, reason: '$r vs timer pill');
        expect(r.overlaps(chips), isFalse, reason: '$r vs HUD row / chips');
        expect(r.overlaps(heart), isFalse, reason: '$r vs heart');
      }
    });
  }

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§5.27 PIGGY BANK banner and the piggy counter both readable (shot)',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, tester) async {
      final run = await startRun(g);
      g.runDebug.god = true;
      final bird = run.birdTrackPosition()!;
      run.spawner.spawnItem(
        GapItemPlan(kind: ElementId.piggy, trackX: bird.x + 150, y: bird.y),
      );
      await flushAndMount(g);
      for (var f = 0; f < 300 && run.state.piggy == null; f++) {
        final pickup = pickupsOf(g).whereType<PiggyPickup>().firstOrNull;
        if (pickup != null) g.runBird!.setFlight(y: pickup.position.y, vy: 0);
        g.update(1 / 60);
        if (f % 10 == 0) await flushAndMount(g);
      }
      // Into the banner's hold.
      for (var f = 0; f < 30; f++) {
        g.update(1 / 60);
        await flushAndMount(g);
      }
      final banner = RunHud.ensureFor(run).banners.current!;
      expect(banner.text, 'PIGGY BANK');
      expect(banner.curveAt(banner.time), (1.0, 1.0), reason: 'in its hold');
      final band = Rect.fromLTWH(
        banner.position.x,
        banner.position.y,
        banner.bandWidth,
        banner.bandHeight,
      );
      for (final r in _piggy) {
        expect(r.overlaps(band), isFalse, reason: '$r vs $band');
      }
      await tester.runAsync(
        () => captureShot(g, 1.5, 's6_f03_piggy_banner_711'),
      );
    },
  );
}
