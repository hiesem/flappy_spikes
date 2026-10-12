import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// PRD-2.2 §9: the music starts at 25 %. A stored volume always wins, and
/// "Delete my data" clears the stored key so the default applies again.
void main() {
  group('PRD-2.2 §9.1 default volume', () {
    test('the default is 0.25 for storage and for the sound service', () async {
      expect(Config.defaultMusicVolume, 0.25);
      SharedPreferences.setMockInitialValues({});
      final storage = GameStorage();
      await storage.load();
      expect(storage.musicVolume, 0.25);
      expect(SoundService(enabled: false).musicVolume, 0.25);
    });

    test('a stored volume wins, including 0', () async {
      SharedPreferences.setMockInitialValues({'musicVolume': 0.9});
      final loud = GameStorage();
      await loud.load();
      expect(loud.musicVolume, 0.9);

      SharedPreferences.setMockInitialValues({'musicVolume': 0.0});
      final silent = GameStorage();
      await silent.load();
      expect(silent.musicVolume, 0.0);
    });

    test('resetMusicVolume removes the key and restores the default', () async {
      SharedPreferences.setMockInitialValues({'musicVolume': 0.9});
      final storage = GameStorage();
      await storage.load();
      await storage.resetMusicVolume();
      expect(storage.musicVolume, 0.25);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('musicVolume'), isFalse);
      final reader = GameStorage();
      await reader.load();
      expect(reader.musicVolume, 0.25);
    });
  });

  group('PRD-2.2 §9 in the game', () {
    late FakeVersusService versus;

    FlameTester<FlappySpikesGame> gameWith(Map<String, Object> prefs) =>
        FlameTester<FlappySpikesGame>(() {
          versus = FakeVersusService();
          return createRunTestGame(prefs: prefs, versus: versus);
        });

    Future<void> boot(FlappySpikesGame game) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
    }

    Future<void> openSettings(FlappySpikesGame game) async {
      game.openSettings();
      await flushAndMount(game);
      stepGame(game, 0.6);
      await flushAndMount(game);
    }

    double sliderValue(FlappySpikesGame game) => game.world.children
        .query<SettingsPanel>()
        .single
        .children
        .whereType<VolumeSlider>()
        .single
        .value;

    gameWith({}).testGameWidget(
      'a fresh install plays and shows the music at 25 %',
      setUp: (game, tester) async => boot(game),
      verify: (game, tester) async {
        expect(game.sound.musicVolume, 0.25);
        await openSettings(game);
        expect(sliderValue(game), 0.25);
      },
    );

    gameWith({'musicVolume': 0.9, 'muteSound': true}).testGameWidget(
      'Delete my data (confirmed) clears the volume: music and slider go to '
      '25 %, the mute setting stays',
      setUp: (game, tester) async => boot(game),
      verify: (game, tester) async {
        await openSettings(game);
        expect(game.sound.musicVolume, 0.9);
        expect(sliderValue(game), 0.9);

        game.openDeleteDataConfirm();
        await flushAndMount(game);
        await game.confirmDeleteMyData();
        await flushAndMount(game);

        expect(versus.deleteCalls, 1);
        expect(game.storage.musicVolume, 0.25);
        expect(game.sound.musicVolume, 0.25);
        expect(sliderValue(game), 0.25);
        expect(game.storage.muteSound, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('musicVolume'), isFalse);
      },
    );

    gameWith({'musicVolume': 0.9}).testGameWidget(
      'a refused Delete my data changes nothing, the volume stays 90 %',
      setUp: (game, tester) async => boot(game),
      verify: (game, tester) async {
        versus.deleteSucceeds = false;
        await openSettings(game);
        game.openDeleteDataConfirm();
        await flushAndMount(game);
        await game.confirmDeleteMyData();
        await flushAndMount(game);

        expect(versus.deleteCalls, 1);
        expect(game.storage.musicVolume, 0.9);
        expect(game.sound.musicVolume, 0.9);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getDouble('musicVolume'), 0.9);
      },
    );
  });
}
