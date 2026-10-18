/// WP-NAME the player's own versus name, chosen in Settings (design A of
/// `design/username_settings/username.html`). The app checks the format;
/// the server (`functions/src/customname.ts`, `setVersusName`) checks the
/// same format plus a word filter and is the one that accepts a name.
library;

/// Shortest and longest custom name.
const int kCustomNameMin = 3;
const int kCustomNameMax = 14;

/// Shown for the player's own name when they have not chosen one.
const String kDefaultOwnName = 'You';

final RegExp _shape = RegExp(r'^[A-Za-z0-9]*$');

/// Why a custom name is refused (the server's reason keys).
enum CustomNameReason {
  length('length'),
  chars('chars'),
  blocked('blocked');

  const CustomNameReason(this.key);
  final String key;

  static CustomNameReason? fromKey(Object? key) {
    for (final r in values) {
      if (r.key == key) return r;
    }
    return null;
  }

  /// The card's inline error.
  String get message => switch (this) {
    CustomNameReason.length => 'Use 3–14 letters or numbers.',
    CustomNameReason.chars => 'Only letters A–Z and numbers 0–9.',
    CustomNameReason.blocked => 'That name is not allowed. Try another.',
  };
}

/// The format rule (3–14, A–Z / a–z / 0–9): null when [name] passes.
CustomNameReason? checkCustomNameFormat(String name) {
  if (!_shape.hasMatch(name)) return CustomNameReason.chars;
  if (name.length < kCustomNameMin || name.length > kCustomNameMax) {
    return CustomNameReason.length;
  }
  return null;
}

/// A custom name read from a pool or storage: itself when it passes the
/// format rule, else ''.
String validCustomName(Object? name) =>
    name is String && name.isNotEmpty && checkCustomNameFormat(name) == null
    ? name
    : '';

/// The result of saving a custom name ('' = cleared).
sealed class CustomNameSave {
  const CustomNameSave();
}

/// The server accepted it (or cleared it) for the Firebase user [uid].
class CustomNameAccepted extends CustomNameSave {
  const CustomNameAccepted(this.uid);
  final String uid;
}

/// The server refused it: nothing changed.
class CustomNameRefused extends CustomNameSave {
  const CustomNameRefused(this.reason);
  final CustomNameReason reason;
}

/// The server could not be reached: kept on the phone, sent later.
class CustomNameOffline extends CustomNameSave {
  const CustomNameOffline();
}
