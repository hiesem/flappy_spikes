/**
 * PRD-2.6 C8 one-time import of verified best runs into the LB3 collections.
 *
 * The client-written `players/{uid}.best` value is never trusted. For each
 * player the verified `bestRun` is used when `checkRun` accepts it; otherwise
 * the highest verified `recent[]` run is used. A player with neither is
 * skipped. The import writes `lbPlayers` (`src: 'import'`, 400-day TTL),
 * rebuilds `lbBest/global` and records `lbMeta/import`.
 *
 *   cd functions && npx tsx scripts/lb_import.ts --project <id> [--keep uid,uid] [--apply]
 *
 * Auth: Application Default Credentials. Never run before the owner's OK on
 * the day (C8); the release-blocking test-player cleanup is separate. The
 * command previews by default and writes only with --apply.
 */
import { isDeepStrictEqual } from 'node:util';
import { getApps, initializeApp } from 'firebase-admin/app';
import {
  FieldValue,
  Timestamp,
  getFirestore,
  type CollectionReference,
  type DocumentData,
  type DocumentSnapshot,
  type Firestore,
  type QueryDocumentSnapshot,
  type Transaction,
  type WriteBatch,
} from 'firebase-admin/firestore';
import { bracketForVerifiedBest, rankBestRuns } from '../src/board.js';
import { versusName } from '../src/nickname.js';
import {
  LB_BEST_COLLECTION,
  LB_BEST_SIZE,
  LB_META_COLLECTION,
  LB_PLAYER_TTL,
  LB_PLAYERS_COLLECTION,
  LB_TOMB_COLLECTION,
  validLook,
  type LbBestDoc,
  type LbBestRow,
  type LbMetaDoc,
  type LbPlayerDoc,
  type Look,
  type PlayerDoc,
  type RunEntry,
} from '../src/schema.js';
import { checkRun } from '../src/timeline.js';

export const IMPORT_USAGE =
  'usage: npx tsx scripts/lb_import.ts --project <firebase-project> [--keep uid1,uid2] [--apply] [--help]';
const PAGE = 500;
const BATCH_LIMIT = 400;

export interface VerifiedRunChoice {
  run: RunEntry;
  atMs: number;
  source: 'bestRun' | 'recent';
}

export interface ImportOptions {
  /** Owner / tester uids to remember for the release-blocking cleanup. */
  keepUids: string[];
  /** Write the import. Default false: preview only. */
  apply?: boolean;
  /** Backwards-compatible explicit preview flag; it always wins over [apply]. */
  dryRun?: boolean;
  /** Injected clock for deterministic tests. */
  nowMs?: number;
  /** Progress output; defaults to console.log. */
  log?: (line: string) => void;
}

export interface ImportResult {
  scanned: number;
  imported: number;
  skipped: number;
  tombstoned: number;
  expired: number;
  preservedPlay: number;
  unchanged: number;
  fromBestRun: number;
  fromRecent: number;
  best: LbBestDoc;
  importedUids: string[];
}

export function logLine(opts: { log?: (line: string) => void }, line: string): void {
  (opts.log ?? console.log)(line);
}

export function parseOption(argv: readonly string[], name: string): string | undefined {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < argv.length && !argv[i + 1].startsWith('--') ? argv[i + 1] : undefined;
}

export function hasFlag(argv: readonly string[], name: string): boolean {
  return argv.includes(`--${name}`);
}

export function parseUidList(value: string | undefined): string[] {
  return [...new Set((value ?? '').split(',').map((uid) => uid.trim()).filter(Boolean))];
}

/** An explicit project is mandatory: neither admin script may pick a default project. */
export function requiredProject(argv: readonly string[]): string | null {
  const project = parseOption(argv, 'project');
  return project !== undefined && project.trim() !== '' ? project.trim() : null;
}

/**
 * Open Firestore for exactly [project]. A pre-existing default Admin app is
 * never reused for a different project: that would make `--project` advisory
 * and could write an operational command into the wrong deployment.
 */
export function databaseForProject(project: string): Firestore {
  const appName = `lb-tools-${project}`;
  // A generated name keeps this app distinct from the default Admin app. The
  // options check below is still the final guard if an app exists under it.
  const existing = getApps().find((app) => app.name === appName);
  const app = existing ?? initializeApp({ projectId: project }, appName);
  if (app.options.projectId !== project) {
    throw new Error(`Admin app ${app.name} is bound to ${app.options.projectId ?? '(unknown)'}, not ${project}.`);
  }
  return getFirestore(app);
}

function validArgs(
  argv: readonly string[],
  valueFlags: readonly string[],
  booleanFlags: readonly string[],
): boolean {
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (valueFlags.includes(arg)) {
      if (i + 1 >= argv.length || argv[i + 1].startsWith('--')) return false;
      i++;
    } else if (!booleanFlags.includes(arg)) {
      return false;
    }
  }
  return true;
}

export function validImportArgs(argv: readonly string[]): boolean {
  return validArgs(argv, ['--project', '--keep'], ['--apply', '--dry-run', '--help', '-h']);
}

export function validCleanupArgs(argv: readonly string[]): boolean {
  return validArgs(argv, ['--project', '--keep'], ['--apply', '--help', '-h']);
}

export function timestampMs(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) {
    const ms = value.getTime();
    return Number.isFinite(ms) ? ms : null;
  }
  return null;
}

function verified(run: unknown, atMs: number): run is RunEntry {
  if (run === null || typeof run !== 'object') return false;
  return atMs >= 0 && checkRun(run as RunEntry, (run as Partial<RunEntry>).score ?? 0) === null;
}

/**
 * Pick the PRD F5 import score. A verified bestRun wins even when another
 * recent run scored higher; otherwise take the highest verified recent run
 * (the earlier run wins a tie, matching BEST RUN's bestAt ordering).
 */
export function verifiedRunFor(player: PlayerDoc | undefined): VerifiedRunChoice | null {
  if (player === null || typeof player !== 'object') return null;
  const bestRun = player.bestRun;
  const bestAt = timestampMs(bestRun?.ts);
  if (bestRun !== undefined && bestRun !== null && bestAt !== null && verified(bestRun, bestAt)) {
    return { run: bestRun, atMs: bestAt, source: 'bestRun' };
  }

  let choice: VerifiedRunChoice | null = null;
  const recent = Array.isArray(player.recent) ? player.recent : [];
  for (const run of recent) {
    const atMs = timestampMs(run?.ts);
    if (run === null || run === undefined || atMs === null || !verified(run, atMs)) continue;
    if (
      choice === null ||
      run.score > choice.run.score ||
      (run.score === choice.run.score && atMs < choice.atMs)
    ) {
      choice = { run, atMs, source: 'recent' };
    }
  }
  return choice;
}

function baseLook(look: Look): Look {
  return {
    bird: look.bird,
    gear: look.gear,
    hat: look.hat,
    hoop: look.hoop,
    trail: look.trail,
  };
}

export function importedPlayerDoc(uid: string, choice: VerifiedRunChoice, nowMs: number): LbPlayerDoc {
  const run = choice.run;
  const card = run.look.card;
  return {
    best: run.score,
    bestAt: Timestamp.fromMillis(choice.atMs),
    bestShadow: run.score,
    name: versusName(run.name, uid),
    look: baseLook(run.look),
    ...(card === undefined ? {} : { card }),
    platform: run.platform,
    bracket: bracketForVerifiedBest(run.score),
    lastRunAt: Timestamp.fromMillis(choice.atMs),
    hidden: false,
    src: 'import',
    expireAt: Timestamp.fromMillis(nowMs + LB_PLAYER_TTL),
  };
}

function sameLook(a: unknown, b: Look): boolean {
  const look = a as Partial<Look> | undefined;
  return (
    look !== undefined &&
    look.bird === b.bird &&
    look.gear === b.gear &&
    look.hat === b.hat &&
    look.hoop === b.hoop &&
    look.trail === b.trail
  );
}

/**
 * Whether an imported row already represents exactly this source run. The
 * existing expiry is deliberately retained: an idempotent rerun must not extend
 * a 400-day TTL or move timestamps just because the command was repeated.
 */
export function sameImportedPlayer(
  existing: LbPlayerDoc | Record<string, unknown> | undefined,
  desired: LbPlayerDoc,
  nowMs: number,
): boolean {
  if (existing === undefined) return false;
  const p = existing as Partial<LbPlayerDoc>;
  const expireAt = timestampMs(p.expireAt);
  return (
    p.src === 'import' &&
    p.hidden === false &&
    p.best === desired.best &&
    p.bestShadow === desired.bestShadow &&
    timestampMs(p.bestAt) === desired.bestAt.toMillis() &&
    p.name === desired.name &&
    sameLook(p.look, desired.look) &&
    p.card === desired.card &&
    p.platform === desired.platform &&
    p.bracket === desired.bracket &&
    timestampMs(p.lastRunAt) === timestampMs(desired.lastRunAt) &&
    expireAt !== null &&
    expireAt > nowMs
  );
}

type ImportCommitOutcome = 'written' | 'unchanged' | 'preservedPlay' | 'tombstoned';

export function receivedLiveSubmission(existing: LbPlayerDoc | Record<string, unknown> | undefined): boolean {
  const player = existing as Partial<LbPlayerDoc> | undefined;
  return (
    player !== undefined &&
    (player.hist !== undefined ||
      player.rate !== undefined ||
      player.groupId !== undefined ||
      player.groupStart !== undefined ||
      player.groupEnd !== undefined)
  );
}

/**
 * Commit one imported row only if it is still safe to do so. The transaction
 * either sees a live play row (and leaves it untouched) or the Delete My Data
 * tombstone (and imports nothing). A live submission that commits between the
 * planning read and this transaction therefore always wins.
 */
async function commitImportedPlayer(
  db: Firestore,
  uid: string,
  desired: LbPlayerDoc,
  expected: LbPlayerDoc | Record<string, unknown> | undefined,
  nowMs: number,
): Promise<ImportCommitOutcome> {
  const playerRef = db.collection(LB_PLAYERS_COLLECTION).doc(uid);
  const tombRef = db.collection(LB_TOMB_COLLECTION).doc(uid);
  return db.runTransaction(async (tx) => {
    const [tombSnap, playerSnap] = await Promise.all([tx.get(tombRef), tx.get(playerRef)]);
    if (tombSnap.exists) return 'tombstoned';
    const current = playerSnap.exists ? (playerSnap.data() as LbPlayerDoc) : undefined;
    if (current?.src === 'play') return 'preservedPlay';
    if (receivedLiveSubmission(current)) return 'preservedPlay';
    if (playerSnap.exists && sameImportedPlayer(current, desired, nowMs)) return 'unchanged';
    // A live submit on an already-imported row keeps `src: 'import'`, so it is
    // not enough to check that field. Any state change since the planning read
    // means the live writer owns this row; never replace it with stale data.
    if (!isDeepStrictEqual(current, expected)) return 'preservedPlay';
    // Invalidate the release gate atomically with an actual player write.
    // Planning alone may overestimate writes when a live player is preserved.
    tx.set(db.collection(LB_META_COLLECTION).doc('import'), {
      cleanedAt: FieldValue.delete(),
    }, { merge: true });
    tx.set(playerRef, desired);
    return 'written';
  });
}

/**
 * Rebuild `lbBest/global` from data read inside the same transaction that
 * writes the cache. Reads of every player and the cache create contention with
 * concurrent submissions and deletions, so Firestore retries this function from
 * fresh committed data instead of publishing a stale snapshot. Tombstones are
 * rechecked as an additional Delete My Data guard.
 */
export async function rebuildBestFromCommitted(db: Firestore, nowMs: number): Promise<LbBestDoc> {
  const bestRef = db.collection(LB_BEST_COLLECTION).doc('global');
  for (let attempt = 0; attempt < 5; attempt++) {
    const { best, clean } = await db.runTransaction(async (tx) => {
      await tx.get(bestRef);
      const rows = await readLbPlayersInTransaction(db, tx);
      const nextBest = bestDocFromPlayers(rows, nowMs);
      const uids = nextBest.rows.map((row) => row.uid);
      const tombstones = await Promise.all(
        uids.map((uid) => tx.get(db.collection(LB_TOMB_COLLECTION).doc(uid))),
      );
      const stillClean = !uids.some((_, i) => tombstones[i].exists);
      if (stillClean) tx.set(bestRef, nextBest);
      return { best: nextBest, clean: stillClean };
    });
    if (clean) return best;
  }
  throw new Error('lbBest rebuild raced Delete My Data; rerun the import');
}

/** Rebuild rank bins from committed players, retrying concurrent changes. */
export async function rebuildHistogramFromCommitted(db: Firestore, nowMs: number): Promise<void> {
  // Histogram rebuild also uses committed players in a transaction, so a
  // concurrent BEST raise either precedes this snapshot or retries the write.
  await db.runTransaction(async (tx) => {
    const histRef = db.collection(LB_BEST_COLLECTION).doc('hist');
    const hist = await tx.get(histRef);
    const players = await tx.get(db.collection(LB_PLAYERS_COLLECTION));
    const bins: Record<string, number> = {};
    for (const row of players.docs) {
      const p = row.data() as LbPlayerDoc;
      const score = p.bestShadow ?? p.best;
      if (p.hidden || !Number.isFinite(score) || score <= 0) continue;
      const key = String(Math.floor(score / 100) * 100);
      bins[key] = (bins[key] ?? 0) + 1;
    }
    const current = hist.data()?.bins as Record<string, number> | undefined;
    if (!current || Object.keys(current).length !== Object.keys(bins).length ||
        Object.entries(bins).some(([key, value]) => current[key] !== value)) {
      tx.set(histRef, { bins, updatedAt: Timestamp.fromMillis(nowMs) });
    }
  });
}

function bestRow(uid: string, data: LbPlayerDoc | Record<string, unknown>): LbBestRow | null {
  const p = data as Partial<LbPlayerDoc>;
  const score = typeof p.bestShadow === 'number' ? p.bestShadow : p.best;
  const atMs = timestampMs(p.bestAt);
  if (
    typeof uid !== 'string' ||
    uid.length === 0 ||
    p.hidden === true ||
    typeof score !== 'number' ||
    !Number.isSafeInteger(score) ||
    score <= 0 ||
    atMs === null ||
    typeof p.name !== 'string' ||
    p.name.length === 0 ||
    !validLook(p.look) ||
    (p.platform !== 'android' && p.platform !== 'ios') ||
    (p.card !== undefined && typeof p.card !== 'string')
  ) {
    return null;
  }
  return {
    uid,
    best: score,
    bestAt: Timestamp.fromMillis(atMs),
    name: p.name,
    look: baseLook(p.look),
    ...(p.card === undefined ? {} : { card: p.card }),
    platform: p.platform,
    bracket: bracketForVerifiedBest(score),
  };
}

/** Build the exact `lbBest/global` document from a snapshot of lbPlayers. */
export function bestDocFromPlayers(
  players: ReadonlyArray<{ uid: string; data: LbPlayerDoc | Record<string, unknown> }>,
  nowMs: number,
): LbBestDoc {
  const rows: LbBestRow[] = [];
  for (const player of players) {
    const row = bestRow(player.uid, player.data);
    if (row !== null) rows.push(row);
  }
  const ranked = rankBestRuns(rows);
  const top = ranked.slice(0, LB_BEST_SIZE).map((row) => {
    const { rank: _rank, ...rest } = row;
    return rest;
  });
  return {
    rows: top,
    floor: ranked.length > 0 ? ranked[Math.min(ranked.length, LB_BEST_SIZE) - 1].best : 0,
    updatedAt: Timestamp.fromMillis(nowMs),
  };
}

function sameBestRow(a: LbBestRow, b: LbBestRow): boolean {
  return (
    a.uid === b.uid &&
    a.best === b.best &&
    timestampMs(a.bestAt) === timestampMs(b.bestAt) &&
    a.name === b.name &&
    sameLook(a.look, b.look) &&
    a.card === b.card &&
    a.platform === b.platform &&
    a.bracket === b.bracket
  );
}

function sameBestDoc(existing: LbBestDoc | undefined, desired: LbBestDoc): boolean {
  if (existing === undefined || existing.floor !== desired.floor) return false;
  if (!Array.isArray(existing.rows) || existing.rows.length !== desired.rows.length) return false;
  return existing.rows.every((row, i) => sameBestRow(row, desired.rows[i]));
}

function sameUidList(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((uid, i) => uid === b[i]);
}

async function readPages(collection: CollectionReference<DocumentData>): Promise<QueryDocumentSnapshot<DocumentData>[]> {
  const docs: QueryDocumentSnapshot<DocumentData>[] = [];
  let last: QueryDocumentSnapshot<DocumentData> | null = null;
  for (;;) {
    let query = collection.limit(PAGE);
    if (last !== null) query = query.startAfter(last);
    const snap = await query.get();
    docs.push(...snap.docs);
    if (snap.size < PAGE) return docs;
    last = snap.docs[snap.docs.length - 1];
  }
}

async function readLbPlayersInTransaction(
  db: Firestore,
  tx: Transaction,
): Promise<Array<{ uid: string; data: LbPlayerDoc | Record<string, unknown> }>> {
  const docs: DocumentSnapshot<DocumentData>[] = [];
  let last: DocumentSnapshot<DocumentData> | null = null;
  for (;;) {
    let query = db.collection(LB_PLAYERS_COLLECTION).limit(PAGE);
    if (last !== null) query = query.startAfter(last);
    const snap = await tx.get(query);
    const lockedDocs = await Promise.all(snap.docs.map((doc) => tx.get(doc.ref)));
    docs.push(...lockedDocs);
    if (lockedDocs.length < PAGE) {
      return docs
        .filter((doc) => doc.exists)
        .map((doc) => ({ uid: doc.id, data: doc.data() as LbPlayerDoc | Record<string, unknown> }));
    }
    last = lockedDocs[lockedDocs.length - 1];
  }
}

/** Read every lbPlayer document (paged; production may hold many players). */
export async function readLbPlayers(
  db: Firestore,
): Promise<Array<{ uid: string; data: LbPlayerDoc | Record<string, unknown> }>> {
  const docs = await readPages(db.collection(LB_PLAYERS_COLLECTION));
  return docs.map((doc) => ({ uid: doc.id, data: doc.data() }));
}

/** Write the global BEST RUN cache from the current lbPlayers collection. */
export async function rebuildBest(db: Firestore, nowMs = Date.now()): Promise<LbBestDoc> {
  const best = bestDocFromPlayers(await readLbPlayers(db), nowMs);
  await db.collection(LB_BEST_COLLECTION).doc('global').set(best);
  return best;
}

export function printTop50(best: LbBestDoc, log: (line: string) => void): void {
  log(`Top 50 (${best.rows.length} row(s), floor ${best.floor}):`);
  best.rows.slice(0, LB_BEST_SIZE).forEach((row, i) => {
    log(`  #${String(i + 1).padStart(2)}  ${String(row.best).padStart(7)}  ${row.name}  ${row.uid}`);
  });
}

/** Small async batch that flushes before Firestore's 500-operation limit. */
export class BatchedWriter {
  private batch: WriteBatch;
  private ops = 0;

  constructor(private readonly db: Firestore) {
    this.batch = db.batch();
  }

  async set(ref: Parameters<WriteBatch['set']>[0], data: unknown): Promise<void> {
    this.batch.set(ref, data);
    await this.count();
  }

  async delete(ref: Parameters<WriteBatch['delete']>[0]): Promise<void> {
    this.batch.delete(ref);
    await this.count();
  }

  private async count(): Promise<void> {
    this.ops++;
    if (this.ops >= BATCH_LIMIT) await this.flush();
  }

  async flush(): Promise<void> {
    if (this.ops === 0) return;
    const batch = this.batch;
    this.batch = this.db.batch();
    this.ops = 0;
    await batch.commit();
  }
}

/**
 * Import one verified run per players/{uid}. Safe to rerun: a row already
 * owned by live play (`src: 'play'`) is preserved; an unchanged imported row
 * is not rewritten, so a repeated command leaves the same data and timestamps.
 * Each write is a transaction that rechecks the live row and the Delete My Data
 * tombstone. `lbBest/global` is rebuilt from the committed lbPlayers data.
 */
export async function importLeaderboard(db: Firestore, opts: ImportOptions): Promise<ImportResult> {
  const nowMs = opts.nowMs ?? Date.now();
  const apply = opts.apply === true && opts.dryRun !== true;
  const players = await readPages(db.collection('players'));
  const existing = await readLbPlayers(db);
  const existingByUid = new Map(existing.map((row) => [row.uid, row.data]));
  const planned = new Map<string, LbPlayerDoc>();
  const sourceCount = { bestRun: 0, recent: 0 };
  let skipped = 0;
  let tombstoned = 0;
  let expired = 0;
  let preservedPlay = 0;
  let planUnchanged = 0;
  let unchangedCount = 0;

  for (const doc of players) {
    const uid = doc.id;
    const playerDoc = doc.data() as PlayerDoc;
    const sourceExpireAt = timestampMs(playerDoc.expireAt);
    // Firestore TTL deletion may lag by a day. A document already past its
    // expiry is inactive source data and must not be revived by the import.
    if (sourceExpireAt !== null && sourceExpireAt <= nowMs) {
      expired++;
      continue;
    }
    const choice = verifiedRunFor(playerDoc);
    if (choice === null) {
      skipped++;
      continue;
    }
    if ((existingByUid.get(uid) as Partial<LbPlayerDoc> | undefined)?.src === 'play') {
      preservedPlay++;
      continue;
    }
    const next = importedPlayerDoc(uid, choice, nowMs);
    planned.set(uid, next);
    if (sameImportedPlayer(existingByUid.get(uid), next, nowMs)) planUnchanged++;
    sourceCount[choice.source]++;
  }

  const projected = new Map(existing.map((row) => [row.uid, row.data]));
  for (const [uid, data] of planned) projected.set(uid, data);
  const best = bestDocFromPlayers([...projected].map(([uid, data]) => ({ uid, data })), nowMs);

  logLine(
    opts,
    `${apply ? 'Import plan' : 'DRY RUN — nothing written'}: scanned ${players.length} player(s), ` +
      `${apply ? 'would write' : 'would import'} ${planned.size} ` +
      `(bestRun ${sourceCount.bestRun}, recent ${sourceCount.recent}), ` +
      `unchanged ${planUnchanged}, expired ${expired}, skip ${skipped}, preserve play-sourced ${preservedPlay}`,
  );
  logLine(
    opts,
    `  lbMeta/import.keepUids: ${opts.keepUids.length === 0 ? '(none)' : opts.keepUids.join(', ')}`,
  );
  printTop50(best, (line) => logLine(opts, line));

  let resultBest = best;
  if (apply) {
    const metaRef = db.collection(LB_META_COLLECTION).doc('import');
    // A changed keep-list invalidates cleanup even if no players are written.
    // Publish the list and invalidate its gate in the same transaction.
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(metaRef);
      const meta = snap.data() as Partial<LbMetaDoc> | undefined;
      if (snap.exists && !sameUidList(meta?.keepUids ?? [], opts.keepUids)) {
        tx.set(metaRef, { keepUids: opts.keepUids, cleanedAt: FieldValue.delete() }, { merge: true });
      }
    });

    let written = 0;
    let unchanged = 0;
    for (const [uid, data] of [...planned]) {
      const outcome = await commitImportedPlayer(db, uid, data, existingByUid.get(uid), nowMs);
      if (outcome === 'written') written++;
      else if (outcome === 'unchanged') unchanged++;
      else if (outcome === 'preservedPlay') {
        preservedPlay++;
        planned.delete(uid);
      } else {
        tombstoned++;
        planned.delete(uid);
      }
    }

    const bestRef = db.collection(LB_BEST_COLLECTION).doc('global');
    const committedBest = bestDocFromPlayers(await readLbPlayers(db), nowMs);
    const bestSnap = await bestRef.get();
    const existingBest = bestSnap.exists ? (bestSnap.data() as LbBestDoc) : undefined;
    const bestNeedsWrite = written > 0 || !sameBestDoc(existingBest, committedBest);
    if (bestNeedsWrite) resultBest = await rebuildBestFromCommitted(db, nowMs);
    else resultBest = existingBest ?? committedBest;
    await rebuildHistogramFromCommitted(db, nowMs);

    await db.runTransaction(async (tx) => {
      const metaSnap = await tx.get(metaRef);
      const meta = (metaSnap.data() ?? {}) as Partial<LbMetaDoc>;
      const keepListChanged = !sameUidList(meta.keepUids ?? [], opts.keepUids);
      const metaNeedsWrite =
        written > 0 ||
        !metaSnap.exists ||
        meta.ranAt === undefined ||
        meta.count !== planned.size ||
        keepListChanged;
      if (metaNeedsWrite) {
        const nextMeta: Record<string, unknown> = {
          ranAt: written > 0 || meta.ranAt === undefined ? Timestamp.fromMillis(nowMs) : meta.ranAt,
          count: planned.size,
          keepUids: opts.keepUids,
        };
        // Player writes already cleared this atomically. Do not clear a cleanup
        // completed since those writes merely because final metadata is due.
        if (keepListChanged) nextMeta.cleanedAt = FieldValue.delete();
        tx.set(metaRef, nextMeta, { merge: true });
      }
    });
    logLine(
      opts,
      written === 0
        ? 'Import complete: no data changed; nothing written.'
        : `Import complete: wrote ${written} lbPlayers, lbBest/global and lbMeta/import.`,
    );
    unchangedCount = unchanged;
  } else {
    unchangedCount = planUnchanged;
  }

  return {
    scanned: players.length,
    imported: planned.size,
    skipped,
    tombstoned,
    expired,
    preservedPlay,
    unchanged: unchangedCount,
    fromBestRun: sourceCount.bestRun,
    fromRecent: sourceCount.recent,
    best: resultBest,
    importedUids: [...planned.keys()].sort(),
  };
}

/** Shared CLI guard/runner: explicit project only, never a hidden production default. */
export async function runImportCli(argv: readonly string[]): Promise<number> {
  if (hasFlag(argv, 'help') || hasFlag(argv, 'h')) {
    console.log(IMPORT_USAGE);
    return 0;
  }
  if (!validImportArgs(argv)) {
    console.error('Invalid arguments.');
    console.error(IMPORT_USAGE);
    return 2;
  }
  const project = requiredProject(argv);
  if (project === null) {
    console.error('--project is required (the exact Firebase project id; there is no default).');
    console.error(IMPORT_USAGE);
    return 2;
  }
  const keepUids = parseUidList(parseOption(argv, 'keep'));
  const apply = hasFlag(argv, 'apply') && !hasFlag(argv, 'dry-run');
  const db = databaseForProject(project);
  console.log(`${project}: LB import${apply ? '' : ' dry run'} — keep ${keepUids.length} uid(s)`);
  await importLeaderboard(db, { keepUids, apply });
  return 0;
}

if (require.main === module) {
  runImportCli(process.argv.slice(2))
    .then((code) => {
      process.exitCode = code;
    })
    .catch((err) => {
      console.error(String(err));
      console.error(IMPORT_USAGE);
      process.exitCode = 1;
    });
}
