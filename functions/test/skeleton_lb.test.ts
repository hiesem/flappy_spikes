/**
 * PRD-2.6 wave 0 server skeleton: schema constants, LB3 exports and the
 * index / TTL declarations that later board work packages rely on.
 */
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
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
import * as schema from '../src/schema.js';
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

  it('accepts the 2.5 look and a defined card now that F9 fills the stub', () => {
    assert.equal(validLook({ ...LOOK }), true);
    assert.equal(validLook({ ...LOOK, card: 'f_orbit|n_fire|s_fireworks' }), true);
    assert.equal(validCard(undefined), true);
    assert.equal(validCard('f_orbit|n_fire|s_fireworks'), true);
    assert.equal(validCard('f_orbit|n_fire'), false);
    assert.equal(validLook({ ...LOOK, extra: 'x' }), false);
  });
});

describe('PRD-2.6 wave 0 deploy declarations', () => {
  const indexes = JSON.parse(readFileSync(join(ROOT, 'firestore.indexes.json'), 'utf8')) as {
    indexes: Array<{ collectionGroup: string; queryScope: string; fields: Array<{ fieldPath: string; order?: string }> }>;
    fieldOverrides: Array<{ collectionGroup: string; fieldPath: string; ttl?: boolean; indexes: unknown[] }>;
  };
  const ttl = readFileSync(join(ROOT, 'functions', 'scripts', 'set_ttl.sh'), 'utf8');

  it('has the LB group and player composite indexes', () => {
    const fields = (group: string) =>
      indexes.indexes.find((i) => i.collectionGroup === group)?.fields.map((f) => `${f.fieldPath}:${f.order}`) ?? [];
    assert.deepEqual(fields('lbGroups'), ['settled:ASCENDING', 'end:ASCENDING']);
    // region P26-S1
    // LB3: exactRank filters hidden and ranges over bestShadow; best is unused.
    assert.deepEqual(fields('lbPlayers'), [
      'hidden:ASCENDING',
      'bestShadow:ASCENDING',
    ]);
    assert.ok(indexes.indexes.some((i) => i.collectionGroup === 'lbPlayers' &&
      i.fields.map((f) => `${f.fieldPath}:${f.order}`).join(',') ===
        'hidden:ASCENDING,bestShadow:ASCENDING,bestAt:ASCENDING')); // S2 tie count
    // endregion
  });

  // region P26-S1
  it('inventories every server where/orderBy query and checks composite index coverage', () => {
    type Clause = { field: string; op: string };
    type Query = { collection: string; clauses: Clause[] };
    const queries = new Map<string, Query>();
    const constants = schema as unknown as Record<string, unknown>;
    for (const file of readdirSync(join(ROOT, 'functions/src')).filter((f) => f.endsWith('.ts'))) {
      const source = readFileSync(join(ROOT, 'functions/src', file), 'utf8');
      const localConstants = Object.fromEntries([...source.matchAll(/\bconst\s+(\w+)\s*=\s*'([^']+)'/g)]
        .map((m) => [m[1], m[2]]));
      const aliases = new Map<string, Query>();
      let scanned = 0;
      // Follow fluent query chains through their terminal get/count or assignment.
      // The coverage count below fails closed for new syntax / unresolved aliases.
      const chains = /(?:\b\w+\s*\.\s*collection(?:Group)?\(\s*(\w+|'[^']+')\s*\)|\b(\w+))(\s*\.(?:where|orderBy|limit)\s*\([^;]*?)(?=\s*\.(?:get|count)\s*\(|;)/g;
      for (const match of source.matchAll(chains)) {
        const [expression, collectionArg, alias, tail] = match;
        assert.ok(!expression.includes('collectionGroup('), `${file}: collection-group index scope must be checked`);
        const name = collectionArg?.startsWith("'") ? collectionArg.slice(1, -1) : (constants[collectionArg] ?? localConstants[collectionArg]);
        const base = collectionArg ? { collection: typeof name === 'string' ? name : collectionArg, clauses: [] } :
          aliases.get(alias);
        assert.ok(base, `${file}: unresolved query alias ${alias}`);
        const query: Query = { ...base, clauses: [...base.clauses] };
        const clauses = /\.(where|orderBy)\(\s*(?:'([^']+)'|(FieldPath\.documentId\(\)))(?:\s*,\s*'([^']+)')?/g;
        for (const clause of tail.matchAll(clauses)) {
          const [, method, literalField, documentId, operator] = clause;
          const field = documentId ? '__name__' : literalField;
          assert.ok(method === 'orderBy' || operator, `${file}: non-literal where operator`);
          query.clauses.push({ field, op: operator ?? 'asc' });
          scanned++;
          const signature = `${file}: ${query.collection} ${query.clauses.map((c) => `${c.field} ${c.op}`).join(', ')}`;
          queries.set(signature, { ...query, clauses: [...query.clauses] });
        }
        const assignment = source.slice(0, match.index).match(/\bconst\s+(\w+)\s*=\s*$/);
        if (assignment) aliases.set(assignment[1], query);
      }
      assert.equal(scanned, [...source.matchAll(/\.(?:where|orderBy)\s*\(/g)].length,
        `${file}: every where/orderBy must be inventoried`);
    }
    // Include intermediate chains: a shared base (exactRank's col) must not hide its range.
    assert.deepEqual([...queries.keys()].sort(), [
      'board_delete.ts: collection uid ==',
      'board_delete.ts: lbGroups ghostUids array-contains',
      'board_delete.ts: lbGroups memberUids array-contains',
      'board_delete.ts: lbPlayers bestShadow desc',
      'board_store.ts: lbGifts gid ==',
      // P26-LB7 round 5: the bounded open/recovery bucket lookup uses its single-field index.
      'board_store.ts: lbGifts giftLookup in',
      'board_store.ts: lbGroups settled ==',
      'board_store.ts: lbGroups settled ==, end <=',
      'board_store.ts: lbGroups settled ==, end <=, end asc',
      'board_store.ts: lbPlayers bestShadow desc',
      'board_store.ts: lbPlayers hidden ==',
      'board_store.ts: lbPlayers hidden ==, bestShadow ==',
      'board_store.ts: lbPlayers hidden ==, bestShadow ==, bestAt <',
      'board_store.ts: lbPlayers hidden ==, bestShadow ==, bestAt ==',
      'board_store.ts: lbPlayers hidden ==, bestShadow ==, bestAt ==, __name__ <',
      'board_store.ts: lbPlayers hidden ==, bestShadow >',
      'pools.ts: versusFlags uid ==',
      'pools.ts: versusNames guestSeen <',
      'pools.ts: versusNames guestSeen <, guestSeen asc',
      'purchases.ts: purchases firstUid ==',
    ].sort());
    for (const [signature, query] of queries) {
      const equalities = [...new Set(query.clauses.filter((c) => c.op === '==').map((c) => c.field))];
      const ordered = new Map<string, string>();
      for (const { field, op } of query.clauses) {
        if (['<', '<=', '>', '>='].includes(op)) ordered.set(field, 'ASCENDING');
        if (op === 'asc' || op === 'desc') ordered.set(field, op === 'asc' ? 'ASCENDING' : 'DESCENDING');
      }
      const fields = new Set(query.clauses.map((c) => c.field));
      for (const field of fields) {
        assert.ok(!indexes.fieldOverrides.some((f) => f.collectionGroup === query.collection &&
          f.fieldPath === field && f.indexes.length === 0), `${signature}: ${field} is exempt from automatic indexing`);
      }
      // Single-field queries and equality-only queries use automatic indexes / index merging.
      if (fields.size <= 1 || ordered.size === 0) continue;
      const expected = [...equalities.map((field) => `${field}:ASCENDING`),
        ...[...ordered].filter(([field]) => !equalities.includes(field) && field !== '__name__').map(([field, order]) => `${field}:${order}`)];
      if (ordered.has('__name__')) {
        assert.equal(ordered.get('__name__'), expected.at(-1)?.split(':').at(-1),
          `${signature}: document-id range must match the index's implicit __name__ direction`);
      }
      assert.ok(indexes.indexes.some((index) => index.collectionGroup === query.collection && index.queryScope === 'COLLECTION' &&
        index.fields.map((f) => `${f.fieldPath}:${f.order}`).join(',') === expected.join(',')),
      `${signature} needs (${expected.join(', ')})`);
    }
  });
  // endregion

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
