/// WP-NAME the player's own versus name, chosen in Settings (design A of
/// `design/username_settings/username.html`). The app checks the format;
/// the server (`functions/src/customname.ts`, `setVersusName`) checks the
/// same format plus a word filter and is the one that accepts a name.
///
/// WP-N2 one owner per name: the server compares names by [customNameKey]
/// (case-insensitive, look-alikes folded) and refuses one another player
/// holds as [CustomNameReason.taken]; names in the generated-nickname shape
/// ([looksGenerated]) are refused as [CustomNameReason.blocked], here
/// already and on the server.
library;

import 'nickname.dart';

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
  blocked('blocked'),

  /// WP-N2 another player holds this name (or a look-alike of it).
  taken('taken');

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
    CustomNameReason.taken => 'This name is taken.',
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

/// WP-N2 the format rule, then the generated-nickname shape (both checked
/// on the phone before the server is asked): null when [name] may be sent.
CustomNameReason? checkCustomNameLocal(String name) =>
    checkCustomNameFormat(name) ??
    (looksGenerated(name) ? CustomNameReason.blocked : null);

/// WP-N2 how the server compares names (`functions/src/nameclaims.ts`
/// `nameKey`): lower case, then the look-alikes folded — 0 → o, 1 and
/// i → l, 5 → s — so "Duck1", "duck1", "DUCKl" and "DuckI" are one name.
String customNameKey(String name) => name.toLowerCase().replaceAllMapped(
  RegExp('[01i5]'),
  (m) => const {'0': 'o', '1': 'l', 'i': 'l', '5': 's'}[m[0]]!,
);

/// WP-N2 [name] reads as a generated nickname (Adjective + Bird + 3
/// digits, either order), compared by [customNameKey]: such names cannot
/// be chosen (mirror of `isGeneratedShape` on the server).
bool looksGenerated(String name) {
  final k = customNameKey(name);
  if (k.length < 3) return false;
  final digits = customNameKey('0123456789');
  final tail = k.substring(k.length - 3);
  if (!tail.split('').every(digits.contains)) return false;
  final words = k.substring(0, k.length - 3);
  final adj = kNicknameAdjectives.map(customNameKey).toList();
  final bird = kNicknameBirds.map(customNameKey).toList();
  bool pairs(List<String> first, List<String> second) => first.any(
    (a) => words.startsWith(a) && second.contains(words.substring(a.length)),
  );
  return pairs(adj, bird) || pairs(bird, adj);
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
  const CustomNameRefused(this.reason, {this.current});
  final CustomNameReason reason;

  /// WP-N2 the name the server holds for this player now ('' = none; null
  /// = it did not say, e.g. a refusal by the format rule or the filter).
  final String? current;
}

/// The server could not be reached: kept on the phone, sent later.
class CustomNameOffline extends CustomNameSave {
  const CustomNameOffline();
}
