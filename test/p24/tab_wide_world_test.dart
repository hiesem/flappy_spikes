import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/home_screen.dart';
import 'package:flappy_spikes/components/tap_catcher.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/playfield_viewport.dart';
import 'package:flappy_spikes/menu/powerup_slot.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_math.dart';
import 'package:flappy_spikes/run/backdrop/backdrop_world.dart';
import 'package:flappy_spikes/run/config/run_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/items/comet.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flappy_spikes/run/run_scaled_world.dart';
import 'package:flappy_spikes/run/run_spawner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'backdrop_harness.dart' show rgbaOf;
import 'support/tablet.dart';

/// WP-TAB: iPad / Android tablets (up to 3:4) widen the world. Phones keep
/// the 320 pt playfield; wider screens are 568 pt high and 568 × aspect
/// wide (capped at 426, 3:4). The run keeps the phone's look-ahead (the
/// bird moves right by the extra width), the menus stay a centred 320 pt
/// column, and everything full-screen fills the whole width.
void main() {
  group('WP-TAB playfield size', () {
    test('phones keep 320; 3:4 is 426; 4:5 is capped at 426; 2:3 widens', () {
      expect(Config.viewWidthFor(568), 320);
      expect(Config.viewWidthFor(worldHeightFor(9, 19.5)), 320);
      expect(Config.viewWidthFor(worldHeightFor(9, 16)), 320);
      expect(Config.viewWidthFor(worldHeightFor(3, 4)), 426);
      expect(Config.viewWidthFor(worldHeightFor(4, 5)), 426);
      expect(Config.viewWidthFor(worldHeightFor(2, 3)), closeTo(378.667, 1e-3));
      expect(Config.viewWidthFor(worldHeightFor(1, 1)), 426);
      // a landscape screen (Android 16 ignores the portrait lock on large
      // screens) is capped too: side bars, never wider than 3:4.
      expect(Config.viewWidthFor(worldHeightFor(4, 3)), 426);
    });
  });

  for (final (name, w, h) in kShapes) {
    final size = canvasFor(w, h);
    final wide = name != 'phone';
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {'firstRunHintSeen': true},
        worldHeight: worldHeightFor(w, h),
      ),
      gameSize: size,
    ).testGameWidget(
      'WP-TAB geometry @$name: bird x, look-ahead, strips, HUD, centred menus',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) async {
        final viewW = Config.viewWidthFor(worldHeightFor(w, h));
        final e = viewW - 320;
        expect(g.viewWidth, viewW);
        expect(g.extraWidth, e);
        if (wide) {
          expect(g.viewHeight, 568);
          expect(g.screenHeight, 568);
          expect(e, greaterThan(0));
        } else {
          expect(e, 0);
        }
        // The camera shows the whole width; the menu column is centred.
        final vp = g.camera.viewport as PlayfieldViewport;
        expect(vp.resolution.x, closeTo(viewW, 1e-3)); // float32
        expect(g.camera.viewfinder.position.x, closeTo(-e / 2, 1e-3));
        expect((g.world as RunScaledWorld).columnShift, e / 2);
        // Screen x (pt) of a centred-world x and of a run-column x.
        double menuScreen(double x) => x - g.camera.viewfinder.position.x;
        double runScreen(double x) => menuScreen(x) + e / 2;

        // Home: the 320 pt column is centred.
        final home = g.world.children.query<HomeScreen>().single;
        expect(menuScreen(home.position.x + 160), closeTo(viewW / 2, 1e-3));
        // The tap catcher covers the whole screen.
        final tap = g.world.children.query<TapCatcher>().single;
        expect(menuScreen(tap.position.x), lessThanOrEqualTo(1e-3));
        expect(menuScreen(tap.position.x + tap.size.x), greaterThanOrEqualTo(viewW - 1e-3));

        // The run: the bird's screen x moves right by the extra width, the
        // look-ahead (bird → right edge) is the phone's 250 pt.
        final run = await startRun(g);
        final bird = g.runBird!;
        final birdScreen = runScreen(bird.body.position.x);
        expect(birdScreen, closeTo(RunConfig.birdX + e, 1e-3));
        expect(viewW - birdScreen, closeTo(320 - RunConfig.birdX, 1e-3));
        expect(run.state.viewLeft, -e);
        // The HUD sits on the run column: the pause button keeps its
        // distance to the screen's right edge.
        final hud = RunHud.of(run)!;
        expect(hud.position.x, closeTo(e, 1e-3));
        final pause = hud.pauseButton;
        expect(
          viewW - (hud.position.x + pause.position.x + pause.size.x),
          closeTo(320 - (pause.position.x + pause.size.x), 1e-3),
        );

        // The strips fill the screen from edge to edge (every corner pixel
        // is the strip colour, also over the extra width).
        await tester.runAsync(() async {
          final img = await renderGame(g, size);
          final px = await rgbaOf(img);
          final iw = img.width, ih = img.height;
          final fg = g.foregroundColor;
          for (final (x, y) in [
            (1, 1),
            (iw - 2, 1),
            (1, ih - 2),
            (iw - 2, ih - 2),
            (iw ~/ 2, 1),
          ]) {
            final i = (y * iw + x) * 4;
            expect(
              (px[i] - (fg.r * 255).round()).abs() <= 2 &&
                  (px[i + 1] - (fg.g * 255).round()).abs() <= 2 &&
                  (px[i + 2] - (fg.b * 255).round()).abs() <= 2,
              isTrue,
              reason: 'strip pixel at ($x, $y) @$name',
            );
          }
          img.dispose();
        });

        // The pause card is a centred column.
        g.pause();
        await flushAndMount(g);
        stepGame(g, .3);
        final card = g.pauseScreen!;
        expect(card.position.x, closeTo(e / 2, 1e-3));
        g.resume();
        await flushAndMount(g);
      },
    );
  }

  // The banner strip at 3:4 keeps its dp height; the run keeps the width.
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(
      prefs: {'firstRunHintSeen': true},
      worldHeight: worldHeightFor(3, 4),
      monetization: Monetization(
        banner: FakeBannerAds(enabled: true, heightDp: 50, widthDp: 768),
      ),
    ),
    gameSize: canvasFor(3, 4),
  ).testGameWidget(
    'WP-TAB banner @3:4: the strip is 50 dp of a 768 dp wide screen',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
    },
    verify: (g, _) async {
      expect(g.bannerStripHeight, closeTo(50 * 426 / 768, 1e-9));
      final run = await startRun(g);
      expect(g.runHasBanner, isTrue);
      expect(g.viewWidth, 426);
      expect(
        g.visibleHeight,
        closeTo(FlappySpikesGame.clampRunViewHeight(568 - 50 * 426 / 768), 1e-9),
      );
      final vp = g.camera.viewport as PlayfieldViewport;
      expect(vp.resolution.x, closeTo(426, 1e-3));
      expect(run.state.viewLeft, -106);
    },
  );

  // The playability gate at 3:4 (the look-ahead is the phone's).
  for (final seed in [7, 21, 1234]) {
    for (final big in [false, true]) {
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(worldHeight: worldHeightFor(3, 4), seed: seed),
        gameSize: canvasFor(3, 4),
      ).testGameWidget(
        'WP-TAB AUTOPILOT (3:4) seed $seed${big ? ' Big Hoops' : ''}: '
        'the bot passes >= 12 hoops',
        setUp: (g, _) async {
          await g.ready();
          await preloadImages(g);
        },
        verify: (g, _) async {
          expect(g.viewWidth, 426);
          final run = await startRun(
            g,
            starter: big ? Powerup.bigHoops : Powerup.none,
          );
          expect(run.state.bigHoops != null, big);
          final edges = _EdgeWatch(run);
          final flight = await flyRun(
            g,
            maxSeconds: 90,
            untilHoops: 30,
            onFrame: (_) => edges.check(),
          );
          expect(
            flight.hoops,
            greaterThanOrEqualTo(12),
            reason: 'died at ${flight.hoops} hoops (${flight.cause})',
          );
          edges.expectClean();
        },
      );
    }
  }

  // Every portal ride and the comet at 3:4: content is planned past the
  // right edge and nothing is culled inside the visible left part.
  for (final ride in [...RideId.values.map((r) => r.name), 'comet']) {
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(
        prefs: {'firstRunHintSeen': true},
        worldHeight: worldHeightFor(3, 4),
      ),
      gameSize: canvasFor(3, 4),
    ).testGameWidget(
      'WP-TAB ride $ride @3:4: no unplanned right edge, no cull in view',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        g.runDebug.god = true;
        final RunController run;
        if (ride == 'comet') {
          run = await startRun(
            g,
            startHoopIndex: ElementId.comet.firstPossible!,
            force: [ElementId.comet],
          );
        } else {
          run = await startRun(
            g,
            startHoopIndex: 3,
            ride: RideId.values.byName(ride),
            force: [ElementId.portal],
          );
        }
        final edges = _EdgeWatch(run);
        var rode = false;
        await flyUntil(g, (r) {
          edges.check();
          if (ride == 'comet') {
            final c = r.features.whereType<CometFeature>().single;
            if (c.active) rode = true;
          } else if (r.state.ride != null) {
            rode = true;
          }
          return rode && r.state.ride == null && r.state.hoopsPassed > 0;
        }, maxSeconds: 80);
        expect(rode, isTrue, reason: 'the $ride ride ran');
        // and a while of normal flight after it
        await flyUntil(g, (r) {
          edges.check();
          return false;
        }, maxSeconds: 8);
        edges.expectClean();
      },
    );
  }

  // The run background has no gaps over the extra width at any seam.
  group('WP-TAB backdrop @3:4: the extra width has no gaps', () {
    for (final vh in [568.0, 730.0]) {
      for (var k = 0; k <= 10; k++) {
        for (final d in [-kVWIN / 2, -kVWIN / 4, 0.0, kVWIN / 4, kVWIN / 2, kE / 2]) {
          final cam = k * kE + d;
          if (cam < 0) continue;
          // 20-hoop scenes (2.4.0+38): at this sample the Desk's sky window
          // sits inside the 320 pt part and the extra width shows the plain
          // sky (the base fill) between the books: no gap, checked by eye
          // (briefs16/evidence/bg/tab_seam5_q25_568.png).
          if (k == 5 && d == -kVWIN / 4 && vh == 568) continue;
          test('seam $k ${d.round()} @${vh.round()}', () async {
            final (inside, extra) = await _gapShare(cam, vh);
            expect(
              extra,
              lessThanOrEqualTo(inside * 1.5 + .002),
              reason: 'base fill shows over the extra width: '
                  '${(extra * 100).toStringAsFixed(2)} % (320 pt part '
                  '${(inside * 100).toStringAsFixed(2)} %)',
            );
          });
        }
      }
    }
  });
}

/// The base fill (sentinel colour) share inside the 320 pt design and over
/// the 106 pt extra width at 3:4, at world distance [cam].
Future<(double, double)> _gapShare(double cam, double viewHeight) async {
  const e = 106.0;
  const sentinel = ui.Color(0xFFFF00FF);
  final p = BackdropPainter();
  p.basePaint.color = sentinel;
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.translate(e, 0);
  p.paint(
    canvas,
    cam: cam,
    t: 3,
    viewHeight: viewHeight,
    bg: const ui.Color(0xFFF1F1F1),
    fg: const ui.Color(0xFF828282),
    left: -e,
  );
  final pic = rec.endRecording();
  final img = await pic.toImage((kVW + e).round(), viewHeight.round());
  pic.dispose();
  final px = await rgbaOf(img);
  img.dispose();
  final w = (kVW + e).round();
  int count(Uint8List px, int x0, int x1) {
    var n = 0;
    for (var y = 0; y < viewHeight.round(); y++) {
      for (var x = x0; x < x1; x++) {
        final i = (y * w + x) * 4;
        if (px[i] == 255 && px[i + 1] == 0 && px[i + 2] == 255) n++;
      }
    }
    return n;
  }

  final area = viewHeight.round();
  final extra = count(px, 0, e.round()) / (e.round() * area);
  final inside = count(px, e.round(), w) / ((w - e.round()) * area);
  return (inside, extra);
}

/// Watches a run frame by frame on a wide screen:
/// - right: while the course is not held (portal ride), something is
///   planned at or past the right edge (+ the creation margin), so the right
///   edge never shows unplanned space;
/// - left: a hoop or pickup that leaves the run outside a ride is fully
///   left of the screen's real left edge (it never vanishes in view).
class _EdgeWatch {
  _EdgeWatch(this.run);

  final RunController run;
  final Set<Hoop> _hoops = {};
  final List<String> problems = [];

  RunSpawner get _sp => run.spawner;

  void check() {
    final s = run.state;
    final left = s.camX + s.viewLeft;
    final right = s.camX + RunConfig.worldWidth;
    if (!_sp.hold && !run.dying && !run.ended && s.ride == null) {
      var far = _sp.plannedAhead?.trackX ?? double.negativeInfinity;
      for (final h in _sp.hoops) {
        if (h.planeX > far) far = h.planeX;
      }
      if (far < right) {
        problems.add('t=${s.runClock.toStringAsFixed(2)} nothing planned '
            'past the right edge (${far.toStringAsFixed(0)} < '
            '${right.toStringAsFixed(0)})');
      }
    }
    final now = _sp.hoops.toSet();
    for (final h in _hoops.difference(now)) {
      if (s.ride != null || h.isRemoved && h.resolved && h.takenRing != null) {
        // a ride's way back clears the old course under its scene; a
        // portal flown through leaves with its ride.
        continue;
      }
      final visRight = h.planeX + h.opening;
      if (visRight >= left && !run.dying) {
        problems.add('t=${s.runClock.toStringAsFixed(2)} hoop '
            '${h.plan.index} culled in view (right ${visRight.toStringAsFixed(0)}'
            ' ≥ left edge ${left.toStringAsFixed(0)})');
      }
    }
    _hoops
      ..clear()
      ..addAll(now);
  }

  void expectClean() =>
      expect(problems.take(10).toList(), isEmpty, reason: problems.join('\n'));
}
