import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// PRD J6 / WP-J8: approved SVG exports, bird-free and plate-centred.
// J7's in-flight asset path differs; the J8 brief owns this folder only.
const _folder = 'assets/levels/emblems';
const _size = 320;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manifest =
      jsonDecode(File('$_folder/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  final emblems = (manifest['emblems'] as List).cast<Map<String, dynamic>>();

  test('32 approved slots, plate centre, density and layer manifest', () {
    expect(emblems, hasLength(32));
    expect(manifest['artSize'], _size);
    expect(manifest['plateCentre'], [160, 160]);
    expect(manifest['scales'], [1, 2, 3]);
    expect(manifest['birdIncluded'], isFalse);
    expect(manifest['source'], 'docs/p26/design/levels_v26/emblems.html');
    expect(emblems.first['name'], 'HATCHLING');
    expect(emblems.last['name'], 'ETERNAL WING');
    for (var i = 0; i < 32; i++) {
      final emblem = emblems[i];
      expect(emblem['id'], 'emblem_${(i + 1).toString().padLeft(2, '0')}');
      final layers = (emblem['layers'] as List).cast<Map<String, dynamic>>();
      // Every emblem has a separate plate sweep; higher tiers add idle art.
      expect(
        layers.length,
        greaterThanOrEqualTo(
          i >= 25
              ? 8
              : i >= 20
              ? 2
              : 1,
        ),
      );
      for (var j = 0; j < layers.length; j++) {
        final layer = layers[j];
        expect(
          layer['id'],
          '${emblem['id']}_layer_${(j + 1).toString().padLeft(2, '0')}',
        );
        expect(layer['insertionPath'], isNotEmpty);
        expect(layer['animations'], isNotEmpty);
        for (final animation in layer['animations'] as List) {
          expect(animation['dur'], isNotEmpty);
          expect(animation['repeatCount'], 'indefinite');
        }
      }
    }
  });

  test('every expected PNG exists and is bundled; no stray exports', () async {
    final expected = <String>{'manifest.json'};
    for (final emblem in emblems) {
      for (final part in [emblem, ...emblem['layers'] as List]) {
        for (final scale in [1, 2, 3]) {
          final name = '${part['id']}@${scale}x.png';
          expected.add(name);
          expect(File('$_folder/$name').existsSync(), isTrue, reason: name);
          expect(await rootBundle.load('$_folder/$name'), isNotNull);
        }
      }
    }
    expect(
      Directory(_folder).listSync().map((f) => f.uri.pathSegments.last).toSet(),
      expected,
    );
  });

  for (var slot = 0; slot < 32; slot++) {
    test(
      '${emblems[slot]['id']} dimensions and transparent padded canvas',
      () async {
        final emblem = emblems[slot];
        for (final part in [emblem, ...emblem['layers'] as List]) {
          for (final scale in [1, 2, 3]) {
            final name = '${part['id']}@${scale}x.png';
            final bytes = File('$_folder/$name').readAsBytesSync();
            // PNG signature and IHDR colour type 6 (RGBA, not flattened RGB).
            expect(bytes.take(8), [
              137,
              80,
              78,
              71,
              13,
              10,
              26,
              10,
            ], reason: name);
            expect(bytes[25], 6, reason: name);
            final codec = await ui.instantiateImageCodec(bytes);
            final image = (await codec.getNextFrame()).image;
            expect(image.width, _size * scale, reason: name);
            expect(image.height, _size * scale, reason: name);
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
            expect(ink, greaterThan(0), reason: '$name is blank');
            expect(edgeInk, 0, reason: '$name clips at the canvas edge');
            expect(ink, lessThan(image.width * image.height), reason: name);
            if (part == emblem) {
              // The plate covers the canvas origin; no baked player bird.
              final centre =
                  ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
              expect(
                pixels[centre + 3],
                255,
                reason: '$name plate is off centre',
              );
              expect(
                pixels.sublist(centre, centre + 3),
                isNot([236, 0, 140]),
                reason: '$name includes the mock bird',
              );
            }
            image.dispose();
            codec.dispose();
          }
        }
      },
    );
  }
}
