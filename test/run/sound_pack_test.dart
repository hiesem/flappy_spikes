import 'dart:io';
import 'dart:typed_data';

import 'package:flappy_spikes/game/sound.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP-3h (PRD-2 §7 "Sound deliverables still to make"): every generated sound
/// is registered, exists, loads through the pool path and loops seamlessly.
void main() {
  // §5.8-§5.31 + §3.0.4: the delivery list of PRD-2 §7, name by name, so a
  // later WP can reference any of them (ARCH-style names).
  const expected = <String, List<Sfx>>{
    '§5.8 versus intro': [
      Sfx.vsWhoosh,
      Sfx.vsTick,
      Sfx.vsChime,
      Sfx.vsRocket,
      Sfx.vsPop,
      Sfx.vsThud,
      Sfx.vsBoing,
    ],
    '§5.17 saw-ring deaths': [
      Sfx.sawWireZap,
      Sfx.sawWireThunder,
      Sfx.sawWireCrackle,
      Sfx.sawFrostCrunch,
      Sfx.sawFrostHiss,
      Sfx.sawFrostCrack,
      Sfx.sawFrostTink,
      Sfx.sawFrostShatter,
      Sfx.sawHoleInhale,
      Sfx.sawHoleRoar,
      Sfx.sawHoleBoom,
      Sfx.sawHoleSubdrop,
    ],
    '§5.18 FEVER': [Sfx.feverPass, Sfx.feverOut],
    '§5.19 switch rings': [
      Sfx.swLockTouch,
      Sfx.swLockOpen,
      Sfx.swLockCrash,
      Sfx.swLaserTouch,
      Sfx.swLaserOpen,
      Sfx.swLaserCrash,
      Sfx.swIrisTouch,
      Sfx.swIrisOpen,
      Sfx.swIrisCrash,
      Sfx.swSnoozeTouch,
      Sfx.swSnoozeOpen,
      Sfx.swSnoozeCrash,
      Sfx.swGiftTouch,
      Sfx.swGiftOpen,
      Sfx.swGiftCrash,
      Sfx.swClear,
    ],
    '§5.20 pair gifts': [
      Sfx.pairBoxOpen,
      Sfx.pairShield,
      Sfx.pairComet,
      Sfx.pairCoins,
      Sfx.pairScore,
      Sfx.pairFever,
      Sfx.pairSkipped,
    ],
    '§5.21 Ring Train': [
      Sfx.trainNote1,
      Sfx.trainNote2,
      Sfx.trainNote3,
      Sfx.trainFinish,
    ],
    '§5.22 Spring Ring': [Sfx.springUp, Sfx.springDown],
    '§5.23 Bullseye Ring': [Sfx.bullThunk, Sfx.bullChord],
    '§5.24 Lucky Spin': [Sfx.luckyTick, Sfx.luckyWhoosh, Sfx.luckyWin],
    '§5.25 Star Trail': [
      Sfx.trailNote1,
      Sfx.trailNote2,
      Sfx.trailNote3,
      Sfx.trailNote4,
      Sfx.trailNote5,
      Sfx.trailNote6,
      Sfx.trailNote7,
      Sfx.trailNote8,
      Sfx.trailPop,
      Sfx.trailChord,
    ],
    '§5.26 Egg': [
      Sfx.eggPickup,
      Sfx.eggCrack,
      Sfx.eggHatch,
      Sfx.eggPeep,
      Sfx.eggBye,
    ],
    '§5.27 Piggy Bank': [
      Sfx.piggyOink,
      Sfx.piggyCoin,
      Sfx.piggyMiss,
      Sfx.piggySmash,
    ],
    '§5.28 Firefly Jar': [
      Sfx.jarPickup,
      Sfx.jarTwinkle,
      Sfx.jarEscape,
      Sfx.jarBreak,
      Sfx.jarFull,
    ],
    '§3.0.4 rim tonk': [Sfx.rimTonk],
    '§5.29 Hourglass': [
      Sfx.hourglassStart,
      Sfx.hourglassTick,
      Sfx.hourglassEnd,
    ],
    '§5.30 Mini Bird': [Sfx.miniStart, Sfx.miniEnd],
    '§5.31 Coin Frenzy': [Sfx.frenzyStart, Sfx.frenzyRing, Sfx.frenzyEnd],
  };

  const loops = <String, SfxLoop>{
    '§5.17 Live Wire hum': SfxLoop.sawWireHum,
    '§5.17 Frost Ring hum': SfxLoop.sawFrostHum,
    '§5.17 Black Hole hum': SfxLoop.sawHoleHum,
    '§5.18 FEVER burning crackle': SfxLoop.feverLoop,
  };

  final newSfx = {for (final l in expected.values) ...l};

  group('§7 sound pack (WP-3h): registered names', () {
    test('§7 every PRD-2 §7 deliverable is a registered Sfx', () {
      for (final entry in expected.entries) {
        expect(entry.value, isNotEmpty, reason: entry.key);
        for (final sfx in entry.value) {
          expect(Sfx.values, contains(sfx), reason: '${entry.key}: $sfx');
        }
      }
      // 88 one-shot cues + the 4 loop cues (30 shipped by WP-0b are untouched).
      expect(newSfx, hasLength(88));
      expect(loops.values, hasLength(4));
    });

    test('§7 the 4 new loops are SfxLoop entries with a .wav file', () {
      for (final entry in loops.entries) {
        expect(SfxLoop.values, contains(entry.value), reason: entry.key);
        expect(entry.value.file, endsWith('.wav'), reason: entry.key);
      }
    });

    test('§7 pools have no duplicate names (Sfx + SfxLoop)', () {
      final names = <String>[
        ...SoundService.audioFiles.values,
        ...SfxLoop.values.map((l) => l.file),
      ];
      expect(names.toSet().length, names.length, reason: 'duplicate pool name');
    });
  });

  group('§7 sound pack (WP-3h): assets exist and load', () {
    Uint8List head(File f, int n) {
      final raf = f.openSync();
      final bytes = raf.readSync(n);
      raf.closeSync();
      return bytes;
    }

    test('§7 every cue maps to one existing, non-empty mp3', () {
      for (final sfx in newSfx) {
        final file = SoundService.audioFiles[sfx]!;
        expect(file, endsWith('.mp3'), reason: '$sfx');
        final f = File('assets/audio/$file');
        expect(f.existsSync(), isTrue, reason: '$sfx -> $file');
        expect(f.lengthSync(), greaterThan(2000), reason: '$sfx -> $file');
        final b = head(f, 3);
        final id3 = String.fromCharCodes(b) == 'ID3';
        final sync = b[0] == 0xFF && (b[1] & 0xE0) == 0xE0;
        expect(id3 || sync, isTrue, reason: '$sfx is not an mp3 ($file)');
      }
    });

    test('§7 every loop is a real 44.1 kHz wav of at least 2.5 s', () {
      for (final entry in loops.entries) {
        final file = 'assets/audio/${entry.value.file}';
        final f = File(file);
        expect(f.existsSync(), isTrue, reason: entry.key);
        final bytes = head(f, 44);
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
        final data = ByteData.sublistView(bytes);
        final sampleRate = data.getUint32(24, Endian.little);
        expect(sampleRate, 44100, reason: entry.key);
        final duration = f.lengthSync() / (44100 * 2 * 2);
        expect(duration, greaterThan(2.5), reason: entry.key);
      }
    });

    test(
      '§7 every cue is handed to the pool path (loads through AudioPool)',
      () async {
        final requested = <String>[];
        final sound = SoundService()
          ..poolFactory = (file, legacy) async {
            requested.add(file);
            return null; // never ready: stays silent, no plugin call
          };
        // Pools are created on first play (WP-P1int): play every cue once.
        for (final sfx in newSfx) {
          sound.play(sfx);
        }
        await pumpEventQueue();
        for (final sfx in newSfx) {
          expect(
            requested,
            contains(SoundService.audioFiles[sfx]),
            reason: '$sfx was never sent to the pool factory',
          );
        }
        // The loops never go through the [AudioPool] factory: they are owned by
        // the [_LoopPlayer] seam (asserted by the loop test below). Every one-shot
        // cue above must, though, so nothing bypasses AudioPool.
      },
    );

    test('§7 the new cues play through onPlay (wired, not dead code)', () {
      final sound = SoundService(enabled: false);
      final played = <Sfx>[];
      sound.onPlay = played.add;
      for (final sfx in newSfx) {
        sound.play(sfx);
      }
      expect(played.toSet(), newSfx);
    });

    test('§7 the 4 new loops start, keep volume and stop', () async {
      final sound = SoundService(enabled: false);
      final seen = <(SfxLoop, double)>[];
      sound.onLoop = (l, v) => seen.add((l, v));
      final handles = <LoopHandle>[];
      for (final l in loops.values) {
        handles.add(sound.loop(l, volume: 0.6));
      }
      expect(seen, [for (final l in loops.values) (l, 0.6)]);
      expect(sound.activeLoops, hasLength(4));
      await handles.first.setVolume(0.2);
      await sound.stopAllLoops();
      expect(sound.activeLoops, isEmpty);
      for (final h in handles) {
        expect(h.stopped, isTrue);
      }
    });
  });
}
