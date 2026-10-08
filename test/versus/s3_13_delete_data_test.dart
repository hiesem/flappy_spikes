import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/delete_data_popup.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/ui/fadable_text.dart';
import 'package:flappy_spikes/components/ui/text_button.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/storage.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, TapDownDetails;
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

  /// The row's tap (fires on tap-down, as the SOUND / RUMBLE rows do).
  void tapRow(FlappySpikesGame game) {
    game.world.children
        .query<SettingsPanel>()
        .single
        .deleteIcon!
        .onTapDown(
          TapDownEvent(
            1,
            game,
            TapDownDetails(kind: PointerDeviceKind.touch),
          ),
        );
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

  at(568).testGameWidget(
    '§3.13 the Settings row sits in the free band, clear of the bottom '
    'spike strip at 568',
    setUp: (game, _) async {
      await boot(game);
      await openSettings(game);
    },
    verify: (game, _) async {
      const centerY = 284.0;
      final panel = game.world.children.query<SettingsPanel>().single;
      final icon = panel.deleteIcon;
      final label = panel.deleteLabel;
      expect(icon, isNotNull);
      expect(label, isNotNull);
      expect(label!.text, 'DELETE MY DATA');
      expect(icon!.position, SettingsPanel.deleteRowPositionFor(centerY));
      expect(label.position.x, Config.settingsContentX);
      expect(label.position.y, icon.position.y);

      // Below the rumble rows / music credit, above the privacy link, and
      // fully inside the safe band between the 44 pt spike strips.
      final credit = panel.children
          .whereType<FadableTextComponent>()
          .singleWhere((t) => t.text.startsWith('Music by'));
      expect(icon.position.y - 15, greaterThan(credit.position.y + 10));
      final link = panel.children.whereType<TextButton>().single;
      expect(icon.position.y + 15, lessThan(link.position.y - link.size.y / 2));
      expect(
        icon.position.y + 15,
        lessThan(game.viewHeight - Config.menuSpikeHeight),
      );
      expect(icon.position.y - 15, greaterThan(Config.menuSpikeHeight));
      expect(game.deleteDataPopup, isNull);
    },
  );

  at(711).testGameWidget(
    '§3.13 the row is in the same band at 711 (mock settings_v3 layout '
    'untouched)',
    setUp: (game, _) async {
      await boot(game);
      await openSettings(game);
    },
    verify: (game, _) async {
      const centerY = 355.5;
      final panel = game.world.children.query<SettingsPanel>().single;
      final icon = panel.deleteIcon!;
      expect(icon.position, SettingsPanel.deleteRowPositionFor(centerY));
      expect(panel.rumbleButton.position.y, centerY + Config.settingsRumbleRowDy);
      expect(
        panel.children.whereType<TextButton>().single.position.y,
        Config.privacyLinkPositionFor(centerY).y,
      );
      expect(
        icon.position.y + 15,
        lessThan(game.viewHeight - Config.menuSpikeHeight),
      );
    },
  );

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
        contains('Coins, skins and levels stay on this phone'),
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
        contains('Coins, skins and levels on this phone are kept'),
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
