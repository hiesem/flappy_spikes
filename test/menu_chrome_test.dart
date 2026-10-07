import 'package:flame/components.dart';
import 'package:flame/effects.dart' show OpacityProvider;
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/menu/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'menu_screenshot_test.dart' show loadFonts;

/// The shared menu chrome (coin pill + top-left gear/back box): it must not
/// dip while two screens that both show it crossfade (PO 2026-10-04: the
/// stacked per-screen pills went ~75 % mid-fade on BACK), but still fade
/// with a screen entered from / left for a scene without it.
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Real fonts: the label-fit check below measures actual glyph widths.
  await loadFonts();

  /// Steps 0.5 s in 60 Hz frames and returns the chrome opacities seen
  /// (pill, corner box) plus [watch]'s opacities, one entry per frame.
  ({List<double> pill, List<double> box, List<double> watched}) sample(
    FlappySpikesGame game, {
    PositionComponent? Function()? watch,
  }) {
    final pill = <double>[], box = <double>[], watched = <double>[];
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60);
      pill.add(game.coinPill.opacity);
      box.add(game.cornerBox.opacity);
      final w = watch?.call();
      if (w is OpacityProvider) watched.add((w as OpacityProvider).opacity);
    }
    return (pill: pill, box: box, watched: watched);
  }

  void chromeTest(
    String name,
    Future<void> Function(FlappySpikesGame game) verify, {
    Map<String, Object> prefs = const {'coins': 1250},
  }) {
    FlameTester<FlappySpikesGame>(
      () => createTestGame(prefs, 711),
      gameSize: Vector2(320, 711),
    ).testGameWidget(
      name,
      setUp: (game, tester) async {
        await game.ready();
        await preloadImages(game);
        await flushAndMount(game);
      },
      verify: (game, tester) async => verify(game),
    );
  }

  chromeTest('the pill is one world-level component, not inside a screen', (
    game,
  ) async {
    expect(game.coinPill.parent, same(game.world));
    expect(game.cornerBox.parent, same(game.world));
    expect(game.homeScreen!.coinPill, same(game.coinPill));
    expect(game.coinPill.opacity, 1);
    expect(game.cornerBox.opacity, 1);
    expect(game.cornerBox.gearMix, 1);
    // Above the screens (its own taps), the box below them.
    expect(game.coinPill.priority, greaterThan(game.homeScreen!.priority));
    expect(game.cornerBox.priority, lessThan(game.homeScreen!.priority));
  });

  chromeTest('home -> Shop -> BACK -> home: pill and box stay at 1.0', (
    game,
  ) async {
    final home = game.homeScreen!;
    game.openShop();
    var s = sample(game, watch: () => home);
    await flushAndMount(game);
    expect(s.pill, everyElement(1.0));
    expect(s.box, everyElement(1.0));
    expect(s.watched.any((o) => o > 0.2 && o < 0.8), isTrue,
        reason: 'the screens really crossfaded');
    expect(game.cornerBox.gearMix, 0, reason: 'back chevron in the Shop');
    expect(game.shopScreen!.coinPill, same(game.coinPill));

    // BACK (the reported flicker).
    final shop = game.shopScreen!;
    shop.backButton.onPressed();
    s = sample(game, watch: () => shop);
    await flushAndMount(game);
    expect(s.pill, everyElement(1.0));
    expect(s.box, everyElement(1.0));
    expect(s.watched.any((o) => o > 0.2 && o < 0.8), isTrue);
    expect(game.homeScreen, isNotNull);
    expect(game.cornerBox.gearMix, 1);
  });

  chromeTest('Shop <-> Skins and rapid hops keep the pill at 1.0', (
    game,
  ) async {
    game.openShop();
    // Back in the same frame (the Shop has not even loaded), then straight
    // to Skins, then Shop again.
    game.closeShop();
    var s = sample(game);
    expect(s.pill, everyElement(1.0));
    await flushAndMount(game);
    game.openSkins();
    s = sample(game);
    expect(s.pill, everyElement(1.0));
    expect(s.box, everyElement(1.0));
    await flushAndMount(game);
    game.openShop();
    s = sample(game);
    expect(s.pill, everyElement(1.0));
    expect(game.cornerBox.gearMix, 0);
    await flushAndMount(game);
    game.shopScreen!.backButton.onPressed(); // -> Skins
    s = sample(game);
    expect(s.pill, everyElement(1.0));
    await flushAndMount(game);
    game.skinShop!.backButton.onPressed(); // -> home
    s = sample(game);
    expect(s.pill, everyElement(1.0));
    expect(game.cornerBox.gearMix, 1);
  });

  chromeTest('home -> settings fades the pill out, and back in; the corner '
      'box stays and turns into the back chevron', (game) async {
    game.openSettings();
    var s = sample(game);
    expect(s.pill.any((o) => o > 0.2 && o < 0.8), isTrue,
        reason: 'fades with home');
    expect(s.pill.last, 0);
    // PRD-home-v3 §8: the back button is the shared top-left box.
    expect(s.box, everyElement(1));
    expect(game.cornerBox.gearMix, 0);
    await flushAndMount(game);
    game.closeSettings();
    s = sample(game);
    expect(s.pill.any((o) => o > 0.2 && o < 0.8), isTrue);
    expect(s.pill.last, 1);
    expect(s.box, everyElement(1));
    expect(game.cornerBox.gearMix, 1);
  });

  chromeTest('START fades the pill out with home; it is not tappable', (
    game,
  ) async {
    await game.startRun();
    expect(game.state, GameState.playing);
    final s = sample(game);
    expect(s.pill.first, lessThan(1));
    expect(s.pill.last, 0);
    expect(game.coinPill.containsLocalPoint(Vector2(10, 10)), isFalse);
  });

  chromeTest('the shared pill keeps the balance live on every screen', (
    game,
  ) async {
    expect(game.coinPill.label.text, '1 250');
    game.openSkins();
    stepGame(game, 0.3);
    await flushAndMount(game);
    await game.menu.wallet.add(50, CoinSource.play);
    game.update(0);
    expect(game.skinShop!.coinPill.label.text, '1 300');
    expect(
      game.coinPill.x + game.coinPill.width,
      Config.homeCoinPillPositionFor(711).x,
    );
    expect(game.coinPill.descendants().whereType<MenuIcon>(), isNotEmpty);
  });

  chromeTest('owned No-ads tile: check in the icon slot, "AD-FREE" fits', (
    game,
  ) async {
    final home = game.homeScreen!;
    final tile = home.noAdsTile;
    expect(tile.showsCheck, isTrue);
    expect(tile.label.text, 'AD-FREE');
    expect(tile.children.whereType<MenuIcon>(), hasLength(1));
    // Inside the 70 pt tile with a margin, on the other tiles' label line.
    expect(tile.label.x, greaterThanOrEqualTo(4));
    expect(tile.label.x + tile.label.width, lessThanOrEqualTo(tile.width - 4));
    expect(tile.label.y, home.shopTile.label.y);
    // The check is centred in the regular icon box.
    final iconBoxTop = home.shopTile.icon.y;
    expect(
      tile.icon.y + tile.icon.height / 2,
      closeTo(iconBoxTop + Config.homeTileIconSize / 2, 1e-9),
    );
  }, prefs: const {'noAds': true});

  // Fast back: a menu screen closed (and removed) before its onLoad ran /
  // finished must not throw, and the game must land on the right screen.
  for (final (name, open) in <(String, void Function(FlappySpikesGame))>[
    ('Shop', (g) => g.openShop()),
    ('Skins', (g) => g.openSkins()),
  ]) {
    chromeTest('$name tile then immediate Esc: no error, back home', (
      game,
    ) async {
      open(game);
      expect(game.handleBack(), isTrue);
      // The fade-out ends (and removes the screen) before its onLoad got a
      // chance to run, as with a slow first image decode.
      stepGame(game, 0.5);
      await flushAndMount(game);
      expect(game.menuScene, MenuScene.home);
      expect(game.homeScreen, isNotNull);
      expect(game.shopScreen, isNull);
      expect(game.skinShop, isNull);
      expect(game.coinPill.opacity, 1);
      // Interactive again: the same screen opens and loads normally.
      open(game);
      await flushAndMount(game);
      stepGame(game, 0.5);
      expect((game.shopScreen ?? game.skinShop)!.isLoaded, isTrue);
    });

    chromeTest('$name tile then double Esc: no error, home stays', (
      game,
    ) async {
      open(game);
      game.handleBack();
      game.handleBack(); // nothing left to close on home
      stepGame(game, 0.5);
      await flushAndMount(game);
      expect(game.menuScene, MenuScene.home);
      expect(game.homeScreen, isNotNull);
      expect(game.state, GameState.start);
    });
  }

  chromeTest('Shop -> Skins -> immediate back twice: no error, home', (
    game,
  ) async {
    game.openShop();
    await flushAndMount(game);
    game.openSkins(); // from the Shop
    game.handleBack(); // -> Shop (re-created, still loading)
    game.handleBack(); // -> home
    stepGame(game, 0.5);
    await flushAndMount(game);
    expect(game.menuScene, MenuScene.home);
    expect(game.homeScreen, isNotNull);
    expect(game.coinPill.opacity, 1);
  });
}
