import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flappy_spikes/game/config.dart';
import 'package:flappy_spikes/services/avatars.dart';
import 'package:flutter_test/flutter_test.dart';

/// PRD-2.2 §33.4 item 4 / §33.7 "Avatars": avatars are decoded at the size
/// they are drawn, and the cache keeps at most [Config.avatarCacheMax]
/// images (the least recently drawn one is disposed first).
class _MapSource implements AvatarSource {
  _MapSource(this.bytes);
  final Map<String, Uint8List> bytes;
  final List<String> fetched = [];

  @override
  Future<Uint8List?> fetch(String url) async {
    fetched.add(url);
    return bytes[url];
  }
}

Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366FF),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  return Uint8List.view(data.buffer);
}

Future<ui.Image?> _load(AvatarImages a, String key) async {
  for (var i = 0; i < 200; i++) {
    final got = a.lookup(key);
    if (got != null) return got;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('config: 52 pt (the VS plate) and 6 images', () {
    expect(Config.avatarDecodePoints, 52);
    expect(Config.avatarCacheMax, 6);
  });

  testWidgets('a big avatar is decoded at the drawn size (short side = '
      '52 pt x pixels per point), aspect kept; small ones stay as they are', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final src = _MapSource({
        'https://a/big.png': await _png(800, 600),
        'https://a/small.png': await _png(64, 64),
      });
      final avatars = AvatarImages(
        Images(prefix: ''),
        source: src,
        pixelsPerPoint: () => 3.375, // Pixel 8: 1080 px / 320 pt
      );
      expect(avatars.decodeSide, 176); // ceil(52 * 3.375)
      final big = await _load(avatars, 'https://a/big.png');
      expect(big, isNotNull);
      expect(big!.height, 176);
      expect(big.width, 235); // 800 * 176 / 600, rounded
      final small = await _load(avatars, 'https://a/small.png');
      expect(small!.width, 64);
      expect(small.height, 64);
    });
  });

  testWidgets('the cache holds at most avatarCacheMax images; the least '
      'recently drawn is evicted (and re-fetched when needed again)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final png = await _png(300, 300);
      final keys = [for (var i = 0; i < 10; i++) 'https://a/$i.png'];
      final src = _MapSource({for (final k in keys) k: png});
      final images = Images(prefix: '');
      final avatars = AvatarImages(
        images,
        source: src,
        pixelsPerPoint: () => 2,
      );
      // The own avatar is drawn between every opponent: it stays.
      final me = keys.first;
      expect(await _load(avatars, me), isNotNull);
      for (final k in keys.skip(1)) {
        expect(await _load(avatars, k), isNotNull);
        expect(avatars.lookup(me), isNotNull);
        expect(avatars.cachedKeys.length, lessThanOrEqualTo(6));
      }
      expect(avatars.cachedKeys.length, Config.avatarCacheMax);
      expect(avatars.cachedKeys, contains(me));
      expect(avatars.cachedKeys, contains(keys.last));
      expect(images.containsKey(keys[1]), isFalse, reason: 'evicted');
      // Evicted keys load again on the next draw (not marked failed).
      final before = src.fetched.length;
      expect(await _load(avatars, keys[1]), isNotNull);
      expect(src.fetched.length, before + 1);
      expect(avatars.cachedKeys.length, Config.avatarCacheMax);
    });
  });
}
