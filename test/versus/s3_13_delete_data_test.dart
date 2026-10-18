import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/delete_data_popup.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

/// WP-4c PRD-2 §3.13 / Q22: the Settings "Delete my data" row, the confirm
/// dialog, the call into `VersusService.deleteMyData`, the result and
/// failure texts, and the local reset.
void main() {
  late FakeVersusService versus;

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

  /// The row's tap (PRD-2.3 §20.2: the PRIVACY & DATA card's row).
  void tapRow(FlappySpikesGame game) {
    game.world.children.query<SettingsPanel>().single.deleteRow!.onPressed();
  }

  FlameTester<FlappySpikesGame> at(double height) =>
      FlameTester<FlappySpikesGame>(
        () {
          versus = FakeVersusService();
          return createRunTestGame(
            worldHeight: height,
            versus: versus,
          );
        },
        gameSize: Vector2(320, height),
      );

  for (final h in [568.0, 711.0]) {
    at(h).testGameWidget(
      '§3.13 / PRD-2.3 §20.2 ($h): Delete my data is the last row of the '
      'PRIVACY & DATA card, red, clear of the bottom spike strip',
      setUp: (game, _) async {
        await boot(game);
        await openSettings(game);
      },
      verify: (game, _) async {
        final panel = game.world.children.query<SettingsPanel>().single;
        final row = panel.deleteRow!;
        expect(row.labelText.text, 'DELETE MY DATA');
        expect(row.labelText.color, Config.settingsRed);
        expect(panel.privacyCard.rows.last, row);
        // WP-NAME the body scrolls (PLAYER card on top): at its end.
        panel.scroll.offset = panel.scroll.maxOffset;
        expect(
          row.toAbsoluteRect().bottom,
          lessThan(game.viewHeight - Config.menuSpikeHeight),
        );
        expect(game.deleteDataPopup, isNull);
      },
    );
  }

  at(711).testGameWidget(
    '§3.13 the row opens the confirm dialog with the PRD wording; CANCEL, '
    'the ✕ and Esc all cancel without calling the service',
    setUp: (game, _) async {
      await boot(game);
      await openSettings(game);
    },
    verify: (game, _) async {
      tapRow(game);
      await flushAndMount(game);
      var popup = game.deleteDataPopup;
      expect(popup, isNotNull);
      expect(popup!.step, DeleteDataStep.confirm);
      expect(popup.titleText.text, 'DELETE MY DATA');
      expect(
        popup.messageText.text,
        contains('uploaded runs'),
        reason: 'the PRD says what is deleted online',
      );
      expect(
        popup.messageText.text,
        contains('your account'),
      );
      expect(
        popup.smallText.text,
        contains('Coins and skins stay; your level resets'),
      );
      expect(popup.cancelButton, isNotNull);
      expect(versus.deleteCalls, 0);

      // CANCEL: no call, no popup.
      popup.cancelButton!.onPressed();
      await flushAndMount(game);
      expect(game.deleteDataPopup, isNull);
      expect(versus.deleteCalls, 0);
      stepGame(game, 0.4);

      // The ✕ box too.
      tapRow(game);
      await flushAndMount(game);
      popup = game.deleteDataPopup!;
      popup.closeButton.onPressed();
      await flushAndMount(game);
      expect(game.deleteDataPopup, isNull);
      expect(versus.deleteCalls, 0);
      stepGame(game, 0.4);

      // Esc (the topmost back handler is the dialog's).
      tapRow(game);
      await flushAndMount(game);
      expect(game.deleteDataPopup, isNotNull);
      game.onKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.escape,
          logicalKey: LogicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
        {},
      );
      await flushAndMount(game);
      expect(game.deleteDataPopup, isNull);
      expect(versus.deleteCalls, 0);
      expect(
        game.world.children.query<SettingsPanel>(),
        hasLength(1),
        reason: 'the settings panel stays up behind the dialog',
      );
      expect(game.state, GameState.start);
    },
  );

  at(711).testGameWidget(
    '§3.13 DELETE calls VersusService.deleteMyData and shows the result text',
    setUp: (game, _) async {
      await boot(game);
      await openSettings(game);
    },
    verify: (game, _) async {
      tapRow(game);
      await flushAndMount(game);
      final popup = game.deleteDataPopup!;
      expect(popup.busy, isFalse);
      popup.confirmButton.onPressed();
      await flushAndMount(game);

      expect(versus.deleteCalls, 1, reason: 'the call reaches the service');
      final result = game.deleteDataPopup;
      expect(result, isNotNull);
      expect(result!.step, DeleteDataStep.done);
      expect(result.titleText.text, 'DATA DELETED');
      expect(result.messageText.text, contains('your account are gone'));
      expect(
        result.messageText.text,
        contains('Coins and skins on this phone are kept'),
      );
      expect(result.cancelButton, isNull, reason: 'one OK on the result');
      result.confirmButton.onPressed();
      await flushAndMount(game);
      expect(game.deleteDataPopup, isNull);
      expect(game.state, GameState.start);
    },
  );

  at(711).testGameWidget(
    '§3.13 the failure text when the callable cannot reach the server',
    setUp: (game, _) async {
      await boot(game);
      versus.deleteSucceeds = false;
      await openSettings(game);
    },
    verify: (game, _) async {
      tapRow(game);
      await flushAndMount(game);
      game.deleteDataPopup!.confirmButton.onPressed();
      await flushAndMount(game);
      expect(versus.deleteCalls, 1);
      final result = game.deleteDataPopup!;
      expect(result.step, DeleteDataStep.failed);
      expect(result.titleText.text, "COULDN'T DELETE");
      expect(result.messageText.text, contains('nothing was deleted'));
      expect(result.smallText.text, contains('try again'));
    },
  );

  test('§3.13 the local reset (Q22) clears the versus keys and keeps '
      'coins, skins, levels, feathers and puzzle', () async {
    SharedPreferences.setMockInitialValues({
      'coins': 77,
      'ownedItems': ['bird:gold'],
      'bestScore': 12,
      'feathers': 2,
      'puzzlePieces': 0x5,
      'puzzleRound': 3,
      'metElements': ['saw'],
      'versusNickname': 'SwiftKiwi482',
      'uploadQueue': ['{"runId":"a"}'],
      'uploadsToday': 2,
      'uploadsDay': '2026-10-08',
    });
    final s = GameStorage();
    await s.load();
    await s.resetVersusData();
    expect(s.versusNickname, isNull, reason: 'regenerated at the next use');
    expect(s.uploadQueue, isEmpty);
    expect(s.uploadsToday, 0);
    expect(s.uploadsDay, '');
    expect(s.coins, 77);
    expect(s.ownedItems, {'bird:gold'});
    expect(s.bestScore, 12);
    expect(s.feathers, 2);
    expect(s.puzzlePieces, 0x5);
    expect(s.puzzleRound, 3);
    expect(s.metElements, {'saw'});

    // And it round-trips through the store.
    final back = GameStorage();
    await back.load();
    expect(back.versusNickname, isNull);
    expect(back.uploadQueue, isEmpty);
    expect(back.uploadsDay, '');
    expect(back.coins, 77);
    expect(back.bestScore, 12);
  });
}
