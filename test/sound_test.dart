import 'dart:async';

import 'package:flappy_spikes/game/sound.dart';
import 'package:flutter_test/flutter_test.dart';

import 'p22/fake_audio.dart';

void main() {
  group('SoundService music', () {
    test('musicVolume defaults to 0.25', () {
      final sound = SoundService(enabled: false);
      expect(sound.musicVolume, 0.25);
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
        ..voiceFactory = (file) async {
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
    test('a pool is published with its first voice (no metadata wait)', () async {
      // PRD-2.2 §22: the length comes from the generated table, so a pool
      // never waits for (or dereferences) plugin metadata.
      final audio = FakeAudio();
      final sound = audio.service();
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        sound.play(Sfx.flap); // starts warm-up; this play is dropped
        await flushAudio();
        sound.play(Sfx.flap);
        await flushAudio();
        expect(audio.of('flap.mp3').fold<int>(0, (n, v) => n + v.starts), 1);
      }, (error, stack) => uncaught.add(error));
      expect(uncaught, isEmpty);
      await sound.dispose();
    });

    test('a failing voice start is contained, never uncaught', () async {
      // S2-12: audio must never take the game down.
      final audio = FakeAudio();
      final sound = audio.service();
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        sound.play(Sfx.flap); // warm-up
        await flushAudio();
        for (final v in audio.of('flap.mp3')) {
          v.startError = StateError('native SoundPool start failed');
        }
        sound.play(Sfx.flap);
        await flushAudio();
      }, (error, stack) => uncaught.add(error));
      expect(audio.of('flap.mp3').fold<int>(0, (n, v) => n + v.starts), 1);
      expect(uncaught, isEmpty);
      await sound.dispose();
    });

    test('a failing voice stop is contained, never uncaught', () async {
      // S2-12: the deferred stop Future must be contained too.
      final audio = FakeAudio();
      final sound = audio.service();
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        sound.play(Sfx.flap); // warm-up
        await flushAudio();
        for (final v in audio.of('flap.mp3')) {
          v.stopError = StateError('native SoundPool stop failed');
        }
        sound.play(Sfx.flap); // the stop timer is scheduled here
        await flushAudio();
        // flap.mp3 is 92 ms + the 100 ms margin.
        await Future<void>.delayed(const Duration(milliseconds: 260));
      }, (error, stack) => uncaught.add(error));
      final flap = audio.of('flap.mp3');
      expect(flap.fold<int>(0, (n, v) => n + v.starts), 1);
      expect(
        flap.fold<int>(0, (n, v) => n + v.stops),
        1,
        reason: 'the stop timer must still fire',
      );
      expect(uncaught, isEmpty);
      await sound.dispose();
    });
  });

  group('§7 lazy pools (WP-P1int)', () {
    test('start-up warms only the core run sounds, not every cue', () async {
      final audio = FakeAudio();
      final sound = audio.service();
      sound.play(Sfx.flap); // first sound of the session: core warm-up
      await flushAudio();
      expect(audio.voices.map((v) => v.file).toSet(), {
        for (final s in SoundService.prewarmed) SoundService.audioFiles[s],
      });
      expect(
        audio.created,
        SoundService.prewarmed.fold<int>(
          0,
          (n, s) => n + SoundService.voicesFor(s),
        ),
      );
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
      await sound.dispose();
    });

    test('a cue gets its pool on first play and that play is heard', () async {
      final audio = FakeAudio();
      final sound = audio.service();
      sound.play(Sfx.sawWireZap);
      await flushAudio();
      int zapStarts() =>
          audio.of('saw_wire_zap.mp3').fold<int>(0, (n, v) => n + v.starts);
      expect(zapStarts(), 1, reason: 'the first request plays once ready');
      final created = audio.created;
      sound.play(Sfx.sawWireZap);
      await flushAudio();
      expect(zapStarts(), 2);
      expect(audio.created, created, reason: 'one pool, no new voice');
      await sound.dispose();
    });

    test('a first play whose pool comes too late is dropped', () async {
      final audio = FakeAudio();
      final gate = audio.gates['egg_hatch.mp3'] = Completer<void>();
      final sound = audio.service();
      sound.play(Sfx.eggHatch);
      await flushAudio();
      await Future<void>.delayed(
        SoundService.firstPlayLateLimit + const Duration(milliseconds: 50),
      );
      gate.complete();
      await flushAudio();
      int hatchStarts() =>
          audio.of('egg_hatch.mp3').fold<int>(0, (n, v) => n + v.starts);
      expect(hatchStarts(), 0);
      sound.play(Sfx.eggHatch); // ready now
      await flushAudio();
      expect(hatchStarts(), 1);
      await sound.dispose();
    });

    test('muted / disabled never create a pool', () async {
      final audio = FakeAudio();
      final muted = audio.service(muted: true);
      final off = audio.service(enabled: false);
      muted.play(Sfx.trailNote1);
      off.play(Sfx.trailNote1);
      muted.preload([Sfx.trailNote2]);
      await flushAudio();
      expect(audio.created, 0);
    });
  });
}
