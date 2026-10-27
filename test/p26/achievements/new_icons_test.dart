// PRD-2.6 J9 / O96 / ART1: the ten recommended achievement icons are
// exported under their approved keys. Game Center ids are fs_ach_<key>.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  const keys = [
    'bullseye',
    'sky_high',
    'bird_of_prey',
    'birdwatcher',
    'second_wind',
    'albatross',
    'three_little_birds',
    'iron_beak',
    'flawless',
    'top_bird',
  ];

  for (final (directory, size, rgb) in [
    ('assets/images/achievements', 160, false),
    ('store/achievements/play', 512, false),
    ('store/achievements/ios', 1024, true),
  ]) {
    for (final key in keys) {
      final path = '$directory/ach_$key.png';
      test('$path is a valid $size px ${rgb ? 'RGB ' : ''}PNG', () async {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: path);
        final bytes = file.readAsBytesSync();
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final header = ByteData.sublistView(bytes);
        expect(header.getUint32(16), size, reason: '$path width');
        expect(header.getUint32(20), size, reason: '$path height');
        if (rgb) {
          expect(bytes[24], 8, reason: '$path has 8-bit channels');
          expect(bytes[25], 2, reason: '$path is RGB without alpha');
          // RGB PNGs can still declare transparency with a tRNS chunk.
          for (var offset = 8; offset < bytes.length;) {
            final length = header.getUint32(offset);
            final type = String.fromCharCodes(
              bytes.sublist(offset + 4, offset + 8),
            );
            expect(type, isNot('tRNS'), reason: '$path has no transparency');
            offset += length + 12;
          }
        }
        expect(bytes.length, lessThan(1024 * 1024), reason: '$path ≤ 1 MB');
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          final frame = await codec.getNextFrame();
          expect(frame.image.width, size);
          expect(frame.image.height, size);
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      });
    }
  }
}
