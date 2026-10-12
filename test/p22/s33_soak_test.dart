
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flappy_spikes/game/audio_counter.dart';
import 'package:flappy_spikes/game/flappy_game.dart';
import 'package:flappy_spikes/services/soak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// PRD-2.2 §33.3 the FS_SOAK flag (profile soak run) and its guard, the
/// soak driver (death → revive declined → bonus → results / CLAIM → NEXT →
/// Home, game after game) and the live native audio player counter.
void main() {
  group('§33.3 FS_SOAK guard', () {
    test('release builds ignore the flag; debug / profile honour it', () {
      expect(soakEnabled(flag: true, release: true), isFalse);
      expect(soakEnabled(flag: true, release: false), isTrue);
      expect(soakEnabled(flag: false, release: false), isFalse);
      expect(soakEnabled(flag: false, release: true), isFalse);
      expect(kSoak, soakEnabled(flag: kSoakFlag, release: kReleaseMode));
    });

    test('the test build has no soak (no define)', () {
      expect(kSoakFlag, isFalse);
      expect(kSoak, isFalse);
      expect(kSoakNoBanner, isFalse, reason: 'S7-19 diagnosis flag');
      expect(kSoakGames, 20);
      expect(kSoakMeasured, {1, 2, 5, 10, 20});
    });

    test('forced games: a bonus and a level-up in every block of 5', () {
      final d = SoakDriver(_NoGame.instance, log: (_) {});
      expect(
        [
          for (var g = 1; g <= 20; g++)
            if (d.forcesBonus(g)) g,
        ],
        [3, 8, 13, 18],
      );
      expect(
        [
          for (var g = 1; g <= 20; g++)
            if (d.forcesLevelUp(g)) g,
        ],
        [4, 9, 14, 19],
      );
    });
  });

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    '§33.3 a normal build has no soak driver',
    verify: (g, _) async {
      expect(g.soak, isNull);
    },
  );

  FlameTester<FlappySpikesGame>(
    () => createRunTestGame(),
    gameSize: Vector2(320, 568),
  ).testGameWidget(
    '§33.3 the driver plays games in a row: revive declined, balloon bonus, '
    'level-up CLAIM, NEXT → Home, holds after measured games',
    setUp: (g, _) async {
      await preloadImages(g);
    },
    verify: (g, _) async {
      final lines = <String>[];
      final d = SoakDriver(
        g,
        games: 4,
        holdSeconds: 2,
        hoopsPerGame: 6,
        measured: {1},
        log: lines.add,
      );
      g.soak = d;
      for (var s = 0; s < 900 && d.phase != SoakPhase.done; s++) {
        await stepSeconds(g, 1);
      }
      expect(d.phase, SoakPhase.done, reason: lines.join('\n'));
      expect(d.finished, 4);
      expect(g.state, GameState.start);
      expect(g.storage.gamesPlayed, 4);
      String? line(String p) =>
          lines.where((l) => l.startsWith('$kSoakTag $p')).firstOrNull;
      expect(lines.where((l) => l.startsWith('$kSoakTag start ')).length, 4);
      expect(lines.where((l) => l.startsWith('$kSoakTag game-end')).length, 4);
      // ≥ 6 hoops: every death gets the revive offer, declined.
      expect(
        lines.where((l) => l.startsWith('$kSoakTag revive-declined')).length,
        4,
        reason: lines.join('\n'),
      );
      // Game 3 forced the balloon bonus, game 4 a level-up with CLAIM.
      expect(line('bonus-done game=3'), isNotNull, reason: lines.join('\n'));
      expect(line('claim game=4'), isNotNull, reason: lines.join('\n'));
      expect(g.storage.unclaimedLevelReward, 0);
      // Measured game 1 and the last game hold on Home.
      expect(line('hold game=1'), isNotNull);
      expect(line('hold game=4'), isNotNull);
      expect(line('done games=4'), isNotNull);
      expect(
        lines.every((l) => !l.contains('error')),
        isTrue,
        reason: lines.join('\n'),
      );
    },
  );

  group('§33.3 live native audio player counter', () {
    test(
      'counts create / dispose / release / position polls, delegates',
      () async {
        final fake = _FakePlatform();
        final c = CountingAudioPlatform(fake);
        await c.create('a');
        await c.create('b');
        await c.resume('a');
        await c.getCurrentPosition('a');
        await c.getCurrentPosition('a');
        await c.release('b');
        expect(c.live, 2, reason: 'release keeps the native player');
        await c.dispose('a');
        expect(c.live, 1);
        expect(c.creates, 2);
        expect(c.disposes, 1);
        expect(c.releases, 1);
        expect(c.positionPolls, 2);
        expect(c.starts, 1);
        expect(fake.calls, [
          'create a',
          'create b',
          'resume a',
          'pos a',
          'pos a',
          'release b',
          'dispose a',
        ]);
      },
    );

    test('not installed in normal builds; the service reports null', () {
      expect(CountingAudioPlatform.installed, isNull);
    });
  });
}

/// A game that is never touched (pure driver rules).
class _NoGame {
  static final FlappySpikesGame instance = FlappySpikesGame(
    soundEnabled: false,
  );
}

class _FakePlatform extends AudioplayersPlatformInterface {
  final List<String> calls = [];

  Future<void> _rec(String c) async => calls.add(c);

  @override
  Future<void> create(String playerId) => _rec('create $playerId');
  @override
  Future<void> dispose(String playerId) => _rec('dispose $playerId');
  @override
  Future<void> release(String playerId) => _rec('release $playerId');
  @override
  Future<void> resume(String playerId) => _rec('resume $playerId');
  @override
  Future<int?> getCurrentPosition(String playerId) async {
    calls.add('pos $playerId');
    return null;
  }

  @override
  Future<void> pause(String playerId) => _rec('pause');
  @override
  Future<void> stop(String playerId) => _rec('stop');
  @override
  Future<void> seek(String playerId, Duration position) => _rec('seek');
  @override
  Future<void> setBalance(String playerId, double balance) => _rec('bal');
  @override
  Future<void> setVolume(String playerId, double volume) => _rec('vol');
  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) =>
      _rec('rm');
  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) =>
      _rec('rate');
  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) => _rec('url');
  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) => _rec('bytes');
  @override
  Future<void> setAudioContext(String playerId, AudioContext audioContext) =>
      _rec('ctx');
  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) =>
      _rec('mode');
  @override
  Future<int?> getDuration(String playerId) async => null;
  @override
  Future<void> emitLog(String playerId, String message) => _rec('log');
  @override
  Future<void> emitError(String playerId, String code, String message) =>
      _rec('err');
  @override
  Stream<AudioEvent> getEventStream(String playerId) => const Stream.empty();
}
