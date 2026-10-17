import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/spike_strip.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/palettes.dart';
import 'package:flappy_spikes/run/config/results_config.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/opponent.dart';
import 'package:flappy_spikes/versus/timeline.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

// captureShot's pattern, using the visible height for §7.5's cropped view.
// Rendering a 544-point logical field into a 524-point view otherwise adds
// spurious stage-coloured margins to the saved PNG despite correct UI pixels.
Future<void> _capture(FlappySpikesGame g, String name) async {
  if (g.visibleHeight == g.viewHeight) {
    await captureShot(g, 2, name);
    return;
  }
  final size = Vector2(640, g.visibleHeight * 2);
  g.onGameResize(size);
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.x, size.y),
    ui.Paint()..color = g.backgroundColor(),
  );
  g.render(canvas);
  final picture = rec.endRecording();
  final image = await picture.toImage(size.x.round(), size.y.round());
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('build/menu_shots/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
}

// QA P3 fills §31's missing bonus / versus / CLAIM assertions and checks
// §7.5's genuinely shortened visible viewport (not merely a logical height).
Future<Uint8List> _frame(FlappySpikesGame g) async {
  g.onGameResize(Vector2(320, g.visibleHeight));
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, 320, g.visibleHeight),
    ui.Paint()..color = g.backgroundColor(),
  );
  g.render(canvas);
  final picture = rec.endRecording();
  final image = await picture.toImage(320, g.visibleHeight.round());
  picture.dispose();
  final raw = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  return raw!.buffer.asUint8List();
}

ui.Color _pixel(Uint8List bytes, int x, int y) {
  final i = (y * 320 + x) * 4;
  return ui.Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
}

Future<void> _grey(FlappySpikesGame g) async {
  expect(g.stageKey, 30, reason: 'the underlying run is still cyan');
  expect(g.postRunPageUp, isTrue);
  final rays = g.resultsScreen?.stage.rays;
  g.resultsScreen?.stage.rays = 0;
  final bytes = await _frame(g);
  if (rays != null) g.resultsScreen!.stage.rays = rays;
  expect(_pixel(bytes, 2, 300), kPostRunPalette.background);
  expect(_pixel(bytes, 5, 5), kPostRunPalette.foreground);
  expect(
    _pixel(bytes, 5, g.visibleHeight.round() - 3),
    kPostRunPalette.foreground,
  );
  expect(g.bannerStripColor.value, kPostRunPalette.foreground);
  for (final strip in g.world.children.whereType<SpikeStrip>()) {
    expect(strip.onPage, isTrue);
    expect(strip.squeezedReach, strip.toothReach);
    expect(strip.toothFlash, 0);
  }
}

ui.Rect _box(ResultsScreen page, PositionComponent child) {
  final scale = page.content.scale.y;
  return ui.Rect.fromLTWH(
    page.content.position.x + child.position.x * scale,
    page.content.position.y + child.position.y * scale,
    child.size.x * scale,
    child.size.y * scale,
  );
}

void _fits(FlappySpikesGame g, ResultsScreen page) {
  final next = _box(page, page.nextButton);
  final reward = _box(page, page.rewardPill);
  final lowerTeeth = g.visibleHeight - g.bottomStripInset;
  expect(next.bottom, lessThan(lowerTeeth));
  expect(reward.bottom, lessThan(next.top));
  expect(next.left, greaterThanOrEqualTo(0));
  expect(next.right, lessThanOrEqualTo(320));
  if (page.claimShowing) {
    final claim = _box(page, page.claimButton);
    expect(claim.bottom, lessThan(reward.top));
    expect(claim.top, greaterThan(44));
  }
}

void main() {
  for (final visible in [711.0, 568.0, 524.0]) {
    for (final result in ['solo', 'win', 'lose', 'draw']) {
      // Sixty clean passes yield 60 points; all three versus outcomes are
      // exercised through the real run recorder and post-run flow.
      final rivalScore = switch (result) {
        'win' => 1,
        'lose' => 100,
        _ => 60,
      };
      final versus = FakeVersusService(
        pool: result == 'solo'
            ? []
            : [
                OpponentRun(
                  uid: 'qa-p3-rival',
                  name: 'Rival',
                  score: rivalScore,
                  best: rivalScore,
                  level: 1,
                  timeline: RunTimeline()
                    ..addEntry(3, rivalScore)
                    ..end(20),
                ),
              ],
      );
      FlameTester<FlappySpikesGame>(
        () => createRunTestGame(
          worldHeight: visible == 524 ? 568 : visible,
          prefs: const {
            'feathers': 3,
            'bestScore': 12,
            'playerLevel': 1, // WP-L EGG (claimed): the 60 run steps to CHICK
            'claimedLevels': ['1'],
          },
          versus: versus,
          monetization: visible == 524
              ? Monetization(
                  banner: FakeBannerAds(
                    enabled: true,
                    heightDp: 44,
                    widthDp: 320,
                  ),
                )
              : null,
        ),
        gameSize: Vector2(320, visible),
      ).testGameWidget(
        '§31 × §7.5 $result at $visible: cyan squeeze → revive → grey bonus '
        '→ grey LEVEL UP / CLAIM → Home',
        setUp: (g, _) async {
          await g.ready();
          await preloadImages(g);
          await loadFonts();
          await (FontLoader('Fredoka')
                ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf')))
              .load();
          await flushAndMount(g);
        },
        verify: (g, tester) async {
          await tester.runAsync(() async {
            await versus.prefetch();
            final run = await startRun(g);
            g.runDebug.god = true;
            for (var i = 0; i < 60; i++) {
              run.debugPass();
            }
            await stepSeconds(g, .6);
            expect(run.state.score, 60);
            expect(g.visibleHeight, visible);
            run.state.squeeze.inset = 80;
            g.update(0);
            final strips = g.world.children.whereType<SpikeStrip>().toList();
            expect(strips.every((s) => s.squeezeInset == 80), isTrue);
            g.runDebug.god = false;
            killRunThroughSaves(g);
            await flushAndMount(g);
            expect(g.state, GameState.reviving);
            expect(g.postRunPageUp, isFalse);
            expect(
              g.reviveScreen!.parent,
              same(g.camera.viewport),
              reason: 'revive UI paints above squeezed world walls',
            );
            await declineRevive(g);
            expect(g.state, GameState.bonus);
            await stepSeconds(g, .5);
            await _grey(g);
            if (result == 'solo') {
              await _capture(g, 'p22/qa3/bonus_squeeze_${visible.round()}');
            }
            final bonus = g.bonusScreen!;
            for (final tile in [0, 1, 2]) {
              bonus.tapTile(tile);
              await stepSeconds(g, 1.2);
            }
            for (
              var i = 0;
              i < 600 && !bonus.noThanksShown && !bonus.nextShown;
              i++
            ) {
              g.update(1 / 60);
            }
            if (bonus.noThanksShown) {
              bonus.tapNoThanks();
            } else {
              bonus.tapNext();
            }
            await flushAndMount(g);
            expect(g.state, GameState.results);
            final page = g.resultsScreen!;
            expect(page.duel?.name ?? 'solo', result);
            expect(page.model.levelUp, isTrue);
            expect(page.model.hasClaim, isTrue);
            await stepSeconds(g, 4.8);
            expect(page.claimShowing, isTrue);
            _fits(g, page);
            await _grey(g);

            // Actual paint with and without rays: opaque card / NEXT / reward
            // pixels must stay identical while the rays change the background.
            page.stage.rays = 0;
            final off = await _frame(g);
            page.stage.rays = 1;
            final on = await _frame(g);
            for (final rect in [
              ui.Rect.fromLTWH(
                page.content.position.x +
                    ResultsConfig.card.left * page.content.scale.x,
                page.content.position.y +
                    ResultsConfig.card.top * page.content.scale.y,
                ResultsConfig.card.width * page.content.scale.x,
                ResultsConfig.card.height * page.content.scale.y,
              ),
              _box(page, page.nextButton),
              _box(page, page.rewardPill),
            ]) {
              for (
                var y = rect.top.ceil() + 2;
                y < rect.bottom.floor() - 2;
                y++
              ) {
                for (
                  var x = rect.left.ceil() + 2;
                  x < rect.right.floor() - 2;
                  x++
                ) {
                  expect(
                    _pixel(on, x, y),
                    _pixel(off, x, y),
                    reason: 'rays behind the $result page UI at ($x, $y)',
                  );
                }
              }
            }
            expect(
              on,
              isNot(orderedEquals(off)),
              reason: 'rays actually paint',
            );
            await _capture(g, 'p22/qa3/${result}_claim_${visible.round()}');
            page.claimButton.onPressed();
            await stepSeconds(g, 1.5);
            expect(page.claimed, isTrue);
            await _grey(g);
            _fits(g, page);
            page.next();
            await stepSeconds(g, 1);
            expect(g.state, GameState.start);
            expect(g.postRunPageUp, isFalse);
            expect(g.stageKey, 0);
          });
        },
      );
    }
  }
}
