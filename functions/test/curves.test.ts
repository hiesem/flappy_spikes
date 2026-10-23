/**
 * PRD-2.6 E6: the server's pass-bound constants stay tied to the gameplay
 * tuning. Parse the Dart sources instead of duplicating their numbers.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { PACE_MIN_MEDIAN_CS, PASS_MAX_SPEED, PASS_SPACING } from '../src/schema.js';

const ROOT = join(__dirname, '..', '..');
const tuning = readFileSync(join(ROOT, 'lib', 'run', 'config', 'tuning_defaults.dart'), 'utf8');
const runConfig = readFileSync(join(ROOT, 'lib', 'run', 'config', 'run_config.dart'), 'utf8');

function tuningCurve(key: string): number[][] {
  const line = tuning.match(new RegExp(`TuningDef\\(\\s*['"]${key}['"]\\s*,\\s*TuningType\\.curve\\s*,\\s*(\\[[\\s\\S]*?\\])\\s*\\)`));
  assert.ok(line, `TuningDef curve ${key}`);
  const pairs = [...line![1].matchAll(/\[\s*([0-9.+-]+)\s*,\s*([0-9.+-]+)\s*\]/g)];
  assert.ok(pairs.length > 0, `${key} has keyframes`);
  return pairs.map((p) => [Number(p[1]), Number(p[2])]);
}

function dartDouble(name: string, source: string): number {
  const m = source.match(new RegExp(`static\\s+const\\s+double\\s+${name}\\s*=\\s*([0-9.]+)\\s*;`));
  assert.ok(m, `${name} in run_config.dart`);
  return Number(m![1]);
}

describe('PRD-2.6 E6 curve equals the gameplay tuning', () => {
  it('PASS_MAX_SPEED equals the top of curve_speed', () => {
    const curve = tuningCurve('curve_speed');
    const top = Math.max(...curve.map(([, speed]) => speed));
    assert.equal(PASS_MAX_SPEED, top, `curve_speed ${JSON.stringify(curve)}`);
  });

  it('PASS_SPACING equals RunConfig.spacing', () => {
    assert.equal(PASS_SPACING, dartDouble('spacing', runConfig));
  });

  it('PACE_MIN_MEDIAN_CS is at most 0.8 × 310 / 187.5 × 100', () => {
    const bound = 0.8 * 310 / 187.5 * 100;
    assert.ok(PACE_MIN_MEDIAN_CS <= bound, `${PACE_MIN_MEDIAN_CS} ≤ ${bound}`);
  });
});
