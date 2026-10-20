import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/achievements/achievement_catalog.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/run/screens/results_screen.dart';
import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/integrity_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// An initialized services instance whose plugin seams only record.
class _Services extends GameServices {
  final List<int> submitted = [];

  @override
  Future<void> submitScorePlugin(int value) async => submitted.add(value);
  @override
  Future<void> unlockAchievementPlugin(AchievementId id) async {}
  @override
  Future<void> setAchievementProgressPlugin(
    AchievementId id,
    double percent,
  ) async {}
  @override
  Future<bool> isAuthenticatedPlugin() async => false;
  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {}
}

/// PRD-2.5 §3.3 (D1): a full run on an untrusted install plays and ends
/// exactly like a trusted one; only the leaderboard submit is missing.
void main() {
  final outcomes = <bool, String>{};
  final submits = <bool, List<int>>{};

  for (final untrusted in [false, true]) {
    final services = _Services()..markInitialized();
    FlameTester<FlappySpikesGame>(
      () => createRunTestGame(seed: 21, services: services),
      gameSize: Vector2(320, 568),
    ).testGameWidget(
      untrusted ? 'untrusted run' : 'trusted run',
      setUp: (g, _) async {
        final guard = IntegrityGuard(
          enforce: true,
          platformOverride: 'android',
        );
        if (untrusted) guard.markUntrusted('sig');
        services.integrity = guard;
        IntegrityGuard.instance = guard;
        await g.ready();
        await preloadImages(g);
      },
      verify: (g, tester) async {
        try {
          await startRun(g);
          await flyRun(g, untilHoops: 6, maxSeconds: 30);
          killRunThroughSaves(g);
          await declineRevive(g);
          await flushAndMount(g);
          await tester.pump();
          expect(g.state, GameState.results);
          expect(g.score, greaterThan(0));
          final results = g.world.children.whereType<ResultsScreen>().length;
          outcomes[untrusted] = [
            g.state,
            g.score,
            g.storage.bestScore,
            g.storage.coins,
            g.storage.gamesPlayed,
            g.storage.playerLevel,
            results,
          ].join('|');
          submits[untrusted] = List.of(services.submitted);
        } finally {
          IntegrityGuard.instance = IntegrityGuard();
        }
      },
    );
  }

  test('both runs ended the same; only the untrusted one never submitted', () {
    expect(outcomes.keys, containsAll([false, true]));
    expect(outcomes[true], outcomes[false]);
    expect(submits[false], isNotEmpty);
    expect(submits[true], isEmpty);
  });
}
