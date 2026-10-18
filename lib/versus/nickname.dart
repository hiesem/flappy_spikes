import 'dart:math';

/// §3.13 nickname adjectives (40; design/nicknames/nickname_words.md). The
/// first 20 are the approved originals; new words are appended after them
/// so old positions stay.
const List<String> kNicknameAdjectives = [
  'Swift', 'Happy', 'Brave', 'Lucky', 'Sunny', 'Fluffy', 'Zippy', 'Mighty', //
  'Jolly', 'Bouncy', 'Clever', 'Speedy', 'Cosmic', 'Golden', 'Tiny', 'Wild',
  'Crazy', 'Sparkly', 'Bold', 'Rapid',
  'Turbo', 'Fizzy', 'Peppy', 'Plucky', 'Dizzy', 'Chirpy', 'Breezy', 'Nifty',
  'Snappy', 'Spiky', 'Jumpy', 'Perky', 'Frosty', 'Super', 'Cheery', 'Daring',
  'Quick', 'Merry', 'Mega', 'Zappy',
];

/// §3.13 nickname bird words (40; same file, same append rule).
const List<String> kNicknameBirds = [
  'Kiwi', 'Robin', 'Finch', 'Puffin', 'Wren', 'Owl', 'Hawk', 'Falcon', //
  'Swift', 'Parrot', 'Toucan', 'Pigeon', 'Eagle', 'Lark', 'Jay', 'Gull',
  'Dove', 'Crow', 'Heron', 'Flappy',
  'Duck', 'Goose', 'Swan', 'Stork', 'Crane', 'Ibis', 'Raven', 'Quail',
  'Egret', 'Kite', 'Tern', 'Emu', 'Macaw', 'Chick', 'Magpie', 'Sparrow',
  'Condor', 'Osprey', 'Penguin', 'Pelican',
];

/// §3.13 Adjective + Bird is at most this long (longer pairs re-roll).
const int kNicknameWordsMax = 14;

/// §3.13 a generated nickname for anonymous players: an adjective and a bird
/// word, in either order (50/50: "TurboDuck111" or "DuckTurbo111"), then 3
/// digits (000–999). Created once per install; no free text, so no
/// moderation is needed. Pairs longer than 14 letters are re-rolled.
String generateNickname(Random r) {
  while (true) {
    final a = kNicknameAdjectives[r.nextInt(kNicknameAdjectives.length)];
    final b = kNicknameBirds[r.nextInt(kNicknameBirds.length)];
    if (a.length + b.length > kNicknameWordsMax) continue;
    final birdFirst = r.nextBool();
    final digits = r.nextInt(1000).toString().padLeft(3, '0');
    return birdFirst ? '$b$a$digits' : '$a$b$digits';
  }
}

/// Whether [name] has the generated-nickname shape, in either word order
/// (tests, migration, the old 20 + 20 names included).
bool isGeneratedNickname(String name) {
  final m = RegExp(r'^([A-Z][a-z]+)([A-Z][a-z]+)(\d{3})$').firstMatch(name);
  if (m == null) return false;
  final first = m[1]!, second = m[2]!;
  if (first.length + second.length > kNicknameWordsMax) return false;
  return (kNicknameAdjectives.contains(first) &&
          kNicknameBirds.contains(second)) ||
      (kNicknameBirds.contains(first) && kNicknameAdjectives.contains(second));
}
