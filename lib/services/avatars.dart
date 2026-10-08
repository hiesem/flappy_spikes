import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/cache.dart';

/// Where avatar bytes come from (PRD-2 §3.13 "Who plays", §5.8 avatars).
/// Platform / network code stays behind this small interface (ARCH §8).
abstract class AvatarSource {
  /// The image bytes at [url], or null (offline, refused, too big).
  /// May throw; [AvatarImages] catches.
  Future<Uint8List?> fetch(String url);
}

/// Tests / desktop / no network: never fetches (the neutral glyph shows,
/// unless an image is already in the cache).
class NoAvatarSource implements AvatarSource {
  const NoAvatarSource();

  @override
  Future<Uint8List?> fetch(String url) async => null;
}

/// The device: an https GET with a timeout and a size cap.
class HttpAvatarSource implements AvatarSource {
  HttpAvatarSource({
    this.timeout = const Duration(seconds: 8),
    this.maxBytes = 512 * 1024,
  });

  final Duration timeout;
  final int maxBytes;

  @override
  Future<Uint8List?> fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final out = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        out.add(chunk);
        if (out.length > maxBytes) return null;
      }
      return out.takeBytes();
    } finally {
      client.close(force: true);
    }
  }
}

/// §3.13 / §5.8 "Avatars load from cache; a neutral avatar shows while an
/// image is missing" (S6-64). One shared cache for the VS intro plates, the
/// versus HUD bar and the results card: [lookup] returns the decoded image
/// when it is in the game's image cache (keyed by the avatar URL, or by a
/// `data:` URI for the Play Games icon image), else starts one background
/// load and returns null — the caller paints the neutral glyph meanwhile.
/// A failed key is not retried in the same session. Never throws.
class AvatarImages {
  AvatarImages(this.images, {this.source = const NoAvatarSource()});

  final Images images;
  final AvatarSource source;
  final Set<String> _loading = {};
  final Set<String> _failed = {};

  /// `data:` URI of a base64 image (the Play Games `iconImage`).
  static String dataUri(String base64) => 'data:image/png;base64,$base64';

  ui.Image? lookup(String key) {
    if (key.isEmpty) return null;
    try {
      if (images.containsKey(key)) return images.fromCache(key);
    } catch (_) {
      return null;
    }
    if (!_loading.contains(key) && !_failed.contains(key)) {
      _loading.add(key);
      unawaited(_load(key));
    }
    return null;
  }

  Future<void> _load(String key) async {
    try {
      final Uint8List? bytes;
      if (key.startsWith('data:')) {
        final comma = key.indexOf(',');
        bytes = comma < 0 ? null : base64Decode(key.substring(comma + 1));
      } else {
        bytes = await source.fetch(key);
      }
      if (bytes == null || bytes.isEmpty) {
        _failed.add(key);
        return;
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      images.add(key, frame.image);
    } catch (_) {
      _failed.add(key);
    } finally {
      _loading.remove(key);
    }
  }

  /// Paints [image] into [dst] (centre-cropped to a square, so it fills
  /// the avatar square like the neutral one).
  static void paint(
    ui.Canvas canvas,
    ui.Image image,
    ui.Rect dst, {
    double opacity = 1,
  }) {
    final w = image.width.toDouble(), h = image.height.toDouble();
    final side = w < h ? w : h;
    final src = ui.Rect.fromLTWH((w - side) / 2, (h - side) / 2, side, side);
    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.medium
      ..color = ui.Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));
    canvas.drawImageRect(image, src, dst, paint);
  }
}
