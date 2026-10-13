import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/services/versus_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../run/shots/versus_shots_test.dart' show rival;

Future<void> advance(FlappySpikesGame g, double seconds) async {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    g.update(1 / 60);
    await Future<void>.value();
  }
  await flushAndMount(g);
}

void main() {
  for (final result in ['held', 'delayed', 'solo']) {
    late FakeVersusService versus;
    late Completer<bool> search;
    late AnalyticsSpy spy;
    FlameTester<FlappySpikesGame>(() {
      search = Completer<bool>();
      versus = FakeVersusService(
        loadingIntro: true,
        pool: result == 'held' ? [rival()] : [],
        onSearch: result == 'delayed' ? () => search.future : null,
      );
      spy = AnalyticsSpy();
      return createRunTestGame(
        worldHeight: 711,
        versus: versus,
        services: spy,
        prefs: {'firstRunHintSeen': true},
      );
    }, gameSize: Vector2(320, 711)).testGameWidget(
      '§10 × §25 $result: intro, waiting, nested pause/settings/back, reminder',
      setUp: (g, _) async {
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, _) async {
        g.onScreenTap();
        await flushAndMount(g);
        expect(g.state, GameState.versusIntro);
        await advance(g, 1.2);
        g.onPlayfieldTap(); // intro taps are inert
        expect(g.run, isNull);
        expect(spy.events.where((e) => e.$1 == 'tap_reminder_shown'), isEmpty);
        if (result == 'delayed') {
          versus.pool.add(rival());
          search.complete(true);
        }
        await finishVersusIntro(g);
        final run = g.run!;
        var starts = 0;
        run.events.on<RunStarted>((_) => starts++);
        expect(run.waiting, isTrue);
        expect(run.waitClock, closeTo(0, .05));
        await advance(g, 3.5);
        expect(g.firstRunHint!.shown, isFalse);
        g.pause();
        await flushAndMount(g);
        g.openRunSettings();
        await flushAndMount(g);
        final heldClock = run.waitClock;
        await advance(g, 5);
        expect(run.waitClock, heldClock);
        expect(run.state.runClock, 0);
        expect(starts, 0);
        g.handleBack();
        await flushAndMount(g);
        expect(g.runSettingsOpen, isFalse);
        expect(g.state, GameState.paused);
        await advance(g, .4);
        g.handleBack();
        await flushAndMount(g);
        expect(g.state, GameState.playing);
        expect(run.waiting, isTrue);
        await advance(g, .9);
        expect(g.firstRunHint!.shown, isTrue);
        expect(
          spy.events.where((e) => e.$1 == 'tap_reminder_shown'),
          hasLength(1),
        );
        g.onPlayfieldTap();
        g.onPlayfieldTap();
        expect(starts, 1);
        expect(versus.runStarts, 1);
        expect(run.clock.running, isTrue);
        await advance(g, .25);
        expect(g.firstRunHint, isNull);
      },
    );
  }
}
