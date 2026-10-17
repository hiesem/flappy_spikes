/**
 * WP-AV (2.4) the pure part of `backfill_avatars.ts`: every versus player
 * gets a sticker-avatar look (a random bird / gear / hat from the
 * catalogue) and a generated name, and loses the old picture URL. No
 * Firestore or Storage here, so the mocha tests cover it directly.
 */
import { generateNickname, isGeneratedNickname, seededRandom } from '../src/nickname.js';

/** The 30 birds of `lib/skins/catalog.dart` (kBirds), grid order. */
export const BIRD_IDS = [
  'classic', 'sky', 'lime', 'grape', 'tangerine', 'mint', 'lemon', 'slate', 'coral', 'snow',
  'robin', 'toucan', 'chick', 'penguin', 'owl', 'duck', 'flamingo', 'puffer', 'zebra', 'buzz',
  'robo', 'zombie', 'ghost', 'pixel', 'frost', 'magma', 'galaxy', 'golden', 'rainbow', 'phoenix',
];

/** The 29 gear items of kGear (without the free 'none'). */
export const GEAR_IDS = [
  'shades', 'bowtie', 'stache', 'scarf', 'bandana', 'snorkel', 'necktie', 'bandaid', 'gum', 'lei',
  'hearts', 'monocle', 'sneakers', 'windup', 'carpet', 'balloon', 'backpack', 'skates', 'swimring',
  'cape', 'chain', 'mask', 'patch', 'butterfly', 'drone', 'jetpack', 'crystal', 'atom', 'disco',
];

/** The 29 hats of kHats (without the free 'none'). */
export const HAT_IDS = [
  'cap', 'beanie', 'party', 'band', 'bucket', 'sprout', 'cone', 'egg', 'paperboat', 'phones',
  'tophat', 'cowboy', 'prop', 'chef', 'viking', 'fishbowl', 'cupcake', 'raincloud', 'antennae',
  'sharkfin', 'pirate', 'wizard', 'volcano', 'ufo', 'bdaycake', 'crown', 'halo', 'planet', 'sunburst',
];

/** Share of players without gear / without a hat (like real players). */
export const NONE_SHARE = 0.4;

export interface AvatarLook {
  bird: string;
  gear: string;
  hat: string;
}

function pick<T>(rand: () => number, list: readonly T[]): T {
  return list[Math.min(list.length - 1, Math.floor(rand() * list.length))];
}

/** A random avatar look: any bird; gear and hat 'none' ~40 % of the time. */
export function randomLook(rand: () => number): AvatarLook {
  const bird = pick(rand, BIRD_IDS);
  const gear = rand() < NONE_SHARE ? 'none' : pick(rand, GEAR_IDS);
  const hat = rand() < NONE_SHARE ? 'none' : pick(rand, HAT_IDS);
  return { bird, gear, hat };
}

/** What one player gets: the same look and name in every doc that holds them. */
export interface PlayerIdentity {
  look: AvatarLook;
  name: string;
}

/**
 * The identity of [uid] for this backfill run ([seed] = the run's random
 * seed): a random look, and the stored [name] when it already is a
 * generated name (the one the player's phone keeps writing), else a new
 * generated name. Deterministic per (seed, uid), so the player doc and
 * every pool entry of a player agree.
 */
export function identityFor(uid: string, name: unknown, seed: string): PlayerIdentity {
  const look = randomLook(seededRandom(`look:${seed}:${uid}`));
  const keep = isGeneratedNickname(name);
  return {
    look,
    name: keep ? (name as string) : generateNickname(seededRandom(`name:${seed}:${uid}`)),
  };
}

type Doc = Record<string, unknown>;

/** Fields a platform account could have left in a versus doc (none are kept). */
export const PLATFORM_FIELDS = ['photoUrl', 'photoURL', 'displayName', 'playerName', 'iconImage', 'pgName'];

/**
 * One stored run (a `recent` / `bestRun` entry or a pool entry) with the
 * new identity: name, avatar '' and the bird / gear / hat replaced (hoop
 * and trail kept; a missing look gets the defaults). Platform-name fields
 * are dropped. Returns a new object; null / non-objects pass through.
 */
export function rewriteRun(run: unknown, id: PlayerIdentity): unknown {
  if (run === null || typeof run !== 'object' || Array.isArray(run)) return run;
  const r = { ...(run as Doc) };
  for (const f of PLATFORM_FIELDS) delete r[f];
  const old = (r.look && typeof r.look === 'object' ? r.look : {}) as Doc;
  r.name = id.name;
  r.avatar = '';
  r.look = {
    bird: id.look.bird,
    gear: id.look.gear,
    hat: id.look.hat,
    hoop: typeof old.hoop === 'string' ? old.hoop : 'pink',
    trail: typeof old.trail === 'string' ? old.trail : 'flame',
  };
  return r;
}

/**
 * The update of a `players/{uid}` doc: name, avatar '', look, and the same
 * in `bestRun` and every `recent` run ([set]); [remove] lists the
 * platform-name fields present (the caller deletes them).
 */
export function rewritePlayer(doc: Doc, id: PlayerIdentity): { set: Doc; remove: string[] } {
  const set: Doc = {};
  const top = rewriteRun({ look: doc.look }, id) as Doc;
  set.name = id.name;
  set.avatar = '';
  set.look = top.look;
  if ('bestRun' in doc) set.bestRun = rewriteRun(doc.bestRun, id);
  if (Array.isArray(doc.recent)) set.recent = doc.recent.map((r) => rewriteRun(r, id));
  const remove = PLATFORM_FIELDS.filter((f) => f in doc);
  return { set, remove };
}

/** Pool entries with each owner's identity (entries without a uid are left alone). */
export function rewritePoolEntries(
  entries: unknown[],
  idOf: (uid: string, name: unknown) => PlayerIdentity,
): unknown[] {
  return entries.map((e) => {
    if (e === null || typeof e !== 'object') return e;
    const uid = (e as Doc).uid;
    if (typeof uid !== 'string' || !uid) return e;
    return rewriteRun(e, idOf(uid, (e as Doc).name));
  });
}

/** The objects to delete from the Storage bucket: everything under `avatars/`. */
export function isAvatarObject(name: string): boolean {
  return name.startsWith('avatars/');
}
