import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// PRD J6; orchestrator J8 round 2: J7 loader paths, density folders and ordered
// static/animated slice stacks. 320 units preserves the approved ALBATROSS wings.
const _folder = 'assets/emblems';
const _size = 320;

String _path(String id, int scale, {bool layer = false}) =>
    '$_folder/${layer ? 'layers/' : ''}${scale == 1 ? '' : '$scale.0x/'}$id.png';

Future<ui.Image> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest =
      jsonDecode(File('$_folder/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  final emblems = (manifest['emblems'] as List).cast<Map<String, dynamic>>();

  test('32 approved slots, plate centre, density and ordered slice manifest', () {
    expect(emblems, hasLength(32));
    expect(manifest['artSize'], _size);
    expect(manifest['plateCentre'], [160, 160]);
    expect(manifest['scales'], [1, 2, 3]);
    expect(manifest['birdIncluded'], isFalse);
    expect(manifest['source'], 'docs/p26/design/levels_v26/emblems.html');
    expect(
      manifest['sourceSha256'],
      sha256
          .convert(File(manifest['source'] as String).readAsBytesSync())
          .toString(),
      reason: 'Regenerate the exports when the approved SVG source changes',
    );
    expect(manifest['compositeTolerance'], 4);
    expect(emblems.first['name'], 'HATCHLING');
    expect(emblems.last['name'], 'ETERNAL WING');
    for (var i = 0; i < 32; i++) {
      final emblem = emblems[i];
      expect(emblem['id'], 'emblem_${(i + 1).toString().padLeft(2, '0')}');
      final slices = (emblem['slices'] as List).cast<Map<String, dynamic>>();
      final animated = slices.where((s) => s['kind'] == 'animated');
      // Preserve the original animation-count assertion; static slices are new.
      expect(
        animated.length,
        greaterThanOrEqualTo(
          i >= 25
              ? 8
              : i >= 20
              ? 2
              : 1,
        ),
      );
      expect(slices.any((s) => s['kind'] == 'static'), isTrue);
      for (var j = 0; j < slices.length; j++) {
        final slice = slices[j];
        expect(
          slice['id'],
          '${emblem['id']}_s${(j + 1).toString().padLeft(2, '0')}',
        );
        expect(slice['kind'], isIn(['static', 'animated']));
        expect(
          slice['animations'],
          slice['kind'] == 'animated' ? isNotEmpty : isEmpty,
        );
        for (final animation in slice['animations'] as List) {
          expect(animation['dur'], isNotEmpty);
          expect(animation['repeatCount'], 'indefinite');
        }
      }
    }
  });

  test(
    'every expected PNG is bundled with Flutter density resolution; no stray exports',
    () async {
      final expected = <String>{'$_folder/manifest.json'};
      for (final emblem in emblems) {
        for (final part in [emblem, ...emblem['slices'] as List]) {
          final layer = part != emblem;
          for (final scale in [1, 2, 3]) {
            final path = _path(part['id'] as String, scale, layer: layer);
            expected.add(path);
            expect(File(path).existsSync(), isTrue, reason: path);
            expect(await rootBundle.load(path), isNotNull);
            final key = await AssetImage(
              _path(part['id'] as String, 1, layer: layer),
            ).obtainKey(ImageConfiguration(devicePixelRatio: scale.toDouble()));
            expect(key.name, path);
            expect(key.scale, scale.toDouble());
          }
        }
      }
      expect(Directory('assets/levels/emblems').existsSync(), isFalse);
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
      '${emblem['id']} dimensions, transparency and reconstruction from ordered slices',
      () async {
        for (final scale in [1, 2, 3]) {
          final full = await _decode(_path(emblem['id'] as String, scale));
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          for (final part in [emblem, ...emblem['slices'] as List]) {
            final layer = part != emblem;
            final path = _path(part['id'] as String, scale, layer: layer);
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
            // Round 2 lossless palette optimisation permits indexed RGBA too;
            // decoded pixels below still enforce actual transparency and coverage.
            expect(bytes[25], isIn([3, 6]), reason: path);
            final image = layer ? await _decode(path) : full;
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
            if (layer) {
              canvas.drawImage(image, ui.Offset.zero, ui.Paint());
              image.dispose();
            } else {
              final centre =
                  ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
              expect(
                pixels[centre + 3],
                255,
                reason: '$path plate is off centre',
              );
              expect(
                pixels.sublist(centre, centre + 3),
                isNot([236, 0, 140]),
                reason: '$path includes the mock bird',
              );
            }
          }
          final picture = recorder.endRecording();
          final rebuilt = await picture.toImage(full.width, full.height);
          final actual = (await rebuilt.toByteData())!.buffer.asUint8List();
          final reference = (await full.toByteData())!.buffer.asUint8List();
          var maxError = 0;
          for (var i = 0; i < reference.length; i++) {
            final error = (actual[i] - reference[i]).abs();
            if (error > maxError) maxError = error;
          }
          // Compare every premultiplied RGBA channel. Allow at most 4/255 for
          // separate antialias coverage/compositing round-off, never a pixel budget
          // or a mean that could hide a missing/incorrectly stacked ornament.
          expect(
            maxError,
            lessThanOrEqualTo(4),
            reason:
                '${emblem['id']} ${scale}x slice stack differs from independent full SVG render',
          );
          picture.dispose();
          rebuilt.dispose();
          full.dispose();
        }
      },
    );
  }
}
