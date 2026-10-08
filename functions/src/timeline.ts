/**
 * Timeline codec and the server cheat filter (PRD-2 §3.13, ARCH §6.1 / §6.3).
 *
 * `tl`: base64 of little-endian uint16 centisecond deltas, one per point
 * (point i's run time = sum of deltas 0..i on the player's runClock).
 * `fl`: base64, one flag byte per point (ride 1 | train 2 | gift 4).
 * A pair's "+5 score" gift is five points (the pair pass + four gift points,
 * or five gift points — any delta, typically 0) flagged gift, so the decoded
 * point count always equals the score.
 */
import { GAP_EXEMPT, MIN_GAP_CS, MIN_SCORE, RunEntry } from './schema.js';

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

export function decodeFlags(fl: string): number[] | null {
  const buf = strictB64(fl);
  return buf === null ? null : Array.from(buf);
}

export function encodeDeltas(deltas: number[]): string {
  const buf = Buffer.alloc(deltas.length * 2);
  deltas.forEach((d, i) => buf.writeUInt16LE(d, i * 2));
  return buf.toString('base64');
}

export function encodeFlags(flags: number[]): string {
  return Buffer.from(flags).toString('base64');
}

export type RejectReason =
  | 'shape'
  | 'low_score'
  | 'best_below_score'
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
  const flags = decodeFlags(run.fl);
  if (deltas === null || flags === null || flags.length !== deltas.length) return 'timeline';
  if (deltas.length !== run.score) return 'count';
  for (let i = 1; i < deltas.length; i++) {
    if ((flags[i] & GAP_EXEMPT) === 0 && deltas[i] < MIN_GAP_CS) return 'gap';
  }
  return null;
}

/** Opponent score at run time [cs] (replay reference for the Dart client, ARCH §6.4). */
export function scoreAt(tl: string, cs: number): number {
  const deltas = decodeDeltas(tl) ?? [];
  let t = 0;
  let n = 0;
  for (const d of deltas) {
    t += d;
    if (t > cs) break;
    n++;
  }
  return n;
}

