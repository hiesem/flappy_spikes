/**
 * PRD-2.5 §3.8 WP-IAP — server purchase verification (D2).
 *
 * The app grants every purchase at once (offline too) and asks
 * `verifyPurchase` later; the answer only ever adds information:
 * - `valid`: the store knows the purchase (license-tester purchases too,
 *   recorded `test: true`);
 * - `revoked`: refunded / voided (Apple `revocationDate`, or the daily
 *   voided-purchases sweep marked the token);
 * - `invalid`: a DEFINITE store answer that the purchase does not exist
 *   (Play 400 purchaseToken… / 404 / 410, Apple 4040010 in both
 *   environments, or a real purchase of another product / app);
 * - `unknown`: everything else (auth, quota, 5xx, network, missing Play
 *   Console grant, missing Apple key, pending / cancelled). The client
 *   retries later. This is the false-positive guard: a check that cannot
 *   answer never accuses an honest player.
 *
 * Records live in `purchases/{sha256(platform + ':' + token)}` (Admin SDK
 * only; the rules deny clients). Everything store-facing goes through
 * [PurchaseDeps] so the tests run on recorded fixtures.
 */
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { GoogleAuth } from 'google-auth-library';

/** Play package and App Store app (PRD §3.8). */
export const ANDROID_PACKAGE = 'com.flappyspikes.flappy_spikes';
export const IOS_BUNDLE_ID = 'com.flappyspikes.flappyspikes';
export const IOS_APP_APPLE_ID = 6823208616;

/** The 7 store products (lib/services/iap_service.dart `IapProduct.storeId`). */
export const PRODUCT_IDS: readonly string[] = [
  'coins_1000',
  'coins_10000',
  'coins_17000',
  'coins_100000',
  'no_ads',
  'gift_coins_10000',
  'gift_noads_coins_10000',
];

export const PURCHASES_COLLECTION = 'purchases';
/** The sweep's own bookkeeping (`lastRunMs`), Admin SDK only. */
export const IAP_META_DOC = 'iapMeta/voidedSweep';

export type Platform = 'android' | 'ios';
export type VerifyStatus = 'valid' | 'revoked' | 'invalid' | 'unknown';

/** What one store check found. */
export interface StoreVerdict {
  status: VerifyStatus;
  /** A license-tester / sandbox purchase. */
  test?: boolean;
  /** Short machine reason for the log (never the token). */
  why: string;
}

/** A plain HTTP answer (status + parsed JSON body, or null). */
export interface HttpAnswer {
  status: number;
  body: unknown;
}

/** One App Store transaction as the signed-data verifier decoded it. */
export interface AppleTransaction {
  bundleId?: string;
  productId?: string;
  revocationDate?: number;
  environment?: string;
}

/** Apple lookups (one environment each). */
export interface AppleApi {
  /**
   * The verified, decoded transaction; `null` = Apple answered 4040010
   * (TransactionIdNotFound) in that environment. Any other failure throws.
   */
  lookup(environment: 'Production' | 'Sandbox', transactionId: string): Promise<AppleTransaction | null>;
}

export interface PurchaseDeps {
  /** GET a Google Play Developer API URL with the function's own credentials. */
  playGet(url: string): Promise<HttpAnswer>;
  /** null = the App Store key is not configured: every iOS check is `unknown`. */
  apple: AppleApi | null;
}

// region input validation

export interface VerifyInput {
  platform: Platform;
  productId: string;
  token: string;
}

/** Play purchase tokens: url-safe characters, well under 1 KB. */
const ANDROID_TOKEN = /^[A-Za-z0-9._:\-]{20,1024}$/;
/** StoreKit transaction ids: digits. */
const IOS_TOKEN = /^[0-9]{1,40}$/;

/** The validated callable input, or null (→ `invalid-argument`). */
export function parseVerifyInput(data: unknown): VerifyInput | null {
  if (data === null || typeof data !== 'object') return null;
  const d = data as Record<string, unknown>;
  const { platform, productId, token } = d;
  if (platform !== 'android' && platform !== 'ios') return null;
  if (typeof productId !== 'string' || !PRODUCT_IDS.includes(productId)) return null;
  if (typeof token !== 'string') return null;
  if (!(platform === 'android' ? ANDROID_TOKEN : IOS_TOKEN).test(token)) return null;
  return { platform, productId, token };
}

// endregion

/** The record id: sha256(platform + ':' + token), hex. */
export function purchaseDocId(platform: Platform, token: string): string {
  return createHash('sha256').update(`${platform}:${token}`).digest('hex');
}

// region Google Play

const PLAY_BASE = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${ANDROID_PACKAGE}`;

function playErrorReasons(body: unknown): string[] {
  const errors = (body as { error?: { errors?: { reason?: unknown }[] } } | null)?.error?.errors;
  if (!Array.isArray(errors)) return [];
  return errors.map((e) => (typeof e?.reason === 'string' ? e.reason : '')).filter((r) => r);
}

/**
 * `purchases.productsv2.getproductpurchasev2` for [token] and the verdict for
 * [productId]. Never throws (a transport failure is `unknown`).
 */
export async function verifyAndroid(deps: PurchaseDeps, productId: string, token: string): Promise<StoreVerdict> {
  let answer: HttpAnswer;
  try {
    answer = await deps.playGet(`${PLAY_BASE}/purchases/productsv2/tokens/${encodeURIComponent(token)}`);
  } catch (err) {
    return { status: 'unknown', why: `play_fetch:${errName(err)}` };
  }
  const { status, body } = answer;
  if (status === 404 || status === 410) return { status: 'invalid', why: `play_${status}` };
  if (status === 400) {
    // Only a token the store itself rejects is fake; any other 400 (a
    // malformed request on our side) stays unknown.
    const reasons = playErrorReasons(body);
    if (reasons.some((r) => /purchaseToken/i.test(r))) return { status: 'invalid', why: `play_400:${reasons.join(',')}` };
    return { status: 'unknown', why: `play_400:${reasons.join(',') || '-'}` };
  }
  if (status < 200 || status >= 300) return { status: 'unknown', why: `play_${status}` };
  const p = body as {
    productLineItem?: { productId?: unknown }[];
    purchaseStateContext?: { purchaseState?: unknown };
    testPurchaseContext?: { fopType?: unknown };
    acknowledgementState?: unknown;
  } | null;
  if (!p || typeof p !== 'object') return { status: 'unknown', why: 'play_body' };
  const state = p.purchaseStateContext?.purchaseState;
  const test = p.testPurchaseContext?.fopType === 'TEST';
  if (state !== 'PURCHASED') return { status: 'unknown', test, why: `play_state:${String(state)}` };
  const items = Array.isArray(p.productLineItem) ? p.productLineItem : [];
  const ids = items.map((i) => i?.productId).filter((x): x is string => typeof x === 'string');
  // A real purchase of another product: the token was moved onto a
  // different (more valuable) grant.
  if (!ids.includes(productId)) return { status: 'invalid', test, why: `play_product:${ids.join(',')}` };
  return { status: 'valid', test, why: `play_ok:ack=${String(p.acknowledgementState ?? '-')}` };
}

/** One voided Play purchase (`purchases.voidedpurchases.list`). */
export interface VoidedPurchase {
  purchaseToken: string;
  voidedTimeMillis: number;
  voidedReason: number | null;
  voidedSource: number | null;
}

/**
 * Pages through `purchases.voidedpurchases.list` (type 0 = one-time
 * products) from [startMs]. Throws on any non-2xx page (the sweep then
 * keeps its old start time and tries again tomorrow).
 */
export async function listVoided(deps: PurchaseDeps, startMs: number, maxPages = 50): Promise<VoidedPurchase[]> {
  const out: VoidedPurchase[] = [];
  let pageToken: string | undefined;
  for (let page = 0; page < maxPages; page++) {
    const q = new URLSearchParams({ startTime: String(Math.floor(startMs)), type: '0', maxResults: '1000' });
    if (pageToken) q.set('token', pageToken);
    const { status, body } = await deps.playGet(`${PLAY_BASE}/purchases/voidedpurchases?${q}`);
    if (status < 200 || status >= 300) throw new Error(`voidedpurchases ${status}`);
    const b = (body ?? {}) as {
      voidedPurchases?: Record<string, unknown>[];
      tokenPagination?: { nextPageToken?: unknown };
    };
    for (const v of b.voidedPurchases ?? []) {
      if (typeof v.purchaseToken !== 'string' || !v.purchaseToken) continue;
      out.push({
        purchaseToken: v.purchaseToken,
        voidedTimeMillis: Number(v.voidedTimeMillis) || 0,
        voidedReason: v.voidedReason === undefined ? null : Number(v.voidedReason),
        voidedSource: v.voidedSource === undefined ? null : Number(v.voidedSource),
      });
    }
    const next = b.tokenPagination?.nextPageToken;
    if (typeof next !== 'string' || !next) return out;
    pageToken = next;
  }
  logger.warn('listVoided: page cap reached', { maxPages });
  return out;
}

// endregion

// region App Store

/**
 * App Store Server API lookup: Production first, Sandbox when Production
 * does not know the id (TestFlight / StoreKit sandbox purchases). Never
 * throws.
 */
export async function verifyIos(deps: PurchaseDeps, productId: string, transactionId: string): Promise<StoreVerdict> {
  const apple = deps.apple;
  if (!apple) return { status: 'unknown', why: 'apple_no_key' };
  let tx: AppleTransaction | null;
  let sandbox = false;
  try {
    tx = await apple.lookup('Production', transactionId);
    if (tx === null) {
      sandbox = true;
      tx = await apple.lookup('Sandbox', transactionId);
    }
  } catch (err) {
    return { status: 'unknown', why: `apple:${errName(err)}` };
  }
  if (tx === null) return { status: 'invalid', why: 'apple_4040010_both' };
  if (tx.bundleId !== IOS_BUNDLE_ID) return { status: 'invalid', test: sandbox, why: 'apple_bundle' };
  if (tx.productId !== productId) return { status: 'invalid', test: sandbox, why: 'apple_product' };
  if (tx.revocationDate) return { status: 'revoked', test: sandbox, why: 'apple_revoked' };
  return { status: 'valid', test: sandbox, why: sandbox ? 'apple_ok_sandbox' : 'apple_ok' };
}

/** Apple's root certificates, committed under functions/certs/. */
export function appleRootCerts(): Buffer[] {
  const dir = join(__dirname, '..', 'certs');
  return ['AppleRootCA-G2.cer', 'AppleRootCA-G3.cer'].map((f) => readFileSync(join(dir, f)));
}

/** Whether a configured value is really set (secrets / params default to a placeholder). */
export function isConfigured(v: string | undefined | null): v is string {
  return typeof v === 'string' && v.trim() !== '' && v.trim() !== 'unset';
}

/**
 * The real Apple lookups (@apple/app-store-server-library), or null when the
 * In-App Purchase key is not configured yet (→ `unknown`). Loaded lazily so
 * the Android-only path never pays for it.
 */
export async function makeAppleApi(cfg: { key?: string; keyId?: string; issuerId?: string }): Promise<AppleApi | null> {
  const { key, keyId, issuerId } = cfg;
  if (!isConfigured(key) || !key.includes('PRIVATE KEY') || !isConfigured(keyId) || !isConfigured(issuerId)) return null;
  const lib = await import('@apple/app-store-server-library');
  const roots = appleRootCerts();
  const clients = new Map<string, { api: InstanceType<typeof lib.AppStoreServerAPIClient>; verifier: InstanceType<typeof lib.SignedDataVerifier> }>();
  const forEnv = (env: 'Production' | 'Sandbox') => {
    let c = clients.get(env);
    if (!c) {
      const e = env === 'Production' ? lib.Environment.PRODUCTION : lib.Environment.SANDBOX;
      c = {
        api: new lib.AppStoreServerAPIClient(key, keyId, issuerId, IOS_BUNDLE_ID, e),
        verifier: new lib.SignedDataVerifier(roots, true, e, IOS_BUNDLE_ID, IOS_APP_APPLE_ID),
      };
      clients.set(env, c);
    }
    return c;
  };
  return {
    async lookup(env, transactionId) {
      const c = forEnv(env);
      let signed: string | undefined;
      try {
        signed = (await c.api.getTransactionInfo(transactionId)).signedTransactionInfo;
      } catch (err) {
        if (err instanceof lib.APIException && err.apiError === lib.APIError.TRANSACTION_ID_NOT_FOUND) return null;
        throw err;
      }
      if (!signed) throw new Error('no signedTransactionInfo');
      const tx = await c.verifier.verifyAndDecodeTransaction(signed);
      return {
        bundleId: tx.bundleId,
        productId: tx.productId,
        revocationDate: tx.revocationDate,
        environment: tx.environment === undefined ? undefined : String(tx.environment),
      };
    },
  };
}

// endregion

// region records

/** The stored record (`purchases/{id}`). */
export interface PurchaseRecord {
  platform: Platform;
  productId?: string;
  status: VerifyStatus;
  test?: boolean;
  firstUid?: string;
  lastCheckedMs?: number;
  voidedMs?: number;
  voidedReason?: number | null;
}

/**
 * Checks [input] with its store, merges the record and returns the status
 * the app acts on. Stored history only ever softens the answer:
 * - a token the sweep (or Apple) marked `revoked` stays revoked;
 * - a token seen `valid` before is never `invalid` later (an expired /
 *   pruned store record must not turn an honest buyer into a cheater):
 *   such an answer is reported `unknown`.
 */
export async function handleVerifyPurchase(
  db: Firestore,
  deps: PurchaseDeps,
  input: VerifyInput,
  uid: string | undefined,
  nowMs: number,
): Promise<{ status: VerifyStatus }> {
  const verdict =
    input.platform === 'android'
      ? await verifyAndroid(deps, input.productId, input.token)
      : await verifyIos(deps, input.productId, input.token);
  const ref = db.collection(PURCHASES_COLLECTION).doc(purchaseDocId(input.platform, input.token));
  let status: VerifyStatus = verdict.status;
  try {
    status = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      const old = snap.exists ? (snap.data() as PurchaseRecord) : undefined;
      let s = verdict.status;
      if (old?.status === 'revoked') s = 'revoked';
      else if (s === 'invalid' && old?.status === 'valid') s = 'unknown';
      // An unknown answer never overwrites what a store said before.
      const stored: VerifyStatus = s === 'unknown' && old ? old.status : s;
      const rec: Partial<PurchaseRecord> = {
        platform: input.platform,
        productId: input.productId,
        status: stored,
        lastCheckedMs: nowMs,
      };
      if (verdict.test !== undefined) rec.test = verdict.test;
      else if (old?.test === undefined) rec.test = false;
      if (uid && !old?.firstUid) rec.firstUid = uid;
      t.set(ref, rec, { merge: true });
      return s;
    });
  } catch (err) {
    // The verdict still answers the app; the record is written next time.
    logger.error('verifyPurchase: record failed', { err: errName(err) });
    if (status === 'invalid') status = 'unknown'; // history unknown: be lenient
  }
  logger.info('verifyPurchase', {
    platform: input.platform,
    productId: input.productId,
    status,
    store: verdict.status,
    why: verdict.why,
    test: verdict.test ?? false,
    signedIn: !!uid,
  });
  return { status };
}

/**
 * How far back the sweep looks at most. Play keeps 30 days and answers 400
 * to a startTime that is older by the time the request arrives, so stay an
 * hour inside the window.
 */
export const SWEEP_MAX_BACK_MS = (30 * 24 - 1) * 3600 * 1000;
const DAY_MS = 24 * 3600 * 1000;

/**
 * Daily: every voided one-time Play purchase since (last run − 1 day, at
 * most 30 days back) marks its record `revoked` (created when missing, so a
 * refund before the first verify still counts). Returns how many tokens
 * were marked. Throws when Play cannot be read (the start time is kept).
 */
export async function sweepVoided(db: Firestore, deps: PurchaseDeps, nowMs: number): Promise<number> {
  const meta = db.doc(IAP_META_DOC);
  const last = (await meta.get()).data()?.lastRunMs;
  const earliest = nowMs - SWEEP_MAX_BACK_MS;
  const start = typeof last === 'number' ? Math.max(earliest, last - DAY_MS) : earliest;
  const voided = await listVoided(deps, start);
  for (let i = 0; i < voided.length; i += 400) {
    const batch = db.batch();
    for (const v of voided.slice(i, i + 400)) {
      batch.set(
        db.collection(PURCHASES_COLLECTION).doc(purchaseDocId('android', v.purchaseToken)),
        {
          platform: 'android',
          status: 'revoked',
          voidedMs: v.voidedTimeMillis,
          voidedReason: v.voidedReason,
        },
        { merge: true },
      );
    }
    await batch.commit();
  }
  await meta.set({ lastRunMs: nowMs }, { merge: true });
  return voided.length;
}

/**
 * "Delete my data": the caller's uid leaves every purchase record it is
 * on (the token record itself stays: refunds / fraud). Idempotent.
 */
export async function clearPurchaseUid(db: Firestore, uid: string): Promise<number> {
  const snap = await db.collection(PURCHASES_COLLECTION).where('firstUid', '==', uid).get();
  for (let i = 0; i < snap.docs.length; i += 400) {
    const batch = db.batch();
    for (const d of snap.docs.slice(i, i + 400)) batch.update(d.ref, { firstUid: FieldValue.delete() });
    await batch.commit();
  }
  return snap.size;
}

// endregion

function errName(err: unknown): string {
  if (err && typeof err === 'object') {
    const e = err as { name?: unknown; httpStatusCode?: unknown; apiError?: unknown; code?: unknown };
    const parts = [typeof e.name === 'string' ? e.name : 'Error'];
    if (e.httpStatusCode !== undefined) parts.push(String(e.httpStatusCode));
    if (e.apiError !== undefined && e.apiError !== null) parts.push(String(e.apiError));
    if (e.code !== undefined) parts.push(String(e.code));
    return parts.join(':');
  }
  return String(err);
}

/** The real Play GET with the function's service account (ADC; no key file). */
export function makePlayGet(): (url: string) => Promise<HttpAnswer> {
  const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
  return async (url) => {
    const token = await auth.getAccessToken();
    if (!token) throw new Error('no access token');
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      body = null;
    }
    return { status: res.status, body };
  };
}
