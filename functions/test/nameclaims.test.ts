/**
 * WP-N2 one owner per custom name, restore and guest expiry:
 * - the claim key folds case and the look-alikes 0→o, 1/i→l, 5→s;
 * - names in the generated-nickname shape cannot be chosen;
 * - setCustomName claims the name in its transaction, refuses `taken`
 *   (answering the caller's current name), renaming frees the old claim;
 * - Delete my data (also the guest clean-up before an account switch)
 *   releases the claim only while that uid holds it;
 * - getCustomName returns the stored name, stamps the activity, claims a
 *   2.4.0 name and drops one another uid holds;
 * - the daily job releases guest names unused for 30 days (not linked
 *   ones, not when Auth cannot answer);
 * - clients can neither read nor write claims; the getVersusName callable.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { assertFails, initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { Timestamp } from 'firebase-admin/firestore';
import { checkCustomName } from '../src/customname.js';
import { CLAIMS_COLLECTION, GUEST_NAME_TTL_DAYS, isGeneratedShape, nameKey } from '../src/nameclaims.js';
import { deletePlayerData, getCustomName, releaseStaleGuestNames, setCustomName } from '../src/pools.js';
import { NAMES_COLLECTION, poolId } from '../src/schema.js';
import { auth, DAY, db, fakeJwt, makePlayer, makeRun, poolEntries, processLive, PROJECT, uniq } from './helpers.js';

const ROOT = join(__dirname, '..', '..');

/** A name unique to this test run (letters only, ≤ 14). */
let n = 0;
function fresh(prefix: string): string {
  n++;
  const tag = (Date.now() + n).toString(36).replace(/[0-9]/g, (d) => 'abcdefghij'[Number(d)]);
  return `${prefix}${tag}`.slice(0, 11) + 'x7';
}

const claim = async (name: string) => (await db.collection(CLAIMS_COLLECTION).doc(nameKey(name)).get()).data();
const nameDoc = async (uid: string) => (await db.collection(NAMES_COLLECTION).doc(uid).get()).data();

describe('WP-N2 claim keys and the generated shape', () => {
  it('folds case and the look-alikes 0→o, 1/i→l, 5→s (only those)', () => {
    const k = nameKey('Duck1');
    for (const same of ['duck1', 'DUCKl', 'DuckI', 'DUCKL', 'duckl', 'Ducki']) assert.equal(nameKey(same), k, same);
    assert.equal(nameKey('B0b'), nameKey('BOB'));
    assert.equal(nameKey('Ka5h'), nameKey('kash'));
    assert.notEqual(nameKey('Duck2'), nameKey('Duck3'));
    assert.notEqual(nameKey('Duck8'), nameKey('DuckB'));
  });

  it('a generated-shape name (either order, any case, look-alikes) cannot be chosen', () => {
    for (const g of ['SwiftKiwi482', 'swiftkiwi482', 'KIWISWIFT482', 'KiwiSwift000', 'SW1FTKIWI4O2', 'DuckTurbo111', 'MegaEmu999']) {
      assert.equal(isGeneratedShape(g), true, g);
      assert.equal(checkCustomName(g), 'blocked', g);
    }
    for (const ok of ['SwiftKiwi48', 'SwiftKiwi4821', 'WiseOwl', 'Duck1', 'KiwiKiwi482', 'MyKiwi482', 'Kiwi482']) {
      assert.equal(isGeneratedShape(ok), false, ok);
    }
    // "Swift" is both an adjective and a bird, so SwiftSwift482 can be generated.
    assert.equal(isGeneratedShape('SwiftSwift482'), true);
  });
});

describe('WP-N2 one owner per name (emulated Firestore)', () => {
  it('claims in the transaction, refuses look-alikes as taken, renaming frees the old claim', async () => {
    const a = uniq('nc-a');
    const b = uniq('nc-b');
    const base = fresh('Duck');
    const one = `${base}1`;
    assert.deepEqual(await setCustomName(db, a, one), { ok: true, name: one, updated: 0 });
    assert.equal((await claim(one))?.uid, a);
    for (const clash of [one.toLowerCase(), `${base.toUpperCase()}l`, `${base}I`, `${base}L`]) {
      assert.deepEqual(await setCustomName(db, b, clash), { ok: false, reason: 'taken', name: '' }, clash);
    }
    const bName = fresh('Hawk');
    assert.equal((await setCustomName(db, b, bName)).ok, true);
    assert.deepEqual(await setCustomName(db, b, one), { ok: false, reason: 'taken', name: bName });
    assert.equal((await nameDoc(b))?.customName, bName, 'a refusal changes nothing');

    // The owner may change the case / look-alikes of their own name.
    assert.equal((await setCustomName(db, a, `${base}l`)).ok, true);
    assert.equal((await claim(one))?.uid, a);
    assert.equal((await claim(one))?.name, `${base}l`);

    // A rename frees the old claim; the other player can take it now.
    const aNew = fresh('Goose');
    assert.equal((await setCustomName(db, a, aNew)).ok, true);
    assert.equal(await claim(one), undefined);
    assert.equal((await claim(aNew))?.uid, a);
    assert.equal((await setCustomName(db, b, `${base}I`)).ok, true);
    assert.equal(await claim(bName), undefined, "b's old claim is gone");
    assert.equal((await claim(one))?.uid, b);

    // Clearing frees it too.
    assert.equal((await setCustomName(db, a, '')).ok, true);
    assert.equal(await claim(aNew), undefined);
    assert.equal(await nameDoc(a), undefined);
  });

  it('a set stamps the activity: guests get guestSeen, linked players not', async () => {
    const g = uniq('nc-g');
    const l = uniq('nc-l');
    const now = Date.now();
    await setCustomName(db, g, fresh('Guest'), now);
    await setCustomName(db, l, fresh('Link'), now, { linked: true });
    const gd = await nameDoc(g);
    assert.equal(gd?.linked, false);
    assert.equal((gd?.guestSeen as Timestamp).toMillis(), now);
    assert.equal((gd?.lastSeen as Timestamp).toMillis(), now);
    const ld = await nameDoc(l);
    assert.equal(ld?.linked, true);
    assert.equal(ld?.guestSeen, undefined);
  });

  it('Delete my data releases the claim, only while that uid holds it', async () => {
    const a = uniq('nc-del');
    const name = fresh('Gone');
    await setCustomName(db, a, name);
    await deletePlayerData(db, a);
    assert.equal(await claim(name), undefined);
    assert.equal(await nameDoc(a), undefined);

    // A guest whose (2.4.0, unclaimed) name equals the account's: the
    // account keeps the claim when the guest is cleaned up.
    const account = uniq('nc-acc');
    const guest = uniq('nc-guest');
    const shared = fresh('Same');
    await setCustomName(db, account, shared, Date.now(), { linked: true });
    await db.collection(NAMES_COLLECTION).doc(guest).set({ customName: shared, updatedAt: Timestamp.now() });
    await deletePlayerData(db, guest);
    assert.equal((await claim(shared))?.uid, account);
    assert.equal((await nameDoc(account))?.customName, shared);
  });

  it('getCustomName returns the name, stamps activity, claims a 2.4.0 name and drops a clash', async () => {
    const uid = uniq('nc-get');
    assert.deepEqual(await getCustomName(db, uid), { ok: true, name: '' });
    assert.equal(await nameDoc(uid), undefined, 'no name: nothing written');

    const name = fresh('Back');
    const t0 = Date.now() - 5 * DAY;
    await setCustomName(db, uid, name, t0);
    // Within 12 h: no rewrite; later: lastSeen / guestSeen move on.
    assert.deepEqual(await getCustomName(db, uid, t0 + 3600_000), { ok: true, name });
    assert.equal(((await nameDoc(uid))?.lastSeen as Timestamp).toMillis(), t0);
    const t1 = t0 + 2 * DAY;
    await getCustomName(db, uid, t1);
    assert.equal(((await nameDoc(uid))?.guestSeen as Timestamp).toMillis(), t1);
    // Linked now: the guest stamp goes at once.
    await getCustomName(db, uid, t1 + 1000, { linked: true });
    assert.equal((await nameDoc(uid))?.linked, true);
    assert.equal((await nameDoc(uid))?.guestSeen, undefined);

    // A 2.4.0 doc without a claim takes it on read.
    const legacy = uniq('nc-legacy');
    const lname = fresh('Old');
    await db.collection(NAMES_COLLECTION).doc(legacy).set({ customName: lname, updatedAt: Timestamp.now() });
    assert.deepEqual(await getCustomName(db, legacy), { ok: true, name: lname });
    assert.equal((await claim(lname))?.uid, legacy);
    // A second 2.4.0 holder of the same name loses it (cleared).
    const late = uniq('nc-late');
    await db.collection(NAMES_COLLECTION).doc(late).set({ customName: lname.toUpperCase(), updatedAt: Timestamp.now() });
    assert.deepEqual(await getCustomName(db, late), { ok: true, name: '' });
    assert.equal(await nameDoc(late), undefined);
    assert.equal((await claim(lname))?.uid, legacy);
  });
});

describe(`WP-N2 guest names are released after ${GUEST_NAME_TTL_DAYS} days`, () => {
  it('releases stale guests (claim, doc, pool entries); keeps fresh, linked and unknown ones', async () => {
    const now = Date.now();
    const stale = uniq('nc-stale');
    const freshGuest = uniq('nc-fresh');
    const linkedLater = uniq('nc-linked');
    const authDown = uniq('nc-down');
    const names = {
      stale: fresh('Stale'),
      fresh: fresh('Fresh'),
      linked: fresh('Linked'),
      down: fresh('Down'),
    };
    // The stale guest has a pooled run carrying the name.
    const run = makeRun({ score: 40 });
    await processLive(stale, undefined, makePlayer({ best: 40, bestRun: run, recent: [run] }), { rand: () => 0 });
    const old = now - (GUEST_NAME_TTL_DAYS + 1) * DAY;
    await setCustomName(db, stale, names.stale, old);
    await setCustomName(db, freshGuest, names.fresh, now - (GUEST_NAME_TTL_DAYS - 1) * DAY);
    await setCustomName(db, linkedLater, names.linked, old);
    await setCustomName(db, authDown, names.down, old);
    const pid = poolId(1, 0);
    assert.equal((await poolEntries(pid)).find((e) => e.runId === run.runId)?.customName, names.stale);

    const mine = new Set([stale, freshGuest, linkedLater, authDown]);
    const released = await releaseStaleGuestNames(db, async (uid) => {
      if (uid === linkedLater) return true;
      if (uid === authDown) return null;
      return mine.has(uid) ? false : true; // other tests' docs: keep
    }, now, 1);
    assert.deepEqual(released, [stale]);
    assert.equal(await nameDoc(stale), undefined);
    assert.equal(await claim(names.stale), undefined);
    assert.equal((await poolEntries(pid)).find((e) => e.runId === run.runId)?.customName, undefined);
    assert.equal((await claim(names.fresh))?.uid, freshGuest);
    assert.equal((await claim(names.linked))?.uid, linkedLater);
    assert.equal((await nameDoc(linkedLater))?.linked, true);
    assert.equal((await nameDoc(linkedLater))?.guestSeen, undefined, 'linked now: never expires');
    assert.equal((await claim(names.down))?.uid, authDown, 'Auth did not answer: kept');
    // The released name is free for anyone.
    assert.equal((await setCustomName(db, uniq('nc-new'), names.stale)).ok, true);
  });
});

describe('WP-N2 claims are closed to clients (rules)', () => {
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

  it('nobody can read or write a claim', async () => {
    const uid = uniq('nc-rules');
    const c = env.authenticatedContext(uid).firestore();
    await assertFails(getDoc(doc(c, CLAIMS_COLLECTION, 'duckl')));
    await assertFails(setDoc(doc(c, CLAIMS_COLLECTION, 'duckl'), { uid }));
  });
});

describe('WP-N2 getVersusName / setVersusName taken (emulated callables)', () => {
  const base = `http://127.0.0.1:5001/${PROJECT}/europe-west1`;
  const idToken = (uid: string) =>
    fakeJwt({ sub: uid, user_id: uid, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, iat: 1, exp: 4e9 });
  const appCheck = fakeJwt({ sub: '1:512525012529:android:8bb85c213b543c6487cf10', aud: [`projects/${PROJECT}`] });
  const call = async (fn: string, uid: string, data: unknown, withAppCheck = true) => {
    const res = await fetch(`${base}/${fn}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${idToken(uid)}`,
        ...(withAppCheck ? { 'X-Firebase-AppCheck': appCheck } : {}),
      },
      body: JSON.stringify({ data }),
    });
    return { status: res.status, result: ((await res.json()) as { result?: unknown }).result };
  };

  it('restores the stored name; a name another uid holds answers taken', async () => {
    const a = uniq('nc-ca');
    const b = uniq('nc-cb');
    await auth.createUser({ uid: a });
    await auth.createUser({ uid: b });
    assert.equal((await call('getVersusName', a, {}, false)).status, 401, 'App Check enforced');
    assert.deepEqual((await call('getVersusName', a, {})).result, { ok: true, name: '' });
    const name = fresh('Call');
    assert.equal(((await call('setVersusName', a, { name })).result as { ok: boolean }).ok, true);
    assert.deepEqual((await call('getVersusName', a, {})).result, { ok: true, name });
    assert.deepEqual((await call('setVersusName', b, { name: name.toUpperCase() })).result, {
      ok: false,
      reason: 'taken',
      name: '',
    });
    assert.equal((await nameDoc(a))?.linked, false, 'an anonymous user is a guest');
  });
});
