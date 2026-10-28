import 'dart:ui';

import 'package:flutter/painting.dart' show AssetImage, ImageConfiguration;
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import 'emblem_painter.dart';

final Map<int, Future<Image?>> _images = {};
Future<AssetManifest>? _manifest;

/// Loads and caches progression art for a level or slot for app lifetime.
Future<Image?> loadEmblemImage(int level) => _images.putIfAbsent(
  EmblemPainter.slotFor(level),
  () async {
    final path = EmblemPainter.assetFor(EmblemPainter.slotFor(level));
    if (path == null) return null;
    try {
      final manifest = await (_manifest ??= AssetManifest.loadFromAssetBundle(
        rootBundle,
      ));
      if (!manifest.listAssets().contains(path)) return null;
      final key = await AssetImage(path).obtainKey(
        ImageConfiguration(
          devicePixelRatio:
              PlatformDispatcher.instance.views.firstOrNull?.devicePixelRatio ??
              1,
        ),
      );
      final bytes = await key.bundle.load(key.name);
      final codec = await instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  },
);
