import 'package:share_plus/share_plus.dart';

export 'package:share_plus/share_plus.dart' show XFile;

/// The system share sheet behind a small interface (PRD-2.3 §2; iOS later:
/// share_plus supports both platforms). Tests swap in a recorder.
abstract class ShareSheet {
  /// Opens the share sheet with [text] and, when given, [files]. The link
  /// is inside the text (§2.0 step 3), never a separate `uri`.
  Future<void> share({required String text, List<XFile> files = const []});
}

/// share_plus implementation.
class SharePlusSheet implements ShareSheet {
  const SharePlusSheet();

  @override
  Future<void> share({
    required String text,
    List<XFile> files = const [],
  }) async {
    await SharePlus.instance.share(
      ShareParams(text: text, files: files.isEmpty ? null : files),
    );
  }
}
