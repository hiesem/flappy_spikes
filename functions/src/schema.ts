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
/**
 * Audit 17: new-best uploads per player per (UTC) day. A new best skips
 * [DAILY_UPLOADS], but `best` is client-written, so a forged client could
 * raise it by 1 on every write and pool without limit. 20 is far above what
 * an honest player sets in a day; an honest best past the cap is simply not
 * pooled (the player never sees the pool upload result).
 */
export const DAILY_BEST_UPLOADS = 20;
/**
 * Audit 17 (owner decision, 2026-10-20): accepted custom-name changes per
 * player per (UTC) day through `setVersusName`. Each change rewrites the
 * caller's entries in all 44 pool shards, so it bounds the cost of a
 * looping client. The 6th change answers `resource-exhausted`: the app
 * shows "Too many changes today. Try tomorrow." and keeps the old name.
 */
export const DAILY_NAME_CHANGES = 5;
/** Runs under this score are never uploaded (§3.13). */
export const MIN_SCORE = 3;
/** Minimum time between two plain points, centiseconds (§3.13 cheat filter, 0.9 s). */
export const MIN_GAP_CS = 90;
/** Entry flags (ARCH §6.1 `fl`): ride 1 | train 2 | gift 4 | bonus 8 (PRD-2.2 §13.5). */
export const FLAG_RIDE = 1;
export const FLAG_TRAIN = 2;
export const FLAG_GIFT = 4;
/** PRD-2.2 §13.6 a coin bonus paid as points (can land right after a pass). */
export const FLAG_BONUS = 8;
/**
 * PRD-2.2 §13.1 / §13.5 (fix S7-05) marks a bonus entry as the puzzle 4/4
 * completion payout (always together with FLAG_BONUS); it has its own cap.
 */
export const FLAG_PUZZLE = 16;
/**
 * Flags that exempt an entry from the 0.9 s gap check (§3.13; gift = the +5
 * pair gift, ARCH §6.3; PRD-2.2 §13.5 adds the bonus entries).
 */
export const GAP_EXEMPT = FLAG_RIDE | FLAG_TRAIN | FLAG_GIFT | FLAG_BONUS;
/** PRD-2.2 §13.5 the `fl` version byte of timeline format v2 (v1 is rejected). */
export const TIMELINE_VERSION = 2;
/**
 * PRD-2.2 §13.5 plausibility cap of a pass entry: at most
 * PASS_CAP_MULT × (pass entries so far, this one included, + PASS_CAP_EXTRA)
 * points — the streak can't exceed the hoops passed, ×2 for the chick, +5 for
 * the FEVER jump.
 */
export const PASS_CAP_MULT = 2;
export const PASS_CAP_EXTRA = 5;
/**
 * PRD-2.2 §13.5 plausibility cap of a generic bonus entry (points):
 * 2 × the largest in-run coin bonus (the 40-coin piggy, doubled by the chick).
 */
export const BONUS_CAP = 80;
/**
 * PRD-2.2 §13.1 / §13.5 (fix S7-05) plausibility cap of a puzzle completion
 * entry (FLAG_BONUS | FLAG_PUZZLE): the largest roll (250, PRD-2 §3.16)
 * doubled by the chick.
 */
export const PUZZLE_BONUS_CAP = 500;
/** PRD-2.2 §13.5 plausibility cap of a gift entry: 2 × the pair's +5. */
export const GIFT_CAP = 10;
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

/**
 * WP-AV (2.4) the shape of a look id: the bird / gear / hat ids draw the
 * player's sticker avatar on every phone, so each id must look like a
 * catalogue id (lowercase letters, digits, `_`; 1–40 characters, the
 * rules' cap). An id the app does not know falls back on the phone.
 */
export const LOOK_ID_RE = /^[a-z0-9_]{1,40}$/;

/** The five look keys, in order. */
export const LOOK_KEYS = ['bird', 'gear', 'hat', 'hoop', 'trail'] as const;

/** Whether [look] has exactly the five keys, each a well-formed id. */
export function validLook(look: unknown): look is Look {
  if (look === null || typeof look !== 'object' || Array.isArray(look)) return false;
  const l = look as Record<string, unknown>;
  return (
    Object.keys(l).length === LOOK_KEYS.length &&
    LOOK_KEYS.every((k) => typeof l[k] === 'string' && LOOK_ID_RE.test(l[k] as string))
  );
}

/** One run as the client stores it in `players/{uid}` (ARCH §6.1 RunEntry). */
export interface RunEntry {
  runId: string;
  score: number;
  best: number;
  ts: Timestamp;
  name: string;
  /**
   * WP-AV the legacy picture URL: the app writes '' (older apps may still
   * send one); the pools always store ''.
   */
  avatar: string;
  look: Look;
  platform: 'android' | 'ios';
  /** base64 of uint16 LE centisecond deltas, one per timeline entry. */
  tl: string;
  /** cs from the last point to death. */
  end: number;
  /**
   * Timeline format v2 (PRD-2.2 §13.5): base64 of the version byte 2, then
   * per entry the flag byte and the entry's value (uint16 LE); the values sum
   * to `score`.
   */
  fl: string;
  /**
   * PRD-2.3 §21.4 the hashed Play Games id: SHA-256 hex (64 chars) of the
   * Play Games player id plus the app salt; '' without Play Games. Optional:
   * runs stored without it match as before.
   */
  pg?: string;
}

/** PRD-2.3 §21.4 the shape of `pg`: '' or 64 lowercase hex characters. */
export function validPg(v: unknown): boolean {
  return v === undefined || (typeof v === 'string' && (v === '' || /^[0-9a-f]{64}$/.test(v)));
}

/** A pool entry: the run plus its owner and the server-computed level; `ts` = server accept time. */
export interface PoolEntry extends RunEntry {
  uid: string;
  level: number;
  /**
   * WP-NAME the owner's custom versus name (customname.ts rules), set only
   * when they chose one; opponents show it instead of [name] (the generated
   * name, which older apps keep showing).
   */
  customName?: string;
}

/** WP-NAME server-only custom names (`versusNames/{uid}`; clients have no access). */
export const NAMES_COLLECTION = 'versusNames';

export interface NameDoc {
  customName: string;
  updatedAt: Timestamp;
  /**
   * WP-N2 the owner's last activity the server saw (a name set, or the
   * app's once-a-day name read on start / resume). Absent on 2.4.0 docs.
   */
  lastSeen?: Timestamp;
  /** WP-N2 the owner is linked to Play Games / Game Center (never expires). */
  linked?: boolean;
  /**
   * WP-N2 = [lastSeen] while the owner is a guest, absent once linked: the
   * daily `releaseGuestNames` job queries `guestSeen < now − 30 d`
   * (single-field index, no composite index needed).
   */
  guestSeen?: Timestamp;
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
  /** Audit 17: new-best uploads this [day] ([DAILY_BEST_UPLOADS]; absent = 0). */
  bestCount?: number;
  /** Audit 17: accepted custom-name changes on [names.day] ([DAILY_NAME_CHANGES]). */
  names?: { day: string; count: number };
  seen: string[];
  last?: { runId: string; status: 'accepted' | 'rejected'; reason?: string; pool?: string };
  /**
   * PRD-2.5 §3.6 the scores of this player's last [SCORE_HISTORY] runs that
   * passed `checkRun` (oldest first), kept by the server in the upload
   * transaction; the `jump` anomaly signal compares a new run with them.
   * Absent on older rate docs (= no history).
   */
  scores?: number[];
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

// region PRD-2.5 §3.6 WP-VERSUS — anomaly flags (D3: flag only, pools unchanged)

/** Server-only collection of anomaly flags, `versusFlags/{uid}_{runId}` (clients have no access). */
export const FLAGS_COLLECTION = 'versusFlags';
/** How long a flag is kept (Firestore TTL on `expireAt`; privacy policy: "up to 60 days"). */
export const FLAG_TTL_DAYS = 60;
/** Scores kept in [RateDoc.scores] (the history of the `jump` signal). */
export const SCORE_HISTORY = 10;
/**
 * `streak_jump`: a pass entry may exceed the previous pass entry's value by
 * at most this much (+1 streak, +1 chick hatching on that pass; PRD: +2) …
 * Run 19: +3 — the autopilot fixtures (honest_runs.json) hit the PRD's
 * exact limit many times, so one point of headroom for honest players.
 */
export const STREAK_STEP_MAX = 3;
/**
 * … or reach this value at most (the FEVER hoop / pair FEVER gift lift the
 * streak to 5, so the next perfect pass scores 6, +1 with the chick = 7;
 * PRD: 7, run 19: 8 for the same one point of headroom).
 */
export const STREAK_FLOOR_MAX = 8;
/**
 * `pace`: flag when the median gap between consecutive plain passes (flag
 * byte 0) is under this many centiseconds. Plain hoops come every 310 pt at
 * ≤ 187.5 pt/s → ≥ ~165 cs; 135 cs leaves room for tilted crossings.
 */
export const PACE_MIN_MEDIAN_CS = 135;
/** `pace` only judges a run with at least this many plain-pass gaps. */
export const PACE_MIN_GAPS = 10;
/** `passes`: the top scroll speed (`curve_speed` max, tuning_defaults.dart). */
export const PASS_MAX_SPEED = 187.5;
/** `passes`: the hoop spacing in pt (`RunConfig.spacing`; the comet's 560 only lowers the count). */
export const PASS_SPACING = 310;
/** `passes`: rings per slot assumed (every slot a 3-ring train — deliberately generous). */
export const PASS_RINGS_PER_SLOT = 3;
/** `passes`: slack on top of the bound. */
export const PASS_EXTRA = 5;
/** `jump` (soft): only scores at least this high are judged. */
export const JUMP_MIN_SCORE = 500;
/** `jump` (soft): a score above this × the median of the history … */
export const JUMP_FACTOR = 5;
/** … with at least this many history entries. */
export const JUMP_MIN_HISTORY = 5;

/** One anomaly flag (`versusFlags/{uid}_{runId}`). */
export interface FlagDoc {
  uid: string;
  runId: string;
  score: number;
  best: number;
  /** Signal name → its measured value (see anomaly.ts). */
  signals: Record<string, number>;
  /** Only the soft `jump` signal fired (listed separately; never acted on alone). */
  soft: boolean;
  durationCs: number;
  passes: number;
  level: number;
  /** The pool the run went into, null when it was not pooled (rate-limited or an older run). */
  pool: string | null;
  platform: string;
  ts: Timestamp;
  expireAt: Timestamp;
}
// endregion PRD-2.5 §3.6
