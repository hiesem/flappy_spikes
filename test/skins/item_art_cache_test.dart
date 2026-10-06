import 'dart:typed_data';
import 'dart:ui';

import 'package:flappy_spikes/components/skins/item_art.dart';
import 'package:flappy_spikes/skins/catalog.dart';
import 'package:flappy_spikes/skins/look.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP-C / fix S1-12: static locked tiles replay one cached picture with the
/// 42 % alpha already baked in, instead of compositing a per-frame layer.
Future<Uint8List> _rgba(Picture picture) async {
  final image = await picture.toImage(ItemArt.w.toInt(), ItemArt.h.toInt());
  final data = await image.toByteData(format: ImageByteFormat.rawStraightRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

int _maxAlpha(Uint8List rgba) {
  var max = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] > max) max = rgba[i];
  }
  return max;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lockedPictureFor caches the 42 % alpha in one picture per item', () async {
    final cache = ItemArtCache();
    addTearDown(cache.dispose);
    final item = itemById(SkinLayer.bird, 'sky')!;

    final plain = cache.pictureFor(item);
    final locked = cache.lockedPictureFor(item);
    expect(identical(cache.lockedPictureFor(item), locked), isTrue);
    expect(identical(locked, plain), isFalse);
    expect(cache.pictureCount, 1, reason: 'only the plain picture is counted');

    final plainAlpha = _maxAlpha(await _rgba(plain));
    final lockedAlpha = _maxAlpha(await _rgba(locked));
    expect(plainAlpha, greaterThan(0));
    expect(
      lockedAlpha,
      closeTo(plainAlpha * 0.42, 2),
      reason: 'the locked replay is the same art at skinShopLockedOpacity',
    );
  });
}
