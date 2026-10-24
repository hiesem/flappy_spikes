import 'package:flame/extensions.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/elements.dart';
import 'package:flappy_spikes/run/run_events.dart';
import 'package:flappy_spikes/services/ftue_tracker.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

List<Map<String, Object>> events(AnalyticsSpy spy, String name) => [
  for (final event in spy.events)
    if (event.$1 == name) event.$2!,
];

FlappySpikesGame makeGame(AnalyticsSpy spy, FtueTracker tracker) {
  SharedPreferences.setMockInitialValues({
    'metElements': ['normal_hoop'],
  });
  return FlappySpikesGame(
    worldHeight: 711,
    services: spy,
    soundEnabled: false,
    ftueTracker: tracker,
  )
    ..runSeed = 7
    ..runDebug.ignoreGates = true;
}

final class RouterTracker extends FtueTracker {
  RouterTracker(this.services);

  final GameServices services;
  final Set<String> _steps = {};

  @override
  void step(String id, {required int gamesPlayed}) {
    if (!_steps.add(id)) return;
    services.track('ftue_step', {'name': id});
  }

  @override
  void highlight(
    String id, {
    required bool scripted,
    required int runNo,
    required int hoop,
  }) => services.track('highlight_seen', {
    'id': id,
    'scripted': scripted,
    'run_no': runNo,
    'hoop': hoop,
  });

  @override
  void firstMeet(
    ElementId element, {
    required int hoop,
    required int games,
    required bool forced,
    required bool survived,
  }) => services.track('first_meet', {
    'element': element.storageId,
    'hoop': hoop,
    'games': games,
    'forced': forced,
    'survived': survived,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final highlightSpy = AnalyticsSpy();
  FlameTester<FlappySpikesGame>(
    () => makeGame(highlightSpy, RouterTracker(highlightSpy)),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'highlight_seen carries the four PRD parameters',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, _) async {
      final run = await startRun(game);
      highlightSpy.events.clear();

      run.events.emit(const HighlightStarted('ride', scripted: true, hoop: 7));

      expect(events(highlightSpy, 'highlight_seen'), [
          {'id': 'ride', 'scripted': true, 'run_no': 1, 'hoop': 7},
      ]);
      expect(
        events(highlightSpy, 'ftue_step').single['name'],
        'run1_highlight',
      );
    },
  );

  final meetSpy = AnalyticsSpy();
  FlameTester<FlappySpikesGame>(
    () => makeGame(meetSpy, RouterTracker(meetSpy)),
    gameSize: Vector2(320, 711),
  ).testGameWidget(
    'first_meet is emitted once for the first element',
    setUp: (game, _) async {
      await game.ready();
      game.sound.enabled = false;
      await preloadImages(game);
    },
    verify: (game, _) async {
      game.runDebug.force.add(ElementId.saw);
      final run = await startRun(game, force: [ElementId.saw]);
      meetSpy.events.clear();

      run.events.emit(const ElementSpawned(ElementId.saw));
      run.events.emit(const ElementSpawned(ElementId.saw));
      run.endRun();

      expect(events(meetSpy, 'first_meet'), [
        {
          'element': 'saw',
          'hoop': run.state.hoopIndex,
          'games': 1,
            'forced': true,
            'survived': true,
        },
      ]);
      expect(
        events(meetSpy, 'ftue_step')
            .where((event) => event['name'] == 'first_saw')
            .single['name'],
        'first_saw',
      );
    },
  );
}
