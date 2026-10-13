import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../services/share_sheet.dart';
import 'share_card.dart';

/// PRD-2.3 §2.0 steps 2-4: draw the card off-screen, encode it as PNG and
/// open the share sheet with the PNG and the text; if drawing or encoding
/// fails, share the text alone. Every collaborator is injectable.
class ShareFlow {
  ShareFlow({
    ShareSheet? sheet,
    Future<ShareCardAssets> Function()? assets,
    Future<Uint8List> Function(ShareCardData, ShareCardAssets)? render,
    Future<Directory> Function()? directory,
  }) : sheet = sheet ?? const SharePlusSheet(),
       _assets = assets ?? ShareCardAssets.load,
       _render = render ?? renderShareCardPng,
       _directory = directory ?? (() async => Directory.systemTemp);

  final ShareSheet sheet;
  final Future<ShareCardAssets> Function() _assets;
  final Future<Uint8List> Function(ShareCardData, ShareCardAssets) _render;
  final Future<Directory> Function() _directory;

  /// The PNG's file name in the temp directory (overwritten by every share).
  static const String fileName = 'flappy_spikes_card.png';

  /// Shares [data]; returns true when the image went along, false for the
  /// text-only fallback. Never throws (no share sheet: ignored).
  Future<bool> share(ShareCardData data) async {
    XFile? file;
    try {
      final png = await _render(data, await _assets());
      final dir = await _directory();
      final f = File('${dir.path}/$fileName');
      await f.writeAsBytes(png, flush: true);
      file = XFile(f.path, mimeType: 'image/png', name: fileName);
    } catch (e) {
      debugPrint('ShareFlow: card failed, sharing the text only: $e');
      file = null;
    }
    try {
      await sheet.share(text: data.text, files: [?file]);
      return file != null;
    } catch (e) {
      debugPrint('ShareFlow: share sheet failed: $e');
      if (file == null) return false;
      // The sheet refused the file: one more try with the text alone.
      try {
        await sheet.share(text: data.text);
      } catch (_) {}
      return false;
    }
  }
}
