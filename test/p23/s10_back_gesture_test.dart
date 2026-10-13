// S8-14 (device QA, PRD-2.3 §10.1 / §10.4, PRD-2.2 §8): an Android back
// edge swipe while the run waits for its first tap must not start the run.
// The OS delivers a pointer-down, then cancels the pointer once it claims
// the gesture; the waiting run therefore starts on a confirmed tap (tap-up),
// while mid-run flaps stay on pointer-down (no added latency).
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/painting.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

int _count(AnalyticsSpy spy, String name) =>
    spy.events.where((e) => e.$1 == name).length;

void _test(
  String name,
  Future<void> Function(FlappySpikesGame game, AnalyticsSpy spy, WidgetTester t)
  verify,
) {
  final spy = AnalyticsSpy();
  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(services: spy),
    pumpWidget: (gameWidget, tester) async {
      tester.view
        ..physicalSize = const Size(320, 568)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(gameWidget);
    },
  ).testGameWidget(
    name,
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
      await flushAndMount(game);
    },
    verify: (game, tester) async {
      final run = await openRun(game);
      expect(run.waiting, isTrue);
      // Let the home screen fade away so nothing but the run takes input.
      stepGame(game, 0.6);
      await flushAndMount(game);
      spy.events.clear();
      await verify(game, spy, tester);
      // Let short-lived timers (the flap's haptic tick) run out.
      await tester.pump(const Duration(milliseconds: 200));
    },
  );
}

void main() {
  group('S8-14 the back edge swipe while waiting (PRD-2.3 §10.1)', () {
    _test(
      'pointer-down then cancel (the OS back gesture) leaves the run waiting',
      (game, spy, tester) async {
        final hintSeen = game.storage.firstRunHintSeen;
        final g = await tester.startGesture(const Offset(2, 300));
        await tester.pump();
        expect(game.run!.waiting, isTrue,
            reason: 'pointer-down alone must not start the waiting run');
        await g.moveBy(const Offset(20, 0));
        await g.cancel();
        await tester.pump(const Duration(milliseconds: 100));
        final run = game.run!;
        expect(game.state, GameState.playing);
        expect(run.waiting, isTrue);
        expect(run.started, isFalse);
        expect(run.state.runClock, 0);
        expect(run.clock.running, isFalse);
        expect(_count(spy, 'run_start'), 0);
        expect(_count(spy, 'game_start'), 0);
        expect(game.storage.firstRunHintSeen, hintSeen);
        // Back during a run does nothing (PRD-2.2 §8).
        expect(game.handleSystemBack(), isFalse);
        expect(run.waiting, isTrue);

        // The next real tap still starts it.
        await tester.tapAt(const Offset(160, 300));
        await tester.pump();
        expect(run.started, isTrue);
        expect(_count(spy, 'run_start'), 1);
      },
    );

    _test(
      'a swipe past the touch slop that the app sees in full does not start '
      'it either',
      (game, spy, tester) async {
        final g = await tester.startGesture(const Offset(2, 300));
        await g.moveBy(const Offset(kTouchSlop * 4, 0));
        await g.up();
        await tester.pump(const Duration(milliseconds: 100));
        expect(game.run!.waiting, isTrue);
        expect(_count(spy, 'run_start'), 0);
      },
    );

    _test(
      'a normal tap starts at once and flaps; mid-run flaps fire on '
      'pointer-down',
      (game, spy, tester) async {
        await tester.tapAt(const Offset(160, 300));
        final run = game.run!;
        expect(run.started, isTrue);
        expect(run.clock.running, isTrue);
        expect(game.runBirdVelocityY!, lessThan(0));
        expect(_count(spy, 'run_start'), 1);

        // Let gravity turn the bird around, then a pointer-down alone flaps.
        stepGame(game, 0.4);
        expect(game.runBirdVelocityY!, greaterThan(0));
        final g = await tester.startGesture(const Offset(160, 300));
        expect(game.runBirdVelocityY!, lessThan(0),
            reason: 'mid-run flaps must stay on pointer-down');
        await g.up();
      },
    );
  });
}
