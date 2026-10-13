import 'dart:io';

import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/game/sfx_pool.dart';
import 'package:flappy_spikes/game/sound.dart';
import 'package:flappy_spikes/game/sound_durations.g.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_audio.dart';

/// PRD-2.2 §22: every one-shot sound plays its full designed length (from
/// the generated table), long sounds get 3 players, and a fully busy pool
/// steals its oldest copy instead of creating a player.
void main() {
  // PRD-2.3 §16.3: two music files (the OGG loop for Android / Linux, the
  // MP3 for iOS), both outside the one-shot table.
  const musicFiles = {
    'HappyBeat_8-Bit_Retro_Game_Loop.mp3',
    'HappyBeat_loop_56bars.ogg',
  };

  group('§22.4 the duration table is current', () {
    final files = Directory('assets/audio')
        .listSync()
        .whereType<File>()
        .where((f) => !musicFiles.contains(f.uri.pathSegments.last))
        .toList();

    test('every file in assets/audio is in kSoundDurations with its size', () {
      expect(files, isNotEmpty);
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        final entry = kSoundDurations[name];
        expect(
          entry,
          isNotNull,
          reason:
              '$name is missing: run python3 -I tool/gen_sound_durations.py',
        );
        expect(
          entry!.$2,
          f.lengthSync(),
          reason:
              '$name changed without regenerating: run '
              'python3 -I tool/gen_sound_durations.py',
        );
        expect(entry.$1, greaterThan(0), reason: name);
      }
      expect(kSoundDurations.length, files.length, reason: 'no stale rows');
      for (final music in musicFiles) {
        expect(kSoundDurations.containsKey(music), isFalse, reason: music);
      }
    });

    test('PRD-2.3 §16.3 the shipped music loop is 92.055 s (56 bars at '
        '146 BPM) and the music file is not in the table', () {
      final ogg = File('assets/audio/HappyBeat_loop_56bars.ogg');
      expect(ogg.existsSync(), isTrue);
      final bytes = ogg.readAsBytesSync();
      // The last Ogg page's granule position = the sample count.
      var i = bytes.length - 4;
      while (i >= 0 &&
          !(bytes[i] == 0x4F &&
              bytes[i + 1] == 0x67 &&
              bytes[i + 2] == 0x67 &&
              bytes[i + 3] == 0x53)) {
        i--;
      }
      var granule = 0;
      for (var k = 7; k >= 0; k--) {
        granule = granule * 256 + bytes[i + 6 + k];
      }
      expect(granule / 44100, closeTo(92.055, 0.0005));
      expect(
        SoundService.musicFileFor(isIOS: false),
        ogg.uri.pathSegments.last,
      );
    });

    test('every Sfx and SfxLoop file is in the table', () {
      for (final file in SoundService.audioFiles.values) {
        expect(kSoundDurations, contains(file));
      }
      for (final l in SfxLoop.values) {
        expect(kSoundDurations, contains(l.file));
      }
    });

    test('the owner-reported lengths (sound_board.html)', () {
      expect(kSoundDurations['perfect_3.mp3']!.$1, 2300);
      expect(kSoundDurations['perfect_1.mp3']!.$1, 900);
      expect(
        SoundService.lengthOf('perfect_3.mp3'),
        const Duration(milliseconds: 2300),
      );
      // More than half of the effects are longer than the old 0.6 s cut.
      final long = SoundService.audioFiles.values
          .where((f) => kSoundDurations[f]!.$1 > 600)
          .length;
      expect(long, greaterThan(90));
    });
  });

  group('§22.1 pool sizes', () {
    test('> 1 s gets 3 players, others 2, legacy 4, bursts 6', () {
      expect(SoundService.voicesFor(Sfx.perfect3), 3); // 2.3 s
      expect(SoundService.voicesFor(Sfx.perfect2), 3); // 1.4 s
      expect(SoundService.voicesFor(Sfx.perfect1), 2); // 0.9 s
      expect(SoundService.voicesFor(Sfx.lvUp), 3);
      expect(SoundService.voicesFor(Sfx.rimTonk), 2);
      for (final s in [Sfx.flap, Sfx.point, Sfx.gameover, Sfx.click]) {
        expect(SoundService.voicesFor(s), Config.sfxVoicesLegacy);
      }
      for (final s in [Sfx.bnCoin, Sfx.skTick, Sfx.piggyCoin]) {
        expect(SoundService.voicesFor(s), Config.sfxVoicesBurst);
      }
      for (final e in SoundService.audioFiles.entries) {
        final n = SoundService.voicesFor(e.key);
        expect(n, inInclusiveRange(2, 6), reason: '${e.key}');
        if (kSoundDurations[e.value]!.$1 > 1000) {
          expect(n, greaterThanOrEqualTo(3), reason: '${e.key}');
        }
      }
    });

    test('the prewarmed core run set has enough players for a streak', () {
      // perfect_3 every ≈ 1.5 s during a streak, 2.4 s busy → 2 at once.
      expect(SoundService.voicesFor(Sfx.perfect3), greaterThanOrEqualTo(2));
      // flap 92 ms + 100 ms busy; 10 taps/s → 2 at once.
      expect(SoundService.voicesFor(Sfx.flap), greaterThanOrEqualTo(2));
      expect(SoundService.prewarmed, contains(Sfx.perfect3));
    });
  });

  group('§22.4 stop timing (fake voices)', () {
    test('perfect_3 stops after 2300 + 100 ms, perfect_1 after 900 + 100 ms; '
        'nothing stops at 600 ms', () async {
      final audio = FakeAudio();
      final sound = audio.service();
      sound.play(Sfx.flap); // core warm-up (perfect_1 / _3 are prewarmed)
      await Future<void>.delayed(const Duration(milliseconds: 50));
      sound.play(Sfx.perfect3);
      sound.play(Sfx.perfect1);
      await flushAudio();
      final p3 = audio.of('perfect_3.mp3').singleWhere((v) => v.starts == 1);
      final p1 = audio.of('perfect_1.mp3').singleWhere((v) => v.starts == 1);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(p3.stops, 0, reason: 'no 0.6 s cut');
      expect(p1.stops, 0, reason: 'no 0.6 s cut');
      await Future<void>.delayed(const Duration(milliseconds: 1900));
      expect(p1.stops, 1);
      expect(p3.stops, 1);
      // Real timers: they never fire early; allow scheduler lateness under
      // a loaded parallel test run on the upper side.
      final d3 = p3.stoppedAt.single - p3.startedAt.single;
      final d1 = p1.stoppedAt.single - p1.startedAt.single;
      expect(d3, inInclusiveRange(2400 - 20, 2400 + 60));
      expect(d1, inInclusiveRange(1000 - 20, 1000 + 60));
      expect(
        sound.poolOf(Sfx.perfect3)!.length + const Duration(milliseconds: 100),
        const Duration(milliseconds: 2400),
      );
      await sound.dispose();
    });
  });

  group('§22.4 overlap', () {
    test('three perfect_3 plays 0.5 s apart all run to their end on 3 '
        'players; a 4th while all are busy steals the oldest', () async {
      final audio = FakeAudio();
      final sound = audio.service();
      sound.play(Sfx.flap); // core warm-up
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final pool = sound.poolOf(Sfx.perfect3)!;
      expect(pool.voiceCount, 3);
      final created = audio.created;
      for (var i = 0; i < 3; i++) {
        sound.play(Sfx.perfect3);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final voices = audio.of('perfect_3.mp3').toList();
      expect(voices.map((v) => v.starts), [1, 1, 1], reason: 'one each');
      await Future<void>.delayed(const Duration(milliseconds: 2000));
      for (final v in voices) {
        expect(v.stops, 1, reason: 'ran to its end, then stopped');
        final d = v.stoppedAt.single - v.startedAt.single;
        expect(d, greaterThanOrEqualTo(2380), reason: 'never cut');
      }
      // All three busy again, then a 4th.
      sound.play(Sfx.perfect3);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      sound.play(Sfx.perfect3);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      sound.play(Sfx.perfect3);
      await flushAudio();
      expect(pool.busyCount, 3);
      final oldest = voices.firstWhere((v) => v.starts == 2);
      sound.play(Sfx.perfect3);
      await flushAudio();
      expect(audio.created, created, reason: 'no new player mid-run');
      expect(pool.steals, 1);
      expect(oldest.starts, 3, reason: 'the oldest copy is reused');
      expect(oldest.stops, 2, reason: 'stopped before its restart');
      expect(pool.busyCount, 3);
      await sound.dispose();
    });
  });

  group('SfxPool ring', () {
    test('free voices first, then the oldest; never above capacity', () {
      final audio = FakeAudio();
      final pool = SfxPool(
        file: 'x.mp3',
        length: const Duration(seconds: 5),
        capacity: 2,
        stopMargin: const Duration(milliseconds: 100),
        nowMs: 0,
      );
      final a = FakeVoice('x.mp3', audio);
      final b = FakeVoice('x.mp3', audio);
      expect(pool.add(a), isTrue);
      expect(pool.add(b), isTrue);
      expect(pool.add(FakeVoice('x.mp3', audio)), isFalse, reason: 'cap');
      expect([pool.play(1), pool.play(2), pool.play(3), pool.play(4)], [
        0,
        1,
        0,
        1,
      ]);
      expect(pool.steals, 2);
      expect(pool.lastUsedMs, 4);
      return pool.dispose().then((_) {
        expect(a.disposed && b.disposed, isTrue);
        expect(pool.play(5), -1, reason: 'a disposed pool is silent');
      });
    });

    test('disabled service: no voice is ever created', () async {
      final audio = FakeAudio();
      final sound = audio.service(enabled: false);
      for (final s in Sfx.values) {
        sound.play(s);
      }
      sound.loop(SfxLoop.cometLoop).stop();
      await flushAudio();
      expect(audio.created, 0);
    });
  });
}
