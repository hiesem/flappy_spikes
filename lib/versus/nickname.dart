import 'dart:math';

/// §3.13 nickname adjectives (20).
const List<String> kNicknameAdjectives = [
  'Swift', 'Happy', 'Brave', 'Lucky', 'Sunny', 'Fluffy', 'Zippy', 'Mighty', //
  'Jolly', 'Bouncy', 'Clever', 'Speedy', 'Cosmic', 'Golden', 'Tiny', 'Wild',
  'Crazy', 'Sparkly', 'Bold', 'Rapid',
];

/// §3.13 nickname bird words (20).
const List<String> kNicknameBirds = [
  'Kiwi', 'Robin', 'Finch', 'Puffin', 'Wren', 'Owl', 'Hawk', 'Falcon', //
  'Swift', 'Parrot', 'Toucan', 'Pigeon', 'Eagle', 'Lark', 'Jay', 'Gull',
  'Dove', 'Crow', 'Heron', 'Flappy',
];

/// §3.13 Adjective + Bird is at most this long (longer pairs re-roll).
const int kNicknameWordsMax = 14;

/// §3.13 a generated nickname for anonymous players: Adjective + Bird + 3
/// digits (000–999), e.g. "SwiftKiwi482". Created once per install; no free
/// text, so no moderation is needed. Pairs longer than 14 characters are
/// skipped and re-rolled.
String generateNickname(Random r) {
  while (true) {
    final a = kNicknameAdjectives[r.nextInt(kNicknameAdjectives.length)];
    final b = kNicknameBirds[r.nextInt(kNicknameBirds.length)];
    if (a.length + b.length > kNicknameWordsMax) continue;
    return '$a$b${r.nextInt(1000).toString().padLeft(3, '0')}';
  }
}

/// Whether [name] has the generated-nickname shape (tests, migration).
bool isGeneratedNickname(String name) {
  final m = RegExp(r'^([A-Z][a-z]+)([A-Z][a-z]+)(\d{3})$').firstMatch(name);
  if (m == null) return false;
  return kNicknameAdjectives.contains(m[1]) &&
      kNicknameBirds.contains(m[2]) &&
      m[1]!.length + m[2]!.length <= kNicknameWordsMax;
}
