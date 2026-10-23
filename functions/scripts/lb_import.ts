/**
 * PRD-2.6 C8 one-time import of verified best runs into the LB3 collections.
 *
 * Wave-0 skeleton: argument parsing and the dry-run contract are installed;
 * the later LB work package fills the import transaction. It is runnable with
 * tsx and writes nothing unless `--execute` is passed.
 *
 *   cd functions && npx tsx scripts/lb_import.ts [--project id] [--keep uid,uid] [--execute]
 *
 * Auth: Application Default Credentials. Never run before the owner's OK on
 * the day (C8); the release-blocking test-player cleanup is separate.
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { LB_META_COLLECTION } from '../src/schema.js';

const USAGE =
  'usage: npx tsx scripts/lb_import.ts [--project id] [--keep uid1,uid2] [--execute] [--help]';

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
  const project = arg('project', process.env.GCLOUD_PROJECT ?? 'flappy-spikes-a2b55');
  const keep = arg('keep', '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  const execute = has('execute');
  initializeApp({ projectId: project });
  const meta = await getFirestore().collection(LB_META_COLLECTION).doc('import').get();
  console.log(
    `${project}: ${execute ? 'execute' : 'dry run'} — LB import skeleton, keep ${keep.length} uid(s)` +
      (meta.exists ? '; lbMeta/import exists' : '; lbMeta/import missing'),
  );
  if (!execute) console.log('dry run: nothing written (pass --execute when the import body is implemented).');
}

main().catch((err) => {
  console.error(String(err));
  console.error(USAGE);
  process.exitCode = 1;
});
