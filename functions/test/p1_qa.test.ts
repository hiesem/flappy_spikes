/** Independent P1 QA (S6-08, fixed in Fix P1 R1). */
import assert from 'node:assert/strict';
import { deletePlayerData, processPlayerWrite } from '../src/pools.js';
import { RATE_COLLECTION, poolId } from '../src/schema.js';
import { db, makePlayer, makeRun, poolEntries, uniq } from './helpers.js';

describe('QA round P1', () => {
  it('S6-08 a delayed write after Delete my data leaves no pool or rate data', async () => {
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
