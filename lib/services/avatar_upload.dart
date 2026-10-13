import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../run/config/versus_config.dart';

/// PRD-2.3 §21.3 the uploaded versus picture: the Play Games picture
/// ([src], any format `package:image` decodes), centre-cropped and resized
/// on the phone to [VersusConfig.avatarSide] (96 × 96) and encoded as JPEG
/// at the highest quality that stays within [VersusConfig.avatarMaxBytes]
/// (30 KB). Null when [src] cannot be decoded or no quality fits. Pure
/// Dart (Android and iOS alike); never throws.
Uint8List? encodeVersusAvatar(Uint8List src) {
  try {
    final decoded = img.decodeImage(src);
    if (decoded == null) return null;
    final square = img.copyResizeCropSquare(
      decoded,
      size: VersusConfig.avatarSide,
      interpolation: img.Interpolation.average,
    );
    for (final q in VersusConfig.avatarQualities) {
      final jpg = img.encodeJpg(square, quality: q);
      if (jpg.length <= VersusConfig.avatarMaxBytes) return jpg;
    }
    return null;
  } catch (_) {
    return null;
  }
}
