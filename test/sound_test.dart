import 'package:flappy_spikes/game/sound.dart';
import 'package:flutter_test/flutter_test.dart';

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

      sound.play(Sfx.skTap); // warms the pools; this play is dropped
      await Future<void>.delayed(Duration.zero);
      expect(built, SoundService.audioFiles.length);

      sound.play(Sfx.skTap); // still no pool: dropped, no new warmup
      expect(built, SoundService.audioFiles.length);
      expect(played, [Sfx.skTap, Sfx.skTap]);
    });
  });
}
