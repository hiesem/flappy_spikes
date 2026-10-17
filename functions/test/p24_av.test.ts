/**
 * WP-AV (2.4) sticker avatars on the backend:
 * - the generated-name port matches the app (same word lists, same shape);
 * - a pool entry never holds a picture URL or a platform name;
 * - look ids are validated (catalogue-id shape, length cap) by the
 *   function and the Firestore rules;
 * - Storage is closed (no read / write anywhere, `avatars/` included);
 * - the backfill's pure parts (random looks, names, rewrites).
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc, Timestamp } from 'firebase/firestore';
import {
  generateNickname,
  isGeneratedNickname,
  NICKNAME_ADJECTIVES,
  NICKNAME_BIRDS,
  seededRandom,
  versusName,
} from '../src/nickname.js';
import { LOOK_ID_RE, poolId, validLook } from '../src/schema.js';
import { checkRun, encodeDeltas, encodeEntries } from '../src/timeline.js';
import {
  BIRD_IDS,
  GEAR_IDS,
  HAT_IDS,
  identityFor,
  isAvatarObject,
  randomLook,
  rewritePlayer,
  rewritePoolEntries,
  rewriteRun,
} from '../scripts/backfill_lib.js';
import { DAY, LOOK, LOOK_FANCY, makePlayer, makeRun, poolEntries, processLive, PROJECT, uniq } from './helpers.js';

const ROOT = join(__dirname, '..', '..');

/** The quoted strings of a Dart `const List<String> <name> = [ … ];`. */
function dartList(file: string, name: string): string[] {
  const src = readFileSync(join(ROOT, file), 'utf8');
  const start = src.indexOf(name);
  assert.ok(start >= 0, `${name} in ${file}`);
  const body = src.slice(src.indexOf('[', start), src.indexOf('];', start));
  return [...body.matchAll(/'([^']+)'/g)].map((m) => m[1]);
}

/** The ids of a Dart catalogue list `const List<SkinItem> <name>`. */
function dartIds(name: string): string[] {
  const src = readFileSync(join(ROOT, 'lib/skins/catalog.dart'), 'utf8');
  const start = src.indexOf(`const List<SkinItem> ${name}`);
  assert.ok(start >= 0, name);
  const body = src.slice(start, src.indexOf('];', start));
  return [...body.matchAll(/id: '([^']+)'/g)].map((m) => m[1]);
}

describe('WP-AV generated names (port of lib/versus/nickname.dart)', () => {
  it('the word lists are the app\'s, word for word', () => {
    assert.deepEqual(NICKNAME_ADJECTIVES, dartList('lib/versus/nickname.dart', 'kNicknameAdjectives'));
    assert.deepEqual(NICKNAME_BIRDS, dartList('lib/versus/nickname.dart', 'kNicknameBirds'));
  });

  it('every generated name has the app\'s shape', () => {
    const r = seededRandom('t');
    for (let i = 0; i < 500; i++) {
      const n = generateNickname(r);
      assert.ok(isGeneratedNickname(n), n);
      assert.ok(n.length <= 17, n);
    }
    assert.equal(isGeneratedNickname('SwiftKiwi482'), true);
    for (const bad of ['Hiesem', 'Molly the Great', 'SwiftKiwi48', 'SwiftDodo123', 'swiftkiwi482', 7, null]) {
      assert.equal(isGeneratedNickname(bad), false, String(bad));
    }
  });

  it('versusName keeps a generated name and replaces a platform name, stable per uid', () => {
    assert.equal(versusName('BoldOwl007', 'u1'), 'BoldOwl007');
    const a = versusName('Hiesem', 'u1');
    assert.ok(isGeneratedNickname(a));
    assert.equal(versusName('Another Name', 'u1'), a, 'same uid, same name');
    assert.notEqual(versusName('Hiesem', 'u2'), a);
  });
});

describe('WP-AV pools hold no pictures and no platform names', () => {
  it('a run from an older app (platform name + picture URL) is pooled with a generated name and avatar ""', async () => {
    const uid = uniq('legacy');
    const run = {
      ...makeRun({ score: 140, look: LOOK_FANCY }),
      name: 'Hiesem Smith',
      avatar: 'https://firebasestorage.googleapis.com/v0/b/x/o/avatars%2Fu.jpg?alt=media',
    };
    const r = await processLive(uid, undefined, makePlayer({ best: 140, bestRun: run, recent: [run] }), {
      rand: () => 0,
    });
    assert.deepEqual(r.accepted, [run.runId]);
    const e = (await poolEntries(poolId(3, 0))).find((x) => x.runId === run.runId)!;
    assert.equal(e.avatar, '');
    assert.ok(isGeneratedNickname(e.name), e.name);
    assert.equal(e.name, versusName('Hiesem Smith', uid));
    assert.deepEqual(e.look, LOOK_FANCY, 'the skin ids travel with the run');
  });

  it('a generated name is pooled unchanged', async () => {
    const uid = uniq('gen');
    const run = makeRun({ score: 141, name: 'JollyWren123' });
    await processLive(uid, undefined, makePlayer({ best: 141, bestRun: run, recent: [run] }), { rand: () => 0 });
    const e = (await poolEntries(poolId(3, 0))).find((x) => x.runId === run.runId)!;
    assert.equal(e.name, 'JollyWren123');
    assert.equal(e.avatar, '');
  });
});

describe('WP-AV look ids are validated', () => {
  it('the function accepts catalogue-shaped ids and refuses others', () => {
    assert.ok(validLook(LOOK));
    assert.ok(validLook({ ...LOOK, bird: 'future_bird_2' }), 'an unknown but well-formed id passes (the phone falls back)');
    for (const bad of ['', 'Grape', 'a b', 'x'.repeat(41), 'cap;drop', 'ünï']) {
      assert.equal(validLook({ ...LOOK, hat: bad }), false, bad);
      assert.equal(checkRun({ ...makeRun(), look: { ...LOOK, gear: bad } }, 99), 'shape', bad);
    }
    assert.equal(validLook({ bird: 'classic', gear: 'none', hat: 'none', hoop: 'pink' }), false);
    assert.equal(validLook({ ...LOOK, extra: 'x' }), false);
    assert.equal(validLook({ ...LOOK, bird: 7 }), false);
    assert.equal(validLook(null), false);
    assert.ok(LOOK_ID_RE.test('x'.repeat(40)));
    assert.equal(checkRun(makeRun({ look: LOOK_FANCY }), 99), null);
  });
});

describe('WP-AV rules: look ids, closed Storage', () => {
  let env: RulesTestEnvironment;
  const storageHost = (): { host: string; port: number } => {
    const [host, port] = (process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '127.0.0.1:9199').split(':');
    return { host, port: Number(port) };
  };

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT,
      firestore: { rules: readFileSync(join(ROOT, 'firestore.rules'), 'utf8') },
      storage: { ...storageHost(), rules: readFileSync(join(ROOT, 'storage.rules'), 'utf8') },
    });
  });

  after(async () => {
    await env?.cleanup();
  });

  function run(look: Record<string, unknown>) {
    return {
      runId: uniq('r'),
      score: 2,
      best: 2,
      ts: Timestamp.now(),
      name: 'SwiftKiwi482',
      avatar: '',
      look,
      platform: 'android',
      tl: encodeDeltas([120, 120]),
      end: 80,
      fl: encodeEntries([0, 0], [1, 1]),
    };
  }
  function player(look: Record<string, unknown>, runLook: Record<string, unknown> = look) {
    return {
      name: 'SwiftKiwi482',
      avatar: '',
      platform: 'android',
      look,
      best: 2,
      level: 0,
      bestRun: null,
      recent: [run(runLook)],
      uploads: { day: '2026-10-17', count: 1 },
      updatedAt: serverTimestamp(),
      expireAt: Timestamp.fromMillis(Date.now() + 60 * DAY),
    };
  }
  const write = (d: Record<string, unknown>) => {
    const uid = uniq('av');
    return setDoc(doc(env.authenticatedContext(uid).firestore(), 'players', uid), d);
  };

  it('accepts catalogue-shaped ids in the player look and the run look', async () => {
    await assertSucceeds(write(player({ ...LOOK_FANCY })));
    await assertSucceeds(write(player({ ...LOOK, bird: 'future_bird' })));
  });

  it('refuses a malformed or too long id in either look', async () => {
    await assertFails(write(player({ ...LOOK, hat: 'Crown' })));
    await assertFails(write(player({ ...LOOK, gear: '' })));
    await assertFails(write(player({ ...LOOK, bird: 'x'.repeat(41) })));
    await assertFails(write(player({ ...LOOK }, { ...LOOK, hat: 'a/b' })));
    await assertFails(write(player({ ...LOOK }, { ...LOOK, trail: '' })));
  });

  it('Storage is closed: no read, write or delete of avatars/ (or anything else)', async () => {
    const uid = uniq('pic');
    const bucket = `gs://${PROJECT}.firebasestorage.app`;
    const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0]);
    const meta = { contentType: 'image/jpeg' };
    const mine = env.authenticatedContext(uid).storage(bucket);
    await assertFails(mine.ref(`avatars/${uid}.jpg`).put(jpeg, meta).then());
    await assertFails(mine.ref(`avatars/${uid}.jpg`).getMetadata());
    await assertFails(mine.ref(`avatars/${uid}.jpg`).delete());
    await assertFails(env.unauthenticatedContext().storage(bucket).ref(`avatars/${uid}.jpg`).getMetadata());
    await assertFails(mine.ref(`other/${uid}.jpg`).put(jpeg, meta).then());
  });
});

describe('WP-AV backfill (pure parts)', () => {
  it('the catalogue ids are the app\'s (lib/skins/catalog.dart)', () => {
    assert.deepEqual(BIRD_IDS, dartIds('kBirds'));
    assert.deepEqual(['none', ...GEAR_IDS], dartIds('kGear'));
    assert.deepEqual(['none', ...HAT_IDS], dartIds('kHats'));
    for (const id of [...BIRD_IDS, ...GEAR_IDS, ...HAT_IDS]) assert.ok(LOOK_ID_RE.test(id), id);
  });

  it('randomLook: catalogue ids, gear and hat "none" about 40 % of the time, every bird used', () => {
    const r = seededRandom('dist');
    const n = 4000;
    let noGear = 0;
    let noHat = 0;
    const birds = new Set<string>();
    for (let i = 0; i < n; i++) {
      const l = randomLook(r);
      assert.ok(BIRD_IDS.includes(l.bird));
      assert.ok(l.gear === 'none' || GEAR_IDS.includes(l.gear));
      assert.ok(l.hat === 'none' || HAT_IDS.includes(l.hat));
      if (l.gear === 'none') noGear++;
      if (l.hat === 'none') noHat++;
      birds.add(l.bird);
    }
    assert.ok(Math.abs(noGear / n - 0.4) < 0.04, `gear none ${noGear / n}`);
    assert.ok(Math.abs(noHat / n - 0.4) < 0.04, `hat none ${noHat / n}`);
    assert.equal(birds.size, BIRD_IDS.length);
  });

  it('identityFor: deterministic per (seed, uid); keeps a generated name, replaces a platform name', () => {
    const a = identityFor('u1', 'Hiesem', 's1');
    assert.deepEqual(identityFor('u1', 'Hiesem', 's1'), a);
    assert.ok(isGeneratedNickname(a.name));
    assert.equal(identityFor('u1', 'BoldOwl007', 's1').name, 'BoldOwl007');
    const looks = new Set(Array.from({ length: 30 }, (_, i) => JSON.stringify(identityFor(`u${i}`, '', 's1').look)));
    assert.ok(looks.size > 20, 'players get different looks');
  });

  it('rewriteRun / rewritePlayer: new name, avatar "", bird / gear / hat replaced, hoop / trail kept, platform fields dropped', () => {
    const id = { look: { bird: 'owl', gear: 'monocle', hat: 'tophat' }, name: 'WiseOwl088' };
    const old = {
      ...makeRun({ look: LOOK_FANCY }),
      name: 'Hiesem',
      avatar: 'https://x/y.jpg',
      displayName: 'Hiesem',
    };
    const r = rewriteRun(old, id) as Record<string, unknown>;
    assert.equal(r.name, 'WiseOwl088');
    assert.equal(r.avatar, '');
    assert.deepEqual(r.look, { bird: 'owl', gear: 'monocle', hat: 'tophat', hoop: 'neon', trail: 'bubbles' });
    assert.equal('displayName' in r, false);
    assert.equal(r.tl, old.tl, 'the run itself is untouched');
    assert.equal(old.name, 'Hiesem', 'input not mutated');

    const p = { ...makePlayer({ best: 12, bestRun: old as never, recent: [old as never, makeRun()] }), photoUrl: 'https://p' };
    const { set, remove } = rewritePlayer(p, id);
    assert.equal(set.name, 'WiseOwl088');
    assert.equal(set.avatar, '');
    assert.deepEqual(set.look, { bird: 'owl', gear: 'monocle', hat: 'tophat', hoop: 'pink', trail: 'flame' });
    assert.equal((set.bestRun as Record<string, unknown>).name, 'WiseOwl088');
    assert.equal((set.recent as unknown[]).length, 2);
    for (const x of set.recent as Record<string, unknown>[]) {
      assert.equal(x.avatar, '');
      assert.deepEqual((x.look as Record<string, unknown>).bird, 'owl');
    }
    assert.deepEqual(remove, ['photoUrl']);
    // A doc without bestRun / a null bestRun.
    assert.equal(rewritePlayer({ name: 'x', recent: [] }, id).set.bestRun, undefined);
    assert.equal(rewritePlayer({ name: 'x', bestRun: null }, id).set.bestRun, null);
  });

  it('rewritePoolEntries: each owner gets their identity; malformed entries are left alone', () => {
    const seen: string[] = [];
    const idOf = (uid: string) => {
      seen.push(uid);
      return { look: { bird: 'sky', gear: 'none', hat: 'cap' }, name: `SwiftKiwi${uid === 'a' ? '001' : '002'}` };
    };
    const out = rewritePoolEntries(
      [{ ...makeRun(), uid: 'a', level: 3 }, { ...makeRun(), uid: 'b', level: 3, avatar: 'https://z' }, null, { runId: 'x' }],
      idOf,
    ) as Record<string, unknown>[];
    assert.deepEqual(seen, ['a', 'b']);
    assert.equal(out[0].name, 'SwiftKiwi001');
    assert.equal(out[1].name, 'SwiftKiwi002');
    assert.equal(out[1].avatar, '');
    assert.equal(out[0].uid, 'a');
    assert.equal(out[0].level, 3);
    assert.equal(out[2], null);
    assert.deepEqual(out[3], { runId: 'x' });
  });

  it('isAvatarObject: everything under avatars/ only', () => {
    assert.ok(isAvatarObject('avatars/u1.jpg'));
    assert.ok(isAvatarObject('avatars/sub/x.png'));
    assert.equal(isAvatarObject('other/avatars/u1.jpg'), false);
    assert.equal(isAvatarObject('avatarsX/u1.jpg'), false);
  });
});
