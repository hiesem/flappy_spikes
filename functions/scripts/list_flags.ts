/**
 * PRD-2.5 §3.6 review of the versus anomaly flags (read-only).
 *
 *   cd functions && npx tsx scripts/list_flags.ts [--days 7] [--limit 200] [--project flappy-spikes-a2b55]
 *
 * Auth: Application Default Credentials (`gcloud auth application-default login`).
 * Prints the newest flags (uid prefix, score, best, signals, pool), hard
 * flags first and soft (`jump` only) ones in their own list. It never
 * writes: removing a pool entry stays a manual decision (Terms of Use).
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { FLAGS_COLLECTION, FlagDoc } from '../src/schema.js';

function arg(name: string, fallback: string): string {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}

async function main(): Promise<void> {
  const days = Number(arg('days', '7'));
  const limit = Number(arg('limit', '200'));
  const project = arg('project', process.env.GCLOUD_PROJECT ?? 'flappy-spikes-a2b55');
  if (!Number.isFinite(days) || days <= 0 || !Number.isInteger(limit) || limit <= 0) {
    console.error('usage: npx tsx scripts/list_flags.ts [--days N] [--limit N] [--project id]');
    process.exit(2);
  }
  initializeApp({ projectId: project });
  const since = Timestamp.fromMillis(Date.now() - days * 24 * 3600 * 1000);
  const snap = await getFirestore()
    .collection(FLAGS_COLLECTION)
    .where('ts', '>=', since)
    .orderBy('ts', 'desc')
    .limit(limit)
    .get();
  const flags = snap.docs.map((d) => d.data() as FlagDoc);
  const line = (f: FlagDoc) =>
    [
      f.ts.toDate().toISOString().slice(0, 16).replace('T', ' '),
      `${f.uid.slice(0, 8)}…`,
      `score ${f.score}`,
      `best ${f.best}`,
      Object.entries(f.signals ?? {})
        .map(([k, v]) => `${k}=${v}`)
        .join(' '),
      `passes ${f.passes} in ${(f.durationCs / 100).toFixed(1)} s`,
      `L${f.level}`,
      f.pool ? `pool ${f.pool}` : 'not pooled',
      f.platform,
    ].join('  ');
  const hard = flags.filter((f) => !f.soft);
  const soft = flags.filter((f) => f.soft);
  console.log(`${project}: ${flags.length} flag(s) in the last ${days} day(s)${flags.length === limit ? ' (limit reached)' : ''}`);
  console.log(`\nHard (${hard.length}):`);
  hard.forEach((f) => console.log(`  ${line(f)}`));
  console.log(`\nSoft — score jump only (${soft.length}):`);
  soft.forEach((f) => console.log(`  ${line(f)}`));
}

main().catch((err) => {
  console.error(String(err));
  process.exit(1);
});
