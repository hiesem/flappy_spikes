import 'dart:async';

import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

import '../game_services_test.dart' show FakeGameServices;
import '../helpers.dart';

/// 2.4.0 (26) Pixel 8, first launch: the consent form, the notification
/// question and Play Games' "Welcome back" banner all landed at once; the
/// banner showed behind the dialogs and the player saw no sign-in. Now they
/// come one at a time: consent → notification question → sign-in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('the notification question waits for the consent form', () {
    final reminders = FakeReminders();
    final consent = Completer<void>();
    FlappySpikesGame make() =>
        createTestGame(const {}, null, null, null, reminders)
          ..awaitLaunchConsent = () => consent.future;

    testWithGame<FlappySpikesGame>(
      'consent first, then the question, then '
      'launchDialogsDone',
      make,
      (game) async {
        await pumpEventQueue();
        expect(reminders.permissionCalls, 0, reason: 'consent form still up');
        var done = false;
        unawaited(game.launchDialogsDone.then((_) => done = true));
        await pumpEventQueue();
        expect(done, isFalse);
        consent.complete();
        await pumpEventQueue();
        expect(reminders.permissionCalls, 1);
        expect(done, isTrue);
      },
    );
  });

  group('no consent flow (tests, Linux): nothing waits', () {
    final reminders = FakeReminders();
    testWithGame<FlappySpikesGame>(
      'the question and launchDialogsDone right away',
      () => createTestGame(const {}, null, null, null, reminders),
      (game) async {
        await game.launchDialogsDone;
        expect(reminders.permissionCalls, 1);
      },
    );
  });

  test('Android: the silent Play Games sign-in waits for the launch '
      'dialogs', () async {
    final s = FakeGameServices()
      ..isAndroidPlatform = (() => true)
      ..authenticated = true
      ..markInitialized();
    final dialogs = Completer<void>();
    s.launchGate = dialogs.future;
    final run = s.recheckSignIn('launch +2s');
    await pumpEventQueue();
    expect(s.authChecks, 0, reason: 'dialogs still up');
    expect(s.signInCalls, 0);
    dialogs.complete();
    await run;
    expect(s.authChecks, 1);
    expect(s.signInCalls, 1);
  });

  test('iOS: Game Center waits for the launch dialogs too', () async {
    final s = FakeGameServices()
      ..isIOSPlatform = (() => true)
      ..markInitialized();
    final dialogs = Completer<void>();
    final run = s.authenticateAtLaunch(after: dialogs.future);
    await pumpEventQueue();
    expect(s.signInCalls, 0);
    dialogs.complete();
    await run;
    expect(s.signInCalls, 1);
  });
}
