/** PRD-2.6 F9 `look.card` in firestore.rules: player docs and run entries. */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc, Timestamp } from 'firebase/firestore';
import { encodeDeltas, encodeEntries } from '../src/timeline.js';
import { DAY, LOOK, PROJECT, uniq } from './helpers.js';

let env: RulesTestEnvironment;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: readFileSync(join(__dirname, '..', '..', 'firestore.rules'), 'utf8') },
  });
});

after(async () => {
  await env?.cleanup();
});

function run(o: Record<string, unknown> = {}) {
  return {
    runId: uniq('r'),
    score: 2,
    best: 2,
    ts: Timestamp.now(),
    name: 'SwiftKiwi482',
    avatar: '',
    look: { ...LOOK },
    platform: 'android',
    tl: encodeDeltas([120, 120]),
    end: 80,
    fl: encodeEntries([0, 0], [1, 1]),
    ...o,
  };
}

function player(o: Record<string, unknown> = {}) {
  return {
    name: 'SwiftKiwi482',
    avatar: '',
    platform: 'android',
    look: { ...LOOK },
    best: 2,
    level: 0,
    bestRun: null,
    recent: [run()],
    uploads: { day: '2026-10-24', count: 1 },
    updatedAt: serverTimestamp(),
    expireAt: Timestamp.fromMillis(Date.now() + 60 * DAY),
    ...o,
  };
}

function write(data: Record<string, unknown>) {
  const uid = uniq('card');
  return setDoc(doc(env.authenticatedContext(uid).firestore(), 'players', uid), data);
}

describe('PRD-2.6 F9 look.card in Firestore rules', () => {
  it('accepts a player and run with a valid card', async () => {
    const card = 'f_orbit|n_fire|s_fireworks';
    await assertSucceeds(write(player({ look: { ...LOOK, card } })));
    await assertSucceeds(write(player({ recent: [run({ look: { ...LOOK, card } })] })));
  });

  it('accepts a 2.5 look with five keys and no card', async () => {
    await assertSucceeds(write(player({ look: { ...LOOK } })));
    await assertSucceeds(write(player({ recent: [run({ look: { ...LOOK } })] })));
  });

  it('rejects an invalid card in a player look', async () => {
    for (const card of [
      'f_orbit|n_fire',
      'f_orbit|n_fire|s_fireworks|',
      'n_fire|f_orbit|s_fireworks',
      'f_unknown||',
      'x'.repeat(49),
      7,
      null,
    ]) {
      await assertFails(write(player({ look: { ...LOOK, card } })));
    }
  });

  it('rejects an invalid card in a run look', async () => {
    for (const card of ['f_orbit|n_fire', 'f_orbit|f_orbit|s_fireworks', '||s_unknown']) {
      await assertFails(write(player({ recent: [run({ look: { ...LOOK, card } })] })));
    }
  });

  it('keeps a look with an unknown extra key invalid', async () => {
    await assertFails(write(player({
      look: { ...LOOK, card: 'f_orbit|n_fire|s_fireworks', extra: 'x' },
    })));
  });
});
