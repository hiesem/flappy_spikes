/**
 * Pool maintenance (PRD-2 §3.13 backend, ARCH §6.3): the logic behind
 * `onPlayerRunWrite`, `deleteMyData` and `sweepPools`, written against a
 * Firestore instance so the emulator tests can drive it directly.
 */
import { DocumentReference, DocumentSnapshot, FieldValue, Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { Anomaly, scoreRun } from './anomaly.js';
import { levelFor } from './levels.js';
import { versusName } from './nickname.js';
import { checkCustomName, CustomNameReason, poolCustomName } from './customname.js';
import { CLAIMS_COLLECTION, ClaimDoc, GUEST_NAME_TTL_MS, nameKey, SEEN_REFRESH_MS } from './nameclaims.js';
import {
  NAMES_COLLECTION,
  NameDoc,
  DAILY_BEST_UPLOADS,
  DAILY_NAME_CHANGES,
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
  FLAG_TTL_DAYS,
  FLAGS_COLLECTION,
  FlagDoc,
  SCORE_HISTORY,
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
  /** PRD-2.5 §3.6 runIds that got a `versusFlags` doc (soft ones included). */
  flagged?: string[];
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
  if (!after) {
    // Deleted (TTL or deleteMyData): deleteMyData / the sweep clean the pools.
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
    const nameRef = db.collection(NAMES_COLLECTION).doc(uid);
    const today = utcDay(nowMs);

    // PRD-2.5 §3.6 anomalies of the runs that passed checkRun (reset on a
    // transaction retry; written after the commit).
    let anomalies: { run: RunEntry; a: Anomaly }[] = [];
    await db.runTransaction(async (tx) => {
      result.accepted = [];
      result.rejected = [];
      anomalies = [];
      delete result.pool;
      delete result.playerGone;
      const [playerSnap, rateSnap, poolSnap, nameSnap] = await Promise.all([
        tx.get(playerRef),
        tx.get(rateRef),
        tx.get(poolRef),
        tx.get(nameRef),
      ]);
      if (!playerSnap.exists) {
        result.playerGone = true;
        return;
      }
      const rate: RateDoc = (rateSnap.data() as RateDoc | undefined) ?? { day: today, count: 0, seen: [] };
      if (rate.day !== today) {
        rate.day = today;
        rate.count = 0;
        rate.bestCount = 0;
      }
      const seen = new Set(rate.seen ?? []);
      // PRD-2.5 §3.6 the last scores of runs that passed checkRun (oldest first).
      const scores = Array.isArray(rate.scores) ? rate.scores.filter((x) => typeof x === 'number') : [];
      let chosen: RunEntry | null = null;
      let last: RateDoc['last'];
      for (const run of fresh) {
        let reason: RejectReason | null = seen.has(run.runId) ? 'duplicate' : checkRun(run, playerBest);
        if (reason === null) {
          // PRD-2.5 §3.6 (D3) judged whether pooled or rate-limited; never changes the outcome.
          try {
            const a = scoreRun(run, scores);
            if (a) anomalies.push({ run, a });
          } catch (err) {
            logger.error('versusFlag: scoring failed', { uid, runId: run.runId, err: String(err) });
          }
          scores.push(run.score);
        }
        const isBest =
          after.bestRun?.runId === run.runId && run.score > prevBest && run.score === playerBest;
        if (reason === null && !isBest) {
          if (rate.count >= DAILY_UPLOADS) reason = 'rate';
          else rate.count++;
        } else if (reason === null) {
          // Audit 17: new bests have their own (generous) daily cap.
          const bests = rate.bestCount ?? 0;
          if (bests >= DAILY_BEST_UPLOADS) reason = 'rate';
          else rate.bestCount = bests + 1;
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
      rate.scores = scores.slice(-SCORE_HISTORY);
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
          // WP-AV only generated names and no pictures reach a pool: a
          // platform name from an older app becomes a generated name.
          name: versusName(chosen.name, uid),
          avatar: '',
          look: {
            bird: chosen.look.bird,
            gear: chosen.look.gear,
            hat: chosen.look.hat,
            hoop: chosen.look.hoop,
            trail: chosen.look.trail,
          },
          platform: chosen.platform,
          tl: chosen.tl,
          end: chosen.end,
          fl: chosen.fl,
          // PRD-2.3 §21.4 the self-match guard's hashed Play Games id.
          pg: typeof chosen.pg === 'string' ? chosen.pg : '',
        };
        // WP-NAME the custom name the server accepted (setCustomName).
        const custom = poolCustomName((nameSnap.data() as NameDoc | undefined)?.customName);
        if (custom) entry.customName = custom;
        const pool = poolSnap.data() as PoolDoc | undefined;
        const { entries } = mergePool(poolRef.path, pool, entry, uid, nowMs);
        tx.set(poolRef, { level, shard, updatedAt: Timestamp.fromMillis(nowMs), entries });
        result.pool = pid;
      }
    });
    if (!result.playerGone && anomalies.length > 0) {
      result.flagged = await writeFlags(db, uid, anomalies, chosenId(result), result.pool ?? null, level, nowMs);
    }
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

/** The runId that went into the pool (the first accepted one), if any. */
function chosenId(r: WriteResult): string | null {
  return r.pool && r.accepted.length > 0 ? r.accepted[0] : null;
}

/** `versusFlags` doc id: flat (`{uid}_{runId}`), idempotent per run. */
export function flagId(uid: string, runId: string): string {
  return `${uid}_${runId}`.replace(/\//g, '_');
}

/**
 * PRD-2.5 §3.6 writes one flag per anomaly after the upload transaction
 * committed. Idempotent (`set` by id); a failure is logged and never
 * touches the pool / rate result (D3). Returns the runIds written.
 */
async function writeFlags(
  db: Firestore,
  uid: string,
  anomalies: { run: RunEntry; a: Anomaly }[],
  pooledRunId: string | null,
  pool: string | null,
  level: number,
  nowMs: number,
): Promise<string[]> {
  const written: string[] = [];
  for (const { run, a } of anomalies) {
    const doc: FlagDoc = {
      uid,
      runId: run.runId,
      score: run.score,
      best: run.best,
      signals: a.signals as Record<string, number>,
      soft: a.soft,
      durationCs: a.durationCs,
      passes: a.passes,
      level,
      pool: run.runId === pooledRunId ? pool : null,
      platform: run.platform,
      ts: Timestamp.fromMillis(nowMs),
      expireAt: Timestamp.fromMillis(nowMs + FLAG_TTL_DAYS * 24 * 3600 * 1000),
    };
    try {
      await db.collection(FLAGS_COLLECTION).doc(flagId(uid, run.runId)).set(doc);
      written.push(run.runId);
      logger.warn('versusFlag', {
        uid,
        runId: run.runId,
        score: run.score,
        signals: a.signals,
        soft: a.soft,
        pool: doc.pool,
      });
    } catch (err) {
      logger.error('versusFlag: write failed', { uid, runId: run.runId, err: String(err) });
    }
  }
  return written;
}

/** PRD-2.5 §3.6 deletes every `versusFlags` doc of [uid] (Delete my data). Returns the count. */
export async function deleteFlags(db: Firestore, uid: string): Promise<number> {
  let n = 0;
  for (;;) {
    const page = await db.collection(FLAGS_COLLECTION).where('uid', '==', uid).limit(400).get();
    if (page.empty) return n;
    const batch = db.batch();
    page.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    n += page.size;
    if (page.size < 400) return n;
  }
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
 * Removes everything stored online for [uid] except the Auth user (the
 * caller deletes that). All-or-nothing (S6-61): the player doc, the rate
 * doc and this uid's entries in all 44 pool shards go in **one**
 * transaction (46 reads, ≤ 46 writes), so a failure deletes nothing and a
 * retry starts from the same state. Serializable with `processPlayerWrite`
 * (which re-reads the player doc in its transaction): a run write either
 * commits first (its pool entry is then removed here) or sees the player
 * gone and writes nothing. Idempotent: a second call removes 0.
 * PRD-2.5 §3.6: after that transaction the uid's `versusFlags` docs are
 * deleted too (a query + batch delete; idempotent, a retry finishes it).
 */
export async function deletePlayerData(db: Firestore, uid: string, nowMs = Date.now()): Promise<number> {
  const removed = await deletePlayerDocs(db, uid, nowMs);
  // PRD-2.5 §3.6 the anti-cheat flags go too (after the transaction; idempotent).
  await deleteFlags(db, uid);
  return removed;
}

async function deletePlayerDocs(db: Firestore, uid: string, nowMs: number): Promise<number> {
  const playerRef = db.collection('players').doc(uid);
  const rateRef = db.collection(RATE_COLLECTION).doc(uid);
  const nameRef = db.collection(NAMES_COLLECTION).doc(uid);
  const poolRefs = allPoolIds().map((pid) => db.collection('pools').doc(pid));
  return db.runTransaction(async (tx) => {
    const [player, rate, name, ...pools] = await Promise.all([
      tx.get(playerRef),
      tx.get(rateRef),
      tx.get(nameRef),
      ...poolRefs.map((ref) => tx.get(ref)),
    ]);
    // WP-N2 the name's claim goes too, but only while this uid holds it.
    const release = await ownClaim(tx, db, uid, (name.data() as NameDoc | undefined)?.customName);
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
    if (name.exists) tx.delete(nameRef);
    if (release) tx.delete(release);
    return removed;
  });
}

/**
 * WP-N2 the claim of [name] when [uid] holds it (read in [tx]; null when
 * there is no name, no claim, or another uid holds it).
 */
async function ownClaim(
  tx: Transaction,
  db: Firestore,
  uid: string,
  name: unknown,
): Promise<DocumentReference | null> {
  if (typeof name !== 'string' || name === '') return null;
  const ref = db.collection(CLAIMS_COLLECTION).doc(nameKey(name));
  const snap = await tx.get(ref);
  return snap.exists && (snap.data() as ClaimDoc).uid === uid ? ref : null;
}

/**
 * WP-N2 the activity fields of a name doc for a linked / guest owner: for
 * an update ([forSet] false) a linked owner's `guestSeen` is deleted; for a
 * full set it is simply left out.
 */
function seenFields(nowMs: number, linked: boolean, forSet = false): Partial<Record<keyof NameDoc, unknown>> {
  const at = Timestamp.fromMillis(nowMs);
  if (!linked) return { lastSeen: at, linked, guestSeen: at };
  return forSet ? { lastSeen: at, linked } : { lastSeen: at, linked, guestSeen: FieldValue.delete() };
}

export type SetNameResult =
  | { ok: true; name: string; updated: number }
  | { ok: false; reason: CustomNameReason; name?: string }
  /** Audit 17: [DAILY_NAME_CHANGES] reached (only with [NameOptions.rateLimit]). */
  | { ok: false; reason: 'rate' };

export interface NameOptions {
  /** The caller is linked to Play Games / Game Center (default: a guest). */
  linked?: boolean;
  /**
   * Audit 17: count this change against [DAILY_NAME_CHANGES] (the client
   * callable; server-side clean-ups never count).
   */
  rateLimit?: boolean;
}

/**
 * WP-NAME sets (or with '' clears) [uid]'s custom versus name: the format
 * rule and the word filter ([checkCustomName]); an accepted name is stored
 * in `versusNames/{uid}` and written into this uid's entries in all 44 pool
 * shards at once (one transaction), so opponents see it right away; a
 * cleared one removes it there (the generated name shows again).
 *
 * WP-N2 one owner per name: in the same transaction the name's claim
 * (`versusNameClaims/{nameKey}`) is taken — refused as `taken` when
 * another uid holds it, answering the caller's current name too — and the
 * caller's previous claim is released. The activity stamp is refreshed.
 */
export async function setCustomName(
  db: Firestore,
  uid: string,
  raw: unknown,
  nowMs = Date.now(),
  opts: NameOptions = {},
): Promise<SetNameResult> {
  const name = raw === '' || raw === null || raw === undefined ? '' : raw;
  if (name !== '') {
    const reason = checkCustomName(name);
    if (reason) return { ok: false, reason };
  }
  const custom = name as string;
  const linked = opts.linked === true;
  const nameRef = db.collection(NAMES_COLLECTION).doc(uid);
  const claimRef = custom ? db.collection(CLAIMS_COLLECTION).doc(nameKey(custom)) : null;
  const poolRefs = allPoolIds().map((pid) => db.collection('pools').doc(pid));
  const rateRef = db.collection(RATE_COLLECTION).doc(uid);
  return db.runTransaction(async (tx): Promise<SetNameResult> => {
    const [nameSnap, rateSnap] = await Promise.all([tx.get(nameRef), tx.get(rateRef)]);
    const current = (nameSnap.data() as NameDoc | undefined)?.customName ?? '';
    // Audit 17: a change (not a re-send of the same name) counts.
    let names: { day: string; count: number } | null = null;
    if (opts.rateLimit && custom !== current) {
      const today = utcDay(nowMs);
      const prev = (rateSnap.data() as RateDoc | undefined)?.names;
      const count = prev?.day === today ? prev.count : 0;
      if (count >= DAILY_NAME_CHANGES) return { ok: false, reason: 'rate' };
      names = { day: today, count: count + 1 };
    }
    if (claimRef) {
      const claim = await tx.get(claimRef);
      if (claim.exists && (claim.data() as ClaimDoc).uid !== uid) {
        return { ok: false, reason: 'taken', name: poolCustomName(current) };
      }
    }
    const old = await ownClaim(tx, db, uid, current);
    const pools = await Promise.all(poolRefs.map((ref) => tx.get(ref)));
    const n = writePoolNames(tx, uid, custom, pools, poolRefs);
    if (old && (!claimRef || old.path !== claimRef.path)) tx.delete(old);
    if (claimRef) {
      tx.set(claimRef, { uid, name: custom, updatedAt: Timestamp.fromMillis(nowMs) } satisfies ClaimDoc);
      tx.set(nameRef, {
        customName: custom,
        updatedAt: Timestamp.fromMillis(nowMs),
        ...seenFields(nowMs, linked, true),
      });
    } else {
      tx.delete(nameRef);
    }
    if (names) tx.set(rateRef, { names }, { merge: true });
    return { ok: true, name: custom, updated: n };
  });
}

/** Writes (or with '' removes) [custom] in [uid]'s pool entries. Returns the count. */
function writePoolNames(
  tx: Transaction,
  uid: string,
  custom: string,
  pools: DocumentSnapshot[],
  refs: DocumentReference[],
): number {
  let n = 0;
  pools.forEach((snap, i) => {
    if (!snap.exists) return;
    const pool = snap.data() as PoolDoc;
    if (!Array.isArray(pool.entries) || !pool.entries.some((e) => e.uid === uid)) return;
    const entries = pool.entries.map((e) => {
      if (e.uid !== uid) return e;
      n++;
      const next: PoolEntry = { ...e };
      if (custom) next.customName = custom;
      else delete next.customName;
      return next;
    });
    tx.update(refs[i], { entries });
  });
  return n;
}

export type GetNameResult = { ok: true; name: string };

/**
 * WP-N2 the caller's stored custom name ('' = none), read by the app after
 * a start, a sign-in or an account switch (the server is the source of
 * truth once a name was confirmed) and at most about once a day otherwise.
 * It doubles as the guest-activity signal: `lastSeen` / `guestSeen` /
 * `linked` are refreshed (at most every 12 h unless the link state
 * changed). A 2.4.0 name without a claim takes its claim now; when another
 * uid already holds that name, this one loses it (cleared).
 */
export async function getCustomName(
  db: Firestore,
  uid: string,
  nowMs = Date.now(),
  opts: NameOptions = {},
): Promise<GetNameResult> {
  const linked = opts.linked === true;
  const nameRef = db.collection(NAMES_COLLECTION).doc(uid);
  const r = await db.runTransaction(async (tx) => {
    const snap = await tx.get(nameRef);
    if (!snap.exists) return { name: '', lost: false };
    const doc = snap.data() as NameDoc;
    const name = poolCustomName(doc.customName);
    if (!name) return { name: '', lost: true };
    const claimRef = db.collection(CLAIMS_COLLECTION).doc(nameKey(name));
    const claim = await tx.get(claimRef);
    if (claim.exists && (claim.data() as ClaimDoc).uid !== uid) return { name: '', lost: true };
    if (!claim.exists) {
      tx.set(claimRef, { uid, name, updatedAt: Timestamp.fromMillis(nowMs) } satisfies ClaimDoc);
    }
    const seen = doc.lastSeen?.toMillis() ?? 0;
    if (!claim.exists || doc.linked !== linked || nowMs - seen >= SEEN_REFRESH_MS) {
      tx.update(nameRef, seenFields(nowMs, linked));
    }
    return { name, lost: false };
  });
  // A stored name that no longer passes the rules or lost its claim: gone
  // everywhere (pools too).
  if (r.lost) await setCustomName(db, uid, '', nowMs, opts);
  return { ok: true, name: r.name };
}

/**
 * WP-N2 the daily job: guest names (`guestSeen` older than 30 days) are
 * released — claim, `versusNames/{uid}` and the pool entries' customName.
 * [isLinked] asks Auth first (true = linked meanwhile: the doc is marked
 * linked and kept; null = Auth could not answer: kept for the next run).
 * Each release re-checks the stamp in its own transaction, so an app that
 * became active meanwhile keeps its name. Returns the uids released.
 */
export async function releaseStaleGuestNames(
  db: Firestore,
  isLinked: (uid: string) => Promise<boolean | null>,
  nowMs = Date.now(),
  pageSize = 200,
): Promise<string[]> {
  const cutoff = Timestamp.fromMillis(nowMs - GUEST_NAME_TTL_MS);
  const released: string[] = [];
  const skipped = new Set<string>();
  for (;;) {
    const limit = pageSize + skipped.size;
    const page = await db
      .collection(NAMES_COLLECTION)
      .where('guestSeen', '<', cutoff)
      .orderBy('guestSeen')
      .limit(limit)
      .get();
    const todo = page.docs.filter((d) => !skipped.has(d.id));
    for (const d of todo) {
      const uid = d.id;
      const linked = await isLinked(uid);
      if (linked === null) {
        skipped.add(uid);
      } else if (linked) {
        await d.ref.update({ linked: true, guestSeen: FieldValue.delete() });
      } else if (await releaseGuestName(db, uid, cutoff)) {
        released.push(uid);
      } else {
        skipped.add(uid);
      }
    }
    if (todo.length === 0 || page.docs.length < limit) break;
  }
  return released;
}

/** Clears [uid]'s name when its `guestSeen` is still before [cutoff]. */
async function releaseGuestName(db: Firestore, uid: string, cutoff: Timestamp): Promise<boolean> {
  const nameRef = db.collection(NAMES_COLLECTION).doc(uid);
  const poolRefs = allPoolIds().map((pid) => db.collection('pools').doc(pid));
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(nameRef);
    const doc = snap.data() as NameDoc | undefined;
    const seen = doc?.guestSeen;
    if (!doc || !seen || seen.toMillis() >= cutoff.toMillis()) return false;
    const claim = await ownClaim(tx, db, uid, doc.customName);
    const pools = await Promise.all(poolRefs.map((ref) => tx.get(ref)));
    writePoolNames(tx, uid, '', pools, poolRefs);
    if (claim) tx.delete(claim);
    tx.delete(nameRef);
    return true;
  });
}
