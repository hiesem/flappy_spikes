/**
 * PRD-2.5 §3.8 WP-IAP: verifyPurchase / sweepVoidedPurchases logic on
 * recorded store fixtures (no live store call), the records in the
 * Firestore emulator, the deleteMyData `firstUid` clean-up and the callable
 * through the functions emulator (input validation, App Check).
 */
import assert from 'node:assert/strict';
import { X509Certificate } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { assertFails, initializeTestEnvironment, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import {
  appleRootCerts,
  type AppleApi,
  type AppleTransaction,
  clearPurchaseUid,
  handleVerifyPurchase,
  type HttpAnswer,
  IAP_META_DOC,
  listVoided,
  makeAppleApi,
  parseVerifyInput,
  type PurchaseDeps,
  purchaseDocId,
  PURCHASES_COLLECTION,
  SWEEP_MAX_BACK_MS,
  sweepVoided,
  verifyAndroid,
  verifyIos,
} from '../src/purchases.js';
import { db, fakeJwt, PROJECT, uniq } from './helpers.js';

const FIX = join(__dirname, 'fixtures', 'purchases');
function fixture(name: string): HttpAnswer {
  const f = JSON.parse(readFileSync(join(FIX, `${name}.json`), 'utf8')) as HttpAnswer;
  return { status: f.status, body: f.body };
}

/** Play GET stub: answers [answer] (or a function of the URL) and records the URLs. */
function play(answer: HttpAnswer | ((url: string) => HttpAnswer) | Error) {
  const urls: string[] = [];
  const playGet = async (url: string) => {
    urls.push(url);
    if (answer instanceof Error) throw answer;
    return typeof answer === 'function' ? answer(url) : answer;
  };
  return { urls, deps: { playGet, apple: null } as PurchaseDeps };
}

const APPLE = JSON.parse(readFileSync(join(FIX, 'apple_transactions.json'), 'utf8')) as Record<
  string,
  Record<string, AppleTransaction | null>
>;

/** Fake Apple client over the fixture table; records the lookups. */
function apple(fail?: Error) {
  const calls: string[] = [];
  const api: AppleApi = {
    async lookup(env, id) {
      calls.push(`${env}:${id}`);
      if (fail) throw fail;
      const row = APPLE[id];
      if (!row || !(env in row)) throw new Error('unexpected lookup');
      return row[env] ?? null;
    },
  };
  return { calls, deps: { playGet: async () => assert.fail('no Play call'), apple: api } as PurchaseDeps };
}

const TOKEN = () => `tok-${uniq('p')}-abcdefghijklmnopqrstuvwxyz`;

describe('WP-IAP input validation', () => {
  it('accepts the 7 products with a plausible token', () => {
    for (const productId of ['coins_1000', 'coins_10000', 'coins_17000', 'coins_100000', 'no_ads', 'gift_coins_10000', 'gift_noads_coins_10000']) {
      assert.ok(parseVerifyInput({ platform: 'android', productId, token: 'a'.repeat(40) }));
    }
    assert.deepEqual(parseVerifyInput({ platform: 'ios', productId: 'no_ads', token: '2000000000000001' }), {
      platform: 'ios',
      productId: 'no_ads',
      token: '2000000000000001',
    });
  });

  it('refuses unknown products, platforms and token shapes', () => {
    for (const bad of [
      null,
      'x',
      {},
      { platform: 'web', productId: 'no_ads', token: 'a'.repeat(40) },
      { platform: 'android', productId: 'skin_gold', token: 'a'.repeat(40) },
      { platform: 'android', productId: 'no_ads', token: 'short' },
      { platform: 'android', productId: 'no_ads', token: 'a'.repeat(1025) },
      { platform: 'android', productId: 'no_ads', token: 'a b'.repeat(20) },
      { platform: 'android', productId: 'no_ads', token: 42 },
      { platform: 'ios', productId: 'no_ads', token: 'abc' },
      { platform: 'ios', productId: 'no_ads', token: '1'.repeat(41) },
    ]) {
      assert.equal(parseVerifyInput(bad), null, JSON.stringify(bad));
    }
  });
});

describe('WP-IAP Play verdicts (recorded fixtures)', () => {
  it('PURCHASED of that product → valid, on the productsv2 URL', async () => {
    const p = play(fixture('play_purchased'));
    const v = await verifyAndroid(p.deps, 'no_ads', 'tok/en+1');
    assert.equal(v.status, 'valid');
    assert.equal(v.test, false);
    assert.equal(
      p.urls[0],
      'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.flappyspikes.flappy_spikes/purchases/productsv2/tokens/tok%2Fen%2B1',
    );
  });

  it('a license-tester (TEST), consumed and unacknowledged pack → valid, test', async () => {
    const v = await verifyAndroid(play(fixture('play_test_consumed')).deps, 'coins_1000', 'x');
    assert.deepEqual([v.status, v.test], ['valid', true]);
  });

  it('PENDING / CANCELLED → unknown (never fake)', async () => {
    assert.equal((await verifyAndroid(play(fixture('play_pending')).deps, 'coins_10000', 'x')).status, 'unknown');
    assert.equal((await verifyAndroid(play(fixture('play_cancelled')).deps, 'no_ads', 'x')).status, 'unknown');
  });

  it('404 / 410 / 400 purchaseToken… → invalid', async () => {
    assert.equal((await verifyAndroid(play(fixture('play_404')).deps, 'no_ads', 'x')).status, 'invalid');
    assert.equal((await verifyAndroid(play({ status: 410, body: null }).deps, 'no_ads', 'x')).status, 'invalid');
    assert.equal((await verifyAndroid(play(fixture('play_400_token')).deps, 'no_ads', 'x')).status, 'invalid');
  });

  it('a real purchase of a different product → invalid', async () => {
    assert.equal((await verifyAndroid(play(fixture('play_other_product')).deps, 'coins_100000', 'x')).status, 'invalid');
  });

  it('403 (no Play Console grant yet), other 400, 5xx, 429, network, bad body → unknown', async () => {
    for (const a of [
      fixture('play_403'),
      fixture('play_400_other'),
      { status: 500, body: null },
      { status: 503, body: null },
      { status: 429, body: null },
      { status: 401, body: null },
      { status: 200, body: null },
    ]) {
      assert.equal((await verifyAndroid(play(a).deps, 'no_ads', 'x')).status, 'unknown', JSON.stringify(a.status));
    }
    assert.equal((await verifyAndroid(play(new Error('ECONNRESET')).deps, 'no_ads', 'x')).status, 'unknown');
  });
});

describe('WP-IAP App Store verdicts (fake client on fixtures)', () => {
  it('found in Production → valid', async () => {
    const a = apple();
    const v = await verifyIos(a.deps, 'no_ads', '2000000000000001');
    assert.deepEqual([v.status, v.test], ['valid', false]);
    assert.deepEqual(a.calls, ['Production:2000000000000001']);
  });

  it('Production 4040010 → Sandbox found → valid, test', async () => {
    const a = apple();
    const v = await verifyIos(a.deps, 'coins_1000', '2000000000000002');
    assert.deepEqual([v.status, v.test], ['valid', true]);
    assert.deepEqual(a.calls, ['Production:2000000000000002', 'Sandbox:2000000000000002']);
  });

  it('revocationDate → revoked', async () => {
    assert.equal((await verifyIos(apple().deps, 'no_ads', '2000000000000003')).status, 'revoked');
  });

  it('4040010 in both environments, another bundle, another product → invalid', async () => {
    assert.equal((await verifyIos(apple().deps, 'no_ads', '2000000000000004')).status, 'invalid');
    assert.equal((await verifyIos(apple().deps, 'no_ads', '2000000000000005')).status, 'invalid');
    assert.equal((await verifyIos(apple().deps, 'coins_100000', '2000000000000001')).status, 'invalid');
  });

  it('no key configured, or any API / verification error → unknown', async () => {
    assert.equal((await verifyIos({ playGet: play(fixture('play_403')).deps.playGet, apple: null }, 'no_ads', '1')).status, 'unknown');
    assert.equal((await verifyIos(apple(new Error('401')).deps, 'no_ads', '2000000000000001')).status, 'unknown');
  });

  it('makeAppleApi is null while the secret / ids are missing or placeholders', async () => {
    const key = '-----BEGIN PRIVATE KEY-----\nMIG...\n-----END PRIVATE KEY-----';
    assert.equal(await makeAppleApi({}), null);
    assert.equal(await makeAppleApi({ key: '', keyId: 'K', issuerId: 'I' }), null);
    assert.equal(await makeAppleApi({ key: 'unset', keyId: 'K', issuerId: 'I' }), null);
    assert.equal(await makeAppleApi({ key: 'not a key', keyId: 'K', issuerId: 'I' }), null);
    assert.equal(await makeAppleApi({ key, keyId: 'unset', issuerId: 'I' }), null);
    assert.equal(await makeAppleApi({ key, keyId: 'K', issuerId: undefined }), null);
  });

  it('the committed Apple root certificates are G2 + G3', () => {
    const subjects = appleRootCerts().map((b) => new X509Certificate(b).subject);
    assert.deepEqual(
      subjects.map((s) => /CN=([^\n]+)/.exec(s)?.[1]),
      ['Apple Root CA - G2', 'Apple Root CA - G3'],
    );
  });
});

describe('WP-IAP records (Firestore emulator)', () => {
  const read = async (platform: 'android' | 'ios', token: string) =>
    (await db.collection(PURCHASES_COLLECTION).doc(purchaseDocId(platform, token)).get()).data();

  it('writes the record keyed by sha256(platform:token); firstUid kept from the first caller', async () => {
    const token = TOKEN();
    const p = play(fixture('play_test_consumed'));
    const r1 = await handleVerifyPurchase(db, p.deps, { platform: 'android', productId: 'coins_1000', token }, 'uid-a', 1000);
    assert.deepEqual(r1, { status: 'valid' });
    assert.match(purchaseDocId('android', token), /^[0-9a-f]{64}$/);
    let rec = await read('android', token);
    assert.deepEqual(rec, { platform: 'android', productId: 'coins_1000', status: 'valid', test: true, firstUid: 'uid-a', lastCheckedMs: 1000 });
    // Idempotent; a second caller does not replace firstUid; no uid is fine.
    await handleVerifyPurchase(db, p.deps, { platform: 'android', productId: 'coins_1000', token }, 'uid-b', 2000);
    await handleVerifyPurchase(db, p.deps, { platform: 'android', productId: 'coins_1000', token }, undefined, 3000);
    rec = await read('android', token);
    assert.equal(rec?.firstUid, 'uid-a');
    assert.equal(rec?.lastCheckedMs, 3000);
    // The raw token is never stored.
    assert.ok(!JSON.stringify(rec).includes(token));
  });

  it('no uid → no firstUid', async () => {
    const token = TOKEN();
    await handleVerifyPurchase(db, play(fixture('play_purchased')).deps, { platform: 'android', productId: 'no_ads', token }, undefined, 1);
    assert.equal((await read('android', token))?.firstUid, undefined);
  });

  it('unknown never overwrites an earlier store answer', async () => {
    const token = TOKEN();
    const input = { platform: 'android' as const, productId: 'no_ads', token };
    await handleVerifyPurchase(db, play(fixture('play_purchased')).deps, input, undefined, 1);
    const r = await handleVerifyPurchase(db, play(fixture('play_403')).deps, input, undefined, 2);
    assert.equal(r.status, 'unknown');
    assert.equal((await read('android', token))?.status, 'valid');
  });

  it('a token seen valid is never called invalid later (expired store record) → unknown', async () => {
    const token = TOKEN();
    const input = { platform: 'android' as const, productId: 'no_ads', token };
    await handleVerifyPurchase(db, play(fixture('play_purchased')).deps, input, undefined, 1);
    const r = await handleVerifyPurchase(db, play({ status: 410, body: null }).deps, input, undefined, 2);
    assert.equal(r.status, 'unknown');
    assert.equal((await read('android', token))?.status, 'valid');
  });

  it('a fake token → invalid and recorded', async () => {
    const token = TOKEN();
    const r = await handleVerifyPurchase(db, play(fixture('play_404')).deps, { platform: 'android', productId: 'coins_100000', token }, 'u', 1);
    assert.equal(r.status, 'invalid');
    assert.equal((await read('android', token))?.status, 'invalid');
  });

  it('iOS records under their own platform', async () => {
    const r = await handleVerifyPurchase(db, apple().deps, { platform: 'ios', productId: 'no_ads', token: '2000000000000003' }, undefined, 5);
    assert.equal(r.status, 'revoked');
    assert.equal((await read('ios', '2000000000000003'))?.status, 'revoked');
  });
});

describe('WP-IAP voided-purchases sweep', () => {
  beforeEach(async () => {
    await db.doc(IAP_META_DOC).delete();
  });

  function pagedPlay() {
    return play((url) => (new URL(url).searchParams.get('token') === 'page-2-token' ? fixture('voided_page2') : fixture('voided_page1')));
  }

  it('pages through nextPageToken (type 0, startTime)', async () => {
    const p = pagedPlay();
    const v = await listVoided(p.deps, 1234.5);
    assert.deepEqual(
      v.map((x) => x.purchaseToken),
      ['voided-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'voided-token-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'voided-token-cccccccccccccccccccccccccccccc'],
    );
    assert.equal(v[0]!.voidedTimeMillis, 1760900000000);
    assert.equal(v[1]!.voidedReason, 7);
    assert.equal(p.urls.length, 2);
    const q1 = new URL(p.urls[0]!).searchParams;
    assert.equal(q1.get('startTime'), '1234');
    assert.equal(q1.get('type'), '0');
    assert.equal(q1.get('token'), null);
    assert.ok(p.urls[0]!.includes('/applications/com.flappyspikes.flappy_spikes/purchases/voidedpurchases?'));
    assert.equal(new URL(p.urls[1]!).searchParams.get('token'), 'page-2-token');
  });

  it('marks known and unknown tokens revoked; a later verify answers revoked', async () => {
    const known = 'voided-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    await db.collection(PURCHASES_COLLECTION).doc(purchaseDocId('android', known)).set({
      platform: 'android', productId: 'no_ads', status: 'valid', test: false, firstUid: 'u1', lastCheckedMs: 1,
    });
    const now = Date.UTC(2026, 9, 20);
    assert.equal(await sweepVoided(db, pagedPlay().deps, now), 3);
    const a = (await db.collection(PURCHASES_COLLECTION).doc(purchaseDocId('android', known)).get()).data();
    assert.deepEqual(a, {
      platform: 'android', productId: 'no_ads', status: 'revoked', test: false, firstUid: 'u1', lastCheckedMs: 1,
      voidedMs: 1760900000000, voidedReason: 1,
    });
    const c = (await db.collection(PURCHASES_COLLECTION).doc(purchaseDocId('android', 'voided-token-cccccccccccccccccccccccccccccc')).get()).data();
    assert.equal(c?.status, 'revoked');
    // Play still says PURCHASED (or CANCELLED): the sweep's verdict wins.
    const r = await handleVerifyPurchase(db, play(fixture('play_purchased')).deps, { platform: 'android', productId: 'no_ads', token: known }, undefined, now);
    assert.equal(r.status, 'revoked');
    assert.equal((await db.doc(IAP_META_DOC).get()).data()?.lastRunMs, now);
  });

  it('start = last run − 1 day, never more than SWEEP_MAX_BACK_MS back', async () => {
    const DAY = 24 * 3600 * 1000;
    const now = Date.UTC(2026, 9, 20);
    const empty = () => play({ status: 200, body: {} });
    let p = empty();
    await sweepVoided(db, p.deps, now);
    assert.equal(new URL(p.urls[0]!).searchParams.get('startTime'), String(now - SWEEP_MAX_BACK_MS));
    p = empty();
    await sweepVoided(db, p.deps, now + DAY);
    assert.equal(new URL(p.urls[0]!).searchParams.get('startTime'), String(now - DAY));
    await db.doc(IAP_META_DOC).set({ lastRunMs: now - 90 * DAY });
    p = empty();
    await sweepVoided(db, p.deps, now);
    assert.equal(new URL(p.urls[0]!).searchParams.get('startTime'), String(now - SWEEP_MAX_BACK_MS));
  });

  it('a failed page keeps the old start time', async () => {
    await db.doc(IAP_META_DOC).set({ lastRunMs: 5 });
    await assert.rejects(sweepVoided(db, play(fixture('play_403')).deps, Date.now()));
    assert.equal((await db.doc(IAP_META_DOC).get()).data()?.lastRunMs, 5);
  });
});

describe('WP-IAP privacy and access', () => {
  let env: RulesTestEnvironment;
  before(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT,
      firestore: { rules: readFileSync(join(__dirname, '..', '..', 'firestore.rules'), 'utf8') },
    });
  });
  after(async () => {
    await env?.cleanup();
  });

  it('clients can neither read nor write purchases/ or iapMeta/', async () => {
    const id = purchaseDocId('android', TOKEN());
    await db.collection(PURCHASES_COLLECTION).doc(id).set({ platform: 'android', status: 'valid', firstUid: 'me' });
    const me = env.authenticatedContext('me').firestore();
    await assertFails(getDoc(doc(me, PURCHASES_COLLECTION, id)));
    await assertFails(setDoc(doc(me, PURCHASES_COLLECTION, id), { status: 'valid' }));
    await assertFails(getDoc(doc(me, 'iapMeta', 'voidedSweep')));
  });

  it('clearPurchaseUid drops firstUid and keeps the record', async () => {
    const uid = uniq('del');
    const ids = [purchaseDocId('android', TOKEN()), purchaseDocId('ios', '2000000000000001' + Date.now())];
    for (const id of ids) {
      await db.collection(PURCHASES_COLLECTION).doc(id).set({ platform: 'android', status: 'valid', firstUid: uid, lastCheckedMs: 1 });
    }
    const other = purchaseDocId('android', TOKEN());
    await db.collection(PURCHASES_COLLECTION).doc(other).set({ platform: 'android', status: 'valid', firstUid: 'someone-else' });
    assert.equal(await clearPurchaseUid(db, uid), 2);
    for (const id of ids) {
      const d = (await db.collection(PURCHASES_COLLECTION).doc(id).get()).data();
      assert.deepEqual(d, { platform: 'android', status: 'valid', lastCheckedMs: 1 });
    }
    assert.equal((await db.collection(PURCHASES_COLLECTION).doc(other).get()).data()?.firstUid, 'someone-else');
    assert.equal(await clearPurchaseUid(db, uid), 0, 'idempotent');
  });
});

describe('WP-IAP callables (functions emulator)', () => {
  const base = `http://127.0.0.1:5001/${PROJECT}/europe-west1`;
  const appCheck = fakeJwt({ sub: '1:512525012529:android:8bb85c213b543c6487cf10', aud: [`projects/${PROJECT}`] });
  const idToken = (uid: string) =>
    fakeJwt({ sub: uid, user_id: uid, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, iat: 1, exp: 4e9 });
  const call = (fn: string, data: unknown, headers: Record<string, string>) =>
    fetch(`${base}/${fn}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...headers },
      body: JSON.stringify({ data }),
    });

  it('verifyPurchase without App Check is refused', async () => {
    const res = await call('verifyPurchase', { platform: 'android', productId: 'no_ads', token: 'a'.repeat(40) }, {});
    assert.equal(res.status, 401);
  });

  it('verifyPurchase refuses bad input with invalid-argument (no sign-in needed)', async () => {
    for (const data of [{}, { platform: 'android', productId: 'free_money', token: 'a'.repeat(40) }, { platform: 'ios', productId: 'no_ads', token: 'x' }]) {
      const res = await call('verifyPurchase', data, { 'X-Firebase-AppCheck': appCheck });
      assert.equal(res.status, 400, JSON.stringify(data));
      const body = (await res.json()) as { error?: { status?: string } };
      assert.equal(body.error?.status, 'INVALID_ARGUMENT');
    }
  });

  it('deleteMyData clears the caller\'s firstUid on purchase records', async () => {
    const uid = uniq('delfn');
    const id = purchaseDocId('android', TOKEN());
    await db.collection(PURCHASES_COLLECTION).doc(id).set({ platform: 'android', status: 'valid', firstUid: uid });
    const res = await call('deleteMyData', {}, { Authorization: `Bearer ${idToken(uid)}`, 'X-Firebase-AppCheck': appCheck });
    assert.equal(res.status, 200);
    const d = (await db.collection(PURCHASES_COLLECTION).doc(id).get()).data();
    assert.deepEqual(d, { platform: 'android', status: 'valid' });
  });
});
