/**
 * Custom versus names (2.4 WP-NAME): the name a player chooses in Settings.
 * Same format rule as the app (`lib/versus/custom_name.dart`): 3–14
 * characters, letters A–Z / a–z and digits only. The server adds a word
 * filter (English, case-insensitive): blocked words are also caught inside
 * longer names ("xxSLURxx") and in simple leetspeak (0→o, 1→i, 3→e, 4→a,
 * 5→s), with repeated letters collapsed ("fuuuck").
 *
 * WP-N2: a name in the generated-nickname shape is refused as 'blocked'
 * (2.4.0 apps already show that reason); a name another player holds is
 * refused as 'taken' (`nameclaims.ts`, checked by `setCustomName`).
 */
import { isGeneratedShape } from './nameclaims.js';

export const CUSTOM_NAME_MIN = 3;
export const CUSTOM_NAME_MAX = 14;

/** Why a name was refused (the app maps each to its card message). */
export type CustomNameReason = 'length' | 'chars' | 'blocked' | 'taken';

/**
 * Words refused anywhere inside a name. Only words that (almost) never
 * occur inside an innocent word are listed here; short or ambiguous words
 * are in [BLOCKED_EXACT] (e.g. "cock" would hit Peacock, "rape" Grape,
 * "coon" Raccoon, "negro" Montenegro).
 */
export const BLOCKED_ANYWHERE: readonly string[] = [
  'fuck', 'fuk', 'fck', 'phuck', 'motherf', 'shit', 'cunt', 'bitch', 'bastard', 'whore', 'slut',
  'nigger', 'nigga', 'niggr', 'faggot', 'fagot', 'retard', 'dickhead', 'cocksuck', 'pussy',
  'penis', 'vagina', 'porn', 'rapist', 'nazi', 'hitler', 'kkk', 'chink', 'wetback', 'tranny',
  'wanker', 'twat', 'jizz', 'dildo', 'asshole', 'arsehole', 'blowjob', 'handjob', 'raghead',
  'towelhead', 'piss', 'bollock', 'boner', 'orgasm', 'molest', 'paedo', 'pedophil',
  'incest', 'skank', 'hooker', 'heilhit', 'jihad', 'killyou',
];

/** Words refused as the whole name (letters only), also with a plural "s". */
export const BLOCKED_EXACT: readonly string[] = [
  'ass', 'arse', 'anal', 'anus', 'cock', 'dick', 'fag', 'rape', 'coon', 'spic', 'kike', 'gook',
  'paki', 'negro', 'dyke', 'homo', 'cum', 'sex', 'tit', 'tits', 'boob', 'boobs', 'crap', 'hoe',
  'beaner', 'damn', 'butt', 'poop', 'turd', 'nude', 'naked', 'sexy', 'horny', 'pedo', 'wank',
  'kys', 'heil', 'isis',
];

const LEET: Record<string, string> = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's' };

/** Lower case with the leetspeak digits read as letters. */
export function normalizeName(name: string): string {
  return name.toLowerCase().replace(/[01345]/g, (d) => LEET[d]);
}

/** Runs of the same letter collapsed to one ("fuuuck" → "fuck"). */
function collapse(s: string): string {
  return s.replace(/(.)\1+/g, '$1');
}

/** The spellings of [name] the filter looks at. */
function variants(name: string): string[] {
  const norm = normalizeName(name);
  const letters = name.toLowerCase().replace(/[^a-z]/g, '');
  const normLetters = norm.replace(/[^a-z]/g, '');
  return [...new Set([norm, collapse(norm), letters, collapse(letters), normLetters, collapse(normLetters)])];
}

/** Whether the word filter refuses [name]. */
export function isBlockedName(name: string): boolean {
  for (const v of variants(name)) {
    if (BLOCKED_ANYWHERE.some((w) => v.includes(w))) return true;
    if (BLOCKED_EXACT.some((w) => v === w || v === `${w}s`)) return true;
  }
  return false;
}

/** The format rule only (the app checks the same before it calls). */
export function customNameFormat(name: unknown): CustomNameReason | null {
  if (typeof name !== 'string') return 'chars';
  if (!/^[A-Za-z0-9]*$/.test(name)) return 'chars';
  if (name.length < CUSTOM_NAME_MIN || name.length > CUSTOM_NAME_MAX) return 'length';
  return null;
}

/** Null when [name] may be used, else the reason it is refused. */
export function checkCustomName(name: unknown): CustomNameReason | null {
  const format = customNameFormat(name);
  if (format) return format;
  return isBlockedName(name as string) || isGeneratedShape(name as string) ? 'blocked' : null;
}

/** A stored custom name as a pool shows it: '' unless it passes the rules now. */
export function poolCustomName(name: unknown): string {
  return typeof name === 'string' && checkCustomName(name) === null ? name : '';
}
