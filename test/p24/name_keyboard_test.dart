import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/components/settings_panel.dart';
import 'package:flappy_spikes/components/settings_player_card.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// WP-N2 (owner bug, Pixel 8 2.4.0 36): a tap on the PLAYER card showed no
/// keyboard. Root cause: GameWidget wraps the game and its overlays in its
/// own FocusScope whose focused child is the game's Focus node, and
/// `EditableText.autofocus` only applies when the scope has NO focused
/// child — so the hidden name field never got focus, never attached to
/// the text input (`TextInput.setClient`) and never asked for the keyboard
/// (`TextInput.show`). The field now asks for focus and the keyboard
/// itself once it is built, and again on a tap on the field while editing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FlappySpikesGame make() => createRunTestGame(
    worldHeight: 568,
    versus: FakeVersusService(
      profile: const VersusProfile(name: 'BraveParrot907'),
    ),
  );

  Future<SettingsPanel> open(FlappySpikesGame g) async {
    g.openSettings();
    await flushAndMount(g);
    stepGame(g, .6);
    await flushAndMount(g);
    return g.world.children.query<SettingsPanel>().single;
  }

  List<String> methods(WidgetTester t) => [
    for (final c in t.testTextInput.log) c.method,
  ];

  FlameTester<FlappySpikesGame>(
    make,
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    'WP-N2 editing the name focuses the hidden field and asks for the '
    'system keyboard (TextInput.setClient + TextInput.show)',
    setUp: (g, _) async {
      await g.ready();
      await preloadImages(g);
      await flushAndMount(g);
    },
    verify: (g, tester) async {
      final card = (await open(g)).playerCard;
      await tester.pump();
      tester.testTextInput.log.clear();
      expect(tester.testTextInput.isVisible, isFalse);

      card.tapTarget.onPressed();
      await flushAndMount(g);
      await tester.pump(); // the overlay is built
      await tester.pump(); // its post-frame focus request
      await tester.pump();

      final state = tester.state<PlayerNameInputState>(
        find.byType(PlayerNameInput),
      );
      expect(state.focus.hasPrimaryFocus, isTrue);
      expect(FocusManager.instance.primaryFocus, same(state.focus));
      expect(methods(tester), contains('TextInput.setClient'));
      expect(methods(tester), contains('TextInput.show'));
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      // The keyboard is hidden by the system (Android's hide arrow): a tap
      // on the card while editing asks for it again.
      tester.testTextInput.log.clear();
      tester.testTextInput.hide();
      expect(tester.testTextInput.isVisible, isFalse);
      card.fieldTarget.onPressed();
      await tester.pump();
      expect(methods(tester), contains('TextInput.show'));
      expect(tester.testTextInput.isVisible, isTrue);

      // Typing reaches the card; ✕ closes the field and the keyboard.
      tester.testTextInput.enterText('Duck1');
      await tester.pump();
      expect(card.draft, 'Duck1');
      card.cancel.onPressed();
      await flushAndMount(g);
      await tester.pump();
      expect(find.byType(PlayerNameInput), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        FocusManager.instance.primaryFocus,
        isNot(
          isA<FocusNode>().having((f) => f.debugLabel, 'label', 'playerName'),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
