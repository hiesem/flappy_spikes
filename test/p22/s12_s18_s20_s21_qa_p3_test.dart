import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/parts_config.dart';
import 'package:flappy_spikes/run/config/feather_config.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/config/puzzle_config.dart';
import 'package:flappy_spikes/run/config/streak_config.dart';
import 'package:flappy_spikes/run/effects/gold_sticker.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/banners.dart';
import 'package:flappy_spikes/run/hud/collect_layer.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/items/fever.dart';
import 'package:flappy_spikes/run/rides/portal_ride.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_layers.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

FlameTester<FlappySpikesGame> _game() => FlameTester(
  () => createRunTestGame(worldHeight: 711, seed: 5),
  gameSize: Vector2(320, 711),
);

Future<void> _boot(FlappySpikesGame g, _) async {
  await g.ready();
  await preloadImages(g);
  await loadFonts();
  await (FontLoader(
    'Fredoka',
  )..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'))).load();
  await flushAndMount(g);
}

// Paint a real branch in screen coordinates to test effective opacity and
// placement, rather than infer either from a component's nominal priority.
Future<Uint8List> _branch(Component branch, ui.Color bg) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 320, 711),
    ui.Paint()..color = bg,
  );
  branch.renderTree(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 711);
  picture.dispose();
  final bytes = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  return bytes!.buffer.asUint8List();
}

ui.Color _pixel(Uint8List bytes, int x, int y) {
  final i = (y * 320 + x) * 4;
  return ui.Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
}

void main() {
  group('S7-14', () {
    _game().testGameWidget(
      '§12.2 the actual banner paint fades with the HUD row opacity',
      setUp: _boot,
      verify: (g, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(g);
          g.runDebug.god = true;
          final hud = RunHud.of(run)!;
          hud.banners.show(StreakBanner(12));
          await flushAndMount(g);
          await stepSeconds(g, .3);
          const bg = ui.Color(0xFF000000);
          final band = StreakConfig.colourFor(12);
          hud.rowOpacity = 1;
          final full = await _branch(hud.bannerLayer, bg);
          expect(_pixel(full, 290, PartsConfig.bannerTop.toInt() + 16), band);
          hud.rowOpacity = .25;
          final fading = await _branch(hud.bannerLayer, bg);
          final expected = ui.Color.lerp(bg, band, .25)!;
          final actual = _pixel(
            fading,
            290,
            PartsConfig.bannerTop.toInt() + 16,
          );
          expect((actual.r - expected.r).abs(), lessThan(2 / 255));
          expect((actual.g - expected.g).abs(), lessThan(2 / 255));
          expect((actual.b - expected.b).abs(), lessThan(2 / 255));
        });
      },
    );
  });

  group('S7-15', () {
    _game().testGameWidget(
      '§12.1 the puzzle count CollectText is painted outside the HUD branch',
      setUp: _boot,
      verify: (g, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(g);
          g.runDebug.god = true;
          run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
          await flushAndMount(g);
          await stepSeconds(g, .9);
          final layer = CollectLayer.of(run)!;
          expect(layer.slot.current, isNotNull);
          final shot = await _branch(RunHud.of(run)!, g.stageBackground);
          // The count area is separate from the kept picture/tray. Its text
          // is the foreground colour; the opaque panel is a lighter mix.
          final cx = (CollectConfig.slotX + PuzzleConfig.countX).round();
          final cy = CollectConfig.slotY.round();
          var textPixels = 0;
          for (var y = cy - 16; y < cy + 18; y++) {
            for (var x = cx - 22; x < cx + 22; x++) {
              if (_pixel(shot, x, y) == g.foregroundColor) textPixels++;
            }
          }
          expect(
            textPixels,
            0,
            reason: '§12 explicitly moves CollectText labels',
          );
        });
      },
    );
  });

  group('S7-16', () {
    _game().testGameWidget(
      '§12.4 death clears an active puzzle completion sticker from the world',
      setUp: _boot,
      verify: (g, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(g);
          g.runDebug.god = true;
          for (var i = 0; i < 8; i++) {
            run.debugPass();
          }
          await g.storage.savePuzzlePieces(7);
          run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
          await flushAndMount(g);
          await stepSeconds(g, 1.5);
          final hud = RunHud.of(run)!;
          expect(
            hud.bannerLayer.descendants().whereType<GoldSticker>(),
            isNotEmpty,
          );
          g.runDebug.god = false;
          killRun(g);
          await stepSeconds(g, .5);
          await flushAndMount(g);
          expect(g.state, GameState.reviving);
          await captureShot(g, 2, 'p22/qa3/stale_puzzle_sticker_revive');
          expect(run.dying, isTrue);
          final remaining = hud.bannerLayer
              .descendants()
              .whereType<GoldSticker>()
              .where((s) => !s.isRemoving && !s.isRemoved);
          expect(
            remaining,
            isEmpty,
            reason: 'the collect layer dies with its HUD',
          );
        });
      },
    );
  });

  for (final id in RideId.values) {
    _game().testGameWidget(
      '§12 × §18 ${id.name}: one world host, one scene paint, restored after exit',
      setUp: _boot,
      verify: (g, tester) async {
        await tester.runAsync(() async {
          final run = await startRun(g, startHoopIndex: 25, ride: id);
          g.runDebug.god = true;
          final feature = run.features.whereType<PortalRideFeature>().single;
          expect(await flyUntil(g, (_) => feature.ride != null), isTrue);
          final ride = feature.ride!;
          final hud = RunHud.of(run)!;
          final host = hud.banners;
          expect(host.parent, same(hud.bannerLayer));
          expect(hud.bannerLayer.parent, same(g.world));
          expect(g.descendants().whereType<BannerHost>(), hasLength(1));
          host.show(ElementBanner('QA P3'));
          await flushAndMount(g);
          await stepSeconds(g, .3);
          expect(host.drawnByScene, isTrue);
          const bg = ui.Color(0xFF000000);
          final suppressed = await _branch(host, bg);
          expect(
            _pixel(suppressed, 290, 206),
            bg,
            reason: 'no duplicate world paint',
          );
          expect(ride.bannerLayer!.parent, same(g.world));
          expect(
            ride.backdropLayer!.priority,
            lessThan(ride.bannerLayer!.priority),
          );
          expect(
            ride.bannerLayer!.priority,
            lessThan(ride.objectsLayer!.priority),
          );
          expect(ride.bannerLayer!.priority, lessThan(RunLayer.hoopBack));
          final scene = await _branch(ride.bannerLayer!, bg);
          expect(
            _pixel(scene, 290, 206),
            isNot(bg),
            reason: 'real scene paint exists',
          );
          await captureShot(g, 2, 'p22/qa3/${id.name}_scene_banner');
          expect(await flyUntil(g, (_) => ride.done, maxSeconds: 30), isTrue);
          expect(host.drawnByScene, isFalse);
          expect(host.parent, same(hud.bannerLayer));
          expect(g.descendants().whereType<BannerHost>(), hasLength(1));
          host.show(ElementBanner('HOME AGAIN'));
          await flushAndMount(g);
          await stepSeconds(g, .3);
          final restored = await _branch(host, bg);
          expect(_pixel(restored, 290, 206), isNot(bg));
        });
      },
    );
  }

  _game().testGameWidget(
    '§20 × §21 accessory colours stay unchanged when fire lights at stage 30',
    setUp: _boot,
    verify: (g, tester) async {
      await tester.runAsync(() async {
        await g.storage.saveOwnedItems({
          ...g.storage.ownedItems,
          'bird:robin',
          'gear:windup',
          'hat:cowboy',
        });
        await g.menu.items.equip(SkinLayer.bird, 'robin');
        await g.menu.items.equip(SkinLayer.gear, 'windup');
        await g.menu.items.equip(SkinLayer.hat, 'cowboy');
        final run = await startRun(g);
        g.runDebug.god = true;
        final look = g.runBird!.lookComponent;
        run.debugPass(perfect: true);
        run.debugPass(perfect: true);
        g.update(0);
        look.paused = true;
        look.opacity = 1;
        look.playFlap();
        const bg = ui.Color(0xFF000000);
        final before = await _branch(look, bg);
        for (var i = 0; i < 60; i++) {
          run.debugPass();
        }
        await stepSeconds(g, .6);
        for (var i = 0; i < 3; i++) {
          run.debugPass(perfect: true);
        }
        await flushAndMount(g);
        look.playFlap();
        expect(g.stageKey, 30);
        expect(look.blend, 0);
        expect(look.goldTier, isTrue);
        expect(
          run.features.whereType<FeverFeature>().single.fire!.burning,
          isTrue,
        );
        final after = await _branch(look, bg);
        // The gold tier changes the classic body only. Accessories and the
        // robin keep their own fill colours; its glow adds surrounding pixels.
        var solid = 0, changed = 0;
        for (var i = 0; i < before.length; i += 4) {
          if (before[i] + before[i + 1] + before[i + 2] == 0) continue;
          if (before[i] == after[i] &&
              before[i + 1] == after[i + 1] &&
              before[i + 2] == after[i + 2]) {
            solid++;
          } else {
            changed++;
          }
        }
        expect(solid, greaterThan(300));
        expect(changed, 0, reason: 'the same gold effect, with no stage blend');
        await captureShot(g, 2, 'p22/qa3/accessory_cyan_fire');
      });
    },
  );
}
