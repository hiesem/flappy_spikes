/**
 * WP-N2 one owner per custom versus name.
 *
 * Names are compared by their claim key ([nameKey]): lower case, then the
 * look-alike characters folded to one letter each:
 *
 *   0 → o      1, i → l      5 → s
 *
 * so "Duck1", "duck1", "DUCKl", "DuckI" and "DUCKL" are the same name, and
 * so are "B0b" / "Bob" and "Ka5h" / "Kash". (Only these four pairs: other
 * digits keep their own meaning, so "Duck2" and "Duck3" stay different.)
 *
 * `versusNameClaims/{key}` = {uid, name, updatedAt} says who holds a name;
 * it is written only by the server, in the same transaction as the
 * owner's `versusNames/{uid}` (clients can neither read nor write it).
 *
 * Names in the generated-nickname shape (Adjective + Bird + 3 digits, either
 * word order, `nickname.ts`) cannot be chosen — compared by the same
 * folding, so "swiftkiwi482" and "SW1FTKIWI4O2" are refused too
 * ([isGeneratedShape]).
 *
 * Guests (anonymous Firebase users, not linked to Play Games / Game Center)
 * lose their name after [GUEST_NAME_TTL_DAYS] days without activity (the
 * daily `releaseGuestNames` job); linked players keep theirs for good.
 */
import type { Timestamp } from 'firebase-admin/firestore';
import { NICKNAME_ADJECTIVES, NICKNAME_BIRDS } from './nickname.js';

/** Server-only claims: `versusNameClaims/{nameKey}` → the owner's uid. */
export const CLAIMS_COLLECTION = 'versusNameClaims';

/** A guest's name is released after this many days without activity. */
export const GUEST_NAME_TTL_DAYS = 30;
export const GUEST_NAME_TTL_MS = GUEST_NAME_TTL_DAYS * 24 * 3600 * 1000;

/** The activity stamp (`lastSeen`) is rewritten at most this often. */
export const SEEN_REFRESH_MS = 12 * 3600 * 1000;

const FOLD: Record<string, string> = { '0': 'o', '1': 'l', i: 'l', '5': 's' };

/** The claim key of [name]: lower case with the look-alikes folded. */
export function nameKey(name: string): string {
  return name.toLowerCase().replace(/[01i5]/g, (c) => FOLD[c]);
}

/** The ten digits as they read after folding. */
const DIGIT_CHARS = new Set(nameKey('0123456789'));

const FOLDED_ADJ = NICKNAME_ADJECTIVES.map(nameKey);
const FOLDED_BIRD = NICKNAME_BIRDS.map(nameKey);

/**
 * Whether [name] reads as a generated nickname (Adjective + Bird + 3
 * digits, either order), case-insensitively and with the look-alikes
 * folded ([nameKey]).
 */
export function isGeneratedShape(name: string): boolean {
  const k = nameKey(name);
  if (k.length < 3) return false;
  const tail = k.slice(-3);
  if (![...tail].every((c) => DIGIT_CHARS.has(c))) return false;
  const words = k.slice(0, -3);
  const pairs = (first: string[], second: string[]) =>
    first.some((a) => words.startsWith(a) && second.includes(words.slice(a.length)));
  return pairs(FOLDED_ADJ, FOLDED_BIRD) || pairs(FOLDED_BIRD, FOLDED_ADJ);
}

/** `versusNameClaims/{key}`. */
export interface ClaimDoc {
  uid: string;
  /** The name as its owner wrote it. */
  name: string;
  updatedAt: Timestamp;
}
