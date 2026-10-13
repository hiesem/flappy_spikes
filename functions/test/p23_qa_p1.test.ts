/** P23 QA P1: §5.5 retention applies to the §21.3 profile picture too. */
import assert from 'node:assert/strict';
import { getStorage } from 'firebase-admin/storage';
import { avatarBucketName, avatarPath } from '../src/avatars.js';
import { processPlayerWrite, sweepStaleAvatars } from '../src/pools.js';
import { db, makePlayer, uniq } from './helpers.js';

describe('PRD-2.3 QA P1 privacy retention', () => {
  it('S8-06: a TTL-deleted player also deletes their publicly readable avatar', async () => {
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

  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]);

  it('S8-06: a player whose doc exists again keeps the picture', async () => {
    const uid = uniq('ttl-back');
    const before = makePlayer({ best: 120 });
    const file = getStorage().bucket(avatarBucketName()).file(avatarPath(uid));
    await file.save(jpeg, { contentType: 'image/jpeg' });
    try {
      // The delete event arrives after the player already wrote a new run.
      await db.collection('players').doc(uid).set(before);
      const r = await processPlayerWrite(db, uid, before, undefined);
      assert.equal(r.avatarDeleted, false);
      assert.equal((await file.exists())[0], true);
    } finally {
      await db.collection('players').doc(uid).delete();
      await file.delete({ ignoreNotFound: true });
    }
  });

  it('S8-06: the daily sweep deletes stale orphan pictures only', async () => {
    const orphan = uniq('sweep-orphan');
    const fresh = uniq('sweep-fresh');
    const live = uniq('sweep-live');
    const bucket = getStorage().bucket(avatarBucketName());
    for (const uid of [orphan, fresh, live]) {
      await bucket.file(avatarPath(uid)).save(jpeg, { contentType: 'image/jpeg' });
    }
    await db.collection('players').doc(live).set(makePlayer({ best: 10 }));
    try {
      const day = 24 * 3600 * 1000;
      const deleted: string[] = [];
      // The emulator stamps every file "now": a fake listing gives the ages.
      const n = await sweepStaleAvatars(db, {
        listAvatars: async () => [
          { uid: orphan, updatedMs: 0 },
          { uid: fresh, updatedMs: 100 * day - day },
          { uid: live, updatedMs: 0 },
        ],
        deleteAvatar: async (uid) => {
          deleted.push(uid);
          await bucket.file(avatarPath(uid)).delete({ ignoreNotFound: true });
        },
      }, 100 * day);
      assert.equal(n, 1);
      assert.deepEqual(deleted, [orphan]);
      assert.equal((await bucket.file(avatarPath(orphan)).exists())[0], false);
      assert.equal((await bucket.file(avatarPath(fresh)).exists())[0], true);
      assert.equal((await bucket.file(avatarPath(live)).exists())[0], true);
    } finally {
      await db.collection('players').doc(live).delete();
      for (const uid of [orphan, fresh, live]) {
        await bucket.file(avatarPath(uid)).delete({ ignoreNotFound: true });
      }
    }
  });

  it('S8-06: the default bucket lists pictures by uid', async () => {
    const { defaultAvatarBucket } = await import('../src/pools.js');
    const uid = uniq('list');
    const bucket = getStorage().bucket(avatarBucketName());
    await bucket.file(avatarPath(uid)).save(jpeg, { contentType: 'image/jpeg' });
    try {
      const all = await defaultAvatarBucket().listAvatars();
      const mine = all.find((f) => f.uid === uid);
      assert.ok(mine, 'listed');
      assert.ok(Math.abs(mine!.updatedMs - Date.now()) < 10 * 60 * 1000);
    } finally {
      await bucket.file(avatarPath(uid)).delete({ ignoreNotFound: true });
    }
  });
});
