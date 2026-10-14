import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/run_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.3.1 §8: a graze (or a clean off-centre pass) that breaks a running
/// streak resets it at once and shows no text. The "GRAZE · streak lost"
/// notice is gone; the analytics `streak_broken` (cause) stays.
void main() {
  late AnalyticsSpy spy;

  final tester = FlameTester<FlappySpikesGame>(() {
    spy = AnalyticsSpy();
    return createRunTestGame(worldHeight: 711, services: spy);
  }, gameSize: Vector2(320, 711));

  Future<void> prepare(FlappySpikesGame g) async {
    await g.ready();
    g.sound.enabled = false;
    await preloadImages(g);
  }

  /// Every text the run HUD shows now.
  List<String> hudText(FlappySpikesGame g) => g.runHud!
      .descendants()
      .whereType<TextComponent>()
      .map((t) => t.text)
      .toList();

  /// Builds a streak of [n] perfect passes, then one frame.
  Future<RunController> streakOf(FlappySpikesGame g, int n) async {
    final run = await startRun(g);
    for (var i = 0; i < n; i++) {
      run.debugPass(perfect: true);
    }
    g.update(1 / 60);
    await flushAndMount(g);
    expect(run.state.streak, n);
    return run;
  }

  tester.testGameWidget(
    'a graze with a streak running resets the streak and adds no text '
    'component to the HUD',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await streakOf(game, 3);
      final before = hudText(game);
      run.debugPass(perfect: false); // a graze
      game.update(1 / 60);
      await flushAndMount(game);
      expect(run.state.streak, 0);
      expect(run.state.tier, 0);
      expect(spy.events.where((e) => e.$1 == 'streak_broken').single.$2, {
        'length': 3,
        'cause': 'graze',
      });
      expect(hudText(game), before, reason: 'no new text on a graze');
      expect(hudText(game), isNot(contains('GRAZE · streak lost')));
      // Still no text a few frames later.
      for (var i = 0; i < 90; i++) {
        game.update(1 / 60);
      }
      await flushAndMount(game);
      expect(hudText(game), before);
    },
  );

  tester.testGameWidget(
    'a clean off-centre pass also resets a running streak with no text '
    '(PRD-2.2 §11.1, cause clean)',
    setUp: (g, _) => prepare(g),
    verify: (game, _) async {
      final run = await streakOf(game, 2);
      final before = hudText(game);
      run.debugPass(perfect: false, clean: true);
      game.update(1 / 60);
      await flushAndMount(game);
      expect(run.state.streak, 0);
      expect(spy.events.where((e) => e.$1 == 'streak_broken').single.$2, {
        'length': 2,
        'cause': 'clean',
      });
      expect(hudText(game), before);
    },
  );
}
