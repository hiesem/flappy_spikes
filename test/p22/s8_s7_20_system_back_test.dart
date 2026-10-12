import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/main.dart' show SystemBackObserver;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §8 / QA S7-20: with predictive back (targetSdk 36) the system
/// back only reaches the game while the framework claims it, and sticky
/// immersive mode needs the navigation bar shown for a single edge swipe.
void main() {
  group('PRD-2.2 §8 S7-20 system back on Android 14+', () {
    FlameTester<FlappySpikesGame>(() => createTestGame()).testGameWidget(
      'install claims system back (again on resume) and pops into the game',
      setUp: (game, tester) async {
        await game.ready();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        final calls = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (call) {
          calls.add(call);
          return Future<Object?>.value();
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final observer = SystemBackObserver(game)..install();
        addTearDown(() {
          WidgetsBinding.instance.removeObserver(observer);
          game.onSystemBackWanted = null;
        });
        await tester.pump();
        bool claims(MethodCall c) =>
            c.method == 'SystemNavigator.setFrameworkHandlesBack' &&
            c.arguments == true;
        expect(calls.where(claims), hasLength(1));

        observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        expect(calls.where(claims), hasLength(2));

        // The predictive-back commit (no observer takes the animated
        // gesture) lands in handlePopRoute → didPopRoute → the back stack.
        game.openSettings();
        await flushAndMount(game);
        expect(game.menuScene, MenuScene.settings);
        expect(await WidgetsBinding.instance.handlePopRoute(), isTrue);
        expect(game.menuScene, MenuScene.home);
        expect(
          calls.map((c) => c.method),
          isNot(contains('SystemNavigator.pop')),
        );
      },
    );

    FlameTester<FlappySpikesGame>(() => createTestGame()).testGameWidget(
      'systemBackWanted follows the menus only (navigation bar shown)',
      setUp: (game, tester) async {
        await game.ready();
        await flushAndMount(game);
      },
      verify: (game, tester) async {
        final sent = <bool>[];
        game.onSystemBackWanted = sent.add;
        expect(game.systemBackWanted, isFalse);

        game.openSettings();
        await flushAndMount(game);
        expect(game.systemBackWanted, isTrue);
        expect(sent, [true]);

        game.closeSettings();
        await stepSeconds(game, 0.6);
        expect(game.systemBackWanted, isFalse);
        expect(sent, [true, false]);

        // In a run back does nothing, so the bar stays hidden even with a
        // back handler (the pause screen's run settings) registered.
        game.openSettings();
        await flushAndMount(game);
        game.state = GameState.paused;
        game.update(0);
        expect(game.systemBackWanted, isFalse);
        expect(sent, [true, false, true, false]);
      },
    );
  });
}
