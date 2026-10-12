/**
 * Timeline codec and the server cheat filter (PRD-2 §3.13, ARCH §6.1 / §6.3;
 * format v2 PRD-2.2 §13.5).
 *
 * `tl`: base64 of little-endian uint16 centisecond deltas, one per entry
 * (entry i's run time = sum of deltas 0..i on the player's runClock).
 * `fl` (v2): base64 of the version byte 2, then per entry the flag byte
 * (ride 1 | train 2 | gift 4 | bonus 8) and the entry's value (uint16 LE):
 * the points it added (a pass 1 / 2 / the streak, a pair gift, a coin bonus).
 * The values sum to the score. v1 (one flag byte per point, no values) is
 * rejected (`version`); old pool runs are converted by `convertV1ToV2`.
 */
import {
  BONUS_CAP,
  FLAG_BONUS,
  FLAG_GIFT,
  GAP_EXEMPT,
  GIFT_CAP,
  MIN_GAP_CS,
  MIN_SCORE,
  PASS_CAP_EXTRA,
  PASS_CAP_MULT,
  RunEntry,
  TIMELINE_VERSION,
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

/** True when `fl` is a well-formed v2 entry list for `entries` entries. */
export function isV2(fl: string, entries: number): boolean {
  const m = decodeEntries(fl);
  return m !== null && m.flags.length === entries;
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

const LOOK_KEYS = ['bird', 'gear', 'hat', 'hoop', 'trail'];

function isStr(v: unknown, min: number, max: number): v is string {
  return typeof v === 'string' && v.length >= min && v.length <= max;
}

/** The display fields a pool entry copies (the rules only bound them loosely). */
function validDisplay(run: RunEntry): boolean {
  const look = run.look as unknown as Record<string, unknown> | null;
  return (
    isStr(run.name, 1, 32) &&
    isStr(run.avatar, 0, 512) &&
    (run.platform === 'android' || run.platform === 'ios') &&
    look !== null &&
    typeof look === 'object' &&
    Object.keys(look).length === LOOK_KEYS.length &&
    LOOK_KEYS.every((k) => isStr(look[k], 0, 40))
  );
}

function isInt(v: unknown, min: number, max: number): v is number {
  return typeof v === 'number' && Number.isInteger(v) && v >= min && v <= max;
}

/**
 * PRD-2.2 §13.5 the plausibility cap of each entry: a pass entry is worth at
 * most 2 × (pass entries so far + 5), a bonus at most BONUS_CAP, a gift at most
 * GIFT_CAP. Returns false when a value is outside.
 */
export function plausibleValues(flags: number[], values: number[]): boolean {
  let passes = 0;
  for (let i = 0; i < values.length; i++) {
    const f = flags[i];
    const v = values[i];
    if ((f & FLAG_BONUS) !== 0) {
      if (v > BONUS_CAP) return false;
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
  for (let i = 1; i < deltas.length; i++) {
    if ((meta.flags[i] & GAP_EXEMPT) === 0 && deltas[i] < MIN_GAP_CS) return 'gap';
  }
  return null;
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

/**
 * PRD-2.2 §13.5 the one-off conversion of a 2.1 (v1) pool run: one entry =
 * one point becomes a v2 entry of value 1 with its flags kept; `tl`, `end`
 * and the score stay. Returns the converted `fl`, or null when the run is
 * already v2 (idempotent) or is not a well-formed v1 run.
 */
export function convertV1ToV2(run: Pick<RunEntry, 'tl' | 'fl'>): string | null {
  const deltas = decodeDeltas(run.tl);
  if (deltas === null) return null;
  if (isV2(run.fl, deltas.length)) return null;
  const buf = strictB64(run.fl);
  if (buf === null || buf.length !== deltas.length) return null;
  const flags = Array.from(buf);
  return encodeEntries(flags, flags.map(() => 1));
}
