import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// PRD J6 "Idle animation (code, on top of the PNG)"; orchestrator J8 round 3:
// export only static bases. J7 owns all animation, so slices/rebuild expectations
// are replaced by removal counts and a source-colour check under the old sweep.
const _folder = 'assets/emblems';
const _size = 320;

String _path(String id, int scale) =>
    '$_folder/${scale == 1 ? '' : '$scale.0x/'}$id.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest =
      jsonDecode(File('$_folder/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  final emblems = (manifest['emblems'] as List).cast<Map<String, dynamic>>();

  test(
    '32 approved static bases, plate centre, density and animation removal',
    () {
      expect(emblems, hasLength(32));
      expect(manifest['artSize'], _size);
      expect(manifest['plateCentre'], [160, 160]);
      expect(manifest['drawBounds'], [-160, -160, 160, 160]);
      expect(manifest['scales'], [1, 2, 3]);
      expect(manifest['birdIncluded'], isFalse);
      expect(
        manifest['pose'],
        'static-only; all animated target subtrees removed',
      );
      expect(manifest.containsKey('compositeTolerance'), isFalse);
      expect(manifest['source'], 'docs/p26/design/levels_v26/emblems.html');
      expect(
        manifest['sourceSha256'],
        sha256
            .convert(File(manifest['source'] as String).readAsBytesSync())
            .toString(),
        reason: 'Regenerate the exports when the approved SVG source changes',
      );
      expect(emblems.first['name'], 'HATCHLING');
      expect(emblems.last['name'], 'ETERNAL WING');
      // Approved source's outermost SMIL paint targets, including every sweep,
      // ray group, glow, twinkle and flicker frame. These must be removed, not
      // merely frozen by deleting their animation tags (the round-2 defect).
      const hiddenCounts = [
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        2,
        2,
        4,
        2,
        2,
        9,
        9,
        9,
        20,
        10,
        14,
        17,
      ];
      for (var i = 0; i < 32; i++) {
        final emblem = emblems[i];
        expect(emblem['id'], 'emblem_${(i + 1).toString().padLeft(2, '0')}');
        expect(emblem['hiddenAnimatedGroups'], hiddenCounts[i]);
        expect(emblem.keys.toSet(), {'id', 'name', 'hiddenAnimatedGroups'});
      }
    },
  );

  test(
    'only 96 base PNGs are bundled with Flutter density resolution',
    () async {
      final expected = <String>{'$_folder/manifest.json'};
      for (final emblem in emblems) {
        for (final scale in [1, 2, 3]) {
          final path = _path(emblem['id'] as String, scale);
          expected.add(path);
          expect(File(path).existsSync(), isTrue, reason: path);
          expect(await rootBundle.load(path), isNotNull);
          final key = await AssetImage(
            _path(emblem['id'] as String, 1),
          ).obtainKey(ImageConfiguration(devicePixelRatio: scale.toDouble()));
          expect(key.name, path);
          expect(key.scale, scale.toDouble());
        }
      }
      expect(Directory('assets/levels/emblems').existsSync(), isFalse);
      expect(Directory('$_folder/layers').existsSync(), isFalse);
      expect(
        Directory(_folder)
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path)
            .toSet(),
        expected,
      );
    },
  );

  for (final emblem in emblems) {
    test(
      '${emblem['id']} static base dimensions, transparency and plate',
      () async {
        for (final scale in [1, 2, 3]) {
          final path = _path(emblem['id'] as String, scale);
          final bytes = File(path).readAsBytesSync();
          expect(bytes.take(8), [
            137,
            80,
            78,
            71,
            13,
            10,
            26,
            10,
          ], reason: path);
          // Lossless indexed PNG or RGBA; decoded pixels enforce transparency.
          expect(bytes[25], isIn([3, 6]), reason: path);
          final codec = await ui.instantiateImageCodec(bytes);
          final image = (await codec.getNextFrame()).image;
          expect(image.width, _size * scale, reason: path);
          expect(image.height, _size * scale, reason: path);
          final pixels = (await image.toByteData())!.buffer.asUint8List();
          var ink = 0;
          var edgeInk = 0;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              final alpha = pixels[(y * image.width + x) * 4 + 3];
              if (alpha != 0) ink++;
              if (x == 0 ||
                  y == 0 ||
                  x == image.width - 1 ||
                  y == image.height - 1) {
                edgeInk += alpha;
              }
            }
          }
          expect(ink, greaterThan(0), reason: '$path is blank');
          expect(edgeInk, 0, reason: '$path clips at the canvas edge');
          expect(ink, lessThan(image.width * image.height), reason: path);
          final centre =
              ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
          expect(pixels[centre + 3], 255, reason: '$path plate is off centre');
          expect(
            pixels.sublist(centre, centre + 3),
            isNot([236, 0, 140]),
            reason: '$path includes the mock bird',
          );
          if (emblem['id'] == 'emblem_01') {
            // PRD J6 static-only base: HATCHLING's source plate is #F6EBD2.
            // The neutral sweep crosses this central patch and lightens it.
            // Check every pixel at all densities, with zero colour tolerance;
            // this fails the round-2 PNGs, including emblem_01 @2x.
            for (var y = 158 * scale; y < 162 * scale; y++) {
              for (var x = 158 * scale; x < 162 * scale; x++) {
                final offset = (y * image.width + x) * 4;
                expect(pixels.sublist(offset, offset + 4), [
                  246,
                  235,
                  210,
                  255,
                ], reason: '$path has a frozen sweep at ($x, $y)');
              }
            }
          }
          // Empty source-art regions above the plate: the round-2 files have
          // visible ray/glow pixels here (alpha 82 / 117 at 1x).
          final clearProbe = switch (emblem['id']) {
            'emblem_21' => (160, 70),
            'emblem_26' => (160, 65),
            _ => null,
          };
          if (clearProbe != null) {
            final offset =
                (clearProbe.$2 * scale * image.width + clearProbe.$1 * scale) *
                4;
            expect(
              pixels[offset + 3],
              0,
              reason: '$path has baked rays or glow above the static plate',
            );
          }
          image.dispose();
          codec.dispose();
        }
      },
    );
  }
}
