/**
 * PRD-2.6 LB3 hooks shared by Delete My Data and the name callables.
 *
 * `deleteBoardData` tombstones the uid before touching any board document,
 * then removes every server-side trace from the LB3 collections. The
 * tombstone makes a late `lbSubmitRun` fail and makes a retry safe; every
 * phase is idempotent, so a partly completed cleanup finishes on the next
 * call. The versus `players` transaction stays separate (S6-61).
 *
 * `lbSyncName` propagates the name the versus path just accepted (or the
 * generated name after clearing one) to the cached player, its open group
 * and its BEST RUN row.
 */
import {
  FieldPath,
  Timestamp,
  type DocumentReference,
  type DocumentSnapshot,
  type Firestore,
  type QueryDocumentSnapshot,
  type Transaction,
} from 'firebase-admin/firestore';
import { poolCustomName } from './customname.js';
import { versusName } from './nickname.js';
import {
  LB_BEST_COLLECTION,
  LB_BEST_SIZE,
  LB_FLAGS_COLLECTION,
  LB_GHOST_POOL_COLLECTION,
  LB_GIFTS_COLLECTION,
  LB_GROUPS_COLLECTION,
  // region P26-S2
  LB_META_COLLECTION,
  // endregion
  LB_PLAYERS_COLLECTION,
  LB_TOMB_COLLECTION,
  MAX_BRACKET,
  NAMES_COLLECTION,
  type LbBestDoc,
  type LbBestRow,
  type LbGhostDay,
  type LbGhostPoolDoc,
  type LbGroupDoc,
  type LbPlayerDoc,
  type Look,
  type NameDoc,
} from './schema.js';

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const TOMB_TTL_MS = 7 * DAY_MS;
const GHOST_SHARDS = 4;
const HIST_BUCKET = 100;
const DELETE_PAGE = 400;
const GROUP_PAGE = 150;
const BEST_PAGE = 100;
const CLEANUP_CONCURRENCY = 8;
const DEFAULT_LOOK: Look = { bird: 'classic', gear: 'none', hat: 'none', hoop: 'pink', trail: 'flame' };

function at(ms: number): Timestamp {
  return Timestamp.fromMillis(Math.floor(ms));
}

function millis(value: unknown): number {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return 0;
}

function count(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

// region P26-S2
/**
 * LB3 addendum: lbMeta/hidden is the transaction-consistent suppression registry.
 * entries[uid] = {until, pending}; pending entries never age out after a failed
 * sweep. Completed entries survive the 14-day ghost supply + 1-day group +
 * 3-day group TTL, including stale group snapshots after cleanupPending clears.
 * lbPlayers.cleanupPending remains the retry marker until the sweep completes.
 */
type HiddenEntries = Record<string, { until: Timestamp; pending: boolean }>;

export function hiddenGhostUids(snap: DocumentSnapshot): string[] {
  return Object.keys(snap.data()?.entries ?? {});
}

export function writeHiddenRegistry(
  tx: Transaction,
  db: Firestore,
  snap: DocumentSnapshot,
  uid: string,
  nowMs: number,
  pending: boolean,
): void {
  const entries = Object.fromEntries(
    Object.entries((snap.data()?.entries ?? {}) as HiddenEntries)
      .filter(([, entry]) => entry.pending || millis(entry.until) > nowMs),
  );
  tx.set(db.collection(LB_META_COLLECTION).doc('hidden'), {
    entries: { ...entries, [uid]: { until: at(nowMs + 18 * DAY_MS), pending } },
  });
}
// endregion

/** A stable tombstone for a retry: an existing one is never refreshed. */
async function ensureTombstone(db: Firestore, uid: string, nowMs: number): Promise<void> {
  const ref = db.collection(LB_TOMB_COLLECTION).doc(uid);
  await db.runTransaction(async (tx) => {
    // region P26-S2
    const [tomb, hidden] = await Promise.all([
      tx.get(ref), tx.get(db.collection(LB_META_COLLECTION).doc('hidden')),
    ]);
    writeHiddenRegistry(tx, db, hidden, uid, nowMs, true);
    if (tomb.exists) return;
    // endregion
    tx.set(ref, {
      uid,
      deletedAt: at(nowMs),
      expireAt: at(nowMs + TOMB_TTL_MS),
    });
  });
}

/** Delete every `lbGifts` / `lbFlags` doc owned by [uid], paged for large accounts. */
async function deleteOwnedDocs(db: Firestore, collection: string, uid: string): Promise<void> {
  for (;;) {
    const snap = await db.collection(collection).where('uid', '==', uid).limit(DELETE_PAGE).get();
    if (snap.empty) return;
    const batch = db.batch();
    for (const doc of snap.docs) batch.delete(doc.ref);
    await batch.commit();
  }
}

function ghostPoolRefs(db: Firestore): DocumentReference[] {
  const refs: DocumentReference[] = [];
  for (let bracket = 0; bracket <= MAX_BRACKET; bracket++) {
    for (let shard = 0; shard < GHOST_SHARDS; shard++) {
      refs.push(db.collection(LB_GHOST_POOL_COLLECTION).doc(`${bracket}_${shard}`));
    }
  }
  return refs;
}

/** The fields of one group that still name [uid], or null when it is clean. */
function groupCleanup(group: LbGroupDoc, uid: string): Record<string, unknown> | null {
  const memberUids = Array.isArray(group.memberUids) ? group.memberUids : [];
  const members = isObject(group.members) ? group.members : {};
  const hasMember = memberUids.includes(uid) || Object.prototype.hasOwnProperty.call(members, uid);
  const ghosts = Array.isArray(group.ghosts) ? group.ghosts : [];
  const ghostUids = Array.isArray(group.ghostUids) ? group.ghostUids : [];
  const hasGhost = ghosts.some((ghost) => isObject(ghost) && ghost.uid === uid) || ghostUids.includes(uid);
  if (!hasMember && !hasGhost) return null;

  const update: Record<string, unknown> = {};
  if (hasMember) {
    update.memberUids = memberUids.filter((id) => id !== uid);
    const next = { ...members };
    delete next[uid];
    update.members = next;
  }
  if (hasGhost) {
    // A partial write may leave the two arrays out of step; filtering each by
    // its own uid avoids removing another player's ghost at a shared index.
    update.ghosts = ghosts.filter((ghost) => !(isObject(ghost) && ghost.uid === uid));
    update.ghostUids = ghostUids.filter((id) => id !== uid);
  }
  return update;
}

async function forEachLimited<T>(items: readonly T[], fn: (item: T) => Promise<void>): Promise<void> {
  let next = 0;
  const workers = Array.from({ length: Math.min(CLEANUP_CONCURRENCY, items.length) }, async () => {
    for (;;) {
      const i = next++;
      if (i >= items.length) return;
      await fn(items[i]);
    }
  });
  await Promise.all(workers);
}

/**
 * Remove [uid] from every group it can be found in: the player's current
 * `groupId` plus the `memberUids` / `ghostUids` array queries. Groups are
 * handled before ghost pools so an in-flight settlement either commits first
 * (and its ghost entry is pruned afterwards) or retries against a group that
 * no longer contains the uid.
 */
export async function stripGroups(db: Firestore, uid: string, currentGid: string | null): Promise<void> {
  let directGid = currentGid;
  for (;;) {
    const [byMember, byGhost] = await Promise.all([
      db.collection(LB_GROUPS_COLLECTION).where('memberUids', 'array-contains', uid).limit(GROUP_PAGE).get(),
      db.collection(LB_GROUPS_COLLECTION).where('ghostUids', 'array-contains', uid).limit(GROUP_PAGE).get(),
    ]);
    const refs = new Map<string, DocumentReference>();
    for (const doc of [...byMember.docs, ...byGhost.docs]) refs.set(doc.ref.path, doc.ref);
    if (directGid !== null) {
      refs.set(`${LB_GROUPS_COLLECTION}/${directGid}`, db.collection(LB_GROUPS_COLLECTION).doc(directGid));
    }
    directGid = null;
    if (refs.size === 0) return;

    // One small transaction per group: a page of full group docs can exceed
    // the 10 MiB transaction limit, and transactions keep a concurrent
    // settlement from being overwritten by a stale snapshot.
    await forEachLimited([...refs.values()], async (ref) => {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) return;
        const update = groupCleanup(snap.data() as LbGroupDoc, uid);
        if (update !== null) tx.update(snap.ref, update);
      });
    });
  }
}

function rowFromPlayer(uid: string, player: LbPlayerDoc): LbBestRow | null {
  const best = count(player.bestShadow);
  if (best <= 0 || player.hidden === true) return null;
  return {
    uid,
    best,
    bestAt: at(millis(player.bestAt)),
    name: player.name,
    look: player.look ?? DEFAULT_LOOK,
    ...(player.card === undefined ? {} : { card: player.card }),
    platform: player.platform ?? 'android',
    bracket: count(player.bracket),
  };
}

function mergeBestRows(rows: readonly LbBestRow[], extra: LbBestRow | null): LbBestRow[] {
  const byUid = new Map<string, LbBestRow>();
  for (const row of rows) {
    if (!row || typeof row.uid !== 'string') continue;
    const old = byUid.get(row.uid);
    if (
      old === undefined ||
      row.best > old.best ||
      (row.best === old.best && millis(row.bestAt) < millis(old.bestAt))
    ) {
      byUid.set(row.uid, row);
    }
  }
  if (extra !== null) {
    const old = byUid.get(extra.uid);
    if (
      old === undefined ||
      extra.best > old.best ||
      (extra.best === old.best && millis(extra.bestAt) < millis(old.bestAt))
    ) {
      byUid.set(extra.uid, extra);
    }
  }
  return [...byUid.values()].sort((a, b) => {
    if (a.best !== b.best) return b.best - a.best;
    const when = millis(a.bestAt) - millis(b.bestAt);
    return when !== 0 ? when : a.uid.localeCompare(b.uid);
  });
}

/**
 * Refill the cached BEST RUN top list from `lbPlayers` after one row was
 * removed. The single-field `bestShadow` order keeps this working without a
 * new composite index; hidden rows are skipped as they are encountered.
 */
async function rebuildBestRows(
  tx: Transaction,
  db: Firestore,
  uid: string,
  rows: readonly LbBestRow[],
): Promise<LbBestRow[]> {
  let merged = mergeBestRows(rows.filter((row) => row?.uid !== uid), null);
  let cursor: QueryDocumentSnapshot | undefined;
  for (;;) {
    const query = db
      .collection(LB_PLAYERS_COLLECTION)
      .orderBy('bestShadow', 'desc')
      .limit(BEST_PAGE);
    const page = await tx.get(cursor === undefined ? query : query.startAfter(cursor));
    for (const doc of page.docs) {
      if (doc.id === uid) continue;
      const row = rowFromPlayer(doc.id, doc.data() as LbPlayerDoc);
      if (row !== null) merged = mergeBestRows(merged, row);
    }
    const last = page.docs.at(-1);
    if (
      page.size < BEST_PAGE ||
      (merged.length >= LB_BEST_SIZE && count(last?.data().bestShadow) < merged[LB_BEST_SIZE - 1].best)
    ) {
      return merged;
    }
    cursor = last;
  }
}

/** Remove the public row from `lbBest/global` and keep its histogram in step. */
async function removeFromBest(
  tx: Transaction,
  db: Firestore,
  uid: string,
  nowMs: number,
  bestRef: DocumentReference,
  bestSnap: DocumentSnapshot,
  histSnap: DocumentSnapshot,
  player: LbPlayerDoc | undefined,
): Promise<void> {
  const best = bestSnap.exists ? (bestSnap.data() as LbBestDoc) : undefined;
  const rows = Array.isArray(best?.rows) ? best!.rows : [];
  const removed = rows.find((row) => row?.uid === uid);

  if (removed !== undefined) {
    const merged = await rebuildBestRows(tx, db, uid, rows);
    const nextRows = merged.slice(0, LB_BEST_SIZE);
    tx.set(bestRef, {
      rows: nextRows,
      floor: merged.length >= LB_BEST_SIZE ? merged[LB_BEST_SIZE - 1].best : 0,
      updatedAt: at(nowMs),
    } satisfies LbBestDoc);
  }

  if (histSnap.exists) {
    const old = histSnap.data();
    const bins: Record<string, number> = isObject(old?.bins) ? { ...old.bins } as Record<string, number> : {};
    const score = player !== undefined
      ? (player.hidden === true ? 0 : count(player.bestShadow))
      : count(removed?.best);
    if (score > 0) {
      const key = String(Math.floor(score / HIST_BUCKET) * HIST_BUCKET);
      const left = count(bins[key]) - 1;
      if (left > 0) bins[key] = left;
      else delete bins[key];
      tx.set(histSnap.ref, { bins, updatedAt: at(nowMs) });
    }
  }
}

/** Remove this uid's rows from all 44 ghost-pool documents. */
export async function pruneGhostPools(db: Firestore, uid: string, nowMs: number): Promise<void> {
  await forEachLimited(ghostPoolRefs(db), async (ref) => {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const pool = snap.data() as LbGhostPoolDoc;
      const entries = Array.isArray(pool.entries) ? pool.entries : [];
      const kept = entries.filter((entry: LbGhostDay) => entry?.uid !== uid);
      if (kept.length !== entries.length) {
        tx.update(ref, { entries: kept, updatedAt: at(nowMs) });
      }
    });
  });
}

/** Delete the player and, when cached, their BEST row (refilling the top list). */
async function deleteBoardCore(db: Firestore, uid: string, nowMs: number): Promise<void> {
  const playerRef = db.collection(LB_PLAYERS_COLLECTION).doc(uid);
  const bestRef = db.collection(LB_BEST_COLLECTION).doc('global');
  const histRef = db.collection(LB_BEST_COLLECTION).doc('hist');
  await db.runTransaction(async (tx) => {
    const [playerSnap, bestSnap, histSnap] = await Promise.all([
      tx.get(playerRef),
      tx.get(bestRef),
      tx.get(histRef),
    ]);
    const player = playerSnap.exists ? (playerSnap.data() as LbPlayerDoc) : undefined;

    // All reads (including the BEST refill) must precede the first write.
    await removeFromBest(tx, db, uid, nowMs, bestRef, bestSnap, histSnap, player);
    if (playerSnap.exists) tx.delete(playerRef);
  });
}

/** Remove every server-side lb trace of [uid], then leave a short tombstone. */
export async function deleteBoardData(db: Firestore, uid: string, nowMs = Date.now()): Promise<void> {
  await ensureTombstone(db, uid, nowMs);
  const playerSnap = await db.collection(LB_PLAYERS_COLLECTION).doc(uid).get();
  const player = playerSnap.exists ? (playerSnap.data() as LbPlayerDoc) : undefined;
  const currentGid = typeof player?.groupId === 'string' && player.groupId ? player.groupId : null;

  await stripGroups(db, uid, currentGid);
  await deleteOwnedDocs(db, LB_GIFTS_COLLECTION, uid);
  await deleteOwnedDocs(db, LB_FLAGS_COLLECTION, uid);
  await pruneGhostPools(db, uid, nowMs);
  await stripGroups(db, uid, null);
  await deleteBoardCore(db, uid, nowMs);
  // region P26-S2
  await db.runTransaction(async (tx) => {
    const hidden = await tx.get(db.collection(LB_META_COLLECTION).doc('hidden'));
    writeHiddenRegistry(tx, db, hidden, uid, nowMs, false);
  });
  // endregion
}

/** Refresh the server-derived display name on [uid]'s leaderboard data. */
export async function lbSyncName(
  db: Firestore,
  uid: string,
  name: string,
  _nowMs = Date.now(),
): Promise<void> {
  const playerRef = db.collection(LB_PLAYERS_COLLECTION).doc(uid);
  const nameRef = db.collection(NAMES_COLLECTION).doc(uid);
  const bestRef = db.collection(LB_BEST_COLLECTION).doc('global');
  await db.runTransaction(async (tx) => {
    const [playerSnap, nameSnap] = await Promise.all([tx.get(playerRef), tx.get(nameRef)]);
    const player = playerSnap.exists ? (playerSnap.data() as LbPlayerDoc) : undefined;
    // The hook can arrive after a newer name was accepted. `versusNames` is
    // the authoritative source, so read it in this transaction instead of
    // trusting the name captured by the earlier call.
    const storedName = nameSnap.exists ? (nameSnap.data() as NameDoc).customName : '';
    const boardName = poolCustomName(storedName) || versusName('', uid);
    const gid = typeof player?.groupId === 'string' && player.groupId ? player.groupId : null;
    const groupRef = gid === null ? null : db.collection(LB_GROUPS_COLLECTION).doc(gid);
    const [groupSnap, bestSnap] = await Promise.all([
      groupRef === null ? Promise.resolve(null) : tx.get(groupRef),
      tx.get(bestRef),
    ]);
    const group = groupSnap?.exists ? (groupSnap.data() as LbGroupDoc) : undefined;
    const member = group?.members?.[uid];
    const best = bestSnap.exists ? (bestSnap.data() as LbBestDoc) : undefined;
    const bestRow = Array.isArray(best?.rows) ? best!.rows.find((row) => row?.uid === uid) : undefined;

    if (player !== undefined && player.name !== boardName) tx.update(playerRef, { name: boardName });
    if (groupRef !== null && group !== undefined && member !== undefined && member.name !== boardName) {
      tx.update(groupRef, new FieldPath('members', uid, 'name'), boardName);
    }
    if (bestRow !== undefined && bestRow.name !== boardName) {
      const rows = best!.rows.map((row) => (row.uid === uid ? { ...row, name: boardName } : row));
      tx.update(bestRef, { rows });
    }
  });
}
