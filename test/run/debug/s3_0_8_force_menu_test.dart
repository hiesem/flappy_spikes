import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/debug_panel.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/debug/force_menu.dart';
import 'package:flappy_spikes/run/director/plans.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hoops/hoop.dart';
import 'package:flappy_spikes/run/hoops/hoop_kind.dart';
import 'package:flappy_spikes/run/hoops/kinds/registry.dart';
import 'package:flappy_spikes/run/run_context.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Same pattern as `captureShot` in test/menu_screenshot_test.dart, writing
/// to build/shots/run/debug/ (ARCH §7.1).
Future<void> _capture(FlappySpikesGame game, String name) async {
  const scale = 1.5;
  final shotSize = Vector2(
    320 * scale,
    (game.viewHeight * scale).roundToDouble(),
  );
  game.onGameResize(shotSize); // resize right before rendering
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, shotSize.x, shotSize.y),
    ui.Paint()..color = game.backgroundColor(),
  );
  game.render(canvas);
  final image = await recorder.endRecording().toImage(
    shotSize.x.toInt(),
    shotSize.y.toInt(),
  );
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  final file = File('build/shots/run/debug/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  debugPrint('SHOT ${file.path}: ${bytes.length} bytes');
  expect(bytes.length, greaterThan(10000));
}

class _TestKind extends HoopKind {
  _TestKind(this.id);
  @override
  final HoopKindId id;
  @override
  bool get usesTierLook => true;
  @override
  void buildVisual(Hoop h, RunContext c) {}
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lvdc = FontLoader('LVDC Common2')
    ..addFont(rootBundle.load('assets/fonts/LVDCC.TTF'));
  final opificio = FontLoader('Opificio Neue')
    ..addFont(rootBundle.load('assets/fonts/Opificio_neue-regular.ttf'));
  await Future.wait([lvdc.load(), opificio.load()]);

  for (final vh in [568.0, 711.0]) {
    final tester = FlameTester<FlappySpikesGame>(
      () => createRunTestGame(worldHeight: vh),
      gameSize: Vector2(Config.worldWidth, vh),
    );

    tester.testGameWidget(
      '§3.0.8 debug force menu at $vh: every element, start at hoop N, reset '
      'met elements, force portal ride',
      setUp: (game, _) async {
        await game.ready();
        await preloadImages(game);
      },
      verify: (game, widgetTester) async {
        expect(FlappySpikesGame.debugAvailable, isTrue);
        game.openDebugPanel();
        await flushAndMount(game);
        final p2 = game.world.children.query<DebugPanel>().single;
        final open = p2.actions.indexWhere(
          (a) => a.label().startsWith('RUN DEBUG'),
        );
        expect(open, greaterThanOrEqualTo(0));
        await p2.press(open);
        await flushAndMount(game);
        expect(p2.actions.first.label(), startsWith('Start at hoop'));

        // WP-B uses the existing DebugAction row master, with live state.
        final showcaseRow = ForceMenu.actions(
          game,
        ).singleWhere((a) => a.label().startsWith('Showcase:'));
        game.storage.showcaseSeen = 1;
        game.storage.showcaseAttempt = 2;
        expect(showcaseRow.label(), 'Showcase: step 2 / attempt 2 / done no');
        game.storage.showcaseDoneAt = 3;
        expect(showcaseRow.label(), endsWith('done yes'));
        game.storage.showcaseSeen = 0;
        game.storage.showcaseAttempt = 0;
        game.storage.showcaseDoneAt = null;

        // Walk every page, collecting the labels.
        final labels = <String>{};
        for (var page = 0; page < 10; page++) {
          labels.addAll(p2.actions.map((a) => a.label()));
          final next = p2.actions.indexWhere(
            (a) => a.label().startsWith('Page '),
          );
          if (page == 0) {
            await widgetTester.runAsync(
              () => _capture(game, 'force_menu_${vh.toInt()}'),
            );
          }
          await p2.press(next);
          await flushAndMount(game);
          if (p2.actions.first.label().startsWith('Start at hoop')) break;
        }
        for (final e in ForceMenu.forceable) {
          expect(
            labels.any((l) => l.startsWith('Force: ${e.storageId}')),
            isTrue,
            reason: e.storageId,
          );
        }
        for (final r in RideId.values) {
          expect(labels, contains('Force portal ride: ${r.name}'));
        }

        // Rows act on the next run's setup.
        Future<void> pressLabel(String prefix) async {
          for (var page = 0; page < 10; page++) {
            final i = p2.actions.indexWhere(
              (a) => a.label().startsWith(prefix),
            );
            if (i >= 0) {
              await p2.press(i);
              return;
            }
            await p2.press(
              p2.actions.indexWhere((a) => a.label().startsWith('Page ')),
            );
          }
          fail('no row $prefix');
        }

        await pressLabel('Start at hoop');
        expect(game.runDebug.startHoopIndex, ForceMenu.startSteps[1]);
        await pressLabel('Force: saw');
        expect(game.runDebug.force, contains(ElementId.saw));
        await pressLabel('Force portal ride: storm');
        expect(game.runDebug.forcedRide, RideId.storm);
        await game.storage.markElementMet('saw');
        await pressLabel('Reset met elements');
        expect(game.storage.metElements, isEmpty);

        // The queue goes into the next run.
        await pressLabel('< Back');
        game.closeDebugPanel();
        await flushAndMount(game);
        final run = await startRun(
          game,
          startHoopIndex: game.runDebug.startHoopIndex,
          force: game.runDebug.force.toList(),
          ride: game.runDebug.forcedRide,
        );
        expect(run.setup.startHoopIndex, ForceMenu.startSteps[1]);
        expect(run.setup.forced, contains(ElementId.saw));
        expect(run.setup.forcedRide, RideId.storm);
      },
    );
  }

  final overlayTester = FlameTester<FlappySpikesGame>(
    () => createRunTestGame(worldHeight: 711),
    gameSize: Vector2(Config.worldWidth, 711),
  );
  overlayTester.testGameWidget(
    '§3.0.8 debug overlay: rim circles, pass planes, index / kind / angle',
    setUp: (game, _) async {
      await game.ready();
      await preloadImages(game);
    },
    verify: (game, widgetTester) async {
      for (final id in [HoopKindId.normal, HoopKindId.bullseye]) {
        testHoopKinds[id] = () => _TestKind(id);
      }
      addTearDown(testHoopKinds.clear);
      game.runDebug
        ..overlay = true
        ..god = true;
      await startRun(game, startHoopIndex: 45, force: [ElementId.angledRing]);
      await flyRun(game, maxSeconds: 2.5);
      await widgetTester.runAsync(() => _capture(game, 'overlay_711'));
    },
  );
}
