import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/home/home_screen.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// Settings behaviour (PRD-home-v3 §8, rebuilt by PRD-2.3 §20; the 2.3
/// layout and its own tests live in test/p23/s20_settings_test.dart).
/// Lets fire-and-forget persistence writes (unawaited Futures completing on
/// microtasks) land before reading the mock store back.
Future<void> flushPrefs() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.value();
  }
}

void main() {
  final withGame = FlameTester<FlappySpikesGame>(
    createTestGame,
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );
  final withUnmutedGame = FlameTester<FlappySpikesGame>(
    () => createTestGame({'muteSound': false}),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  );
  // For real gesture simulation: pump the game widget on a surface sized
  // exactly 320x568 logical px so widget offsets map 1:1 to world points
  // (the default 800x600 test surface letterboxes the fixed-resolution
  // camera, shifting every tap). flame_test's gameSize parameter is
  // inert in 2.2.4, hence the custom pumpWidget.
  final withExactSurface = FlameTester<FlappySpikesGame>(
    createTestGame,
    pumpWidget: (gameWidget, tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(gameWidget);
    },
  );

  Future<void> openSettings(FlappySpikesGame game) async {
    game.openSettings();
    await flushAndMount(game);
  }

  withExactSurface.testGameWidget(
    'gear button opens settings; no tap leaks to gameplay while open',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final home = game.world.children.query<HomeScreen>().single;
      final gear = home.gearButton;
      final gearRect = Config.homeGearRectFor(game.viewHeight);
      expect(gear.position.x, gearRect.left);
      expect(gear.position.y, gearRect.top);

      gear.onPressed();
      await flushAndMount(game);
      expect(game.world.children.query<SettingsPanel>(), hasLength(1));
      expect(game.state, GameState.start, reason: 'gear tap must not leak');

      // A real tap on empty panel space is swallowed by the blocker.
      await tester.tapAt(const Offset(30, 450));
      // Advance past the MultiTapGestureRecognizer's 40 ms countdown so no
      // fake-async timer is left pending at teardown.
      await tester.pump(const Duration(milliseconds: 100));
      expect(game.state, GameState.start);

      // Even a direct (gesture-bypassing) screen tap must not start.
      game.onScreenTap();
      expect(game.state, GameState.start);

      // The home screen fades out and is removed; settings reaches full
      // opacity.
      stepGame(game, 0.6);
      await flushAndMount(game);
      expect(game.world.children.query<HomeScreen>(), isEmpty);
      expect(game.world.children.query<SettingsPanel>().single.opacity, 1);
    },
  );

  withGame.testGameWidget(
    'openSettings is a no-op while playing',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
      game.onScreenTap(); // start -> playing
    },
    verify: (game, tester) async {
      expect(game.state, GameState.playing);
      game.openSettings();
      await flushAndMount(game);
      expect(game.world.children.query<SettingsPanel>(), isEmpty);
      expect(game.state, GameState.playing);
    },
  );

  withUnmutedGame.testGameWidget(
    'SOUND tile toggles mute and persists it',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
      await openSettings(game);
    },
    verify: (game, tester) async {
      final panel = game.world.children.query<SettingsPanel>().single;
      final sfxButton = panel.soundTile;

      expect(game.sound.muted, isFalse);
      sfxButton.onPressed();
      expect(game.sound.muted, isTrue);
      expect(panel.muted, isTrue, reason: 'tile icon swaps to the mute sprite');
      expect(panel.soundTile.on, isFalse);
      await flushPrefs();
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('muteSound'), isTrue);

      sfxButton.onPressed();
      expect(game.sound.muted, isFalse);
      expect(panel.muted, isFalse);
      await flushPrefs();
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('muteSound'), isFalse);
      expect(game.state, GameState.start);
    },
  );

  withExactSurface.testGameWidget(
    'music volume bars set the volume by tap and drag and persist it',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
      await openSettings(game);
    },
    verify: (game, tester) async {
      final panel = game.world.children.query<SettingsPanel>().single;
      final bars = panel.volumeBars;
      Offset barCentre(int i) {
        final r = bars.barRect(i).shift(bars.absolutePosition.toOffset());
        return Offset(r.center.dx, bars.absolutePosition.y + bars.height / 2);
      }

      // Tap bar 2 (0-based) -> level 3 = 3 / 8.
      await tester.tapAt(barCentre(2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(game.sound.musicVolume, closeTo(3 / 8, 1e-9));
      expect(bars.level, 3);
      await flushPrefs();
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('musicVolume'), closeTo(3 / 8, 1e-9));

      // Drag to the last bar -> 8 / 8.
      final gesture = await tester.startGesture(barCentre(2));
      await gesture.moveTo(barCentre(7));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(game.sound.musicVolume, closeTo(1, 1e-9));
      await flushPrefs();
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('musicVolume'), closeTo(1, 1e-9));

      // The card's far left -> 0 (music off).
      await tester.tapAt(Offset(bars.absolutePosition.x + 2, barCentre(0).dy));
      await tester.pump(const Duration(milliseconds: 100));
      expect(game.sound.musicVolume, 0.0);
      expect(panel.musicTile.on, isFalse);

      expect(game.state, GameState.start, reason: 'bar taps must not leak');
    },
  );

  withGame.testGameWidget(
    'back button fades settings out and the home screen back in',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
      await openSettings(game);
    },
    verify: (game, tester) async {
      final panel = game.world.children.query<SettingsPanel>().single;
      panel.backButton.onPressed();
      await flushAndMount(game);
      stepGame(game, 0.6);
      await flushAndMount(game);

      expect(game.world.children.query<SettingsPanel>(), isEmpty);
      final home = game.world.children.query<HomeScreen>().single;
      expect(home.opacity, 1);
      expect(
        game.world.children.query<Bird>(),
        hasLength(1),
        reason: 'closing settings must not add a second bird',
      );
      expect(game.state, GameState.start);
    },
  );

  withGame.testGameWidget(
    'Privacy policy row stays a guarded no-op without a browser',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
      await openSettings(game);
    },
    verify: (game, tester) async {
      final panel = game.world.children.query<SettingsPanel>().single;
      final link = panel.privacyRow;
      expect(link.labelText.text, 'PRIVACY POLICY');
      link.onPressed(); // no browser in tests: guarded no-op, and no tap leak
      expect(game.state, GameState.start);
    },
  );

  withGame.testGameWidget(
    'RUMBLE tile: off is silent, on knocks once and buzzes; persists',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
      await openSettings(game);
    },
    verify: (game, tester) async {
      final panel = game.world.children.query<SettingsPanel>().single;
      final toggle = panel.rumbleButton;
      expect(game.rumble.on, isTrue, reason: 'on by default');
      expect(toggle.on, isTrue);
      stepGame(game, 0.2); // clear the knock throttle of the gear press
      game.rumble.fired.clear();

      // Off: silent, no buzz.
      panel.rumbleTile.onPressed();
      expect(game.rumble.on, isFalse);
      expect(panel.rumbleTile.on, isFalse);
      expect(toggle.on, isFalse);
      expect(toggle.buzzing, isFalse);
      expect(game.rumble.fired, isEmpty);
      await flushPrefs();
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('rumble'), isFalse);

      // On: exactly one knock (the press knock is throttled away), buzz.
      stepGame(game, 0.2);
      panel.rumbleTile.onPressed();
      expect(game.rumble.on, isTrue);
      expect(panel.rumbleTile.on, isTrue);
      expect(toggle.on, isTrue);
      expect(toggle.buzzing, isTrue);
      expect(game.rumble.fired, [RumbleKind.knock]);
      stepGame(game, Config.settingsRumbleBuzz + 0.05);
      expect(toggle.buzzing, isFalse);
      await flushPrefs();
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('rumble'), isTrue);
      expect(game.state, GameState.start, reason: 'no tap leak');
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createTestGame(const {'rumble': false}),
    gameSize: Vector2(Config.worldWidth, Config.worldHeight),
  ).testGameWidget(
    'RUMBLE off is restored from storage; Esc closes settings',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
      await openSettings(game);
    },
    verify: (game, tester) async {
      final panel = game.world.children.query<SettingsPanel>().single;
      expect(game.rumble.on, isFalse);
      expect(panel.rumbleButton.on, isFalse);
      game.onKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.escape,
          logicalKey: LogicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
        {},
      );
      stepGame(game, 0.6);
      await flushAndMount(game);
      expect(game.world.children.query<SettingsPanel>(), isEmpty);
      expect(game.menuScene, MenuScene.home);
    },
  );
}
