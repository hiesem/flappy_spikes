import 'dart:io';
import 'dart:typed_data';

import 'package:flappy_spikes/game/sound.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.3 §16.5: the seamless 56-bar music loop.
void main() {
  const oggPath = 'assets/audio/HappyBeat_loop_56bars.ogg';

  int u32(Uint8List b, int i) =>
      b[i] | b[i + 1] << 8 | b[i + 2] << 16 | b[i + 3] << 24;

  int indexOf(Uint8List b, List<int> pat, {int from = 0, bool last = false}) {
    bool at(int i) {
      for (var k = 0; k < pat.length; k++) {
        if (b[i + k] != pat[k]) return false;
      }
      return true;
    }

    if (last) {
      for (var i = b.length - pat.length; i >= 0; i--) {
        if (at(i)) return i;
      }
      return -1;
    }
    for (var i = from; i <= b.length - pat.length; i++) {
      if (at(i)) return i;
    }
    return -1;
  }

  group('§16.5 the asset', () {
    final bytes = File(oggPath).readAsBytesSync();

    test('the last Ogg page: granule position = 4 059 616 samples '
        '(56 bars at 146 BPM, 44 100 Hz)', () {
      final i = indexOf(bytes, 'OggS'.codeUnits, last: true);
      expect(i, greaterThanOrEqualTo(0));
      var granule = 0;
      for (var k = 7; k >= 0; k--) {
        granule = granule * 256 + bytes[i + 6 + k];
      }
      expect(granule, 4059616);
      expect(granule, (56 * 240 / 146 * 44100).round());
      // The last page carries the end-of-stream flag.
      expect(bytes[i + 5] & 0x04, 0x04);
    });

    test('the Vorbis identification header says 44 100 Hz, 2 channels', () {
      final i = indexOf(bytes, [0x01, ...'vorbis'.codeUnits]);
      expect(i, greaterThanOrEqualTo(0));
      expect(u32(bytes, i + 7), 0, reason: 'vorbis_version');
      expect(bytes[i + 11], 2);
      expect(u32(bytes, i + 12), 44100);
    });

    test('the ANDROID_LOOP=true comment is present', () {
      var k = indexOf(bytes, [0x03, ...'vorbis'.codeUnits]) + 7;
      final vendor = u32(bytes, k);
      k += 4 + vendor;
      final count = u32(bytes, k);
      k += 4;
      final comments = <String>[];
      for (var c = 0; c < count; c++) {
        final n = u32(bytes, k);
        k += 4;
        comments.add(String.fromCharCodes(bytes.sublist(k, k + n)));
        k += n;
      }
      expect(
        comments.map((c) => c.toUpperCase()),
        contains('ANDROID_LOOP=TRUE'),
      );
    });
  });

  group('§16.3 the music file per platform', () {
    test('Android and Linux get the OGG, iOS gets the MP3', () {
      expect(
        SoundService.musicFileFor(isIOS: false),
        'HappyBeat_loop_56bars.ogg',
      );
      expect(
        SoundService.musicFileFor(isIOS: true),
        'HappyBeat_8-Bit_Retro_Game_Loop.mp3',
      );
      // Both files ship (the MP3 stays for iOS).
      for (final f in [
        SoundService.musicFileFor(isIOS: false),
        SoundService.musicFileFor(isIOS: true),
      ]) {
        expect(File('assets/audio/$f').existsSync(), isTrue, reason: f);
      }
    });
  });
}
