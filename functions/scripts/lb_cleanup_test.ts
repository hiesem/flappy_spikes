/**
 * PRD-2.6 C9 release-blocking cleanup of generated test players from the
 * NEW leaderboard collections only (never the versus pools, O7).
 *
 * Wave-0 skeleton: dry run is the default and prints its usage / contract.
 * The later LB work package implements the delete batches, the keep list and
 * `lbMeta/import.cleanedAt`.
 *
 *   cd functions && npx tsx scripts/lb_cleanup_test.ts --keep uid1,uid2 [--project id] [--execute]
 *
 * Auth: Application Default Credentials.
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { LB_META_COLLECTION } from '../src/schema.js';

const USAGE =
  'usage: npx tsx scripts/lb_cleanup_test.ts --keep uid1,uid2 [--project id] [--execute] [--help]';

function arg(name: string, fallback: string): string {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}

function has(name: string): boolean {
  return process.argv.includes(`--${name}`);
}

async function main(): Promise<void> {
  if (has('help') || has('h')) {
    console.log(USAGE);
    return;
  }
  const keep = arg('keep', '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  const project = arg('project', process.env.GCLOUD_PROJECT ?? 'flappy-spikes-a2b55');
  const execute = has('execute');
  if (keep.length === 0) {
    console.error('--keep is required: the owner uids that must survive the cleanup');
    console.error(USAGE);
    process.exitCode = 2;
    return;
  }
  initializeApp({ projectId: project });
  const meta = await getFirestore().collection(LB_META_COLLECTION).doc('import').get();
  console.log(
    `${project}: ${execute ? 'execute' : 'dry run'} — LB test cleanup skeleton, keep ${keep.length} uid(s)` +
      (meta.exists ? '; lbMeta/import exists' : '; lbMeta/import missing'),
  );
  if (!execute) console.log('dry run: nothing deleted (pass --execute when the cleanup body is implemented).');
}

main().catch((err) => {
  console.error(String(err));
  console.error(USAGE);
  process.exitCode = 1;
});
