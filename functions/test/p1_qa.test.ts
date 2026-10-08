/** Independent P1 QA; activated only by the skipped Dart S6-08 reproducer. */
import assert from 'node:assert/strict';
import { deletePlayerData, processPlayerWrite } from '../src/pools.js';
import { RATE_COLLECTION, poolId } from '../src/schema.js';
import { db, makePlayer, makeRun, poolEntries, uniq } from './helpers.js';

describe('QA round P1', () => {
  const open = process.env.S6_QA_OPEN === '1' ? it : it.skip;
  open('S6-08 open: a delayed write after Delete my data leaves no pool or rate data', async () => {
    const uid = uniq('s6-delete');
    // A trigger can carry this snapshot after the callable has finished.
    const run = makeRun({ score: 160 });
    const snapshot = makePlayer({ best: 160, bestRun: run, recent: [run] });
    await deletePlayerData(db, uid);
    assert.equal((await db.collection('players').doc(uid).get()).exists, false);
    await processPlayerWrite(db, uid, undefined, snapshot, { rand: () => 0 });
    assert.deepEqual((await poolEntries(poolId(3, 0))).filter((e) => e.uid === uid), []);
    assert.equal((await db.collection(RATE_COLLECTION).doc(uid).get()).exists, false);
  });
});
