/**
 * Flappy Spikes versus backend (PRD-2 §3.13, ARCH §6.3). 2nd gen, europe-west1
 * (inside the eur3 multi-region of the Firestore database).
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { setGlobalOptions, logger } from 'firebase-functions/v2';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret } from 'firebase-functions/params';
import {
  deletePlayerData,
  getCustomName,
  processPlayerWrite,
  releaseStaleGuestNames,
  setCustomName,
  SetNameResult,
  sweepAllPools,
} from './pools.js';
import type { PlayerDoc } from './schema.js';
import {
  clearPurchaseUid,
  handleVerifyPurchase,
  makeAppleApi,
  makePlayGet,
  parseVerifyInput,
  type PurchaseDeps,
  sweepVoided,
} from './purchases.js';
import {
  lbClaimGift as claimGift,
  lbGetBoard as getBoard,
  lbSettleGroups as settleGroups,
  lbSubmitRun as submitRun,
} from './board_store.js';
import { deleteBoardData } from './board_delete.js';

initializeApp();

/** Region next to the eur3 database; small caps keep the Blaze bill near zero (§3.13 costs). */
const REGION = 'europe-west1';
setGlobalOptions({ region: REGION, maxInstances: 10, memory: '256MiB' });

/** Shared LB3 callable options: region, cap and App Check are pinned per export. */
const LB_CALLABLE_OPTIONS = {
  enforceAppCheck: true,
  consumeAppCheckToken: false,
  region: REGION,
  maxInstances: 10,
} as const;

/** The caller's Firebase Auth uid; LB3 callables require anonymous or linked auth. */
function requireUid(auth: { uid?: string } | undefined): string {
  if (!auth?.uid) throw new HttpsError('unauthenticated', 'Sign-in required.');
  return auth.uid;
}

/**
 * Validates the new run of a `players/{uid}` write and maintains the pools.
 * Not client-invoked, so App Check does not apply here: Firestore itself
 * enforces App Check on the client write that triggers it (ARCH §6.2).
 */
export const onPlayerRunWrite = onDocumentWritten(
  { document: 'players/{uid}', retry: false },
  async (event) => {
    const uid = event.params.uid;
    const before = event.data?.before.data() as PlayerDoc | undefined;
    const after = event.data?.after.data() as PlayerDoc | undefined;
    try {
      const r = await processPlayerWrite(getFirestore(), uid, before, after);
      if (r.accepted.length || r.rejected.length || r.trimmedRecent) {
        logger.info('onPlayerRunWrite', { uid, ...r });
      }
    } catch (err) {
      logger.error('onPlayerRunWrite failed', { uid, err: String(err) });
    }
  },
);

/**
 * WP-N2 whether [uid] is linked to Play Games / Game Center (an anonymous
 * Firebase user has no provider). False when the user is gone; null when
 * Auth could not answer.
 */
async function isLinked(uid: string): Promise<boolean | null> {
  try {
    const user = await getAuth().getUser(uid);
    return user.providerData.length > 0;
  } catch (err) {
    if ((err as { code?: string }).code === 'auth/user-not-found') return false;
    return null;
  }
}

/**
 * "Delete my data" (§3.13 privacy): the caller's pool entries in all 44
 * shards, `players/{uid}`, the server rate doc, the custom name and its
 * claim (WP-N2: released only while this uid holds it) and the Auth user.
 * Also the guest clean-up before an account switch (the app calls it as
 * the old anonymous uid), so a guest's name is free again for anyone.
 * Idempotent. (WP-AV: there are no versus pictures any more.)
 * App Check enforced (ARCH §6.3 / §6.5); tokens are not consumed (no replay
 * risk: the call only deletes the caller's own data).
 */
export const deleteMyData = onCall({ enforceAppCheck: true, consumeAppCheckToken: false }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign-in required.');
  const auth = getAuth();
  // S6-61: Auth must answer before anything is deleted, so an Auth outage
  // fails the call with every online document intact.
  try {
    await auth.getUser(uid);
  } catch (err) {
    if ((err as { code?: string }).code !== 'auth/user-not-found') {
      throw new HttpsError('unavailable', 'Auth unavailable; nothing was deleted.');
    }
  }
  // PRD-2.5 §3.8: the uid leaves its purchase records first (idempotent;
  // the token records stay for refunds / fraud and are not personal then).
  try {
    await clearPurchaseUid(getFirestore(), uid);
  } catch (err) {
    logger.error('deleteMyData: purchase uid clean-up failed, nothing deleted', { uid, err: String(err) });
    throw new HttpsError('unavailable', 'Delete failed; nothing was deleted.');
  }
  // PRD-2.6 LB3: the same privacy boundary covers our leaderboard. This
  // tombstone and the lb cleanup run after purchases and before the
  // all-or-nothing players transaction.
  try {
    await deleteBoardData(getFirestore(), uid);
  } catch (err) {
    logger.error('deleteMyData: board clean-up failed, nothing deleted', { uid, err: String(err) });
    throw new HttpsError('unavailable', 'Delete failed; nothing was deleted.');
  }
  // All-or-nothing: the player, rate and every pool membership in one
  // transaction (a failure deletes nothing).
  let removed: number;
  try {
    removed = await deletePlayerData(getFirestore(), uid);
  } catch (err) {
    logger.error('deleteMyData: data delete failed, nothing deleted', { uid, err: String(err) });
    throw new HttpsError('unavailable', 'Delete failed; nothing was deleted.');
  }
  // The data part is idempotent, so a failure here is completed by the
  // client's retry with the same (still existing) account.
  try {
    await auth.deleteUser(uid);
  } catch (err) {
    if ((err as { code?: string }).code !== 'auth/user-not-found') throw new HttpsError('internal', 'Auth delete failed.');
  }
  logger.info('deleteMyData', { uid, removed });
  return { ok: true, removed };
});

/**
 * WP-NAME "Player name" in Settings: sets (`{name: 'Wise0wl'}`) or clears
 * (`{name: ''}`) the caller's custom versus name. Refused names answer
 * `{ok: false, reason: 'length' | 'chars' | 'blocked' | 'taken', name?}`
 * (the app shows the reason in the card; WP-N2 `taken` = another player
 * holds it, `name` = the caller's current name); accepted ones `{ok: true,
 * name}` and are written into the caller's pool entries at once. App Check
 * enforced, like deleteMyData. Audit 17: at most DAILY_NAME_CHANGES
 * accepted changes a UTC day (then `resource-exhausted`).
 */
export const setVersusName = onCall({ enforceAppCheck: true, consumeAppCheckToken: false }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign-in required.');
  const data = req.data as { name?: unknown } | undefined;
  let r: SetNameResult;
  try {
    const linked = (await isLinked(uid)) === true;
    r = await setCustomName(getFirestore(), uid, data?.name, Date.now(), { linked, rateLimit: true });
  } catch (err) {
    logger.error('setVersusName failed', { uid, err: String(err) });
    throw new HttpsError('unavailable', 'Name not saved.');
  }
  // Audit 17: the daily change cap answers an error. The app (2.4.0+44 on)
  // shows it and keeps the old name; older versions treat it as offline
  // (kept on the phone, sent again later).
  if (!r.ok && r.reason === 'rate') throw new HttpsError('resource-exhausted', 'Name not saved.');
  if (r.ok) logger.info('setVersusName', { uid, set: r.name !== '', updated: r.updated });
  return r;
});

/**
 * WP-N2 the caller's stored custom name (`{ok: true, name}`, '' = none):
 * the app restores it after a reinstall, a sign-in or an account switch.
 * Also the once-a-day activity ping that keeps a guest's name (see
 * `releaseGuestNames`). App Check enforced.
 */
export const getVersusName = onCall({ enforceAppCheck: true, consumeAppCheckToken: false }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign-in required.');
  try {
    const linked = (await isLinked(uid)) === true;
    return await getCustomName(getFirestore(), uid, Date.now(), { linked });
  } catch (err) {
    logger.error('getVersusName failed', { uid, err: String(err) });
    throw new HttpsError('unavailable', 'Name not read.');
  }
});

/**
 * WP-N2 daily: guest names (anonymous, not linked) unused for 30 days are
 * released (claim, name doc, pool entries); linked players' names never
 * expire.
 */
export const releaseGuestNames = onSchedule({ schedule: 'every 24 hours', timeZone: 'Etc/UTC' }, async () => {
  const released = await releaseStaleGuestNames(getFirestore(), isLinked);
  logger.info('releaseGuestNames', { released: released.length });
});

/** Daily retention sweep of the pool shards (ARCH §6.2: entries > 60 d). */
export const sweepPools = onSchedule({ schedule: 'every 24 hours', timeZone: 'Etc/UTC' }, async () => {
  const removed = await sweepAllPools(getFirestore());
  logger.info('sweepPools', { removed });
});

// region PRD-2.6 §3 LB3 — daily leaderboard callables and settlement

/** Submit up to ten finished runs; the stub returns an empty accepted set in wave 0. */
export const lbSubmitRun = onCall(LB_CALLABLE_OPTIONS, async (req) => {
  const uid = requireUid(req.auth);
  return submitRun(getFirestore(), uid, req.data, Date.now());
});

/** Read TODAY / BEST RUN; the stub returns empty boards in wave 0. */
export const lbGetBoard = onCall(LB_CALLABLE_OPTIONS, async (req) => {
  const uid = requireUid(req.auth);
  return getBoard(getFirestore(), uid, req.data, Date.now());
});

/** Claim a podium gift idempotently; the stub answers `ok: false` in wave 0. */
export const lbClaimGift = onCall(LB_CALLABLE_OPTIONS, async (req) => {
  const uid = requireUid(req.auth);
  return claimGift(getFirestore(), uid, req.data, Date.now());
});

/** Every 10 minutes: settle ended groups and write ghost days (idempotent). */
export const lbSettleGroups = onSchedule(
  { schedule: 'every 10 minutes', timeZone: 'Etc/UTC', region: REGION, maxInstances: 10 },
  async () => {
    const r = await settleGroups(getFirestore(), Date.now());
    logger.info('lbSettle', r);
  },
);

// endregion PRD-2.6 §3 LB3

// region PRD-2.5 §3.8 WP-IAP — server purchase verification

/**
 * The dedicated service account of the purchase functions: Play Console
 * grants it "View financial data, orders, and cancellation survey
 * responses" (productsv2 get + voidedpurchases list); IAM gives it
 * datastore.user + logging.logWriter. No key file (ADC).
 */
const IAP_SA = 'iap-verify@flappy-spikes-a2b55.iam.gserviceaccount.com';

/**
 * App Store Connect In-App Purchase key (.p8 contents). Until the real key
 * exists the secret holds a placeholder and every iOS check answers
 * `unknown`.
 */
const ASC_IAP_KEY = defineSecret('ASC_IAP_KEY');
/*
 * Its key id and the ASC issuer id are not secret: plain environment
 * variables ASC_IAP_KEY_ID / ASC_ISSUER_ID (functions/.env.<project> at
 * deploy time, once the key exists). Not params, so a deploy never prompts;
 * missing = iOS checks answer `unknown`.
 */

let playGet: PurchaseDeps['playGet'] | undefined;

async function purchaseDeps(): Promise<PurchaseDeps> {
  playGet ??= makePlayGet();
  let apple: PurchaseDeps['apple'] = null;
  try {
    apple = await makeAppleApi({
      key: ASC_IAP_KEY.value(),
      keyId: process.env.ASC_IAP_KEY_ID,
      issuerId: process.env.ASC_ISSUER_ID,
    });
  } catch (err) {
    logger.warn('verifyPurchase: Apple client unavailable', { err: String(err) });
  }
  return { playGet, apple };
}

/**
 * `{platform: 'android'|'ios', productId, token}` → `{status: 'valid' |
 * 'revoked' | 'invalid' | 'unknown'}` (see purchases.ts). App Check
 * enforced, tokens not consumed (idempotent and read-only towards the
 * stores, like the other callables). Sign-in optional: the uid is stored
 * when present.
 */
export const verifyPurchase = onCall(
  { enforceAppCheck: true, consumeAppCheckToken: false, serviceAccount: IAP_SA, secrets: [ASC_IAP_KEY] },
  async (req) => {
    const input = parseVerifyInput(req.data);
    if (!input) throw new HttpsError('invalid-argument', 'Bad purchase.');
    return handleVerifyPurchase(getFirestore(), await purchaseDeps(), input, req.auth?.uid, Date.now());
  },
);

/** Daily: refunded / voided Play purchases → `revoked` (replaces RTDN). */
export const sweepVoidedPurchases = onSchedule(
  { schedule: 'every 24 hours', timeZone: 'Etc/UTC', serviceAccount: IAP_SA },
  async () => {
    try {
      const marked = await sweepVoided(getFirestore(), { playGet: (playGet ??= makePlayGet()), apple: null }, Date.now());
      logger.info('sweepVoidedPurchases', { marked });
    } catch (err) {
      logger.error('sweepVoidedPurchases failed', { err: String(err) });
    }
  },
);

// endregion
