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
import {
  deletePlayerData,
  getCustomName,
  processPlayerWrite,
  releaseStaleGuestNames,
  setCustomName,
  sweepAllPools,
} from './pools.js';
import type { PlayerDoc } from './schema.js';

initializeApp();

/** Region next to the eur3 database; small caps keep the Blaze bill near zero (§3.13 costs). */
const REGION = 'europe-west1';
setGlobalOptions({ region: REGION, maxInstances: 10, memory: '256MiB' });

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
 * Idempotent. (WP-AV: there are no versus pictures any more; the one-off
 * `scripts/backfill_avatars.ts` deleted every old one.)
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
 * enforced, like deleteMyData.
 */
export const setVersusName = onCall({ enforceAppCheck: true, consumeAppCheckToken: false }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign-in required.');
  const data = req.data as { name?: unknown } | undefined;
  try {
    const linked = (await isLinked(uid)) === true;
    const r = await setCustomName(getFirestore(), uid, data?.name, Date.now(), { linked });
    if (r.ok) logger.info('setVersusName', { uid, set: r.name !== '', updated: r.updated });
    return r;
  } catch (err) {
    logger.error('setVersusName failed', { uid, err: String(err) });
    throw new HttpsError('unavailable', 'Name not saved.');
  }
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
