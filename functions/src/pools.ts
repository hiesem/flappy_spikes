/**
 * Pool maintenance (PRD-2 §3.13 backend, ARCH §6.3): the logic behind
 * `onPlayerRunWrite`, `deleteMyData` and `sweepPools`, written against a
 * Firestore instance so the emulator tests can drive it directly.
 */
import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { avatarBucketName, avatarPath } from './avatars.js';
import { levelFor } from './levels.js';
import {
  DAILY_UPLOADS,
  PlayerDoc,
  POOL_CAP,
  POOL_MAX_BYTES,
  PoolDoc,
  PoolEntry,
  poolId,
  RATE_COLLECTION,
  RateDoc,
  RETENTION_MS,
  RunEntry,
  SEEN_KEEP,
  SHARDS,
  allPoolIds,
  utcDay,
  MAX_LEVEL,
} from './schema.js';
import { docSize } from './size.js';
import { checkRun, RejectReason } from './timeline.js';

export interface WriteResult {
  accepted: string[];
  rejected: { runId: string; reason: RejectReason }[];
  pool?: string;
  trimmedRecent?: number;
  /** The live `players/{uid}` doc is gone (Delete my data): nothing written. */
  playerGone?: boolean;
  /** S8-06: the deleted player's picture was removed (or was already gone). */
  avatarDeleted?: boolean;
}

/** The slice of a Storage bucket the picture clean-up needs (tests inject one). */
export interface AvatarBucket {
  deleteAvatar(uid: string): Promise<void>;
  /** Pictures as (uid, last update ms); paged internally. */
  listAvatars(): Promise<{ uid: string; updatedMs: number }[]>;
}

/** The default Storage bucket of the project (`avatars/{uid}.jpg`). */
export function defaultAvatarBucket(): AvatarBucket {
  const bucket = () => getStorage().bucket(avatarBucketName());
  return {
    async deleteAvatar(uid) {
      await bucket().file(avatarPath(uid)).delete({ ignoreNotFound: true });
    },
    async listAvatars() {
      const [files] = await bucket().getFiles({ prefix: 'avatars/', autoPaginate: true });
      const out: { uid: string; updatedMs: number }[] = [];
      for (const f of files) {
        const m = /^avatars\/(.+)\.jpg$/.exec(f.name);
        if (!m) continue;
        const t = Date.parse(String(f.metadata?.updated ?? f.metadata?.timeCreated ?? ''));
        out.push({ uid: m[1], updatedMs: Number.isFinite(t) ? t : 0 });
      }
      return out;
    },
  };
}

/**
 * PRD-2.3 §5.5 / §21.3 (S8-06): the versus picture is versus data, so it
 * goes when `players/{uid}` goes (the Firestore TTL ≈ 60 days after the
 * last run, or Delete my data). The live doc is re-read first: a player
 * who wrote a new run since the delete keeps the picture. Idempotent; the
 * daily [sweepStaleAvatars] retries a failed delete.
 */
async function deleteAvatarOfDeletedPlayer(
  db: Firestore,
  uid: string,
  bucket: AvatarBucket,
): Promise<boolean> {
  const live = await db.collection('players').doc(uid).get();
  if (live.exists) return false;
  await bucket.deleteAvatar(uid);
  return true;
}

function runsOf(p: PlayerDoc | undefined): RunEntry[] {
  if (!p) return [];
  const out: RunEntry[] = [];
  if (p.bestRun) out.push(p.bestRun);
  if (Array.isArray(p.recent)) out.push(...p.recent);
  return out;
}

function tsMillis(t: unknown): number {
  if (t instanceof Timestamp) return t.toMillis();
  if (t instanceof Date) return t.getTime();
  return 0;
}

/** Runs present in [after] but not in [before], unique by runId, newest first. */
export function newRuns(before: PlayerDoc | undefined, after: PlayerDoc): RunEntry[] {
  const old = new Set(runsOf(before).map((r) => r?.runId));
  const seen = new Set<string>();
  const out: RunEntry[] = [];
  for (const r of runsOf(after)) {
    if (!r || typeof r.runId !== 'string' || old.has(r.runId) || seen.has(r.runId)) continue;
    seen.add(r.runId);
    out.push(r);
  }
  return out.sort((a, b) => tsMillis(b.ts) - tsMillis(a.ts));
}

/** Drops this uid's entries and expired ones, prepends [entry], trims to 150 / 900 KB. */
export function mergePool(
  path: string,
  pool: PoolDoc | undefined,
  entry: PoolEntry | null,
  removeUid: string | null,
  nowMs: number,
): { entries: PoolEntry[]; changed: boolean } {
  const before = Array.isArray(pool?.entries) ? pool!.entries : [];
  const cutoff = nowMs - RETENTION_MS;
  let entries = before.filter((e) => e.uid !== removeUid && tsMillis(e.ts) >= cutoff);
  if (entry) entries.unshift(entry);
  if (entries.length > POOL_CAP) entries = entries.slice(0, POOL_CAP);
  const shell = { level: pool?.level ?? 0, shard: pool?.shard ?? 0, updatedAt: Timestamp.fromMillis(nowMs) };
  while (entries.length > 1 && docSize(path, { ...shell, entries }) > POOL_MAX_BYTES) entries.pop();
  const changed = entry !== null || entries.length !== before.length;
  return { entries, changed };
}

export interface ProcessOptions {
  nowMs?: number;
  /** Random in [0, 1); picks the shard. */
  rand?: () => number;
  /** The picture bucket (default: the project's Storage bucket). */
  avatars?: AvatarBucket;
}

/**
 * Handles one `players/{uid}` write: validates the new run(s), applies the
 * upload rate, writes the newest accepted run to a random shard of the
 * player's (server-recomputed) level and trims stale `recent` entries.
 *
 * The event snapshot may arrive after `deletePlayerData` (S6-08): the
 * transaction re-reads the live player doc and writes nothing (no rate doc,
 * no pool entry) when it no longer exists, so a delayed write can never
 * recreate deleted data (§3.13 privacy). `deletePlayerData` deletes that doc
 * first, so either this transaction sees it gone or the deletion's pool
 * rewrite runs after this commit.
 */
export async function processPlayerWrite(
  db: Firestore,
  uid: string,
  before: PlayerDoc | undefined,
  after: PlayerDoc | undefined,
  opts: ProcessOptions = {},
): Promise<WriteResult> {
  const result: WriteResult = { accepted: [], rejected: [] };
  if (!after) {
    // Deleted (TTL or deleteMyData): deleteMyData / the sweep clean the
    // pools; the picture goes here (S8-06).
    if (before) {
      result.avatarDeleted = await deleteAvatarOfDeletedPlayer(db, uid, opts.avatars ?? defaultAvatarBucket());
    }
    return result;
  }
  const nowMs = opts.nowMs ?? Date.now();
  const rand = opts.rand ?? Math.random;

  const fresh = newRuns(before, after);
  if (fresh.length > 0) {
    const playerBest = typeof after.best === 'number' ? after.best : 0;
    const prevBest = typeof before?.best === 'number' ? before.best : 0;
    const level = Math.min(MAX_LEVEL, levelFor(playerBest));
    const shard = Math.min(SHARDS - 1, Math.floor(rand() * SHARDS));
    const pid = poolId(level, shard);
    const poolRef = db.collection('pools').doc(pid);
    const rateRef = db.collection(RATE_COLLECTION).doc(uid);
    const playerRef = db.collection('players').doc(uid);
    const today = utcDay(nowMs);

    await db.runTransaction(async (tx) => {
      result.accepted = [];
      result.rejected = [];
      delete result.pool;
      delete result.playerGone;
      const [playerSnap, rateSnap, poolSnap] = await Promise.all([
        tx.get(playerRef),
        tx.get(rateRef),
        tx.get(poolRef),
      ]);
      if (!playerSnap.exists) {
        result.playerGone = true;
        return;
      }
      const rate: RateDoc = (rateSnap.data() as RateDoc | undefined) ?? { day: today, count: 0, seen: [] };
      if (rate.day !== today) {
        rate.day = today;
        rate.count = 0;
      }
      const seen = new Set(rate.seen ?? []);
      let chosen: RunEntry | null = null;
      let last: RateDoc['last'];
      for (const run of fresh) {
        let reason: RejectReason | null = seen.has(run.runId) ? 'duplicate' : checkRun(run, playerBest);
        const isBest =
          after.bestRun?.runId === run.runId && run.score > prevBest && run.score === playerBest;
        if (reason === null && !isBest) {
          if (rate.count >= DAILY_UPLOADS) reason = 'rate';
          else rate.count++;
        }
        if (reason !== 'duplicate') seen.add(run.runId);
        if (reason === null) {
          result.accepted.push(run.runId);
          if (!chosen) chosen = run;
          last = { runId: run.runId, status: 'accepted', pool: pid };
        } else {
          result.rejected.push({ runId: run.runId, reason });
          if (reason !== 'duplicate') last = { runId: run.runId, status: 'rejected', reason };
        }
      }
      rate.seen = [...seen].slice(-SEEN_KEEP);
      if (last) rate.last = last;
      tx.set(rateRef, rate);
      if (chosen) {
        const entry: PoolEntry = {
          runId: chosen.runId,
          uid,
          level,
          score: chosen.score,
          best: chosen.best,
          ts: Timestamp.fromMillis(nowMs),
          name: chosen.name,
          avatar: chosen.avatar,
          look: chosen.look,
          platform: chosen.platform,
          tl: chosen.tl,
          end: chosen.end,
          fl: chosen.fl,
          // PRD-2.3 §21.4 the self-match guard's hashed Play Games id.
          pg: typeof chosen.pg === 'string' ? chosen.pg : '',
        };
        const pool = poolSnap.data() as PoolDoc | undefined;
        const { entries } = mergePool(poolRef.path, pool, entry, uid, nowMs);
        tx.set(poolRef, { level, shard, updatedAt: Timestamp.fromMillis(nowMs), entries });
        result.pool = pid;
      }
    });
  }

  // Retention for `recent` (ARCH §6.2): drop entries older than 60 days. The
  // follow-up trigger sees no new run and nothing stale, so it stops.
  if (!result.playerGone && Array.isArray(after.recent)) {
    const cutoff = nowMs - RETENTION_MS;
    const kept = after.recent.filter((r) => tsMillis(r?.ts) >= cutoff);
    if (kept.length !== after.recent.length) {
      await db.collection('players').doc(uid).update({ recent: kept });
      result.trimmedRecent = after.recent.length - kept.length;
    }
  }
  return result;
}

async function rewritePool(
  db: Firestore,
  pid: string,
  removeUid: string | null,
  nowMs: number,
): Promise<number> {
  const ref = db.collection('pools').doc(pid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return 0;
    const pool = snap.data() as PoolDoc;
    const { entries, changed } = mergePool(ref.path, pool, null, removeUid, nowMs);
    if (!changed) return 0;
    tx.update(ref, { entries, updatedAt: Timestamp.fromMillis(nowMs) });
    return (pool.entries?.length ?? 0) - entries.length;
  });
}

/** Daily sweep: trims entries older than 60 days in all 44 shards. Returns removed count. */
export async function sweepAllPools(db: Firestore, nowMs = Date.now()): Promise<number> {
  const counts = await Promise.all(allPoolIds().map((pid) => rewritePool(db, pid, null, nowMs)));
  return counts.reduce((a, b) => a + b, 0);
}

/**
 * PRD-2.3 §5.5 / §21.3 (S8-06) daily retry of the picture clean-up: every
 * `avatars/{uid}.jpg` whose `players/{uid}` doc no longer exists and that
 * was not updated for [graceMs] (default: the 60-day retention, so a
 * picture uploaded before the player's first run is kept that long) is
 * deleted. Returns the number deleted.
 */
export async function sweepStaleAvatars(
  db: Firestore,
  bucket: AvatarBucket = defaultAvatarBucket(),
  nowMs = Date.now(),
  graceMs = RETENTION_MS,
): Promise<number> {
  const files = await bucket.listAvatars();
  let deleted = 0;
  for (const f of files) {
    if (nowMs - f.updatedMs < graceMs) continue;
    const live = await db.collection('players').doc(f.uid).get();
    if (live.exists) continue;
    await bucket.deleteAvatar(f.uid);
    deleted++;
  }
  return deleted;
}

/**
 * Removes everything stored online for [uid] except the Auth user (the
 * caller deletes that). All-or-nothing (S6-61): the player doc, the rate
 * doc and this uid's entries in all 44 pool shards go in **one**
 * transaction (46 reads, ≤ 46 writes), so a failure deletes nothing and a
 * retry starts from the same state. Serializable with `processPlayerWrite`
 * (which re-reads the player doc in its transaction): a run write either
 * commits first (its pool entry is then removed here) or sees the player
 * gone and writes nothing. Idempotent: a second call removes 0.
 */
export async function deletePlayerData(db: Firestore, uid: string, nowMs = Date.now()): Promise<number> {
  const playerRef = db.collection('players').doc(uid);
  const rateRef = db.collection(RATE_COLLECTION).doc(uid);
  const poolRefs = allPoolIds().map((pid) => db.collection('pools').doc(pid));
  return db.runTransaction(async (tx) => {
    const [player, rate, ...pools] = await Promise.all([
      tx.get(playerRef),
      tx.get(rateRef),
      ...poolRefs.map((ref) => tx.get(ref)),
    ]);
    let removed = 0;
    pools.forEach((snap, i) => {
      if (!snap.exists) return;
      const pool = snap.data() as PoolDoc;
      const { entries, changed } = mergePool(poolRefs[i].path, pool, null, uid, nowMs);
      if (!changed) return;
      tx.update(poolRefs[i], { entries, updatedAt: Timestamp.fromMillis(nowMs) });
      removed += (pool.entries?.length ?? 0) - entries.length;
    });
    if (player.exists) tx.delete(playerRef);
    if (rate.exists) tx.delete(rateRef);
    return removed;
  });
}
