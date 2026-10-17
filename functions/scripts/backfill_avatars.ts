/**
 * WP-AV (2.4) one-off: the sticker-avatar backfill ("all users including
 * test users get new thumbnails"). For every `players/{uid}` doc and every
 * pool entry it sets a RANDOM bird / gear / hat from the catalogue (gear
 * and hat 'none' ~40 % of the time; hoop and trail kept), a generated name
 * (a name that already is a generated one is kept: the player's phone
 * writes it again with its next run) and `avatar: ''`, and drops any
 * platform-name field. Then it deletes every object under `avatars/` in
 * the default Storage bucket. A player keeps one identity across their
 * player doc and all their pool entries. Idempotent in effect (a second
 * run just re-rolls the looks); nothing else is touched.
 *
 * Run AFTER the 2.4 functions + rules are deployed (orchestrator only),
 * with application-default credentials of an owner account:
 *
 *   cd functions
 *   GCLOUD_PROJECT=flappy-spikes-a2b55 npx tsx scripts/backfill_avatars.ts --dry-run
 *   GCLOUD_PROJECT=flappy-spikes-a2b55 npx tsx scripts/backfill_avatars.ts --run
 *
 * `--dry-run` reads everything and prints the counts, writes nothing.
 * `--run` writes. One of the two flags is required. Optional
 * `--bucket=<name>` (default `<project>.firebasestorage.app`, else
 * `<project>.appspot.com` when that one exists) and `--seed=<text>` (the
 * random seed, default: random; printed so a run can be repeated).
 *
 * Against the emulators: FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 * FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 GCLOUD_PROJECT=demo-flappy-spikes …
 */
import { randomBytes } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { allPoolIds } from '../src/schema.js';
import { identityFor, isAvatarObject, PlayerIdentity, rewritePlayer, rewritePoolEntries } from './backfill_lib.js';

function flag(name: string): string | undefined {
  const hit = process.argv.find((a) => a === `--${name}` || a.startsWith(`--${name}=`));
  if (!hit) return undefined;
  const eq = hit.indexOf('=');
  return eq < 0 ? '' : hit.slice(eq + 1);
}

async function main(): Promise<void> {
  const project = process.env.GCLOUD_PROJECT;
  if (!project) throw new Error('Set GCLOUD_PROJECT (e.g. flappy-spikes-a2b55).');
  const dryRun = flag('dry-run') !== undefined;
  const run = flag('run') !== undefined;
  if (dryRun === run) throw new Error('Pass exactly one of --dry-run or --run.');
  const seed = flag('seed') || randomBytes(8).toString('hex');
  initializeApp({ projectId: project });
  const db = getFirestore();
  const mode = dryRun ? 'DRY RUN (nothing is written)' : 'RUN';
  console.log(`backfill_avatars ${mode} project=${project} seed=${seed}`);

  // 1. Player docs: one identity per uid.
  const ids = new Map<string, PlayerIdentity>();
  const players = await db.collection('players').get();
  let playerWrites = 0;
  let platformFields = 0;
  let renamed = 0;
  let batch = db.batch();
  let pending = 0;
  for (const snap of players.docs) {
    const doc = snap.data();
    const id = identityFor(snap.id, doc.name, seed);
    ids.set(snap.id, id);
    const { set, remove } = rewritePlayer(doc, id);
    if (set.name !== doc.name) renamed++;
    platformFields += remove.length;
    const update: Record<string, unknown> = { ...set };
    for (const f of remove) update[f] = FieldValue.delete();
    playerWrites++;
    if (!dryRun) {
      batch.update(snap.ref, update);
      if (++pending >= 400) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }
  }
  if (!dryRun && pending > 0) await batch.commit();
  console.log(
    `players: ${players.size} docs, ${playerWrites} updated, ${renamed} renamed, ` +
      `${platformFields} platform fields removed`,
  );

  // 2. Pool entries (all 44 shards), each in its own transaction.
  const idOf = (uid: string, name: unknown) => {
    let id = ids.get(uid);
    if (!id) {
      id = identityFor(uid, name, seed);
      ids.set(uid, id);
    }
    return id;
  };
  let poolDocs = 0;
  let poolEntries = 0;
  for (const pid of allPoolIds()) {
    const ref = db.collection('pools').doc(pid);
    if (dryRun) {
      const snap = await ref.get();
      if (!snap.exists) continue;
      const entries = snap.get('entries');
      if (!Array.isArray(entries)) continue;
      rewritePoolEntries(entries, idOf);
      poolDocs++;
      poolEntries += entries.length;
      continue;
    }
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const entries = snap.get('entries');
      if (!Array.isArray(entries)) return;
      tx.update(ref, { entries: rewritePoolEntries(entries, idOf) });
      poolDocs++;
      poolEntries += entries.length;
    });
  }
  console.log(`pools: ${poolDocs} docs, ${poolEntries} entries rewritten`);

  // 3. Storage: every object under avatars/.
  let bucketName = flag('bucket') || `${project}.firebasestorage.app`;
  let bucket = getStorage().bucket(bucketName);
  if (!flag('bucket')) {
    const [exists] = await bucket.exists().catch(() => [false]);
    if (!exists) {
      bucketName = `${project}.appspot.com`;
      bucket = getStorage().bucket(bucketName);
    }
  }
  const [files] = await bucket.getFiles({ prefix: 'avatars/', autoPaginate: true });
  const doomed = files.filter((f) => isAvatarObject(f.name));
  if (!dryRun) {
    for (const f of doomed) await f.delete({ ignoreNotFound: true });
  }
  console.log(`storage gs://${bucketName}: ${doomed.length} objects under avatars/ ${dryRun ? 'to delete' : 'deleted'}`);
  console.log(`players with an identity: ${ids.size}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
