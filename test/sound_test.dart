import 'dart:async';

import 'package:flame_audio/flame_audio.dart' show AudioPool;
import 'package:flappy_spikes/game/sound.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plugin-free pool seam: the duration query and the start/stop results can be
/// delayed or failed independently, like the real asynchronous pool.
class _FakePool implements AudioPool {
  _FakePool({Duration? duration}) {
    if (duration != null) durationReady.complete(duration);
  }

  final durationReady = Completer<Duration?>();
  Object? startError;
  Object? stopError;
  int starts = 0;
  int stops = 0;

  @override
  Future<Duration?> getDuration() => durationReady.future;

  @override
  Future<Future<void> Function()> start({double volume = 1}) async {
    starts++;
    final error = startError;
    if (error != null) throw error;
    return () async {
      stops++;
      final stopError = this.stopError;
      if (stopError != null) throw stopError;
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Lets the warm-up's awaited futures run to their next suspension point.
Future<void> _flush() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.value();
  }
}

/// A service whose pools are all fakes: [flap] is the pool under test, every
/// other file gets a ready fake so no real AudioPool is ever created.
SoundService _fakeSound(_FakePool flap) => SoundService()
  ..poolFactory = (file, legacy) async => file == 'flap.mp3'
      ? flap
      : _FakePool(duration: const Duration(milliseconds: 1));

void main() {
  group('SoundService music', () {
    test('musicVolume defaults to 0.6', () {
      final sound = SoundService(enabled: false);
      expect(sound.musicVolume, 0.6);
    });

    test('setMusicVolume clamps to 0..1', () async {
      final sound = SoundService(enabled: false);
      await sound.setMusicVolume(-0.5);
      expect(sound.musicVolume, 0.0);
      await sound.setMusicVolume(1.7);
      expect(sound.musicVolume, 1.0);
      await sound.setMusicVolume(0.4);
      expect(sound.musicVolume, 0.4);
    });

    test('startMusic/setMusicVolume are safe no-ops when disabled', () async {
      final sound = SoundService(enabled: false);
      // No audioplayers platform channel exists in headless tests; with
      // enabled=false none of these may reach it or throw.
      await sound.startMusic();
      await sound.startMusic();
      await sound.setMusicVolume(0.8);
      expect(sound.musicVolume, 0.8);
    });

    test('SFX muted does not change musicVolume', () async {
      final sound = SoundService(muted: true, enabled: false);
      await sound.setMusicVolume(0.3);
      sound.play(Sfx.flap); // muted: swallowed, must not throw
      expect(sound.musicVolume, 0.3);
    });

    test('an SFX with no ready pool is dropped, never one-shotted', () async {
      // Enabled but no pool ready (warmup still running / failed): play must
      // drop the sound instead of opening a one-shot player (CLAUDE.md:
      // preloaded low-latency pools only, no bare FlameAudio.play).
      var built = 0;
      final sound = SoundService()
        ..poolFactory = (file, legacy) async {
          built++;
          return null; // models a pool that never became ready
        };
      final played = <Sfx>[];
      sound.onPlay = played.add;

      sound.play(Sfx.skTap); // warms the core pools + skTap's; dropped
      await Future<void>.delayed(Duration.zero);
      // WP-P1int: only the core run sounds warm up, plus the requested one.
      expect(built, SoundService.prewarmed.length + 1);

      sound.play(Sfx.skTap); // still no pool: dropped, no new warmup
      expect(built, SoundService.prewarmed.length + 1);
      expect(played, [Sfx.skTap, Sfx.skTap]);
    });
  });

  group('SoundService low-latency pools', () {
    test('a pool without its stop duration is not published yet', () async {
      // S2-11: warm-up must publish the pool and its duration TOGETHER, so a
      // play during that window is dropped instead of dereferencing a missing
      // duration (which would throw out of an unawaited future).
      final pool = _FakePool();
      final sound = _fakeSound(pool);
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        sound.play(Sfx.flap); // starts warm-up; this play is dropped
        await _flush(); // pool created, its duration still pending
        sound.play(Sfx.flap);
        await _flush();
        expect(pool.starts, 0, reason: 'not ready: no duration, no playback');
        pool.durationReady.complete(const Duration(milliseconds: 1));
        await _flush();
        sound.play(Sfx.flap); // the pair is published now
        await _flush();
        expect(pool.starts, 1);
      }, (error, stack) => uncaught.add(error));
      expect(uncaught, isEmpty);
    });

    test('a failing pool start is contained, never uncaught', () async {
      // S2-12: audio must never take the game down.
      final pool = _FakePool(duration: const Duration(milliseconds: 1))
        ..startError = StateError('native SoundPool start failed');
      final sound = _fakeSound(pool);
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        sound.play(Sfx.flap); // warm-up, then a rejected start
        await _flush();
        sound.play(Sfx.flap);
        await _flush();
      }, (error, stack) => uncaught.add(error));
      expect(
        pool.starts,
        1,
        reason: 'the failure must exercise the ready pool',
      );
      expect(uncaught, isEmpty);
    });

    test('a failing pool stop is contained, never uncaught', () async {
      // S2-12: the deferred player-return stop Future must be contained too.
      final pool = _FakePool(duration: const Duration(milliseconds: 1))
        ..stopError = StateError('native SoundPool stop failed');
      final sound = _fakeSound(pool);
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        sound.play(Sfx.flap); // warm-up
        await _flush();
        sound.play(Sfx.flap); // the stop timer is scheduled here
        await _flush();
        await Future<void>.delayed(const Duration(milliseconds: 130));
      }, (error, stack) => uncaught.add(error));
      expect(pool.starts, 1);
      expect(pool.stops, 1, reason: 'the stop timer must still fire');
      expect(uncaught, isEmpty);
    });
  });

  group('§7 lazy pools (WP-P1int)', () {
    test('start-up warms only the core run sounds, not every cue', () async {
      final built = <String>[];
      final sound = SoundService()
        ..poolFactory = (file, legacy) async {
          built.add(file);
          return _FakePool(duration: const Duration(milliseconds: 1));
        };
      sound.play(Sfx.flap); // first sound of the session: core warm-up
      await _flush();
      expect(built.toSet(), {
        for (final s in SoundService.prewarmed) SoundService.audioFiles[s],
      });
      expect(built, hasLength(SoundService.prewarmed.length));
      expect(
        SoundService.prewarmed,
        containsAll(<Sfx>[
          Sfx.flap,
          Sfx.point,
          Sfx.rimTonk,
          Sfx.perfect1,
          Sfx.perfect2,
          Sfx.perfect3,
        ]),
      );
      expect(sound.poolRequested(Sfx.sawWireZap), isFalse);
      expect(
        SoundService.prewarmed.length,
        lessThan(SoundService.audioFiles.length ~/ 10),
      );
    });

    test('a cue gets its pool on first play and that play is heard', () async {
      final pools = <String, _FakePool>{};
      var built = 0;
      final sound = SoundService()
        ..poolFactory = (file, legacy) async {
          built++;
          return pools[file] = _FakePool(
            duration: const Duration(milliseconds: 1),
          );
        };
      sound.play(Sfx.sawWireZap);
      await _flush();
      final zap = pools['saw_wire_zap.mp3']!;
      expect(zap.starts, 1, reason: 'the first request plays once ready');
      expect(built, SoundService.prewarmed.length + 1);
      sound.play(Sfx.sawWireZap);
      await _flush();
      expect(zap.starts, 2);
      expect(built, SoundService.prewarmed.length + 1, reason: 'one pool');
      await Future<void>.delayed(const Duration(milliseconds: 130));
    });

    test('a first play whose pool comes too late is dropped', () async {
      final slow = _FakePool();
      final sound = SoundService()
        ..poolFactory = (file, legacy) async => file == 'egg_hatch.mp3'
            ? slow
            : _FakePool(duration: const Duration(milliseconds: 1));
      sound.play(Sfx.eggHatch);
      await _flush();
      await Future<void>.delayed(
        SoundService.firstPlayLateLimit + const Duration(milliseconds: 50),
      );
      slow.durationReady.complete(const Duration(milliseconds: 1));
      await _flush();
      expect(slow.starts, 0);
      sound.play(Sfx.eggHatch); // ready now
      await _flush();
      expect(slow.starts, 1);
      await Future<void>.delayed(const Duration(milliseconds: 130));
    });

    test('muted / disabled never create a pool', () async {
      var built = 0;
      final muted = SoundService(muted: true)
        ..poolFactory = (file, legacy) async {
          built++;
          return null;
        };
      final off = SoundService(enabled: false)..poolFactory = muted.poolFactory;
      muted.play(Sfx.trailNote1);
      off.play(Sfx.trailNote1);
      await _flush();
      expect(built, 0);
    });
  });
}
