/**
 * Flappy Spikes versus backend (PRD-2 §3.13, ARCH §6.3). 2nd gen, europe-west1
 * (inside the eur3 multi-region of the Firestore database).
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { setGlobalOptions, logger } from 'firebase-functions/v2';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { deletePlayerData, processPlayerWrite, sweepAllPools, sweepStaleAvatars } from './pools.js';
import type { PlayerDoc } from './schema.js';
import { avatarBucketName, avatarPath } from './avatars.js';

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
      if (r.accepted.length || r.rejected.length || r.trimmedRecent || r.avatarDeleted) {
        logger.info('onPlayerRunWrite', { uid, ...r });
      }
    } catch (err) {
      logger.error('onPlayerRunWrite failed', { uid, err: String(err) });
    }
  },
);

/**
 * "Delete my data" (§3.13 privacy): the caller's pool entries in all 44
 * shards, `players/{uid}`, the server rate doc, the versus picture
 * `avatars/{uid}.jpg` (PRD-2.3 §21.3) and the Auth user. Idempotent.
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
  // PRD-2.3 §21.3 the versus picture `avatars/{uid}.jpg` (absent = fine).
  // Before the Auth delete, so a failure is completed by the client's retry.
  try {
    await getStorage().bucket(avatarBucketName()).file(avatarPath(uid)).delete({ ignoreNotFound: true });
  } catch (err) {
    logger.error('deleteMyData: picture delete failed', { uid, err: String(err) });
    throw new HttpsError('unavailable', 'Picture delete failed; please retry.');
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
 * Daily retention sweep of the pool shards (ARCH §6.2: entries > 60 d) and
 * of the versus pictures whose player doc is gone (PRD-2.3 §5.5, S8-06).
 */
export const sweepPools = onSchedule({ schedule: 'every 24 hours', timeZone: 'Etc/UTC' }, async () => {
  const removed = await sweepAllPools(getFirestore());
  let avatars = 0;
  try {
    avatars = await sweepStaleAvatars(getFirestore());
  } catch (err) {
    logger.error('sweepPools: picture sweep failed', { err: String(err) });
  }
  logger.info('sweepPools', { removed, avatars });
});
