/**
 * PRD-2.6 C8 one-time import of verified best runs into the LB3 collections.
 *
 * The client-written `players/{uid}.best` value is never trusted. For each
 * player the verified `bestRun` is used when `checkRun` accepts it; otherwise
 * the highest verified `recent[]` run is used. A player with neither is
 * skipped. The import writes `lbPlayers` (`src: 'import'`, 400-day TTL),
 * rebuilds `lbBest/global` and records `lbMeta/import`.
 *
 *   cd functions && npx tsx scripts/lb_import.ts --project <id> [--keep uid,uid] [--dry-run]
 *
 * Auth: Application Default Credentials. Never run before the owner's OK on
 * the day (C8); the release-blocking test-player cleanup is separate.
 */
import { getApps, initializeApp } from 'firebase-admin/app';
import {
  FieldValue,
  Timestamp,
  getFirestore,
  type CollectionReference,
  type DocumentData,
  type Firestore,
  type QueryDocumentSnapshot,
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
  'usage: npx tsx scripts/lb_import.ts --project <firebase-project> [--keep uid1,uid2] [--dry-run] [--help]';
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
  /** Preview only: read and print, but write nothing. Default false. */
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
  preservedPlay: number;
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
  return validArgs(argv, ['--project', '--keep'], ['--dry-run', '--help', '-h']);
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
 * owned by live play (`src: 'play'`) is preserved; imported rows are updated.
 */
export async function importLeaderboard(db: Firestore, opts: ImportOptions): Promise<ImportResult> {
  const nowMs = opts.nowMs ?? Date.now();
  const dryRun = opts.dryRun === true;
  const players = await readPages(db.collection('players'));
  const existing = await readLbPlayers(db);
  const existingByUid = new Map(existing.map((row) => [row.uid, row.data]));
  const importedNow = new Map<string, LbPlayerDoc>();
  const sourceCount = { bestRun: 0, recent: 0 };
  let skipped = 0;
  let preservedPlay = 0;

  for (const doc of players) {
    const uid = doc.id;
    const choice = verifiedRunFor(doc.data() as PlayerDoc);
    if (choice === null) {
      skipped++;
      continue;
    }
    if ((existingByUid.get(uid) as Partial<LbPlayerDoc> | undefined)?.src === 'play') {
      preservedPlay++;
      continue;
    }
    importedNow.set(uid, importedPlayerDoc(uid, choice, nowMs));
    sourceCount[choice.source]++;
  }

  const projected = new Map(existing.map((row) => [row.uid, row.data]));
  for (const [uid, data] of importedNow) projected.set(uid, data);
  const best = bestDocFromPlayers([...projected].map(([uid, data]) => ({ uid, data })), nowMs);

  logLine(
    opts,
    `${dryRun ? 'DRY RUN — nothing written' : 'Import plan'}: scanned ${players.length} player(s), ` +
      `${dryRun ? 'would import' : 'will write'} ${importedNow.size} ` +
      `(bestRun ${sourceCount.bestRun}, recent ${sourceCount.recent}), ` +
      `skip ${skipped}, preserve play-sourced ${preservedPlay}`,
  );
  logLine(
    opts,
    `  lbMeta/import.keepUids: ${opts.keepUids.length === 0 ? '(none)' : opts.keepUids.join(', ')}`,
  );
  printTop50(best, (line) => logLine(opts, line));

  if (!dryRun) {
    const writer = new BatchedWriter(db);
    for (const [uid, data] of importedNow) {
      await writer.set(db.collection(LB_PLAYERS_COLLECTION).doc(uid), data);
    }
    await writer.flush();
    await db.collection(LB_BEST_COLLECTION).doc('global').set(best);
    const meta: Pick<LbMetaDoc, 'ranAt' | 'count' | 'keepUids'> = {
      ranAt: Timestamp.fromMillis(nowMs),
      count: importedNow.size,
      keepUids: opts.keepUids,
    };
    // A rerun invalidates an earlier cleanup gate.
    await db
      .collection(LB_META_COLLECTION)
      .doc('import')
      .set({ ...meta, cleanedAt: FieldValue.delete() }, { merge: true });
    logLine(opts, `Import complete: wrote ${importedNow.size} lbPlayers, lbBest/global and lbMeta/import.`);
  }

  return {
    scanned: players.length,
    imported: importedNow.size,
    skipped,
    preservedPlay,
    fromBestRun: sourceCount.bestRun,
    fromRecent: sourceCount.recent,
    best,
    importedUids: [...importedNow.keys()].sort(),
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
  const dryRun = hasFlag(argv, 'dry-run');
  if (getApps().length === 0) initializeApp({ projectId: project });
  console.log(`${project}: ${dryRun ? 'LB import dry run' : 'LB import'} — keep ${keepUids.length} uid(s)`);
  await importLeaderboard(getFirestore(), { keepUids, dryRun });
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
