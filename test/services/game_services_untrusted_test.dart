import 'package:flappy_spikes/services/game_services.dart';
import 'package:flappy_spikes/services/integrity_guard.dart';
import 'package:flappy_spikes/services/leaderboard_limits.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts plugin submits without touching any plugin.
class _Services extends GameServices {
  final List<int> submitted = [];
  final List<String> events = [];

  @override
  Future<void> submitScorePlugin(int value) async => submitted.add(value);

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) =>
      events.add(name);
}

/// PRD-2.5 §3.3 / §3.7: the leaderboard submit is skipped silently for an
/// untrusted install and for values outside 0..kLeaderboardMaxScore.
void main() {
  _Services services(IntegrityGuard guard) => _Services()
    ..integrity = guard
    ..markInitialized();

  test('untrusted: no plugin submit, no event', () async {
    final guard = IntegrityGuard(enforce: true, platformOverride: 'android')
      ..markUntrusted('sig');
    final s = services(guard);
    await s.submitBestScore(42);
    expect(s.submitted, isEmpty);
    expect(s.events, isEmpty);
  });

  test('trusted: submitted as before', () async {
    final s = services(
      IntegrityGuard(enforce: true, platformOverride: 'android'),
    );
    await s.submitBestScore(42);
    expect(s.submitted, [42]);
  });

  test('non-release (not enforced) stays trusted after a mark', () async {
    final guard = IntegrityGuard(enforce: false)..markUntrusted('save');
    final s = services(guard);
    await s.submitBestScore(7);
    expect(s.submitted, [7]);
  });

  test('the cap: values above kLeaderboardMaxScore are never sent', () async {
    final s = services(
      IntegrityGuard(enforce: true, platformOverride: 'android'),
    );
    await s.submitBestScore(kLeaderboardMaxScore);
    await s.submitBestScore(kLeaderboardMaxScore + 1);
    await s.submitBestScore(2147483647);
    await s.submitBestScore(-1);
    expect(s.submitted, [kLeaderboardMaxScore]);
    expect(s.events, isEmpty);
  });

  test('a fresh start waits for the verdict before sending', () async {
    final guard = IntegrityGuard(enforce: true, platformOverride: 'android');
    final verdict = Future<void>.delayed(
      const Duration(milliseconds: 50),
      () => guard.markUntrusted('save'),
    );
    guard.track(verdict);
    final s = services(guard);
    await s.submitBestScore(42);
    expect(s.submitted, isEmpty);
  });
}
