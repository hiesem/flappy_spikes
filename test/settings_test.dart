import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/bird.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/home/home_screen.dart';
import 'package:flappy_spikes/components/ui/fadable_text.dart';
import 'package:flappy_spikes/components/ui/sprite_button.dart';
import 'package:flappy_spikes/components/ui/text_button.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// Settings-panel layout contract (mirrors the private constants in
/// settings_panel.dart; pinned here so layout regressions fail loudly).
const iconX = 85.0;
const contentX = 115.0;
const titleDy = -140.0;
const sfxRowDy = -45.0;
const musicRowDy = 15.0;
const creditDy = 60.0;
const backDy = 115.0;

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
  final withTallGame = FlameTester<FlappySpikesGame>(
    () => createTestGame(const {}, 711),
    gameSize: Vector2(Config.worldWidth, 711),
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

  withGame.testGameWidget(
    'settings panel builds fully at the 568 design height',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
      await openSettings(game);
    },
    verify: (game, tester) async {
      const centerY = 284.0;
      final panel = game.world.children.query<SettingsPanel>().single;

      final texts = panel.children.whereType<FadableTextComponent>().toList();
      expect(
        texts.map((t) => t.text),
        containsAll(['SETTINGS', 'SOUND EFFECTS', 'Music by ElectroBaptist']),
      );
      final title = texts.singleWhere((t) => t.text == 'SETTINGS');
      expect(title.position.x, 160);
      expect(title.position.y, centerY + titleDy);

      // SFX row: 30x30 speaker button + label; MUSIC row: note icon + slider.
      final buttons = panel.children.whereType<SpriteButton>().toList();
      expect(buttons, hasLength(2), reason: 'sfx toggle + back button');
      final sfxButton = buttons.singleWhere((b) => b.position.x == iconX);
      expect(sfxButton.position.y, centerY + sfxRowDy);
      expect(sfxButton.size.x, Config.settingsButtonSize.x);

      final musicIcons = panel.children
          .whereType<SpriteComponent>()
          .where((c) => c is! SpriteButton)
          .toList();
      expect(musicIcons, hasLength(1));
      expect(musicIcons.single.position.x, iconX);
      expect(musicIcons.single.position.y, centerY + musicRowDy);

      final slider = panel.children.whereType<VolumeSlider>().single;
      expect(slider.position.x, contentX);
      expect(slider.position.y, centerY + musicRowDy - 12);
      expect(slider.size.x, VolumeSlider.trackWidth);
      expect(slider.value, 0.6, reason: 'default music volume');

      final back = buttons.singleWhere((b) => b.position.x == 160);
      expect(back.position.y, centerY + backDy);

      final link = panel.children.whereType<TextButton>().single;
      expect(link.label.text, 'Privacy Policy');
      expect(link.position, Config.privacyLinkPosition);

      // Everything sits in the safe band between the spike strips.
      expect(title.position.y - 14, greaterThan(Config.spikeHeight));
      expect(
        back.position.y + 15,
        lessThan(Config.worldHeight - Config.spikeHeight),
      );
    },
  );

  withTallGame.testGameWidget(
    'settings panel lays out within the safe band at 711',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
      await openSettings(game);
    },
    verify: (game, tester) async {
      const centerY = 711 / 2;
      final panel = game.world.children.query<SettingsPanel>().single;

      final texts = panel.children.whereType<FadableTextComponent>().toList();
      expect(texts.singleWhere((t) => t.text == 'SETTINGS').position.y,
          centerY + titleDy);

      final buttons = panel.children.whereType<SpriteButton>().toList();
      final sfxButton = buttons.singleWhere((b) => b.position.x == iconX);
      expect(sfxButton.position.y, centerY + sfxRowDy);
      final back = buttons.singleWhere((b) => b.position.x == 160);
      expect(back.position.y, centerY + backDy);

      final slider = panel.children.whereType<VolumeSlider>().single;
      expect(slider.position.y, centerY + musicRowDy - 12);

      final link = panel.children.whereType<TextButton>().single;
      expect(link.position, Config.privacyLinkPositionFor(centerY));

      expect(centerY + titleDy - 14, greaterThan(Config.spikeHeight));
      expect(
        centerY + backDy + 15,
        lessThan(711 - Config.spikeHeight),
      );
    },
  );

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
    'SOUND EFFECTS row toggles mute and persists it',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
      await openSettings(game);
    },
    verify: (game, tester) async {
      final panel = game.world.children.query<SettingsPanel>().single;
      final sfxButton = panel.children
          .whereType<SpriteButton>()
          .singleWhere((b) => b.position.x == iconX);

      expect(game.sound.muted, isFalse);
      sfxButton.onPressed();
      expect(game.sound.muted, isTrue);
      expect(panel.muted, isTrue, reason: 'row icon swaps to the mute sprite');
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
    'music slider sets the volume by tap and drag and persists it',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
      await openSettings(game);
    },
    verify: (game, tester) async {
      final panel = game.world.children.query<SettingsPanel>().single;
      final slider = panel.children.whereType<VolumeSlider>().single;
      // Slider world rect: x 115..255, y 287..311 (track center y = 299).
      const trackY = 299.0;
      double worldX(double localX) => contentX + localX;

      // Tap at local x=35 -> 0.25.
      await tester.tapAt(Offset(worldX(35), trackY));
      await tester.pump(const Duration(milliseconds: 100));
      expect(game.sound.musicVolume, closeTo(0.25, 1e-9));
      expect(slider.value, closeTo(0.25, 1e-9));
      await flushPrefs();
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('musicVolume'), closeTo(0.25, 1e-9));

      // Drag from local x=35 to local x=119 -> 0.85. Driven with explicit
      // moveTo (dragFrom's slop-compensation sends extra intermediate moves).
      final gesture = await tester.startGesture(Offset(worldX(35), trackY));
      await gesture.moveTo(Offset(worldX(119), trackY));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(game.sound.musicVolume, closeTo(0.85, 1e-9));
      expect(slider.value, closeTo(0.85, 1e-9));
      await flushPrefs();
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('musicVolume'), closeTo(0.85, 1e-9));

      // Tap the very left edge -> 0.0 (music off); volume stays in [0, 1].
      await tester.tapAt(Offset(worldX(0), trackY));
      await tester.pump(const Duration(milliseconds: 100));
      expect(game.sound.musicVolume, 0.0);
      expect(game.sound.musicVolume, inInclusiveRange(0.0, 1.0));

      expect(game.state, GameState.start, reason: 'slider taps must not leak');
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
      final back = panel.children
          .whereType<SpriteButton>()
          .singleWhere((b) => b.position.x == 160);

      back.onPressed();
      await flushAndMount(game);
      stepGame(game, 0.6);
      await flushAndMount(game);

      expect(game.world.children.query<SettingsPanel>(), isEmpty);
      final home = game.world.children.query<HomeScreen>().single;
      expect(home.opacity, 1);
      expect(game.world.children.query<Bird>(), hasLength(1),
          reason: 'closing settings must not add a second bird');
      expect(game.state, GameState.start);
    },
  );

  withGame.testGameWidget(
    'privacy link on the settings panel stays a guarded no-op',
    setUp: (game, tester) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
      await openSettings(game);
    },
    verify: (game, tester) async {
      final panel = game.world.children.query<SettingsPanel>().single;
      final link = panel.children.whereType<TextButton>().single;
      expect(link.label.text, 'Privacy Policy');
      link.onPressed(); // no browser in tests: guarded no-op, and no tap leak
      expect(game.state, GameState.start);
    },
  );
}
