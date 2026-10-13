/** P23 QA P1: §5.5 retention applies to the §21.3 profile picture too. */
import assert from 'node:assert/strict';
import { getStorage } from 'firebase-admin/storage';
import { avatarBucketName, avatarPath } from '../src/avatars.js';
import { processPlayerWrite } from '../src/pools.js';
import { db, makePlayer, uniq } from './helpers.js';

describe('PRD-2.3 QA P1 privacy retention', () => {
  it.skip('S8-06: a TTL-deleted player also deletes their publicly readable avatar', async () => {
    const uid = uniq('ttl-avatar');
    const before = makePlayer({ best: 120 });
    const file = getStorage().bucket(avatarBucketName()).file(avatarPath(uid));
    await file.save(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]), { contentType: 'image/jpeg' });
    try {
      await db.collection('players').doc(uid).set(before);
      await db.collection('players').doc(uid).delete();
      // onPlayerRunWrite forwards exactly these snapshots for a TTL delete.
      await processPlayerWrite(db, uid, before, undefined);
      assert.equal((await file.exists())[0], false,
        '§5.5: versus data is deleted about 60 days after the last run');
    } finally {
      await file.delete({ ignoreNotFound: true });
    }
  });
});
