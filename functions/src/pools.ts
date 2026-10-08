/**
 * Pool maintenance (PRD-2 §3.13 backend, ARCH §6.3): the logic behind
 * `onPlayerRunWrite`, `deleteMyData` and `sweepPools`, written against a
 * Firestore instance so the emulator tests can drive it directly.
 */
import { Firestore, Timestamp } from 'firebase-admin/firestore';
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
  if (!after) return result; // deleted: deleteMyData cleans the pools
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

/** Removes everything stored online for [uid] except the Auth user (the caller deletes that). */
export async function deletePlayerData(db: Firestore, uid: string, nowMs = Date.now()): Promise<number> {
  // The player doc first, so no later write can re-add a pool entry from it.
  await db.collection('players').doc(uid).delete();
  await db.collection(RATE_COLLECTION).doc(uid).delete();
  const counts = await Promise.all(allPoolIds().map((pid) => rewritePool(db, pid, uid, nowMs)));
  return counts.reduce((a, b) => a + b, 0);
}
