/**
 * PRD-2.2 §13.5 the one-off conversion of the 2.1 (timeline v1) pool runs into
 * format v2: every entry keeps its `tl`, `end`, score and flags and gets the
 * value 1 per entry (one v1 entry was one point). In place, every level and
 * shard, one transaction per pool document; idempotent (v2 entries are left
 * alone) and nothing is deleted. Driven by `scripts/convert_pools_v2.ts`; not
 * exported as a Cloud Function.
 */
import { Firestore } from 'firebase-admin/firestore';
import { allPoolIds, PoolDoc } from './schema.js';
import { convertV1ToV2, decodeDeltas, isV2 } from './timeline.js';

export interface ConvertResult {
  /** Pool documents read. */
  docs: number;
  /** Entries seen. */
  entries: number;
  /** Entries rewritten from v1 to v2. */
  converted: number;
  /** Entries already v2 (left alone). */
  alreadyV2: number;
  /** Entries that are neither well-formed v1 nor v2 (left alone, logged). */
  malformed: string[];
}

/** Converts every pool shard ([dryRun]: counts only, writes nothing). */
export async function convertPools(db: Firestore, { dryRun = false } = {}): Promise<ConvertResult> {
  const result: ConvertResult = { docs: 0, entries: 0, converted: 0, alreadyV2: 0, malformed: [] };
  for (const id of allPoolIds()) {
    const ref = db.collection('pools').doc(id);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      result.docs++;
      const pool = snap.data() as PoolDoc;
      const entries = Array.isArray(pool.entries) ? pool.entries : [];
      let changed = 0;
      const next = entries.map((e) => {
        result.entries++;
        const fl = convertV1ToV2(e);
        if (fl === null) {
          // Already v2 (idempotent) or malformed: left alone.
          const deltas = decodeDeltas(e.tl);
          if (deltas !== null && isV2(e.fl, deltas.length)) result.alreadyV2++;
          else result.malformed.push(`${id}/${e.runId}`);
          return e;
        }
        changed++;
        return { ...e, fl };
      });
      result.converted += changed;
      if (changed > 0 && !dryRun) tx.update(ref, { entries: next });
    });
  }
  return result;
}
