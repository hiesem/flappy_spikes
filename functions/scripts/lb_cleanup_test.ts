/**
 * PRD-2.6 C9 release-blocking cleanup of generated test players from the
 * NEW leaderboard collections only (never the versus pools, O7).
 *
 * Dry run is the default: it reads the LB collections, prints the exact
 * deletions and writes nothing. `--apply` deletes every imported
 * `lbPlayers` uid not on `--keep`, plus their gifts, ghost-pool entries and
 * rows in groups, rebuilds `lbBest/global`, sets `lbMeta/import.cleanedAt`
 * and prints the remaining top 50. Live play rows (`src: 'play'`) are never
 * deleted.
 *
 *   cd functions && npx tsx scripts/lb_cleanup_test.ts --project <id> --keep uid1,uid2 [--apply]
 *
 * Auth: Application Default Credentials.
 */
import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import {
  LB_BEST_COLLECTION,
  LB_GIFTS_COLLECTION,
  LB_GHOST_POOL_COLLECTION,
  LB_GROUPS_COLLECTION,
  LB_META_COLLECTION,
  LB_PLAYERS_COLLECTION,
  type LbGhostDay,
  type LbGhostPoolDoc,
  type LbGroupDoc,
  type LbMetaDoc,
  type LbPlayerDoc,
} from '../src/schema.js';
import {
  BatchedWriter,
  bestDocFromPlayers,
  databaseForProject,
  hasFlag,
  logLine,
  parseOption,
  parseUidList,
  printTop50,
  readLbPlayers,
  requiredProject,
  validCleanupArgs,
} from './lb_import.js';

export const CLEANUP_USAGE =
  'usage: npx tsx scripts/lb_cleanup_test.ts --project <firebase-project> --keep uid1,uid2 [--apply] [--help]';

const PAGE = 500;

export interface CleanupOptions {
  /** The only imported players allowed to survive. */
  keepUids: string[];
  /** Dry run unless true. */
  apply: boolean;
  nowMs?: number;
  log?: (line: string) => void;
}

export interface CleanupResult {
  keep: string[];
  imported: number;
  removedPlayers: string[];
  keptImported: number;
  keptPlay: number;
  gifts: number;
  ghostEntries: number;
  groupRows: number;
  groupsChanged: number;
  bestRows: number;
}

interface Orphan {
  collection: string;
  id: string;
  uid: string;
}

interface GhostChange {
  uid: string;
  pool: string;
}

export interface GroupChange {
  gid: string;
  removeMembers: string[];
  removeGhosts: string[];
  removeGhostUids: string[];
}

export interface CleanupPlan {
  result: CleanupResult;
  keepUids: string[];
  apply: boolean;
  removed: Set<string>;
  orphans: Orphan[];
  ghostChanges: GhostChange[];
  groupChanges: GroupChange[];
  best: ReturnType<typeof bestDocFromPlayers>;
  nowMs: number;
  remaining: Array<{ uid: string; data: LbPlayerDoc | Record<string, unknown> }>;
}

function playerUid(data: unknown): string {
  const uid = (data as { uid?: unknown } | null)?.uid;
  return typeof uid === 'string' ? uid : '';
}

/** Gift doc ids are `<uid>_<gid>`; the stored uid is authoritative when present. */
function giftUid(id: string, data: unknown): string {
  const stored = playerUid(data);
  if (stored) return stored;
  const cut = id.lastIndexOf('_');
  return cut > 0 ? id.slice(0, cut) : id;
}

/** Remove uids from one embedded ghost-pool list, preserving every other row. */
export function pruneGhostEntries(entries: unknown, removed: ReadonlySet<string>): LbGhostDay[] {
  if (!Array.isArray(entries)) return [];
  return (entries as LbGhostDay[]).filter((entry) => !removed.has(entry?.uid));
}

/** Remove a uid's member row and every ghost row; keep all remaining rows intact. */
export function pruneGroup(group: LbGroupDoc, removed: ReadonlySet<string>): GroupChange | null {
  // memberUids and members are normally in sync, but a partial write must not
  // let a removed test player survive in either representation.
  const memberIds = new Set([...(group.memberUids ?? []), ...Object.keys(group.members ?? {})]);
  const removeMembers = [...memberIds].filter((uid) => removed.has(uid)).sort();
  const removeGhosts = (group.ghosts ?? [])
    .filter((ghost) => typeof ghost.uid === 'string' && removed.has(ghost.uid))
    .map((ghost) => ghost.uid as string);
  const removeGhostUids = [...new Set([...(group.ghostUids ?? []), ...removeGhosts])].filter((uid) =>
    removed.has(uid),
  );
  if (removeMembers.length === 0 && removeGhosts.length === 0 && removeGhostUids.length === 0) return null;
  return { gid: '', removeMembers, removeGhosts: [...new Set(removeGhosts)], removeGhostUids };
}

async function readAll<T>(db: Firestore, collection: string): Promise<Array<{ id: string; data: T }>> {
  const out: Array<{ id: string; data: T }> = [];
  const ref = db.collection(collection);
  let last: unknown = null;
  for (;;) {
    let query = ref.limit(PAGE);
    if (last !== null) query = query.startAfter(last);
    const snap = await query.get();
    for (const doc of snap.docs) out.push({ id: doc.id, data: doc.data() as T });
    if (snap.size < PAGE) return out;
    last = snap.docs[snap.docs.length - 1];
  }
}

/** Pure cleanup plan; the caller serialises exactly this, whether applying or printing it. */
export async function planCleanup(db: Firestore, opts: CleanupOptions): Promise<CleanupPlan> {
  const nowMs = opts.nowMs ?? Date.now();
  const keep = new Set(opts.keepUids);
  const players = await readLbPlayers(db);
  const imported = players.filter((row) => (row.data as Partial<LbPlayerDoc>).src === 'import');
  const removed = new Set<string>();
  let keptImported = 0;
  let keptPlay = 0;
  for (const row of imported) {
    if (keep.has(row.uid)) keptImported++;
    else removed.add(row.uid);
  }
  for (const row of players) {
    if ((row.data as Partial<LbPlayerDoc>).src === 'play') keptPlay++;
  }

  const orphans: Orphan[] = [];
  for (const doc of await readAll<Record<string, unknown>>(db, LB_GIFTS_COLLECTION)) {
    const uid = giftUid(doc.id, doc.data);
    if (removed.has(uid)) orphans.push({ collection: LB_GIFTS_COLLECTION, id: doc.id, uid });
  }

  const ghostChanges: GhostChange[] = [];
  for (const doc of await readAll<LbGhostPoolDoc>(db, LB_GHOST_POOL_COLLECTION)) {
    for (const entry of doc.data.entries ?? []) {
      if (removed.has(entry?.uid)) ghostChanges.push({ uid: entry.uid, pool: doc.id });
    }
  }

  const groupChanges: GroupChange[] = [];
  for (const doc of await readAll<LbGroupDoc>(db, LB_GROUPS_COLLECTION)) {
    const change = pruneGroup(doc.data, removed);
    if (change !== null) groupChanges.push({ ...change, gid: doc.id });
  }

  const remaining = players.filter((row) => !removed.has(row.uid));
  const best = bestDocFromPlayers(remaining, nowMs);
  const result: CleanupResult = {
    keep: opts.keepUids,
    imported: imported.length,
    removedPlayers: [...removed].sort(),
    keptImported,
    keptPlay,
    gifts: orphans.length,
    ghostEntries: ghostChanges.length,
    groupRows: groupChanges.reduce(
      (n, change) => n + change.removeMembers.length + change.removeGhosts.length,
      0,
    ),
    groupsChanged: groupChanges.length,
    bestRows: best.rows.length,
  };
  return {
    result,
    keepUids: opts.keepUids,
    apply: opts.apply,
    removed,
    orphans,
    ghostChanges,
    groupChanges,
    best,
    nowMs,
    remaining,
  };
}

/** Print every planned action. Dry-run output is the review contract before C9's --apply. */
export function printCleanupPlan(project: string, apply: boolean, plan: CleanupPlan, log = console.log): void {
  const { result } = plan;
  log(`${project}: ${apply ? 'LB cleanup APPLY' : 'LB cleanup DRY RUN'} — keep ${result.keep.length} uid(s)`);
  log(
    `  imported lbPlayers ${result.imported}; keep ${result.keptImported}; ` +
      `remove ${result.removedPlayers.length}; leave play-sourced ${result.keptPlay}`,
  );
  log(
    `  delete ${result.gifts} gift(s), ${result.ghostEntries} ghost-pool entr(y/ies), ` +
      `and remove ${result.groupRows} group row(s) in ${result.groupsChanged} group(s)`,
  );
  for (const uid of result.removedPlayers) log(`  DELETE lbPlayers/${uid}`);
  for (const item of plan.orphans) log(`  DELETE ${item.collection}/${item.id} (uid ${item.uid})`);
  for (const item of plan.ghostChanges) log(`  REMOVE ghost ${item.uid} from ${LB_GHOST_POOL_COLLECTION}/${item.pool}`);
  for (const change of plan.groupChanges) {
    for (const uid of change.removeMembers) log(`  REMOVE member ${uid} from ${LB_GROUPS_COLLECTION}/${change.gid}`);
    for (const uid of change.removeGhosts) log(`  REMOVE ghost ${uid} from ${LB_GROUPS_COLLECTION}/${change.gid}`);
    if (change.removeGhostUids.length > 0) {
      log(`  PRUNE ghostUids [${change.removeGhostUids.join(', ')}] from ${LB_GROUPS_COLLECTION}/${change.gid}`);
    }
  }
  if (apply) log('  REBUILD lbBest/global, SET lbMeta/import.cleanedAt');
  else log('DRY RUN — nothing written. Pass --apply to perform these exact deletions.');
  printTop50(plan.best, log);
}

async function applyCleanup(db: Firestore, plan: CleanupPlan): Promise<ReturnType<typeof bestDocFromPlayers>> {
  const writer = new BatchedWriter(db);
  for (const uid of plan.result.removedPlayers) {
    await writer.delete(db.collection(LB_PLAYERS_COLLECTION).doc(uid));
  }
  for (const item of plan.orphans) {
    await writer.delete(db.collection(item.collection).doc(item.id));
  }

  const poolIds = [...new Set(plan.ghostChanges.map((change) => change.pool))];
  for (const id of poolIds) {
    const ref = db.collection(LB_GHOST_POOL_COLLECTION).doc(id);
    const snap = await ref.get();
    if (!snap.exists) continue;
    const pool = snap.data() as LbGhostPoolDoc;
    const entries = pruneGhostEntries(pool.entries, plan.removed);
    // Remove the entries, not the pool document itself.
    await writer.set(ref, { ...pool, entries, updatedAt: Timestamp.fromMillis(plan.nowMs) });
  }

  for (const change of plan.groupChanges) {
    const ref = db.collection(LB_GROUPS_COLLECTION).doc(change.gid);
    const snap = await ref.get();
    if (!snap.exists) continue;
    const group = snap.data() as LbGroupDoc;
    const members = Object.fromEntries(
      Object.entries(group.members ?? {}).filter(([uid]) => !plan.removed.has(uid)),
    );
    await writer.set(ref, {
      ...group,
      memberUids: (group.memberUids ?? []).filter((uid) => !plan.removed.has(uid)),
      members,
      ghosts: (group.ghosts ?? []).filter((ghost) => !plan.removed.has(ghost.uid ?? '')),
      ghostUids: (group.ghostUids ?? []).filter((uid) => !plan.removed.has(uid)),
    });
  }

  await writer.flush();
  // Re-read after the deletes: the printed board is exactly what the live collection now holds.
  const after = bestDocFromPlayers(await readLbPlayers(db), plan.nowMs);
  await db.collection(LB_BEST_COLLECTION).doc('global').set(after);

  const metaRef = db.collection(LB_META_COLLECTION).doc('import');
  const metaSnap = await metaRef.get();
  const meta = (metaSnap.exists ? metaSnap.data() : {}) as Partial<LbMetaDoc>;
  await metaRef.set(
    {
      ranAt: meta.ranAt ?? FieldValue.serverTimestamp(),
      count: meta.count ?? 0,
      keepUids: plan.keepUids,
      cleanedAt: Timestamp.fromMillis(plan.nowMs),
    },
    { merge: true },
  );
  return after;
}

export async function cleanupLeaderboard(db: Firestore, opts: CleanupOptions): Promise<CleanupResult> {
  const plan = await planCleanup(db, opts);
  printCleanupPlan('cleanup', opts.apply, plan, (line) => logLine(opts, line));
  if (opts.apply) plan.best = await applyCleanup(db, plan);
  return plan.result;
}

export async function runCleanupCli(argv: readonly string[]): Promise<number> {
  if (hasFlag(argv, 'help') || hasFlag(argv, 'h')) {
    console.log(CLEANUP_USAGE);
    return 0;
  }
  if (!validCleanupArgs(argv)) {
    console.error('Invalid arguments.');
    console.error(CLEANUP_USAGE);
    return 2;
  }
  const project = requiredProject(argv);
  if (project === null) {
    console.error('--project is required (the exact Firebase project id; there is no default).');
    console.error(CLEANUP_USAGE);
    return 2;
  }
  const keepUids = parseUidList(parseOption(argv, 'keep'));
  if (keepUids.length === 0) {
    console.error('--keep is required: the owner uids that must survive the cleanup');
    console.error(CLEANUP_USAGE);
    return 2;
  }
  const apply = hasFlag(argv, 'apply');
  const db = databaseForProject(project);
  const plan = await planCleanup(db, { keepUids, apply });
  printCleanupPlan(project, apply, plan);
  if (apply) plan.best = await applyCleanup(db, plan);
  return 0;
}

if (require.main === module) {
  runCleanupCli(process.argv.slice(2))
    .then((code) => {
      process.exitCode = code;
    })
    .catch((err) => {
      console.error(String(err));
      console.error(CLEANUP_USAGE);
      process.exitCode = 1;
    });
}
