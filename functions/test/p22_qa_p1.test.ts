import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { checkRun, scoreAt } from '../src/timeline.js';
import { makeRun } from './helpers.js';

interface Case {
  name: string;
  entries: [number, number, number][];
  expect: string | null;
  finding?: string;
}
const cases: Case[] = JSON.parse(readFileSync(
  join(__dirname, '..', '..', 'test', 'fixtures', 'p22_qa_p1_timeline.json'), 'utf8',
)).cases;

describe('PRD-2.2 §13.5 QA P1 shared boundary fixtures', () => {
  for (const c of cases) {
    const verify = () => {
      let last = 0;
      const deltas = c.entries.map(([t]) => {
        const now = Math.round(t * 100);
        const delta = now - last;
        last = now;
        return delta;
      });
      const values = c.entries.map(e => e[1]);
      const flags = c.entries.map(e => e[2]);
      const score = values.reduce((a, b) => a + b, 0);
      const run = makeRun({ score, deltas, values, flags });
      assert.equal(checkRun(run, score), c.expect);
      for (const cs of [0, 199, 200, 289, 290, 380, 400, 600]) {
        const expected = c.entries.filter(e => Math.round(e[0] * 100) <= cs)
          .reduce((sum, e) => sum + e[1], 0);
        assert.equal(scoreAt(run.tl, run.fl, cs), expected, `replay at ${cs}`);
      }
    };
    if (c.finding) it.skip(`${c.finding}: ${c.name}`, verify);
    else it(c.name, verify);
  }
});
