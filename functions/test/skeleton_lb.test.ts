/**
 * PRD-2.6 wave 0 server skeleton: schema constants, LB3 exports and the
 * index / TTL declarations that later board work packages rely on.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { validCard } from '../src/card.js';
import { bracketFor } from '../src/brackets.js';
import {
  LB_ALL_COLLECTIONS,
  LB_BEST_SIZE,
  LB_GHOST_MAX_AGE,
  LB_GHOST_RUNS,
  LB_GIFT_TTL,
  LB_GROUP_MS,
  LB_GROUP_SIZE,
  LB_HIST_FROM,
  LB_MAX_RUNS_DAY,
  LB_MAX_SCORE,
  LB_MIN_LEFT_MS,
  LB_OFFLINE_BACKDATE,
  LB_OPEN_SHARDS,
  LB_PLAYER_TTL,
  LB_PLAYING_NOW_MS,
  LB_PRIZE_PLACES,
  MAX_BRACKET,
  MAX_LEVEL,
  validLook,
} from '../src/schema.js';
import { LOOK, fakeJwt, PROJECT } from './helpers.js';

const ROOT = join(__dirname, '..', '..');
const DAY = 24 * 3600 * 1000;

describe('PRD-2.6 wave 0 schema constants', () => {
  it('pins the LB3 tuning values', () => {
    assert.equal(LB_GROUP_SIZE, 50);
    assert.equal(LB_GROUP_MS, DAY);
    assert.equal(LB_MIN_LEFT_MS, 3 * 3600 * 1000);
    assert.equal(LB_OPEN_SHARDS, 1);
    assert.equal(LB_PLAYING_NOW_MS, 5 * 60 * 1000);
    assert.equal(LB_GHOST_MAX_AGE, 14 * DAY);
    assert.equal(LB_GHOST_RUNS, 48);
    assert.equal(LB_MAX_RUNS_DAY, 400);
    assert.equal(LB_OFFLINE_BACKDATE, 6 * 3600 * 1000);
    assert.equal(LB_BEST_SIZE, 50);
    assert.equal(LB_MAX_SCORE, 32_500_000);
    assert.equal(LB_PLAYER_TTL, 400 * DAY);
    assert.equal(LB_GIFT_TTL, 400 * DAY);
    assert.equal(LB_PRIZE_PLACES, 3);
    assert.equal(LB_HIST_FROM, 20_000);
  });

  it('keeps the pool brackets at 0–10 and the 2.5 name as a compatibility alias', () => {
    assert.equal(MAX_BRACKET, 10);
    assert.equal(MAX_LEVEL, MAX_BRACKET);
    assert.equal(bracketFor(0), 0);
    assert.equal(bracketFor(24), 0);
    assert.equal(bracketFor(25), 1);
    assert.equal(bracketFor(5000), 10);
  });

  it('accepts the 2.5 look, rejects a defined card until F9 fills the stub', () => {
    assert.equal(validLook({ ...LOOK }), true);
    assert.equal(validLook({ ...LOOK, card: 'f_orbit|n_fire|s_fireworks' }), false);
    assert.equal(validCard(undefined), true);
    assert.equal(validCard('f_orbit|n_fire|s_fireworks'), false);
    assert.equal(validLook({ ...LOOK, extra: 'x' }), false);
  });
});

describe('PRD-2.6 wave 0 deploy declarations', () => {
  const indexes = JSON.parse(readFileSync(join(ROOT, 'firestore.indexes.json'), 'utf8')) as {
    indexes: Array<{ collectionGroup: string; fields: Array<{ fieldPath: string; order?: string }> }>;
    fieldOverrides: Array<{ collectionGroup: string; fieldPath: string; ttl?: boolean; indexes: unknown[] }>;
  };
  const ttl = readFileSync(join(ROOT, 'functions', 'scripts', 'set_ttl.sh'), 'utf8');

  it('has the LB group and player composite indexes', () => {
    const fields = (group: string) =>
      indexes.indexes.find((i) => i.collectionGroup === group)?.fields.map((f) => `${f.fieldPath}:${f.order}`) ?? [];
    assert.deepEqual(fields('lbGroups'), ['settled:ASCENDING', 'end:ASCENDING']);
    assert.deepEqual(fields('lbPlayers'), [
      'hidden:ASCENDING',
      'bestShadow:ASCENDING',
      'best:DESCENDING',
    ]);
  });

  it('exempts the embedded LB arrays from indexing', () => {
    const exempt = (group: string, field: string) =>
      indexes.fieldOverrides.some((f) => f.collectionGroup === group && f.fieldPath === field && f.indexes.length === 0);
    assert.ok(exempt('lbGroups', 'members'));
    assert.ok(exempt('lbGroups', 'ghosts'));
    assert.ok(exempt('lbGhostPool', 'entries'));
    assert.ok(exempt('lbBest', 'rows'));
  });

  it('enables TTL on expireAt for all five LB collections, in the JSON and set_ttl.sh', () => {
    for (const group of ['lbPlayers', 'lbGroups', 'lbGifts', 'lbTomb', 'lbFlags']) {
      assert.ok(
        indexes.fieldOverrides.some((f) => f.collectionGroup === group && f.fieldPath === 'expireAt' && f.ttl === true),
        group,
      );
      assert.match(ttl, new RegExp(`\\b${group}\\b`));
    }
  });

  it('lists exactly the nine server-only LB collections', () => {
    assert.deepEqual(LB_ALL_COLLECTIONS, [
      'lbPlayers',
      'lbGroups',
      'lbOpen',
      'lbGhostPool',
      'lbBest',
      'lbGifts',
      'lbTomb',
      'lbFlags',
      'lbMeta',
    ]);
  });
});

describe('PRD-2.6 wave 0 LB3 callable exports', () => {
  it('pins enforceAppCheck, europe-west1 and maxInstances 10', async () => {
    const mod = (await import('../src/index.js')) as unknown as Record<string, { __endpoint?: Record<string, unknown> }>;
    for (const name of ['lbSubmitRun', 'lbGetBoard', 'lbClaimGift']) {
      const ep = mod[name]?.__endpoint;
      assert.ok(ep, `${name} is exported`);
      assert.deepEqual(ep!.region, ['europe-west1']);
      assert.equal(ep!.maxInstances, 10);
      assert.equal(ep!.callableTrigger !== undefined, true);
      assert.equal(ep!.scheduleTrigger, undefined);
    }
    const settle = mod.lbSettleGroups?.__endpoint;
    assert.ok(settle, 'lbSettleGroups is exported');
    assert.deepEqual(settle!.region, ['europe-west1']);
    assert.equal(settle!.maxInstances, 10);
    const schedule = settle!.scheduleTrigger as { schedule?: string; timeZone?: string } | undefined;
    assert.deepEqual(
      {
        schedule: schedule?.schedule,
        timeZone: schedule?.timeZone,
      },
      {
        schedule: 'every 10 minutes',
        timeZone: 'Etc/UTC',
      },
    );
  });

  it('refuses a call without auth or App Check through the functions emulator', async () => {
    const base = `http://127.0.0.1:5001/${PROJECT}/europe-west1`;
    const appCheck = fakeJwt({ sub: '1:512525012529:android:8bb85c213b543c6487cf10', aud: [`projects/${PROJECT}`] });
    const idToken = (uid: string) =>
      fakeJwt({ sub: uid, user_id: uid, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, iat: 1, exp: 4e9 });
    for (const fn of ['lbSubmitRun', 'lbGetBoard', 'lbClaimGift']) {
      const unauthenticated = await fetch(`${base}/${fn}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Firebase-AppCheck': appCheck },
        body: JSON.stringify({ data: {} }),
      });
      assert.equal(unauthenticated.status, 401, `${fn} auth: ${await unauthenticated.clone().text()}`);
      const withoutAppCheck = await fetch(`${base}/${fn}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${idToken('lb-skeleton')}` },
        body: JSON.stringify({ data: {} }),
      });
      assert.equal(withoutAppCheck.status, 401, `${fn} App Check: ${await withoutAppCheck.clone().text()}`);
      const body = (await unauthenticated.json()) as { error?: { status?: string } };
      assert.equal(body.error?.status, 'UNAUTHENTICATED');
    }
  });
});
