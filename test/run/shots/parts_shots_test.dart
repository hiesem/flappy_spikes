import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/effects/block_trail.dart';
import 'package:flappy_spikes/run/effects/coin_popup.dart';
import 'package:flappy_spikes/run/effects/dashed_path.dart';
import 'package:flappy_spikes/run/effects/dust_puff.dart';
import 'package:flappy_spikes/run/effects/fetch_flight.dart';
import 'package:flappy_spikes/run/effects/gold_sticker.dart';
import 'package:flappy_spikes/run/effects/particle_pool.dart';
import 'package:flappy_spikes/run/effects/perfect_burst.dart';
import 'package:flappy_spikes/run/effects/pickup_touch_fx.dart';
import 'package:flappy_spikes/run/effects/ring_tier_fx.dart';
import 'package:flappy_spikes/run/effects/screen_edge_glow.dart';
import 'package:flappy_spikes/run/effects/shock_ring.dart';
import 'package:flappy_spikes/run/effects/spike_teeth.dart';
import 'package:flappy_spikes/run/effects/twinkle.dart';
import 'package:flappy_spikes/run/hoops/ring_painter.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/skins/art/look_painter.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// WP-0c screenshot check of every shared part (PRD-2 §3.0.9 masters and
/// the ARCH §3 extra parts). Writes PNGs at 1.5 x (480 x 1067 = the mock
/// PNG size) to `build/parts_shots/` for a side-by-side look with the
/// approved mocks in `design/menu_v2/` (the contact sheets are built with
/// ffmpeg from these files). Nothing here is asserted beyond "rendered".
const String outDir = 'build/parts_shots';
const double k = 1.5; // mock PNG scale
const double viewH = 711;

const Color bg = Color(0xFFF1F1F1);
const Color fg = Color(0xFF828282);

Future<void> _fonts() async {
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  await Future.wait([lvdc.load(), opificio.load()]);
}

Future<ui.Image> _image(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

Future<void> _write(
  String name,
  void Function(Canvas c) draw, {
  double w = 320,
  double h = viewH,
  Color background = bg,
  double scale = k,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(scale);
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = background);
  draw(canvas);
  final image = await recorder.endRecording().toImage(
    (w * scale).round(),
    (h * scale).round(),
  );
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  image.dispose();
  final file = File('$outDir/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  debugPrint('SHOT ${file.path}');
  expect(bytes.length, greaterThan(1000));
}

void _strips(Canvas c, {Color color = fg, double offset = 0}) {
  SpikeTeethPainter.paint(c, width: 320, color: color, offset: offset);
  c.save();
  c.translate(0, viewH);
  c.scale(1, -1);
  SpikeTeethPainter.paint(c, width: 320, color: color, offset: offset);
  c.restore();
}

/// The bird with its body centre at [p] (LookComponent anchoring).
void _bird(
  Canvas c,
  Offset p, {
  Look look = Look.defaults,
  bool gold = false,
  bool dead = false,
  bool flap = false,
  double angle = 0,
  double scale = Config.lookScale,
}) {
  c.save();
  c.translate(p.dx, p.dy);
  c.rotate(angle);
  c.scale(scale);
  c.translate(1, 0); // art-box centre (22,18) vs body centre (21,18)
  LookPainter.paint(c, look, t: .3, gold: gold, dead: dead, flap: flap);
  c.restore();
}

void _scoreCircle(Canvas c, ui.Image disc, int score) {
  final centre = const Offset(160, viewH / 2 + 35);
  final paint = Paint()
    ..colorFilter = const ColorFilter.mode(fg, BlendMode.modulate);
  c.drawImageRect(
    disc,
    Rect.fromLTWH(0, 0, disc.width.toDouble(), disc.height.toDouble()),
    Rect.fromCenter(center: centre, width: 183, height: 183),
    paint,
  );
  final tp = TextPainter(
    text: TextSpan(
      text: '$score',
      style: const TextStyle(
        fontFamily: Config.scoreFont,
        fontSize: 125,
        color: bg,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, centre - Offset(tp.width / 2, tp.height / 2));
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _fonts();

  group('§3.0.9 shared parts shots', () {
    testWidgets('#1 spike strip 44 pt + #2 score circle + #3 M0 ring', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final disc = await _image('assets/images/background_score.png');
        // hoops_m0.png layout (640 x 1422 = 2x): rings at the mock places.
        await _write('01_hoops_m0', (c) {
          _scoreCircle(c, disc, 12);
          _strips(c);
          for (final (x, y) in [(110.0, 260.0), (270.0, 400.0)]) {
            RingPainter.paintHalf(c, centre: Offset(x, y), opening: 92 - 14, front: false);
          }
          _bird(c, const Offset(70, 300));
          for (final (x, y) in [(110.0, 260.0), (270.0, 400.0)]) {
            RingPainter.paintHalf(c, centre: Offset(x, y), opening: 92 - 14, front: true);
          }
        });
        await _write('01_hoops_m0_big', (c) {
          _scoreCircle(c, disc, 12);
          _strips(c);
          for (final front in [false, true]) {
            for (final (x, y) in [(110.0, 260.0), (270.0, 400.0)]) {
              RingPainter.paintHalf(
                c,
                centre: Offset(x, y),
                opening: (92 - 14) * 1.5,
                front: front,
                colors: RingColors.gold,
              );
            }
            if (!front) _bird(c, const Offset(70, 300));
          }
        });
        // Every opening of the ramp + tilt + skins + ghost/dash.
        await _write('03_ring_variants', (c) {
          _strips(c);
          final openings = [118.0, 105.0, 92.0, 177.0];
          for (var i = 0; i < openings.length; i++) {
            RingPainter.paintBoth(c, centre: Offset(40 + i * 80, 160), opening: openings[i]);
          }
          final skins = ['pink', 'sky', 'candy', 'neon', 'galaxy', 'blackhole'];
          for (var i = 0; i < skins.length; i++) {
            RingPainter.paintBoth(
              c,
              centre: Offset(30 + i * 52, 360),
              opening: 92,
              skinId: skins[i],
              t: .7,
            );
          }
          for (var i = 0; i < 4; i++) {
            RingPainter.paintBoth(
              c,
              centre: Offset(40 + i * 80, 550),
              opening: 105,
              tilt: [-45.0, -15.0, 15.0, 45.0][i] * math.pi / 180,
            );
          }
          for (final front in [false, true]) {
            RingPainter.paintHalf(
              c,
              centre: const Offset(280, 160),
              opening: 92,
              front: front,
              colors: RingColors.ghost,
              opacity: .35,
              dash: const [6, 6],
            );
          }
        });
        // The 72 pt physics strip drawn with the new teeth (before WP-1a).
        await _write('01_strip_72_reach', (c) {
          SpikeTeethPainter.paint(c, width: 320, color: fg, reach: 72);
          c.save();
          c.translate(0, viewH);
          c.scale(1, -1);
          SpikeTeethPainter.paint(c, width: 320, color: fg, reach: 44, offset: 13);
          c.restore();
        });
      });
    });

    testWidgets('#4–#6, #10, #11 ring tiers with the gold bird and trail', (
      tester,
    ) async {
      await tester.runAsync(() async {
        for (final tier in [0, 1, 2, 3]) {
          final rnd = math.Random(3 + tier);
          final fxA = RingTierFx(random: rnd, opening: 92 - 14)..tier = tier;
          final fxB = RingTierFx(random: rnd, opening: 92 - 14)..tier = tier;
          final pool = ParticlePool();
          final trail = BlockTrail(random: rnd);
          const bird = Offset(84, 300);
          for (var f = 0; f < 90; f++) {
            fxA.update(1 / 60);
            fxB.update(1 / 60);
            if (tier >= 3) trail.update(pool, 1 / 60, bird, 0);
            pool.step(1 / 60);
          }
          final colors = RingPainter.colorsForTier(tier);
          await _write('04_ringtier_$tier', (c) {
            _strips(c);
            for (final (fx, centre) in [
              (fxA, const Offset(100, 300)),
              (fxB, const Offset(330, 420)),
            ]) {
              c.save();
              c.translate(centre.dx, centre.dy);
              fx.paintBack(c);
              c.restore();
              RingPainter.paintHalf(c, centre: centre, opening: 78, front: false, colors: colors);
            }
            pool.paint(c);
            _bird(c, bird, gold: tier >= 2);
            for (final (fx, centre) in [
              (fxA, const Offset(100, 300)),
              (fxB, const Offset(330, 420)),
            ]) {
              RingPainter.paintHalf(c, centre: centre, opening: 78, front: true, colors: colors);
              c.save();
              c.translate(centre.dx, centre.dy);
              fx.paintFront(c);
              c.restore();
            }
            if (tier > 0) {
              final b = StreakBanner(tier)..update(.5);
              c.save();
              c.translate(0, b.position.y);
              b.render(c);
              c.restore();
            }
          });
        }
      });
    });

    testWidgets('#4 #5 #6 bird looks: classic, gold, dead X, other skins', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await _write('05_birds', (c) {
          final birds = ['classic', 'sky', 'night', 'ghost', 'owl', 'duck', 'robo', 'golden'];
          for (var i = 0; i < birds.length; i++) {
            final x = 30.0 + (i % 4) * 80;
            final y = 80.0 + (i ~/ 4) * 300;
            final look = Look(bird: birds[i]);
            _bird(c, Offset(x, y), look: look, scale: 2);
            _bird(c, Offset(x, y + 80), look: look, gold: true, scale: 2);
            _bird(c, Offset(x, y + 160), look: look, dead: true, scale: 2, angle: .4);
          }
        });
        // Gold + dead at game scale on the miss-flash mock layout.
        await _write('05_dead_on_strip', (c) {
          _strips(c);
          _bird(c, Offset(160, viewH - 44 - 14.75 + 4), dead: true);
          _bird(c, Offset(220, viewH - 44 - 14.75 + 4), dead: true, gold: true);
          for (final front in [false, true]) {
            RingPainter.paintHalf(
              c,
              centre: const Offset(110, 330),
              opening: 92,
              front: front,
              colors: RingColors.ghost,
              opacity: .35,
              dash: const [6, 6],
            );
          }
        });
      });
    });

    testWidgets('#7 streak banners, #8 coin popup, #9 burst, 5.1 pulse', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final coin = await _image('assets/images/menu/coin.png');
        await _write('07_banners', (c) {
          for (var tier = 1; tier <= 10; tier++) {
            final b = StreakBanner(tier);
            final (sy, _) = b.curveAt(b.duration * .5);
            expect(sy, 1);
            b.update(b.duration * .5);
            c.save();
            c.translate(0, 20 + (tier - 1) * 66.0);
            b.render(c);
            c.restore();
          }
        }, background: const Color(0xFFF4E2BF));
        // perfect_tier5.png layout: banner tier 5, burst, +2 coin.
        for (final tier in [1, 2, 3, 5, 10]) {
          final rnd = math.Random(tier);
          final pool = ParticlePool();
          const at = Offset(84, 420);
          PerfectBurst.emit(pool, at, tier, rnd);
          for (var f = 0; f < 9; f++) {
            pool.step(1 / 60);
          }
          final popup = CoinPopup()
            ..coinImage = coin
            ..play(at, 2);
          popup.time = .3;
          final banner = StreakBanner(tier)..update(.5);
          await _write('07_perfect_tier$tier', (c) {
            _strips(c, color: const Color(0xFFA08C6A));
            pool.paint(c);
            _bird(c, at, gold: tier >= 2);
            c.save();
            c.translate(at.dx, at.dy);
            popup.renderAt(c, popup.progress);
            c.restore();
            c.save();
            c.translate(0, banner.position.y);
            banner.render(c);
            c.restore();
          }, background: const Color(0xFFF4E2BF));
        }
        // Coin popup timeline strip: k = 0 .. 1.
        await _write('08_coin_popup_timeline', (c) {
          for (var i = 0; i <= 8; i++) {
            final p = CoinPopup()
              ..coinImage = coin
              ..play(Offset(40.0 + (i % 3) * 110, 150.0 + (i ~/ 3) * 200), i == 8 ? 4 : (i.isEven ? 2 : 1), doubled: i == 8);
            p.time = p.duration * i / 8;
            c.save();
            c.translate(p.position.x, p.position.y);
            c.drawCircle(Offset.zero, 2, Paint()..color = const Color(0xFFFF0000));
            p.renderAt(c, p.progress);
            c.restore();
          }
        });
        // Burst frames per tier and the non-perfect pulse / miss wave.
        await _write('09_burst_pulse', (c) {
          for (var tier = 1; tier <= 3; tier++) {
            for (var f = 0; f < 3; f++) {
              final pool = ParticlePool();
              final at = Offset(60.0 + f * 100, 80.0 + (tier - 1) * 120);
              PerfectBurst.emit(pool, at, tier, math.Random(tier * 10 + f));
              for (var s = 0; s < [1, 12, 24][f]; s++) {
                pool.step(1 / 60);
              }
              pool.paint(c);
            }
          }
          for (var f = 0; f < 3; f++) {
            final centre = Offset(60.0 + f * 100, 470);
            RingPainter.paintBoth(c, centre: centre, opening: 78);
            final ring = ShockRing()..passPulse(centre, opening: 78);
            ring.time = ring.duration * [.05, .3, .6][f];
            c.save();
            c.translate(centre.dx, centre.dy);
            ring.renderAt(c, ring.progress);
            c.restore();
            final miss = ShockRing()..missWave(centre + const Offset(0, 160), opening: 78);
            miss.time = miss.duration * [.05, .3, .6][f];
            c.save();
            c.translate(centre.dx, centre.dy + 160);
            miss.renderAt(c, miss.progress);
            c.restore();
          }
        });
      });
    });

    testWidgets('#10 block trail follows the flight direction', (tester) async {
      await tester.runAsync(() async {
        await _write('10_trail_direction', (c) {
          final cases = <(Offset, double)>[
            (const Offset(160, 110), 0),
            (const Offset(160, 260), -35 * math.pi / 180),
            (const Offset(160, 420), 40 * math.pi / 180),
          ];
          for (final (bird, h) in cases) {
            final pool = ParticlePool();
            final trail = BlockTrail(random: math.Random(5));
            for (var f = 0; f < 40; f++) {
              trail.update(pool, 1 / 60, bird, h);
              pool.step(1 / 60);
            }
            pool.paint(c);
            _bird(c, bird, gold: true, angle: h);
          }
          // Curved flight: heading follows an arc.
          final pool = ParticlePool();
          final trail = BlockTrail(random: math.Random(9));
          var bird = const Offset(60, 640);
          for (var f = 0; f < 60; f++) {
            final h = -math.pi / 2 * f / 60;
            bird += Offset(math.cos(h), math.sin(h)) * 4;
            trail.update(pool, 1 / 60, bird, h);
            pool.step(1 / 60);
          }
          pool.paint(c);
          _bird(c, bird, gold: true, angle: -math.pi / 2);
        });
      });
    });

    testWidgets('dust puff, pickup touch, fetch flight, twinkle, sticker', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await _write('11_dust_pickups', (c) {
          _strips(c);
          for (var f = 0; f < 3; f++) {
            final pool = ParticlePool();
            final at = Offset(60.0 + f * 100, viewH - 44);
            DustPuff.emit(pool, at, fg, math.Random(f));
            for (var s = 0; s < [2, 15, 35][f]; s++) {
              pool.step(1 / 60);
            }
            pool.paint(c);
          }
          final specs = [
            PickupTouchSpec.feather,
            PickupTouchSpec.puzzlePiece.withBodyColor(const Color(0xFF0CD9FF)),
            PickupTouchSpec.heart,
            PickupTouchSpec.capsule.withBodyColor(const Color(0xFF2F80FF)),
          ];
          for (var i = 0; i < specs.length; i++) {
            final pool = ParticlePool();
            final at = Offset(45.0 + i * 76, 110);
            final fx = PickupTouchFx()..play(at, specs[i], pool: pool, random: math.Random(i));
            for (var s = 0; s < 8; s++) {
              pool.step(1 / 60);
            }
            fx.time = 8 / 60;
            pool.paint(c);
            c.save();
            c.translate(at.dx, at.dy);
            fx.renderAt(c, fx.progress);
            c.restore();
          }
          for (var i = 0; i < 6; i++) {
            Twinkle.paint(
              c,
              Offset(40.0 + i * 48, 200),
              8.0 + i * 3,
              i.isEven ? const Color(0xFFFFD54A) : const Color(0xFFFFB529),
              waist: i < 3 ? Twinkle.ringWaist : Twinkle.pickupWaist,
            );
          }
          // Fetch flight path sampled every 0.06 s with its trail.
          final pool = ParticlePool();
          final flight = FetchFlight(
            from: const Offset(84, 420),
            to: const Offset(160, 230),
            art: (cc, s, r) {
              cc.save();
              cc.rotate(r);
              cc.drawRect(
                Rect.fromCenter(center: Offset.zero, width: 10 * s, height: 16 * s),
                Paint()..color = const Color(0xFFFFB529),
              );
              cc.restore();
            },
            pool: pool,
            random: math.Random(1),
          );
          for (var f = 0; f < 40; f++) {
            flight.update(1 / 60);
            pool.step(1 / 60);
            if (f % 4 == 0 && !flight.landed) flight.render(c);
          }
          pool.paint(c);
          final newBest = GoldSticker.newBest()..update(1);
          c.save();
          c.translate(160 - newBest.box.width / 2, 520 - newBest.box.height / 2);
          newBest.render(c);
          c.restore();
          final bonus = GoldSticker.collect('BONUS UNLOCKED!')..update(1);
          c.save();
          c.translate(160 - bonus.box.width / 2, 580 - bonus.box.height / 2);
          bonus.render(c);
          c.restore();
          DashedPathPainter.line(c, const Offset(20, 630), const Offset(300, 630), color: fg.withValues(alpha: .75));
        });
        await _write('12_edge_glows', (c) {
          final size = Vector2(320, viewH);
          final miss = ScreenEdgeGlow.miss(size)..update(.35);
          miss.render(c);
          final frenzy = ScreenEdgeGlow.coinFrenzy(size)..update(.2);
          frenzy.render(c);
        });
      });
    });

  });

  // Master #1 in the menus: the strips switched to the 44 pt teeth art
  // must read exactly like today's inset sprite (44 pt) on the home screen.
  FlameTester<FlappySpikesGame>(
    () => createTestGame(const {
      'bestScore': 12,
      'gamesPlayed': 34,
      'claimedLevels': ['1'],
      'coins': 1250,
    }, 711),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    '§3.0.9 #1 menu with the 44 pt teeth art (WP-1a one-line switch)',
    setUp: (game, tester) async {
      await game.ready();
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      for (final strip in game.world.children.whereType<SpikeStrip>()) {
        expect(strip.art, SpikeArt.teeth, reason: 'the default since WP-1a');
        expect(strip.toothReach, 44, reason: 'menus show the 44 pt strip');
      }
      Future<void> shot(String name) => tester.runAsync(() async {
        final shotSize = Vector2(480, (711 * 1.5).roundToDouble());
        game.onGameResize(shotSize);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, shotSize.x, shotSize.y),
          Paint()..color = game.backgroundColor(),
        );
        game.render(canvas);
        final image = await recorder.endRecording().toImage(
          shotSize.x.toInt(),
          shotSize.y.toInt(),
        );
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        final file = File('$outDir/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        expect(bytes.length, greaterThan(10000));
      });
      await shot('13_menu_teeth');
      for (final strip in game.world.children.whereType<SpikeStrip>()) {
        strip.art = SpikeArt.sprite;
      }
      await shot('13_menu_sprite');
    },
  );
}
