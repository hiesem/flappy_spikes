/**
 * Versus data model and backend limits (PRD-2 §3.13, ARCH §6.1).
 * Every knob carries its PRD / ARCH section.
 */
import type { Timestamp } from 'firebase-admin/firestore';

/** Levels 0–10 (§3.13 "level 0–10"). */
export const MAX_LEVEL = 10;
/** Shards per level (§3.13 "4 shards per level to spread writes"). */
export const SHARDS = 4;
/** Entries per pool document (§3.13 "up to 150 compact run entries"). */
export const POOL_CAP = 150;
/** Byte cap of a pool document (ARCH §6.1: ≤ 900 KB, under the 1 MiB doc limit). */
export const POOL_MAX_BYTES = 900 * 1024;
/** Retention of pool entries and recent runs (§3.13 "older than 60 days"). */
export const RETENTION_DAYS = 60;
export const RETENTION_MS = RETENTION_DAYS * 24 * 3600 * 1000;
/** Non-best uploads per player per (UTC) day (§3.13 "at most 3 a day"). */
export const DAILY_UPLOADS = 3;
/** Runs under this score are never uploaded (§3.13). */
export const MIN_SCORE = 3;
/** Minimum time between two plain points, centiseconds (§3.13 cheat filter, 0.9 s). */
export const MIN_GAP_CS = 90;
/** Point flags (ARCH §6.1 `fl`): ride 1 | train 2 | gift 4. */
export const FLAG_RIDE = 1;
export const FLAG_TRAIN = 2;
export const FLAG_GIFT = 4;
/** Flags that exempt a point from the 0.9 s gap check (§3.13; gift = the +5 pair steps, ARCH §6.3). */
export const GAP_EXEMPT = FLAG_RIDE | FLAG_TRAIN | FLAG_GIFT;
/** How many processed runIds the server remembers per player (idempotent retries). */
export const SEEN_KEEP = 20;

/** Server-only collection holding the per-player upload rate (not readable by clients). */
export const RATE_COLLECTION = 'versusRate';

export interface Look {
  bird: string;
  gear: string;
  hat: string;
  hoop: string;
  trail: string;
}

/** One run as the client stores it in `players/{uid}` (ARCH §6.1 RunEntry). */
export interface RunEntry {
  runId: string;
  score: number;
  best: number;
  ts: Timestamp;
  name: string;
  avatar: string;
  look: Look;
  platform: 'android' | 'ios';
  /** base64 of uint16 LE centisecond deltas, one per point. */
  tl: string;
  /** cs from the last point to death. */
  end: number;
  /** base64, one flag byte per point. */
  fl: string;
}

/** A pool entry: the run plus its owner and the server-computed level; `ts` = server accept time. */
export interface PoolEntry extends RunEntry {
  uid: string;
  level: number;
}

export interface PlayerDoc {
  name: string;
  avatar: string;
  platform: 'android' | 'ios';
  look: Look;
  best: number;
  level: number;
  bestRun?: RunEntry | null;
  recent: RunEntry[];
  uploads?: { day: string; count: number };
  updatedAt: Timestamp;
  expireAt: Timestamp;
}

export interface PoolDoc {
  level: number;
  shard: number;
  updatedAt: Timestamp;
  entries: PoolEntry[];
}

export interface RateDoc {
  day: string;
  count: number;
  seen: string[];
  last?: { runId: string; status: 'accepted' | 'rejected'; reason?: string; pool?: string };
}

export function poolId(level: number, shard: number): string {
  return `${level}_${shard}`;
}

/** All 44 pool document ids. */
export function allPoolIds(): string[] {
  const ids: string[] = [];
  for (let l = 0; l <= MAX_LEVEL; l++) for (let s = 0; s < SHARDS; s++) ids.push(poolId(l, s));
  return ids;
}

/** UTC day key, the server's upload-rate window. */
export function utcDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}
