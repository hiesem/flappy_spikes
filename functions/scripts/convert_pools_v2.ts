/**
 * PRD-2.2 §13.5 one-off: converts every 2.1 (timeline v1) run in the versus
 * pools to format v2 (value 1 per entry, same score, flags kept), in place,
 * every level and shard. Idempotent; logs the counts. Nothing is deleted.
 *
 * Run AFTER the updated functions are deployed (orchestrator only):
 *
 *   gcloud auth application-default login        # once, an owner account
 *   cd functions
 *   GCLOUD_PROJECT=flappy-spikes-a2b55 npx tsx scripts/convert_pools_v2.ts --dry-run
 *   GCLOUD_PROJECT=flappy-spikes-a2b55 npx tsx scripts/convert_pools_v2.ts
 *
 * Against the emulator: FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 * GCLOUD_PROJECT=demo-flappy-spikes npx tsx scripts/convert_pools_v2.ts
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { convertPools } from '../src/convert.js';

async function main(): Promise<void> {
  const project = process.env.GCLOUD_PROJECT;
  if (!project) throw new Error('Set GCLOUD_PROJECT (e.g. flappy-spikes-a2b55).');
  const dryRun = process.argv.includes('--dry-run');
  initializeApp({ projectId: project });
  const r = await convertPools(getFirestore(), { dryRun });
  console.log(
    `convert_pools_v2 ${dryRun ? '(dry run) ' : ''}project=${project}: ` +
      `${r.docs} pool docs, ${r.entries} entries, ${r.converted} converted, ` +
      `${r.alreadyV2} already v2, ${r.malformed.length} malformed`,
  );
  if (r.malformed.length) console.log('malformed (left alone):', r.malformed.join(', '));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
