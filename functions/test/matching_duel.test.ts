/**
 * PRD-2.6 E5 duel staircase: the reference rules in `matching.ts` against the
 * fixture shared with the Dart matcher of wave 2 (`test/fixtures/
 * versus_duel.json`), plus a seeded long-series simulation of the staircase.
 * Reference-only: the deployed server matcher (`matchCandidates` /
 * `pickOpponent`) does not call these helpers.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  DUEL_STEP_MAX,
  DUEL_STEP_MIN,
  DUEL_STEP_START,
  DuelOutcome,
  DuelPickTier,
  MatchEntry,
  duelStepAfter,
  duelTarget,
  pickDuelOpponent,
} from '../src/matching.js';

interface Fixture {
  stepCases: Array<{
    name: string;
    step?: number;
    result: DuelOutcome;
    expect: { step: number };
  }>;
  targetCases: Array<{
    name: string;
    step: number;
    recentScores: number[];
    expect: { target: number };
  }>;
  pickCases: Array<{
    name: string;
    step?: number;
    recentScores?: number[];
    me: { uid: string; pg?: string };
    seen: string[];
    pool: MatchEntry[];
    expect: { tier: DuelPickTier; pick: string | null; runIds?: string[]; target: number };
  }>;
}

const fixture = JSON.parse(
  readFileSync(join(__dirname, '..', '..', 'test', 'fixtures', 'versus_duel.json'), 'utf8'),
) as Fixture;

function close(actual: number, expected: number, message: string): void {
  assert.ok(Math.abs(actual - expected) < 1e-9, `${message}: ${actual} != ${expected}`);
}

describe('PRD-2.6 E5 duel staircase fixture (shared with the Dart matcher)', () => {
  it('§E5 the fixture has the staircase boundaries and all four pick tiers', () => {
    assert.equal(DUEL_STEP_START, -2);
    assert.equal(DUEL_STEP_MIN, -4);
    assert.equal(DUEL_STEP_MAX, 8);
    assert.ok(fixture.stepCases.some((c) => (c.step ?? DUEL_STEP_START) === -4 && c.result === 'loss'));
    assert.ok(fixture.stepCases.some((c) => (c.step ?? DUEL_STEP_START) === 8 && c.result === 'win'));
    assert.ok(fixture.stepCases.some((c) => c.step !== undefined && c.result === 'draw' && c.expect.step === c.step));
    assert.ok(fixture.targetCases.some((c) => c.recentScores.length === 0));
    assert.ok(fixture.targetCases.some((c) => c.expect.target === 40));
    assert.ok(fixture.targetCases.some((c) => c.expect.target === 160));
    assert.deepEqual(new Set(fixture.pickCases.map((c) => c.expect.tier)), new Set(['band', 'closest', 'rematch', 'solo']));
  });

  for (const c of fixture.stepCases) {
    it(`§E5 step: ${c.name}`, () => {
      assert.equal(duelStepAfter(c.step ?? DUEL_STEP_START, c.result), c.expect.step);
    });
  }

  for (const c of fixture.targetCases) {
    it(`§E5 target: ${c.name}`, () => {
      close(duelTarget(c.step, c.recentScores), c.expect.target, c.name);
    });
  }

  for (const c of fixture.pickCases) {
    it(`§E5 pick: ${c.name}`, () => {
      const step = c.step ?? DUEL_STEP_START;
      const recentScores = c.recentScores ?? [];
      const args = [c.pool, c.me, step, recentScores, c.seen] as const;
      const picked = pickDuelOpponent(...args, () => 0.1);
      assert.equal(picked.tier, c.expect.tier);
      close(picked.target, c.expect.target, c.name);
      if (c.expect.pick === null) {
        assert.equal(picked.entry, null);
      } else {
        assert.equal(picked.entry?.runId, c.expect.pick);
      }
      if (c.expect.runIds) {
        for (const rand of [0, 0.1, 0.5, 0.999]) {
          const p = pickDuelOpponent(...args, () => rand);
          assert.ok(p.entry && c.expect.runIds.includes(p.entry.runId), `rand ${rand}`);
        }
      }
    });
  }

  it('§E5 the median uses only the last 10 scores and does not reorder the input', () => {
    const recent = [1000, 1000, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    const before = [...recent];
    close(duelTarget(0, recent), 4.4, 'median of the last 10');
    assert.deepEqual(recent, before);
  });
});

/** Deterministic 32-bit LCG in [0, 1) (no Math.random in the simulation). */
function seeded(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(1664525, state) + 1013904223) >>> 0;
    return state / 0x1_0000_0000;
  };
}

function between(rand: () => number, lo: number, hi: number): number {
  return lo + Math.min(hi - lo, Math.floor(rand() * (hi - lo + 1)));
}

describe('PRD-2.6 E5 duel staircase simulation', () => {
  it('§E5 a seeded long series settles at about 67 % wins (± 3 pp)', () => {
    const rand = seeded(7);
    const runs = 30000;
    const warmup = 3000;
    let step = DUEL_STEP_START;
    let recentScores = Array.from({ length: 10 }, () => 100);
    let wins = 0;
    let losses = 0;
    let draws = 0;
    let minStep = step;
    let maxStep = step;
    for (let i = 0; i < runs; i++) {
      // A steady player: around 100 points, with a small run-to-run variance.
      const myScore = 100 + between(rand, -10, 10);
      // A typical found pool: eight nearby rival runs, spread around the target.
      const target = duelTarget(step, recentScores);
      const pool: MatchEntry[] = Array.from({ length: 8 }, (_, j) => ({
        uid: `opp-${i}-${j}`,
        runId: `run-${i}-${j}`,
        bracket: 3,
        score: Math.max(1, Math.round(target + (rand() * 2 - 1) * 120)),
      }));
      const picked = pickDuelOpponent(pool, { uid: 'me' }, step, recentScores, [], rand);
      const opp = picked.entry?.score ?? null;
      const result: DuelOutcome = opp === null || myScore === opp ? 'draw' : myScore > opp ? 'win' : 'loss';
      step = duelStepAfter(step, result);
      minStep = Math.min(minStep, step);
      maxStep = Math.max(maxStep, step);
      recentScores = [...recentScores, myScore].slice(-10);
      if (i >= warmup) {
        if (result === 'win') wins++;
        else if (result === 'loss') losses++;
        else draws++;
      }
    }
    const played = wins + losses + draws;
    const winRate = wins / played;
    const decidedWinRate = wins / (wins + losses);
    assert.ok(winRate >= 0.64 && winRate <= 0.70, `all-duel win rate ${(winRate * 100).toFixed(2)} %`);
    assert.ok(
      decidedWinRate >= 0.64 && decidedWinRate <= 0.70,
      `decided-duel win rate ${(decidedWinRate * 100).toFixed(2)} %`,
    );
    assert.ok(draws / played <= 0.05, `draws ${draws} of ${played}`);
    assert.ok(minStep >= DUEL_STEP_MIN && maxStep <= DUEL_STEP_MAX, `steps ${minStep}..${maxStep}`);
  });
});
