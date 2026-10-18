import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/settings_player_card.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flappy_spikes/versus/custom_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../menu_screenshot_test.dart' show loadFonts;
import '../share/share_card_golden_test.dart' show loadCardFonts;
import 'support/tablet.dart' show renderGame;

/// WP-N2 evidence and fit checks: the PLAYER card while editing (with the
/// keyboard state written next to the PNG), the "taken" error, the renamed
/// "DELETE MY ACCOUNT & DATA" row and confirm popup — both labels fit.
/// PNGs land in $FS_EVIDENCE_DIR (default build/menu_shots/n2).
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadFonts();
  await loadCardFonts();
  final outDir =
      Platform.environment['FS_EVIDENCE_DIR'] ?? 'build/menu_shots/n2';

  Future<void> shot(FlappySpikesGame g, String name) async {
    final img = await renderGame(g, Vector2(640, g.viewHeight * 2));
    final bytes = (await img.toByteData(
      format: ImageByteFormat.png,
    ))!.buffer.asUint8List();
    img.dispose();
    final file = File('$outDir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  late FakeVersusService versus;
  FlappySpikesGame make() {
    versus = FakeVersusService(
      profile: const VersusProfile(name: 'BraveParrot907'),
    );
    SettingsPanel.debugResetMusicMemory();
    return createRunTestGame(
      worldHeight: 568,
      prefs: const {
        'ownedItems': ['bird:owl'],
        'equippedItem.bird': 'owl',
      },
      versus: versus,
    );
  }

  Future<SettingsPanel> open(FlappySpikesGame g) async {
    g.openSettings();
    await flushAndMount(g);
    stepGame(g, .6);
    await flushAndMount(g);
    return g.world.children.query<SettingsPanel>().single;
  }

  Future<void> boot(FlappySpikesGame g, WidgetTester _) async {
    await g.ready();
    await preloadImages(g);
    await flushAndMount(g);
  }

  FlameTester<FlappySpikesGame>(
    make,
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'WP-N2 evidence: editing with the keyboard up; "This name is taken"',
    setUp: boot,
    verify: (g, tester) async {
      final card = (await open(g)).playerCard;
      card.tapTarget.onPressed();
      await flushAndMount(g);
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      final state = tester.state<PlayerNameInputState>(
        find.byType(PlayerNameInput),
      );
      tester.testTextInput.enterText('Duck1');
      await tester.pump();
      stepGame(g, .1);
      final calls = [for (final c in tester.testTextInput.log) c.method];
      final kb =
          'focus(playerName)=${state.focus.hasPrimaryFocus}\n'
          'keyboardVisible=${tester.testTextInput.isVisible}\n'
          'textInputCalls=${calls.toSet().join(', ')}\n'
          'draft=${card.draft}\n';
      expect(state.focus.hasPrimaryFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.runAsync(() async {
        await shot(g, 'n2_name_editing_keyboard');
        await File('$outDir/n2_name_editing_keyboard.txt').writeAsString(kb);
      });

      versus.nameAnswer = const CustomNameRefused(
        CustomNameReason.taken,
        current: '',
      );
      await card.commit();
      await flushAndMount(g);
      expect(card.editing, isTrue);
      expect(card.error, CustomNameReason.taken);
      expect(g.storage.versusCustomName, '');
      stepGame(g, .6); // caret off
      await tester.runAsync(() => shot(g, 'n2_name_taken'));
    },
  );

  FlameTester<FlappySpikesGame>(
    make,
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'WP-N2 "DELETE MY ACCOUNT & DATA": the row and the popup title fit',
    setUp: boot,
    verify: (g, tester) async {
      final panel = await open(g);
      final row = panel.deleteRow!;
      expect(row.labelText.text, 'DELETE MY ACCOUNT & DATA');
      final labelRight = row.labelText.x + row.labelText.width;
      final chevronLeft = row.chevron.x - Config.settingsChevronSize / 2;
      expect(labelRight, lessThan(chevronLeft - 4));
      // Scrolled so the row is in view.
      panel.scroll.offset = panel.scroll.maxOffset;
      await flushAndMount(g);
      await tester.runAsync(() => shot(g, 'n2_delete_row'));

      row.onPressed();
      await flushAndMount(g);
      stepGame(g, .5);
      await flushAndMount(g);
      final popup = g.deleteDataPopup!;
      expect(popup.titleText.text, 'DELETE MY ACCOUNT & DATA');
      expect(
        popup.titleText.width,
        lessThanOrEqualTo(Config.p1PopupWidth - 2 * Config.p1PopupPad),
      );
      await tester.runAsync(() => shot(g, 'n2_delete_popup'));
    },
  );
}
