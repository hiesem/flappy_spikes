import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/config/feather_config.dart';
import 'package:flappy_spikes/run/config/puzzle_config.dart';
import 'package:flappy_spikes/run/effects/gold_sticker.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/hud/collect_layer.dart';
import 'package:flappy_spikes/run/hud/collect_slot.dart';
import 'package:flappy_spikes/run/hud/run_hud.dart';
import 'package:flappy_spikes/run/items/puzzle.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/run/run_layers.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

/// PRD-2.2 §12.1 / §12.2 (fix round P3-R1, S7-14…16): the puzzle's collect
/// text ("n/4", the coin badge's "+N") is drawn by the run's banner layer,
/// behind the gameplay, while the pill and the badge keep their panel in the
/// HUD with a window over each text. The labels share the slot's clock and
/// fade, the banner layer fades with the HUD row, and a death takes the
/// collect parts with it.
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

/// Paints [layers] in order (the world's banner layer, then the viewport HUD,
/// as the game does) over a flat [bg] field of the test's 320 × 711 size.
Future<Uint8List> _stack(List<Component> layers, ui.Color bg) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 320, 711),
    ui.Paint()..color = bg,
  );
  for (final c in layers) {
    c.renderTree(canvas);
  }
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

/// Pixels in [area] (whole pixels, x and y inclusive-exclusive) that are
/// exactly [colour].
int _count(Uint8List bytes, ui.Rect area, ui.Color colour) {
  var n = 0;
  for (var y = area.top.toInt(); y < area.bottom.toInt(); y++) {
    for (var x = area.left.toInt(); x < area.right.toInt(); x++) {
      if (_pixel(bytes, x, y) == colour) n++;
    }
  }
  return n;
}

/// Pixels in [area] that are not [bg].
int _painted(Uint8List bytes, ui.Rect area, ui.Color bg) {
  var n = 0;
  for (var y = area.top.toInt(); y < area.bottom.toInt(); y++) {
    for (var x = area.left.toInt(); x < area.right.toInt(); x++) {
      if (_pixel(bytes, x, y) != bg) n++;
    }
  }
  return n;
}

bool _near(ui.Color a, ui.Color b) =>
    (a.r - b.r).abs() < 2 / 255 &&
    (a.g - b.g).abs() < 2 / 255 &&
    (a.b - b.b).abs() < 2 / 255;

/// The "n/4" text's box (screen coordinates) for [n] held.
ui.Rect _countArea(FlappySpikesGame g, int n) {
  final label = CollectText.of(
    '$n/4',
    PuzzleConfig.countSize,
    g.foregroundColor,
  );
  final x = CollectConfig.slotX + PuzzleConfig.countX;
  final y = CollectConfig.slotY + 2;
  return ui.Rect.fromLTWH(
    x - label.width / 2,
    y - label.height / 2,
    label.width,
    label.height,
  );
}

/// The coin badge's "+N" area: centred under the pill, 24 pt type.
ui.Rect get _badgeArea {
  const cx = CollectConfig.slotX;
  const cy =
      CollectConfig.slotY + PuzzleConfig.pillHeight / 2 + PuzzleConfig.badgeGap;
  return const ui.Rect.fromLTWH(cx - 50, cy - 22, 100, 44);
}

void main() {
  _game().testGameWidget(
    '§12.1 the count and the badge text are CollectLabels in the banner '
    'layer; the collect layer keeps the pill in the HUD',
    setUp: _boot,
    verify: (g, tester) async {
      await tester.runAsync(() async {
        final run = await startRun(g);
        g.runDebug.god = true;
        run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
        await flushAndMount(g);
        await stepSeconds(g, .9);
        final hud = RunHud.of(run)!;
        final layer = CollectLayer.of(run)!;
        expect(layer.parent, same(hud));
        expect(layer.children.whereType<CollectLabels>(), isEmpty);
        expect(layer.labels.parent, same(hud.bannerLayer));
        expect(
          hud.bannerLayer.children.whereType<CollectLabels>().single,
          same(layer.labels),
        );
        expect(
          layer.labels.priority,
          greaterThan(1),
          reason: 'above the stickers (priority 1)',
        );
        expect(hud.bannerLayer.priority, lessThan(RunLayer.bird));
        expect(layer.labels.priority, lessThan(RunLayer.bird));
      });
    },
  );

  _game().testGameWidget(
    '§12.1 the count reads through the pill: the glyphs show, the window '
    'shows the panel colour, the HUD alone paints none of the text',
    setUp: _boot,
    verify: (g, tester) async {
      await tester.runAsync(() async {
        final run = await startRun(g);
        g.runDebug.god = true;
        run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
        await flushAndMount(g);
        await stepSeconds(g, .9);
        final hud = RunHud.of(run)!;
        hud.rowOpacity = 1;
        const bg = ui.Color(0xFF000000);
        final fg = g.foregroundColor;
        final panel = ui.Color.lerp(
          g.stageBackground,
          fg,
          PuzzleConfig.panelMix,
        )!;
        final area = _countArea(g, 1).inflate(4);

        final composite = await _stack([hud.bannerLayer, hud], bg);
        expect(
          _count(composite, area, fg),
          greaterThan(10),
          reason: 'the 1/4 glyphs',
        );

        // The window's top-left corner lies in the pill's knockout, so the
        // banner layer's backing shows there: the panel colour, not the bg.
        final corner = _countArea(g, 1);
        final cx = corner.left.floor() - 1;
        final cy = corner.top.floor() - 1;
        expect(
          _near(_pixel(composite, cx, cy), panel),
          isTrue,
          reason: 'the window shows the panel colour under the label',
        );
        expect(
          _near(_pixel(composite, cx - 6, cy), panel),
          isTrue,
          reason: 'the panel colour: the pill around the window is unchanged',
        );

        final hudOnly = await _stack([hud], bg);
        expect(_count(hudOnly, area, fg), 0);
        expect(
          _painted(hudOnly, corner, bg),
          0,
          reason: 'the HUD leaves the count window open',
        );
      });
    },
  );

  _game().testGameWidget(
    '§12.1 the badge "+N" is drawn by the banner layer, behind the gameplay, '
    'and the badge keeps a window over it',
    setUp: _boot,
    verify: (g, tester) async {
      await tester.runAsync(() async {
        final run = await startRun(g);
        await g.storage.savePuzzlePieces(7);
        g.runDebug.god = true;
        run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
        await flushAndMount(g);
        await stepSeconds(g, 3);
        final hud = RunHud.of(run)!;
        hud.rowOpacity = 1;
        const bg = ui.Color(0xFF000000);
        const plum = ui.Color(0xFF7A0044);
        final area = _badgeArea;

        final banner = await _stack([hud.bannerLayer], bg);
        final composite = await _stack([hud.bannerLayer, hud], bg);
        expect(
          _count(banner, area, plum),
          greaterThan(10),
          reason: 'the +N glyphs are in the banner layer',
        );
        expect(
          _count(composite, area, plum),
          _count(banner, area, plum),
          reason: 'the badge does not cover its own text',
        );
      });
    },
  );

  _game().testGameWidget(
    '§12.2 the labels fade with the pill and are gone once it has faded; a '
    'hidden row hides them as it hides the bands',
    setUp: _boot,
    verify: (g, tester) async {
      await tester.runAsync(() async {
        final run = await startRun(g);
        g.runDebug.god = true;
        run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
        await flushAndMount(g);
        await stepSeconds(g, .9);
        final hud = RunHud.of(run)!;
        hud.rowOpacity = 1;
        const bg = ui.Color(0xFF000000);
        final fg = g.foregroundColor;
        final area = _countArea(g, 1).inflate(4);

        hud.rowOpacity = 0;
        final hidden = await _stack([hud.bannerLayer], bg);
        expect(
          _painted(hidden, area, bg),
          0,
          reason: 'the banner layer fades out with the row',
        );
        hud.rowOpacity = 1;

        // The pill fades out at fadeAt + fadeOut; the labels end with it.
        await stepSeconds(
          g,
          PuzzleConfig.fadeAt + CollectSlot.fadeOut + .2 - .9,
        );
        expect(CollectLayer.of(run)!.slot.current, isNull);
        final faded = await _stack([hud.bannerLayer], bg);
        expect(
          _painted(faded, area, bg),
          0,
          reason: 'no label once the item has faded out',
        );
        expect(_count(faded, area, fg), 0);
      });
    },
  );

  _game().testGameWidget(
    '§12.4 a death takes the active and the queued collect parts with it: '
    'no sticker and no label stays in the banner layer',
    setUp: _boot,
    verify: (g, tester) async {
      await tester.runAsync(() async {
        final run = await startRun(g);
        g.runDebug.god = true;
        run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
        run.events.emit(const PickupCollected(ElementId.feather, null));
        await flushAndMount(g);
        await stepSeconds(g, .9);
        final layer = CollectLayer.of(run)!;
        expect(layer.slot.current, isA<PuzzlePillItem>());
        expect(layer.slot.waiting, 1);
        final hud = RunHud.of(run)!;
        g.runDebug.god = false;
        killRun(g);
        await stepSeconds(g, .5);
        await flushAndMount(g);
        expect(run.dying, isTrue);
        expect(layer.labels.isRemoved || layer.labels.isRemoving, isTrue);
        expect(layer.slot.waiting, 0);
        expect(
          hud.bannerLayer.descendants().whereType<GoldSticker>().where(
            (s) => !s.isRemoving && !s.isRemoved,
          ),
          isEmpty,
        );
      });
    },
  );

  _game().testGameWidget(
    '§12.1 screenshots: the count (1/4) and the 4/4 coin badge at 711 pt',
    setUp: _boot,
    verify: (g, tester) async {
      await tester.runAsync(() async {
        final run = await startRun(g);
        await g.storage.savePuzzlePieces(7);
        g.runDebug.god = true;
        run.events.emit(const PickupCollected(ElementId.puzzlePiece, null));
        await flushAndMount(g);
        await stepSeconds(g, .9);
        await captureShot(g, 2, 'p22/fix3/pill_count_711');
        await stepSeconds(g, 2.1);
        await captureShot(g, 2, 'p22/fix3/pill_badge_711');
      });
    },
  );
}
