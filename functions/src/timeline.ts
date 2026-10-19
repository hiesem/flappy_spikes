/**
 * Timeline codec and the server cheat filter (PRD-2 §3.13, ARCH §6.1 / §6.3;
 * format v2 PRD-2.2 §13.5).
 *
 * `tl`: base64 of little-endian uint16 centisecond deltas, one per entry
 * (entry i's run time = sum of deltas 0..i on the player's runClock).
 * `fl` (v2): base64 of the version byte 2, then per entry the flag byte
 * (ride 1 | train 2 | gift 4 | bonus 8 | puzzle 16) and the entry's value (uint16 LE):
 * the points it added (a pass 1 / 2 / the streak, a pair gift, a coin bonus).
 * The values sum to the score. v1 (one flag byte per point, no values) is
 * rejected (`version`).
 */
import {
  BONUS_CAP,
  FLAG_BONUS,
  FLAG_GIFT,
  FLAG_PUZZLE,
  GAP_EXEMPT,
  GIFT_CAP,
  MIN_GAP_CS,
  MIN_SCORE,
  PASS_CAP_EXTRA,
  PASS_CAP_MULT,
  PUZZLE_BONUS_CAP,
  RunEntry,
  TIMELINE_VERSION,
  validLook,
  validPg,
} from './schema.js';

const B64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

function strictB64(s: string): Buffer | null {
  if (typeof s !== 'string' || !B64.test(s)) return null;
  return Buffer.from(s, 'base64');
}

export function decodeDeltas(tl: string): number[] | null {
  const buf = strictB64(tl);
  if (buf === null || buf.length % 2 !== 0) return null;
  const out: number[] = [];
  for (let i = 0; i < buf.length; i += 2) out.push(buf.readUInt16LE(i));
  return out;
}

export function encodeDeltas(deltas: number[]): string {
  const buf = Buffer.alloc(deltas.length * 2);
  deltas.forEach((d, i) => buf.writeUInt16LE(d, i * 2));
  return buf.toString('base64');
}

/** One v2 entry's flag and value. */
export interface EntryMeta {
  flags: number[];
  values: number[];
}

/** Decodes a v2 `fl` (null for v1 / malformed / a zero value). */
export function decodeEntries(fl: string): EntryMeta | null {
  const buf = strictB64(fl);
  if (buf === null || buf.length < 1 || buf[0] !== TIMELINE_VERSION || (buf.length - 1) % 3 !== 0) return null;
  const flags: number[] = [];
  const values: number[] = [];
  for (let i = 1; i < buf.length; i += 3) {
    const v = buf.readUInt16LE(i + 1);
    if (v < 1) return null;
    flags.push(buf[i]);
    values.push(v);
  }
  return { flags, values };
}

/** Encodes a v2 `fl` (version byte, then flag + uint16 LE value per entry). */
export function encodeEntries(flags: number[], values: number[]): string {
  const buf = Buffer.alloc(1 + flags.length * 3);
  buf[0] = TIMELINE_VERSION;
  flags.forEach((f, i) => {
    buf[1 + i * 3] = f & 0xff;
    buf.writeUInt16LE(values[i], 2 + i * 3);
  });
  return buf.toString('base64');
}

export type RejectReason =
  | 'shape'
  | 'low_score'
  | 'best_below_score'
  | 'version'
  | 'timeline'
  | 'count'
  | 'gap'
  | 'rate'
  | 'duplicate';

function isStr(v: unknown, min: number, max: number): v is string {
  return typeof v === 'string' && v.length >= min && v.length <= max;
}

/**
 * The display fields a pool entry copies (the rules only bound them loosely).
 * WP-AV: the look ids must have the catalogue-id shape ([validLook]).
 */
function validDisplay(run: RunEntry): boolean {
  return (
    isStr(run.name, 1, 32) &&
    isStr(run.avatar, 0, 512) &&
    (run.platform === 'android' || run.platform === 'ios') &&
    validLook(run.look) &&
    // PRD-2.3 §21.4 the optional hashed Play Games id.
    validPg(run.pg)
  );
}

function isInt(v: unknown, min: number, max: number): v is number {
  return typeof v === 'number' && Number.isInteger(v) && v >= min && v <= max;
}

/**
 * PRD-2.2 §13.5 the plausibility cap of each entry: a pass entry is worth at
 * most 2 × (pass entries so far + 5), a bonus at most BONUS_CAP (a puzzle
 * completion bonus, flagged FLAG_PUZZLE, at most PUZZLE_BONUS_CAP), a gift at
 * most GIFT_CAP. Returns false when a value is outside.
 */
export function plausibleValues(flags: number[], values: number[]): boolean {
  let passes = 0;
  for (let i = 0; i < values.length; i++) {
    const f = flags[i];
    const v = values[i];
    if ((f & FLAG_BONUS) !== 0) {
      if (v > ((f & FLAG_PUZZLE) !== 0 ? PUZZLE_BONUS_CAP : BONUS_CAP)) return false;
    } else if ((f & FLAG_GIFT) !== 0) {
      if (v > GIFT_CAP) return false;
    } else {
      passes++;
      if (v > PASS_CAP_MULT * (passes + PASS_CAP_EXTRA)) return false;
    }
  }
  return true;
}

/**
 * PRD-2.2 §13.5 the 0.9 s gap rule: a non-exempt entry must come at least
 * MIN_GAP_CS after the previous entry that is not a bonus. (Fix S7-02) a bonus
 * entry is exempt *and* does not restart the interval, so a pickup bonus just
 * before a pass can't make a legitimately spaced pass look too close.
 */
export function gapOk(deltas: number[], flags: number[]): boolean {
  let t = 0;
  let anchor: number | null = null;
  for (let i = 0; i < deltas.length; i++) {
    t += deltas[i];
    const f = flags[i];
    if ((f & GAP_EXEMPT) === 0 && anchor !== null && t - anchor < MIN_GAP_CS) return false;
    if ((f & FLAG_BONUS) === 0) anchor = t;
  }
  return true;
}

/**
 * The cheat filter without the upload rate (that needs server state).
 * Returns null when the run is acceptable.
 */
export function checkRun(run: RunEntry, playerBest: number): RejectReason | null {
  if (
    run === null ||
    typeof run !== 'object' ||
    typeof run.runId !== 'string' ||
    run.runId.length === 0 ||
    !isInt(run.score, 0, 1e6) ||
    !isInt(run.best, 0, 1e6) ||
    !isInt(run.end, 0, 65535) ||
    !isStr(run.tl, 0, 16384) ||
    !isStr(run.fl, 0, 8192) ||
    !validDisplay(run)
  ) {
    return 'shape';
  }
  if (run.score < MIN_SCORE) return 'low_score';
  if (run.best < run.score || playerBest < run.score) return 'best_below_score';
  const deltas = decodeDeltas(run.tl);
  if (deltas === null) return 'timeline';
  const meta = decodeEntries(run.fl);
  // PRD-2.2 §13.5 no v1 support: a v1 `fl` (one flag byte per point) is refused.
  if (meta === null) return 'version';
  if (meta.flags.length !== deltas.length) return 'timeline';
  const sum = meta.values.reduce((a, b) => a + b, 0);
  if (sum !== run.score) return 'count';
  if (!plausibleValues(meta.flags, meta.values)) return 'count';
  return gapOk(deltas, meta.flags) ? null : 'gap';
}

/** Opponent score at run time [cs] (replay reference for the Dart client, ARCH §6.4). */
export function scoreAt(tl: string, fl: string, cs: number): number {
  const deltas = decodeDeltas(tl) ?? [];
  const meta = decodeEntries(fl);
  if (meta === null || meta.values.length !== deltas.length) return 0;
  let t = 0;
  let n = 0;
  for (let i = 0; i < deltas.length; i++) {
    t += deltas[i];
    if (t > cs) break;
    n += meta.values[i];
  }
  return n;
}
