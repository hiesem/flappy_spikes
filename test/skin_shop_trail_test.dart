import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/extensions.dart';
import 'package:flappy_spikes/components/skins/preview_stage.dart';
import 'package:flappy_spikes/components/skins/skin_shop_screen.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'menu_screenshot_test.dart' show loadFonts;
import 'shop_flow_test.dart' show shopTest;
import 'skin_shop_flow_test.dart' show allSeen, prefsWith;

// Owner bug (skin shop): the selected bird must ALWAYS show its equipped
// trail. The preview used to burn the trail only for 1.7 s after each hoop
// pass and while the TRAILS tab was open, so on a fresh open (BIRDS tab) it
// was missing before the first pass and between passes, and a re-entry
// started with an empty trail. Every check samples the trail alone (the
// preview's own TrailEmitter, painted without the bird, hat, gear or hoops):
// it must hold points or particles AND paint visible pixels.

/// Seconds after the shop is entered at which the trail is sampled: before the
/// first hoop pass (it reaches the bird at ~2.5 s), after it (3 s), between
/// the passes (4.5, 7, 9 s) and after the second one (6 s).
const List<double> _samples = [1, 2, 3, 4.5, 6, 7, 8, 9];

/// Points on the trail right now: live particles plus path-history points.
int _trailPoints(PreviewStage stage) =>
    stage.trail.particleCount + stage.trail.pathLength;

/// Visible (alpha > 8) pixels the trail alone paints on the stage.
Future<int> _trailPixels(PreviewStage stage) async {
  final w = stage.size.x.round(), h = stage.size.y.round();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  stage.trail.paint(canvas, k: PreviewStage.k);
  final image = await recorder.endRecording().toImage(w, h);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  var visible = 0;
  for (var i = 3; i < bytes.lengthInBytes; i += 4) {
    if (bytes.getUint8(i) > 8) visible++;
  }
  return visible;
}

/// What is wrong with the trail at [when], or null when it is drawn.
Future<String?> _trailProblem(
  WidgetTester tester,
  PreviewStage stage,
  String when,
) async {
  final id = stage.trail.trailId;
  if (_trailPoints(stage) == 0) {
    return '$id, $when: no trail points or particles';
  }
  final pixels = (await tester.runAsync(() => _trailPixels(stage)))!;
  if (pixels == 0) return '$id, $when: the trail paints nothing';
  return null;
}

/// Records the trail's problem at [when] in [problems], if there is one.
Future<void> _check(
  WidgetTester tester,
  PreviewStage stage,
  String when,
  List<String> problems,
) async {
  final problem = await _trailProblem(tester, stage, when);
  if (problem != null) problems.add(problem);
}

/// Opens the skin shop from home and returns it at t = 0 (no time stepped).
Future<SkinShopScreen> _enterShop(FlappySpikesGame game) async {
  game.openSkins();
  await flushAndMount(game);
  return game.skinShop!;
}

/// Leaves the shop for home, waits a second there and re-enters it.
Future<SkinShopScreen> _reenterShop(FlappySpikesGame game) async {
  game.skinShop!.backButton.onPressed();
  stepGame(game, 1);
  await flushAndMount(game);
  expect(game.skinShop, isNull);
  return _enterShop(game);
}

/// Evidence frames (`build/trail_shots/`, copied to briefs14/evidence/shop):
/// the top of the shop (collection bar, preview stage, tabs) at 2 x.
const double _shotScale = 2;
const double _shotHeight = 340;

Future<void> _shot(
  WidgetTester tester,
  FlappySpikesGame game,
  String name,
) async {
  await tester.runAsync(() async {
    // As the menu screenshot harness does: resize right before rendering,
    // then put the logical 320-wide size back for the rest of the test.
    final height = game.viewHeight;
    game.onGameResize(Vector2(320 * _shotScale, height * _shotScale));
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, 320 * _shotScale, height * _shotScale),
      ui.Paint()..color = game.backgroundColor(),
    );
    game.render(canvas);
    final image = await recorder.endRecording().toImage(
      (320 * _shotScale).round(),
      (_shotHeight * _shotScale).round(),
    );
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    game.onGameResize(Vector2(320, height));
    final file = File('build/trail_shots/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  });
}

/// Equipped trails shown in the evidence: one per trail family.
const List<String> _shotTrails = [
  'flame',
  'laser',
  'rainbow',
  'echo',
  'prism',
  'paint',
];

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();

  shopTest(
    'every trail is drawn on open, after equips and on every tab, before, '
    'between and after the hoop loops, and after leaving to home and '
    're-entering the shop',
    prefs: prefsWith(
      owned: [for (final item in kTrails) 'trail:${item.id}', 'hat:crown'],
      seen: allSeen,
    ),
    verify: (game, spy, ads, iap, tester) async {
      final problems = <String>[];
      var shop = await _enterShop(game);
      expect(shop.tab, SkinLayer.bird);
      for (final item in kTrails) {
        // Equip on the TRAILS tab, then look at every tab.
        game.selectSkinTab(SkinLayer.trail);
        game.tapItem(SkinLayer.trail, item.id);
        await flushAndMount(game);
        expect(shop.stage.trail.trailId, item.id);
        await _check(tester, shop.stage, 'equipped on TRAILS', problems);
        for (final layer in SkinLayer.values) {
          game.selectSkinTab(layer);
          stepGame(game, 0.2);
          await _check(tester, shop.stage, '${layer.key} tab', problems);
        }
        // Equip a hat from its tab.
        game.selectSkinTab(SkinLayer.hat);
        game.tapItem(SkinLayer.hat, 'crown');
        await flushAndMount(game);
        await _check(tester, shop.stage, 'after equipping a hat', problems);
        // Leave to home and re-enter: BIRDS tab again, trail at open.
        shop = await _reenterShop(game);
        expect(shop.tab, SkinLayer.bird);
        expect(shop.stage.trail.trailId, item.id);
        await _check(tester, shop.stage, 're-entry at open', problems);
        var at = 0.0;
        for (final t in _samples) {
          stepGame(game, t - at);
          at = t;
          await _check(tester, shop.stage, 're-entry +${t}s', problems);
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    },
  );

  for (final id in _shotTrails) {
    shopTest(
      'evidence: $id open, after 1 s, after 3 s, re-entry, re-entry + 3 s',
      prefs: prefsWith(owned: ['trail:$id'], seen: allSeen)
        ..['equippedItem.trail'] = id,
      verify: (game, spy, ads, iap, tester) async {
        final problems = <String>[];
        game.openSkins();
        await flushAndMount(game);
        stepGame(game, 0.6); // the open fade is done
        var shop = game.skinShop!;
        await _shot(tester, game, '${id}_1_open');
        await _check(tester, shop.stage, 'open', problems);
        stepGame(game, 1);
        await _shot(tester, game, '${id}_2_after1s');
        await _check(tester, shop.stage, 'after 1 s', problems);
        stepGame(game, 2);
        await _shot(tester, game, '${id}_3_after3s');
        await _check(tester, shop.stage, 'after 3 s', problems);
        shop = await _reenterShop(game);
        stepGame(game, 0.6);
        await _shot(tester, game, '${id}_4_reentry');
        await _check(tester, shop.stage, 're-entry', problems);
        stepGame(game, 3);
        await _shot(tester, game, '${id}_5_reentry_after3s');
        await _check(tester, shop.stage, 're-entry + 3 s', problems);
        expect(problems, isEmpty, reason: problems.join('\n'));
      },
    );
  }
}
