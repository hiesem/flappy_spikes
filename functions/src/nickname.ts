/**
 * WP-AV (2.4) the game's generated versus names on the backend: a 1:1 port
 * of `lib/versus/nickname.dart` (same word lists, same rule: Adjective +
 * Bird + 3 digits, pairs longer than 14 letters re-roll). Versus shows only
 * these names; Play Games / Game Center display names are never stored in
 * a pool.
 */
import { createHash } from 'node:crypto';

/** §3.13 nickname adjectives (20), as `kNicknameAdjectives`. */
export const NICKNAME_ADJECTIVES = [
  'Swift', 'Happy', 'Brave', 'Lucky', 'Sunny', 'Fluffy', 'Zippy', 'Mighty',
  'Jolly', 'Bouncy', 'Clever', 'Speedy', 'Cosmic', 'Golden', 'Tiny', 'Wild',
  'Crazy', 'Sparkly', 'Bold', 'Rapid',
];

/** §3.13 nickname bird words (20), as `kNicknameBirds`. */
export const NICKNAME_BIRDS = [
  'Kiwi', 'Robin', 'Finch', 'Puffin', 'Wren', 'Owl', 'Hawk', 'Falcon',
  'Swift', 'Parrot', 'Toucan', 'Pigeon', 'Eagle', 'Lark', 'Jay', 'Gull',
  'Dove', 'Crow', 'Heron', 'Flappy',
];

/** Adjective + Bird is at most this long (longer pairs re-roll). */
export const NICKNAME_WORDS_MAX = 14;

/** A random integer in [0, n) from [rand] in [0, 1). */
function pick(rand: () => number, n: number): number {
  return Math.min(n - 1, Math.floor(rand() * n));
}

/** A generated name, e.g. "SwiftKiwi482" (same logic as the app). */
export function generateNickname(rand: () => number): string {
  for (;;) {
    const a = NICKNAME_ADJECTIVES[pick(rand, NICKNAME_ADJECTIVES.length)];
    const b = NICKNAME_BIRDS[pick(rand, NICKNAME_BIRDS.length)];
    if (a.length + b.length > NICKNAME_WORDS_MAX) continue;
    return `${a}${b}${String(pick(rand, 1000)).padStart(3, '0')}`;
  }
}

/** Whether [name] has the generated shape (as `isGeneratedNickname`). */
export function isGeneratedNickname(name: unknown): boolean {
  if (typeof name !== 'string') return false;
  const m = /^([A-Z][a-z]+)([A-Z][a-z]+)(\d{3})$/.exec(name);
  if (!m) return false;
  return (
    NICKNAME_ADJECTIVES.includes(m[1]) &&
    NICKNAME_BIRDS.includes(m[2]) &&
    m[1].length + m[2].length <= NICKNAME_WORDS_MAX
  );
}

/** A deterministic [0, 1) stream seeded from [seed] (sha256 counter mode). */
export function seededRandom(seed: string): () => number {
  let counter = 0;
  return () => {
    const h = createHash('sha256').update(`${seed}:${counter++}`).digest();
    return h.readUInt32BE(0) / 0x1_0000_0000;
  };
}

/**
 * WP-AV the name a pool shows for [uid]: [name] when it is a generated
 * name, else (a platform name written by an older app) a generated name
 * derived from the uid, stable for that player.
 */
export function versusName(name: unknown, uid: string): string {
  return isGeneratedNickname(name) ? (name as string) : generateNickname(seededRandom(`name:${uid}`));
}
