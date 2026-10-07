import 'package:flappy_spikes/components/home/menu_primitives.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/game/rumble.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'home_flow_test.dart' show flushPrefs, homeTest;

/// PRD-2 §3.33 Rumble service + PRD-home-v3 §10 menu knocks.
void main() {
  group('Rumble service', () {
    late double now;
    Rumble make({bool on = true}) =>
        Rumble(on: on, hardware: false, clock: () => now);
    setUp(() => now = 0);

    test('pulses per spec', () {
      expect(Rumble.knockMs, 15);
      expect(Rumble.knockAmplitude, 90);
      expect(Rumble.shakeMs, 45);
      expect(Rumble.shakeAmplitude, 255);
      expect(Rumble.knockThrottle, 0.09);
    });

    test('knocks are throttled to one per 90 ms', () {
      final r = make();
      r.knock();
      now = 0.05;
      r.knock(); // skipped
      now = 0.089;
      r.knock(); // skipped (window counts from the last fired)
      now = 0.091;
      r.knock();
      now = 0.2;
      r.knock();
      expect(r.fired, [RumbleKind.knock, RumbleKind.knock, RumbleKind.knock]);
    });

    test('a shake is never skipped and wins its window', () {
      final r = make();
      r.knock();
      now = 0.01;
      r.shake(); // inside the knock window: still fires
      now = 0.02;
      r.knock(); // inside the shake window: dropped
      r.shake();
      r.shake();
      now = 0.2;
      r.knock();
      expect(r.fired, [
        RumbleKind.knock,
        RumbleKind.shake,
        RumbleKind.shake,
        RumbleKind.shake,
        RumbleKind.knock,
      ]);
    });

    test('off: nothing fires; applies immediately', () {
      final r = make(on: false);
      r.knock();
      r.shake();
      expect(r.fired, isEmpty);
      r.on = true;
      r.knock();
      expect(r.fired, [RumbleKind.knock]);
    });

    test('no hardware off-device (Linux test host) and never throws', () {
      final r = Rumble(clock: () => now);
      expect(r.hardware, isFalse);
      r.knock();
      r.shake();
      expect(r.fired, [RumbleKind.knock, RumbleKind.shake]);
    });
  });

  group('menu knocks (PRD-home-v3 §10)', () {
    homeTest(
      'a MenuButton press knocks once when RUMBLE is on',
      verify: (game, spy, ads, tester) async {
        expect(game.rumble.on, isTrue);
        expect(game.rumble.hardware, isFalse); // recorder in tests
        final shop = game.homeScreen!.shopTile;
        var pressed = 0;
        final button = MenuButton(onPressed: () => pressed++);
        game.world.add(button);
        await flushAndMount(game);
        withMenuKnock(button, () => pressed++);
        expect(pressed, 1);
        expect(game.rumble.fired, [RumbleKind.knock]);
        // Throttled inside 90 ms, then again.
        withMenuKnock(button, () {});
        expect(game.rumble.fired.length, 1);
        stepGame(game, 0.1);
        expect(shop.knocks, isTrue);
        withMenuKnock(shop, () {});
        expect(game.rumble.fired, [RumbleKind.knock, RumbleKind.knock]);
      },
    );

    homeTest(
      'START (real tap) knocks even though the run starts in the press',
      exactSurface: true,
      verify: (game, spy, ads, tester) async {
        final start = Config.homeStartRectFor(game.viewHeight);
        await tester.tapAt(start.center);
        await tester.pump(const Duration(milliseconds: 100));
        expect(game.state, GameState.playing);
        expect(game.rumble.fired, [RumbleKind.knock]);
        // A playfield tap during the run never knocks.
        stepGame(game, 0.2);
        await tester.tapAt(const Offset(160, 300));
        await tester.pump(const Duration(milliseconds: 100));
        expect(game.rumble.fired, [RumbleKind.knock]);
      },
    );

    homeTest(
      'no knock while a run is on',
      verify: (game, spy, ads, tester) async {
        final button = game.homeScreen!.gearButton;
        game.state = GameState.playing;
        withMenuKnock(button, () {});
        expect(game.rumble.fired, isEmpty);
        game.state = GameState.start;
      },
    );

    homeTest(
      'RUMBLE off (stored): presses are silent',
      prefs: const {'rumble': false},
      exactSurface: true,
      verify: (game, spy, ads, tester) async {
        expect(game.rumble.on, isFalse);
        final gear = Config.homeGearRectFor(game.viewHeight);
        await tester.tapAt(gear.center);
        await tester.pump(const Duration(milliseconds: 100));
        expect(game.menuScene, MenuScene.settings);
        expect(game.rumble.fired, isEmpty);
      },
    );

    homeTest(
      'switching RUMBLE on knocks once, off is silent; persisted + logged',
      prefs: const {'rumble': false},
      verify: (game, spy, ads, tester) async {
        game.setRumble(true);
        expect(game.rumble.fired, [RumbleKind.knock]);
        stepGame(game, 0.2);
        game.setRumble(false);
        expect(game.rumble.fired, [RumbleKind.knock]);
        await flushPrefs();
        expect(game.storage.rumble, isFalse);
        expect(
          spy.events.where((e) => e.$1 == 'rumble_toggle').map((e) => e.$2),
          [
            {'on': 1},
            {'on': 0},
          ],
        );
        // A switch press itself (knock after the action): on -> one knock.
        stepGame(game, 0.2);
        withMenuKnock(game.homeScreen!.gearButton, () => game.setRumble(true));
        expect(game.rumble.fired, [RumbleKind.knock, RumbleKind.knock]);
        stepGame(game, 0.2);
        withMenuKnock(game.homeScreen!.gearButton, () => game.setRumble(false));
        expect(game.rumble.fired.length, 2);
      },
    );
  });
}
