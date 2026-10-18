/**
 * WP-NAME (2.4) custom versus names and the 40 + 40 generated names:
 * - the generated-name lists are the app's (40 / 40, same order), both word
 *   orders are generated and accepted, every pair is ≤ 14 letters;
 * - the custom-name rules (3–14, A–Z / a–z / 0–9) and the word filter
 *   (case-insensitive, inside longer names, simple leetspeak);
 * - setCustomName stores the name server-only, writes it into the caller's
 *   pool entries at once and clears it again; new pool entries carry it;
 * - Delete my data removes it; clients can neither read nor write it;
 * - the `setVersusName` callable (App Check enforced).
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { assertFails, initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import {
  checkCustomName,
  CUSTOM_NAME_MAX,
  CUSTOM_NAME_MIN,
  isBlockedName,
  poolCustomName,
} from '../src/customname.js';
import {
  generateNickname,
  isGeneratedNickname,
  NICKNAME_ADJECTIVES,
  NICKNAME_BIRDS,
  NICKNAME_WORDS_MAX,
  seededRandom,
} from '../src/nickname.js';
import { deletePlayerData, setCustomName } from '../src/pools.js';
import { NAMES_COLLECTION, poolId } from '../src/schema.js';
import { auth, db, fakeJwt, makePlayer, makeRun, poolEntries, processLive, PROJECT, uniq } from './helpers.js';

const ROOT = join(__dirname, '..', '..');

function dartList(name: string): string[] {
  const src = readFileSync(join(ROOT, 'lib/versus/nickname.dart'), 'utf8');
  const start = src.indexOf(`const List<String> ${name}`);
  assert.ok(start >= 0, name);
  const body = src.slice(src.indexOf('[', start), src.indexOf('];', start));
  return [...body.matchAll(/'([^']+)'/g)].map((m) => m[1]);
}

describe('WP-NAME generated names: 40 + 40, either order', () => {
  it('the lists are 40 / 40 and word for word the app\'s (mirror)', () => {
    assert.equal(NICKNAME_ADJECTIVES.length, 40);
    assert.equal(NICKNAME_BIRDS.length, 40);
    assert.equal(new Set(NICKNAME_ADJECTIVES).size, 40);
    assert.equal(new Set(NICKNAME_BIRDS).size, 40);
    assert.deepEqual(NICKNAME_ADJECTIVES, dartList('kNicknameAdjectives'));
    assert.deepEqual(NICKNAME_BIRDS, dartList('kNicknameBirds'));
    assert.equal(NICKNAME_ADJECTIVES[19], 'Rapid', 'old words keep their positions');
    assert.equal(NICKNAME_BIRDS[19], 'Flappy');
  });

  it('every pair is at most 14 letters', () => {
    for (const a of NICKNAME_ADJECTIVES) {
      for (const b of NICKNAME_BIRDS) assert.ok(a.length + b.length <= NICKNAME_WORDS_MAX, a + b);
    }
  });

  it('both orders are generated (about 50/50) and accepted; old names still match', () => {
    const r = seededRandom('order');
    let adjFirst = 0;
    let birdFirst = 0;
    for (let i = 0; i < 2000; i++) {
      const n = generateNickname(r);
      assert.ok(isGeneratedNickname(n), n);
      const m = /^([A-Z][a-z]+)([A-Z][a-z]+)\d{3}$/.exec(n)!;
      if (NICKNAME_ADJECTIVES.includes(m[1]) && NICKNAME_BIRDS.includes(m[2])) adjFirst++;
      else birdFirst++;
    }
    assert.ok(adjFirst > 850 && adjFirst < 1150, String(adjFirst));
    assert.ok(birdFirst > 850 && birdFirst < 1150, String(birdFirst));
    for (const ok of ['TurboDuck111', 'DuckTurbo111', 'BraveParrot907', 'ParrotBrave907']) {
      assert.equal(isGeneratedNickname(ok), true, ok);
    }
    for (const bad of ['DuckGoose111', 'TurboMega111', 'DuckTurbo11']) {
      assert.equal(isGeneratedNickname(bad), false, bad);
    }
  });
});

describe('WP-NAME custom name rules and word filter', () => {
  it('3–14 letters A–Z / a–z or digits', () => {
    assert.equal(CUSTOM_NAME_MIN, 3);
    assert.equal(CUSTOM_NAME_MAX, 14);
    for (const ok of ['Bob', 'WiseOwl', 'Player1', 'ABCDEFGHIJKLMN', '123', 'Grape', 'Peacock', 'Scrap', 'Swanky']) {
      assert.equal(checkCustomName(ok), null, ok);
    }
    assert.equal(checkCustomName('Al'), 'length');
    assert.equal(checkCustomName('ABCDEFGHIJKLMNO'), 'length');
    assert.equal(checkCustomName(''), 'length');
    for (const bad of ['Wise Owl', 'Zoë', 'a_b', 'abc!', 'ab-c']) assert.equal(checkCustomName(bad), 'chars', bad);
    assert.equal(checkCustomName(7), 'chars');
    assert.equal(checkCustomName(null), 'chars');
  });

  it('blocks words case-insensitively, inside longer names and in leetspeak', () => {
    for (const bad of ['fuck', 'FUCK', 'xxFUCKxx', 'Fuuuuck', 'Sh1t', 'sh1tty', 'B1TCH', 'xxN1GG3Rxx', 'n4z1', 'Ass', 'ASS', 'A55', 'Ass123', 'cocks', 'Pen1s', 'whore99']) {
      assert.equal(isBlockedName(bad), true, bad);
      if (/^[A-Za-z0-9]{3,14}$/.test(bad)) assert.equal(checkCustomName(bad), 'blocked', bad);
    }
    for (const fine of ['Peacock', 'Grape', 'Classic', 'Raccoon', 'Swanky', 'Bass', 'Assassin', 'Hancock', 'Sussex', 'WiseOwl', 'Cocktail9']) {
      assert.equal(isBlockedName(fine), false, fine);
    }
  });

  it('a pool only ever shows a name that passes the rules now', () => {
    assert.equal(poolCustomName('WiseOwl'), 'WiseOwl');
    assert.equal(poolCustomName('xxfuckxx'), '');
    assert.equal(poolCustomName('Wise Owl'), '');
    assert.equal(poolCustomName(undefined), '');
  });
});

describe('WP-NAME setCustomName (emulated Firestore)', () => {
  it('stores the name server-only, writes it into the caller\'s pool entries and clears it again', async () => {
    const uid = uniq('cn');
    const other = uniq('cn-other');
    const run = makeRun({ score: 40 });
    const otherRun = makeRun({ score: 41 });
    await processLive(uid, undefined, makePlayer({ best: 40, bestRun: run, recent: [run] }), { rand: () => 0 });
    await processLive(other, undefined, makePlayer({ best: 41, bestRun: otherRun, recent: [otherRun] }), {
      rand: () => 0,
    });
    const pid = poolId(1, 0);
    const mine = async () => (await poolEntries(pid)).find((e) => e.runId === run.runId)!;
    const theirs = async () => (await poolEntries(pid)).find((e) => e.runId === otherRun.runId)!;
    assert.equal((await mine()).customName, undefined);

    const r = await setCustomName(db, uid, 'WiseOwl');
    assert.deepEqual(r, { ok: true, name: 'WiseOwl', updated: 1 });
    assert.equal((await mine()).customName, 'WiseOwl');
    assert.ok(isGeneratedNickname((await mine()).name), 'the generated name stays for older apps');
    assert.equal((await theirs()).customName, undefined, 'other players are untouched');
    assert.equal((await db.collection(NAMES_COLLECTION).doc(uid).get()).data()?.customName, 'WiseOwl');

    // A new run is pooled with the stored custom name.
    const run2 = makeRun({ score: 45 });
    await processLive(uid, makePlayer({ best: 40, bestRun: run, recent: [run] }), makePlayer({ best: 45, bestRun: run2, recent: [run2, run] }), {
      rand: () => 0,
    });
    const e2 = (await poolEntries(pid)).find((e) => e.runId === run2.runId)!;
    assert.equal(e2.customName, 'WiseOwl');

    const cleared = await setCustomName(db, uid, '');
    assert.equal(cleared.ok, true);
    assert.equal((await poolEntries(pid)).filter((e) => e.uid === uid && 'customName' in e).length, 0);
    assert.equal((await db.collection(NAMES_COLLECTION).doc(uid).get()).exists, false);
  });

  it('refuses a bad name with its reason and changes nothing', async () => {
    const uid = uniq('cn-bad');
    await setCustomName(db, uid, 'GoodName');
    assert.deepEqual(await setCustomName(db, uid, 'xxSh1txx'), { ok: false, reason: 'blocked' });
    assert.deepEqual(await setCustomName(db, uid, 'No'), { ok: false, reason: 'length' });
    assert.deepEqual(await setCustomName(db, uid, 'No way'), { ok: false, reason: 'chars' });
    assert.equal((await db.collection(NAMES_COLLECTION).doc(uid).get()).data()?.customName, 'GoodName');
  });

  it('Delete my data removes the custom name too', async () => {
    const uid = uniq('cn-del');
    await setCustomName(db, uid, 'GoodName');
    await deletePlayerData(db, uid);
    assert.equal((await db.collection(NAMES_COLLECTION).doc(uid).get()).exists, false);
  });
});

describe('WP-NAME versusNames is closed to clients (rules)', () => {
  let env: RulesTestEnvironment;
  before(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT,
      firestore: { rules: readFileSync(join(ROOT, 'firestore.rules'), 'utf8') },
    });
  });
  after(async () => {
    await env?.cleanup();
  });

  it('the owner can neither read nor write their versusNames doc', async () => {
    const uid = uniq('cn-rules');
    const c = env.authenticatedContext(uid).firestore();
    await assertFails(getDoc(doc(c, NAMES_COLLECTION, uid)));
    await assertFails(setDoc(doc(c, NAMES_COLLECTION, uid), { customName: 'xxfuckxx' }));
  });
});

describe('WP-NAME setVersusName (emulated callable, App Check enforced)', () => {
  const url = `http://127.0.0.1:5001/${PROJECT}/europe-west1/setVersusName`;
  const idToken = (uid: string) =>
    fakeJwt({ sub: uid, user_id: uid, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, iat: 1, exp: 4e9 });
  const appCheck = fakeJwt({ sub: '1:512525012529:android:8bb85c213b543c6487cf10', aud: [`projects/${PROJECT}`] });
  const call = (headers: Record<string, string>, name: unknown) =>
    fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...headers },
      body: JSON.stringify({ data: { name } }),
    });

  it('refuses a call without App Check', async () => {
    const res = await call({ Authorization: `Bearer ${idToken('nobody')}` }, 'GoodName');
    assert.equal(res.status, 401);
  });

  it('sets, refuses with a reason, and clears', async () => {
    const uid = uniq('cn-call');
    await auth.createUser({ uid });
    const headers = { Authorization: `Bearer ${idToken(uid)}`, 'X-Firebase-AppCheck': appCheck };
    const ok = await call(headers, 'WiseOwl');
    assert.equal(ok.status, 200, await ok.clone().text());
    assert.deepEqual(((await ok.json()) as { result: unknown }).result, { ok: true, name: 'WiseOwl', updated: 0 });
    const bad = await call(headers, 'FUCKxx');
    assert.deepEqual(((await bad.json()) as { result: unknown }).result, { ok: false, reason: 'blocked' });
    const clear = await call(headers, '');
    assert.equal(((await clear.json()) as { result: { ok: boolean } }).result.ok, true);
    assert.equal((await db.collection(NAMES_COLLECTION).doc(uid).get()).exists, false);
  });
});
