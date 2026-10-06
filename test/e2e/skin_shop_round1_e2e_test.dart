import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/components/look_component.dart';
import 'package:flappy_spikes/components/pipe_pair.dart';
import 'package:flappy_spikes/components/skins/celebration.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/services/ads_service.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/iap_service.dart';
import 'package:flappy_spikes/services/monetization.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show captureShot, loadFonts;

// Existing PRD-1 QA tests already use S1-01..09. This round starts at S1-10.
// S1-10..S1-15 shipped as skipped reproductions in the QA round; branch
// ss-fix1 fixed the product code, so their pinning tests now run by default.
// Run just them with:
//   flutter test test/e2e/skin_shop_round1_e2e_test.dart --name S1-

class _Events extends GameServices {
  final recorded = <(String, Map<String, Object>?)>[];

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) =>
      recorded.add((name, parameters));

  List<Map<String, Object>?> params(String name) => recorded
      .where((event) => event.$1 == name)
      .map((event) => event.$2)
      .toList();
}

class _Rig {
  final events = _Events();
  final ads = FakeRewardedAds();
  final iap = FakeIapService();
  final sounds = <Sfx>[];
}

void _journey(
  String name,
  Future<void> Function(FlappySpikesGame, _Rig, WidgetTester) verify, {
  Map<String, Object> prefs = const {},
  double height = 711,
}) {
  group(name, () {
    final rig = _Rig();
    FlameTester<FlappySpikesGame>(
      () => createTestGame(
        prefs,
        height,
        rig.events,
        Monetization(ads: rig.ads, iap: rig.iap),
      ),
      gameSize: Vector2(320, height),
      pumpWidget: (widget, tester) async {
        tester.view
          ..physicalSize = ui.Size(320, height)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(widget);
      },
    ).testGameWidget(
      'user journey',
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        game.sound.onPlay = rig.sounds.add;
        game.purchases
          ..dispose()
          ..start();
        try {
          await verify(game, rig, tester);
        } finally {
          // Flutter's double-tap recognizer retains a 40 ms timer after taps.
          await tester.pump(const Duration(milliseconds: 50));
        }
      },
    );
  });
}

Future<void> _settle(FlappySpikesGame game, WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 16));
  await flushAndMount(game);
}

Future<void> _tap(
  FlappySpikesGame game,
  WidgetTester tester,
  PositionComponent component,
) async {
  final centre = component.absolutePositionOfAnchor(Anchor.center);
  await tester.tapAt(ui.Offset(centre.x, centre.y));
  await _settle(game, tester);
}

Future<void> _fade(FlappySpikesGame game) async {
  stepGame(game, .3);
  await flushAndMount(game);
}

Future<void> _tab(
  FlappySpikesGame game,
  WidgetTester tester,
  SkinLayer layer,
) async {
  await _tap(game, tester, game.skinShop!.tabBar.tabFor(layer));
  stepGame(game, .7);
  await flushAndMount(game);
}

Future<void> _shot(
  FlappySpikesGame game,
  WidgetTester tester,
  String name,
) async {
  await tester.runAsync(() => captureShot(game, 2, 'skin_qa_$name'));
  game.onGameResize(Vector2(320, game.viewHeight));
}

Future<void> _deadLookShot(LookComponent look, WidgetTester tester) async {
  // Inspect the actual dead component separately: after the physics tumble,
  // the full game capture can have the bird outside the viewport.
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 240, 200),
      ui.Paint()..color = const ui.Color(0xFFF0F0F0),
    );
    canvas.translate(55, 40);
    canvas.scale(4);
    final opacity = look.opacity;
    look.opacity = 1; // inspect the pose after the results fade has completed
    look.render(canvas);
    look.opacity = opacity;
    final picture = recorder.endRecording();
    final image = await picture.toImage(240, 200);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final file = File('build/look_shots/qa_dead_galaxy_shades_cap.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
  });
}

const _dressedPrefs = <String, Object>{
  'ownedItems': ['bird:robin', 'gear:windup', 'hat:cowboy'],
  'equippedItem.bird': 'robin',
  'equippedItem.gear': 'windup',
  'equippedItem.hat': 'cowboy',
};

/// A draw-command counter. Rendering still builds the real cached pictures;
/// this canvas counts compositing work without depending on GPU timing.
class _LayerCounter implements ui.Canvas {
  int layers = 0;

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) => layers++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(loadFonts);

  _journey(
    'fresh install → legendary → debug coins → buy → home → run → death',
    (game, rig, tester) async {
      expect(game.menu.wallet.balance, 0);
      expect(game.menu.items.look, Look.defaults);
      expect(game.homeScreen!.bird.look, Look.defaults);
      await _tap(game, tester, game.homeScreen!.skinsTile);
      await _fade(game);
      final screen = game.skinShop!;
      expect(screen.bar.labelText, '3 / 88');
      expect(screen.tabBar.tabs.map((tab) => tab.countText), [
        '1/30',
        '0/14',
        '0/14',
        '1/15',
        '1/15',
      ]);

      // Reach the last grid rows using actual drag input, then try Galaxy.
      for (var i = 0; i < 6; i++) {
        await tester.dragFrom(
          const ui.Offset(160, 600),
          const ui.Offset(0, -190),
        );
        await _settle(game, tester);
      }
      final galaxy = screen.tileFor('galaxy');
      final centre = galaxy.absolutePositionOfAnchor(Anchor.center);
      expect(centre.y, inInclusiveRange(326, 667));
      await _tap(game, tester, galaxy);
      expect(screen.previewLook.bird, 'galaxy');
      expect(game.menu.items.look.bird, 'classic');
      expect(screen.actionButton.poor, isTrue);
      expect(galaxy.current.tryingOn, isTrue);
      await _tap(game, tester, screen.actionButton);
      expect(
        screen.children.query<ShopToast>().single.message,
        'NOT ENOUGH COINS',
      );
      expect(game.menu.wallet.balance, 0);
      expect(rig.events.params('item_no_coins').single, {
        'layer': 'bird',
        'id': 'galaxy',
        'shortfall': 5000,
      });

      // The real debug-panel action, six presses; closing restores this try-on.
      game.openDebugPanel();
      await flushAndMount(game);
      final panel = game.debugPanel!;
      final addCoins = panel.children.query<MenuButton>().first;
      for (var i = 0; i < 6; i++) {
        await _tap(game, tester, addCoins);
      }
      game.closeDebugPanel();
      await flushAndMount(game);
      expect(game.menu.wallet.balance, 6000);
      expect(screen.tryOnId, 'galaxy');
      await _tap(game, tester, screen.actionButton);
      expect(game.menu.wallet.balance, 1000);
      expect(screen.stage.confettiCount, greaterThan(100));
      expect(screen.tryOnId, isNull);
      expect(game.menu.items.look.bird, 'galaxy');
      stepGame(game, .7);
      expect(game.coinPill.shownBalance, 1000);
      expect(screen.bar.labelText, '4 / 88');
      expect(screen.tabBar.tabs.first.countText, '2/30');
      expect(rig.events.params('item_purchase').single, {
        'layer': 'bird',
        'id': 'galaxy',
        'rarity': 'LEGENDARY',
        'price': 5000,
      });

      // Add two freely combinable layers via their own tabs and BUY buttons.
      await _tab(game, tester, SkinLayer.gear);
      await _tap(game, tester, screen.tileFor('shades'));
      await _tap(game, tester, screen.actionButton);
      await _tab(game, tester, SkinLayer.hat);
      await _tap(game, tester, screen.tileFor('cap'));
      await _tap(game, tester, screen.actionButton);
      const dressed = Look(bird: 'galaxy', gear: 'shades', hat: 'cap');
      expect(game.menu.items.look, dressed);
      expect(game.menu.wallet.balance, 500);
      expect(screen.bar.labelText, '6 / 88');
      expect(screen.tabBar.tabFor(SkinLayer.gear).countText, '1/14');
      expect(screen.tabBar.tabFor(SkinLayer.hat).countText, '1/14');
      final reloaded = GameStorage();
      await reloaded.load();
      expect(
        reloaded.ownedItems,
        containsAll(['bird:galaxy', 'gear:shades', 'hat:cap']),
      );
      expect(reloaded.equippedItems[SkinLayer.bird], 'galaxy');
      expect(reloaded.equippedItems[SkinLayer.gear], 'shades');
      expect(reloaded.equippedItems[SkinLayer.hat], 'cap');

      await _tap(game, tester, screen.backButton);
      await _fade(game);
      expect(game.homeScreen!.bird.look, dressed);
      expect(game.homeScreen!.bird.lookComponent.blend, 0);
      await _tap(game, tester, game.homeScreen!.startButton);
      expect(game.state, GameState.playing);
      final bird = game.world.children.query<Bird>().single;
      expect(bird.look, dressed);
      expect(bird.body.fixtures, hasLength(1));
      expect(bird.body.fixtures.single.shape.radius, 14.75);
      expect(bird.lookComponent.artScale * 30, closeTo(29.5, 1e-6));
      // Complete the first colour transition, preserving the equipped identity.
      for (var i = 0; i < 5; i++) {
        game.onScoreSensor(PipePair(gapBottomY: 351));
      }
      stepGame(game, .55, flapBelow: game.viewHeight / 2);
      expect(bird.lookComponent.blend, closeTo(.35, 1e-6));
      expect(bird.look, dressed);
      // A real collision with the spikes ends the run.
      stepGame(game, 2);
      await flushAndMount(game);
      expect(game.state, GameState.gameOver);
      expect(bird.lookComponent.pose, LookPose.dead);
      expect(bird.look, dressed);
      final deadTime = bird.lookComponent.time;
      stepGame(game, .2);
      expect(bird.lookComponent.time, deadTime);
      await _shot(game, tester, 'dead_galaxy_shades_cap');
      await _deadLookShot(bird.lookComponent, tester);
      // Tap the actual results REPLAY button (SPEC.md: centreY + 25.25).
      await tester.tapAt(ui.Offset(160, game.viewHeight / 2 + 25.25));
      await _settle(game, tester);
      await flushAndMount(game);
      await _fade(game);
      expect(game.state, GameState.start);
      expect(game.homeScreen!.bird.look, dressed);
      expect(game.homeScreen!.bird.lookComponent.blend, 0);
    },
  );

  _journey(
    'equip NONE gear/hat, cancel try-on, and preserve collection counters',
    prefs: _dressedPrefs,
    (game, rig, tester) async {
      await _tap(game, tester, game.homeScreen!.skinsTile);
      await _fade(game);
      final screen = game.skinShop!;
      expect(screen.bar.labelText, '6 / 88');
      await _tab(game, tester, SkinLayer.gear);
      await _tap(game, tester, screen.tileFor(kNoneId));
      expect(game.menu.items.look.gear, kNoneId);
      expect(screen.actionButton.label, 'NOTHING ON');
      expect(screen.tabBar.tabFor(SkinLayer.gear).countText, '1/14');
      await _tab(game, tester, SkinLayer.hat);
      await _tap(game, tester, screen.tileFor('beanie'));
      expect(screen.previewLook.hat, 'beanie');
      await _tab(game, tester, SkinLayer.hoop);
      expect(screen.tryOnId, isNull);
      expect(screen.previewLook.hat, 'cowboy');
      await _tab(game, tester, SkinLayer.hat);
      await _tap(game, tester, screen.tileFor(kNoneId));
      expect(screen.actionButton.label, 'NOTHING ON');
      expect(screen.bar.labelText, '6 / 88');
      await _tap(game, tester, screen.backButton);
      await _fade(game);
      expect(game.homeScreen!.bird.look, const Look(bird: 'robin'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('equippedItem.gear'), kNoneId);
      expect(prefs.getString('equippedItem.hat'), kNoneId);
      expect(
        rig.events.params('item_equip'),
        containsAll([
          {'layer': 'gear', 'id': 'none'},
          {'layer': 'hat', 'id': 'none'},
        ]),
      );
    },
  );

  _journey('GET → rewarded completion → six coins fly → +40 and cooldown', (
    game,
    rig,
    tester,
  ) async {
    await _tap(game, tester, game.homeScreen!.shopTile);
    await _fade(game);
    final shop = game.shopScreen!;
    expect(shop.freeCoins.chipText, 'GET');
    expect(shop.freeCoins.chip!.size, Vector2(112, 32));
    rig.sounds.clear();
    await _tap(game, tester, shop.freeCoins.chip!);
    expect(game.menu.wallet.balance, 40);
    final fly = game.coinFly!;
    expect(fly.count, 6);
    expect(fly.duration, .65);
    expect(fly.stagger, .07);
    stepGame(game, .5);
    expect(game.coinPill.shownBalance, 0);
    await _shot(game, tester, 'get_in_flight');
    stepGame(game, fly.totalDuration - .5 + .05);
    await flushAndMount(game);
    expect(fly.landed, 6);
    stepGame(game, .15);
    expect(game.coinPill.shownBalance, inExclusiveRange(0, 40));
    expect(game.coinPill.coinScale, greaterThan(1.2));
    stepGame(game, .4);
    await flushAndMount(game);
    expect(game.coinPill.shownBalance, 40);
    expect(game.coinFly, isNull);
    expect(rig.sounds, [Sfx.bnAdBtn, Sfx.bnCoin, Sfx.skProgress]);
    expect(shop.freeCoins.chipText, '05:00');
    final rewarded = rig.events.params('coins_earned');
    expect(rewarded, [
      {'amount': 40, 'source': 'rewarded'},
    ]);
    await _tap(game, tester, shop.freeCoins.chip!);
    expect(game.menu.wallet.balance, 40);
    expect(game.coinFly, isNull);
  });

  _journey(
    'reduce motion across home, Shop, try-on and legendary purchase',
    prefs: const {'coins': 6000},
    (game, rig, tester) async {
      // The game's documented seam substitutes the OS accessibility flag.
      game.reduceMotionOverride = true;
      expect(game.reduceMotion, isTrue);
      final home = game.homeScreen!;
      stepGame(game, 13);
      expect(home.slotButton.pulse.scale, 1);
      expect(home.slotButton.streak.progress, isNull);
      expect(home.bird.idle.lastAction, isNull);
      expect(game.coinPill.glintOpacity, 0);
      await _tap(game, tester, home.shopTile);
      await _fade(game);
      final shop = game.shopScreen!;
      stepGame(game, 13);
      expect(shop.freeCoins.pulse.scale, 1);
      for (final pack in shop.packs) {
        expect(pack.streak.progress, isNull);
        expect(pack.tagWiggle.isIdentity, isTrue);
      }
      await _tap(game, tester, shop.backButton);
      await _fade(game);
      await _tap(game, tester, game.homeScreen!.skinsTile);
      await _fade(game);
      await _tab(game, tester, SkinLayer.hat);
      final screen = game.skinShop!;
      screen.scroll.offset = screen.scroll.maxOffset;
      await _tap(game, tester, screen.tileFor('crown'));
      stepGame(game, .3);
      expect(screen.stage.tryOnAlpha, .42);
      expect(screen.actionButton.pulseScale, 1);
      await _tap(game, tester, screen.actionButton);
      expect(game.menu.items.look.hat, 'crown');
      expect(game.world.children.query<ScreenFlash>(), isEmpty);
      expect(game.world.children.query<ScreenShake>(), isEmpty);
      expect(screen.stage.rays, 0);
      stepGame(game, .7);
      expect(screen.bar.popScale, 1);
    },
  );

  for (final height in [568.0, 730.0]) {
    _journey(
      'all five skin tabs scroll and fit at $height pt',
      height: height,
      (game, rig, tester) async {
        await _tap(game, tester, game.homeScreen!.skinsTile);
        await _fade(game);
        final screen = game.skinShop!;
        expect(
          screen.stage.toRect(),
          const ui.Rect.fromLTWH(14, 126, 292, 138),
        );
        expect(
          screen.tabBar.toRect(),
          const ui.Rect.fromLTWH(14, 270, 292, 52),
        );
        expect(screen.scroll.viewport.bottom, height - 44);
        for (final layer in SkinLayer.values) {
          await _tab(game, tester, layer);
          expect(screen.tiles, hasLength(layer == SkinLayer.bird ? 30 : 15));
          expect(screen.tiles.first.toRect().top, 332);
          screen.scroll.offset = screen.scroll.maxOffset;
          final last = screen.tiles.last;
          final lastY = last.absolutePositionOfAnchor(Anchor.bottomCenter).y;
          expect(lastY, closeTo(height - 74, 1e-6));
          await _tap(game, tester, last);
          expect(screen.tryOnId, last.item.id);
          stepGame(game, .7); // settle outline and warm newly visible trails
          await _shot(game, tester, '${height.toInt()}_${layer.key}_bottom');
        }
      },
    );
  }

  test('S1-10 SFX never fall back to a fresh MediaPlayer', () {
    final source = File('lib/game/sound.dart').readAsStringSync();
    expect(
      RegExp(r'FlameAudio\.play\s*\(').hasMatch(source),
      isFalse,
      reason: 'CLAUDE.md and PRD §4.4 require preloaded low-latency pools only',
    );
  });

  _journey(
    'S1-11 animated home gear freezes under a popup and debug panel',
    prefs: _dressedPrefs,
    (game, rig, tester) async {
      final home = game.homeScreen!;
      game.openNoAdsPopup();
      await flushAndMount(game);
      final t = home.bird.lookComponent.time;
      stepGame(game, .5);
      expect(
        home.bird.lookComponent.time,
        t,
        reason: '§8.4 includes wind-up key / animated look, not only bob/flap',
      );
      game.closeNoAdsPopup();
      await flushAndMount(game);
      game.openDebugPanel();
      await flushAndMount(game);
      final debugT = home.bird.lookComponent.time;
      stepGame(game, .5);
      expect(home.bird.lookComponent.time, debugT);
    },
  );

  _journey(
    'long featured item name does not overlap its price',
    prefs: const {
      'ownedItems': ['bird:lemon', 'bird:toucan', 'bird:ghost'],
    },
    (game, rig, tester) async {
      await _tap(game, tester, game.homeScreen!.shopTile);
      await _fade(game);
      final featured = game.shopScreen!.featured;
      expect(featured.item!.id, 'carpet');
      await _shot(game, tester, 'featured_carpet');
      final name = featured.children.query<MenuText>().singleWhere(
        (text) => text.text == 'MAGIC CARPET',
      );
      expect(
        name.x + name.width,
        lessThanOrEqualTo(featured.pricePill!.x - 6),
        reason: '§8.3 featured row must show a readable name and price',
      );
    },
  );

  _journey(
    'S1-12 settled locked static tiles need no per-frame saveLayer',
    (game, rig, tester) async {
      await _tap(game, tester, game.homeScreen!.skinsTile);
      await _fade(game);
      final tile = game.skinShop!.tileFor('sky');
      expect(tile.animatesArt, isFalse);
      final cache = game.skinShop!.art;
      cache.pictureFor(tile.item); // warm the static picture before counting
      final canvas = _LayerCounter();
      tile.render(canvas);
      expect(
        canvas.layers,
        0,
        reason: 'static locked art at 42% should be cached already dimmed',
      );
    },
  );

  _journey(
    'S1-13 featured-item try-on clears its NEW tag and persists seen',
    (game, rig, tester) async {
      await _tap(game, tester, game.homeScreen!.shopTile);
      await _fade(game);
      await _tap(game, tester, game.shopScreen!.featured);
      await _fade(game);
      final screen = game.skinShop!;
      expect(screen.tryOnId, 'lemon');
      expect(
        screen.tileFor('lemon').current.isNew,
        isFalse,
        reason: '§3.3 NEW clears when this item is tapped, including featured',
      );
      expect(game.storage.seenItems, contains('bird:lemon'));
    },
  );

  _journey(
    'S1-14 debug reset immediately restores the default home look',
    prefs: _dressedPrefs,
    (game, rig, tester) async {
      game.openDebugPanel();
      await flushAndMount(game);
      final reset = game.debugPanel!.children.query<MenuButton>().elementAt(1);
      await _tap(game, tester, reset);
      game.closeDebugPanel();
      await flushAndMount(game);
      expect(game.menu.items.look, Look.defaults);
      expect(
        game.homeScreen!.bird.look,
        Look.defaults,
        reason: 'WP-A reset and §3.8 home look must agree without relaunch',
      );
    },
  );

  _journey(
    'S1-15 animated featured gear freezes under the debug panel',
    prefs: const {
      'ownedItems': ['bird:lemon', 'bird:toucan', 'bird:ghost'],
    },
    (game, rig, tester) async {
      await _tap(game, tester, game.homeScreen!.shopTile);
      await _fade(game);
      final featured = game.shopScreen!.featured;
      expect(featured.item!.id, 'carpet');
      game.openDebugPanel();
      await flushAndMount(game);
      // Capture the exact art draw commands before/after while overlays pause
      // the idle clock. Render only this row so overlay fades cannot differ.
      ui.Picture draw() {
        final recorder = ui.PictureRecorder();
        featured.render(ui.Canvas(recorder));
        return recorder.endRecording();
      }

      await tester.runAsync(() async {
        final before = draw();
        stepGame(game, .25);
        final after = draw();
        final a = await before.toImage(292, 56);
        final b = await after.toImage(292, 56);
        final aBytes = (await a.toByteData())!.buffer.asUint8List();
        final bBytes = (await b.toByteData())!.buffer.asUint8List();
        a.dispose();
        b.dispose();
        before.dispose();
        after.dispose();
        expect(
          bBytes,
          orderedEquals(aBytes),
          reason: '§8.4 animated featured artwork must pause with its row',
        );
      });
    },
  );
}
