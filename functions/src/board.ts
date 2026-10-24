/**
 * PRD-2.6 LB1–LB3 own leaderboard: pure board logic shared by the callables
 * and the Firestore store. This module never reads or writes Firestore; it
 * only builds and validates the documents and payloads those layers use.
 *
 * The wave-0 callable surface lives in `board_store.ts`. Keeping groups,
 * ghosts, ranking, prizes, gift rolls and run checks here makes every rule
 * testable with a fixed clock and an injected random source.
 */
import { createHash } from 'node:crypto';
import { Timestamp } from 'firebase-admin/firestore';
import { passBound, runFacts, scoreRun, type Anomaly, type RunFacts } from './anomaly.js';
import { bracketFor } from './brackets.js';
import {
  LB_BEST_SIZE,
  LB_GIFTS,
  LB_GHOST_MAX_AGE,
  LB_GROUP_MS,
  LB_GROUP_SIZE,
  LB_HIST_FROM,
  LB_MAX_RUNS_DAY,
  LB_MAX_SCORE,
  LB_MIN_LEFT_MS,
  LB_OFFLINE_BACKDATE,
  LB_PLAYING_NOW_MS,
  LB_PRIZE_PLACES,
  MIN_SCORE,
  utcDay,
  type LbBestRow,
  type LbGiftDoc,
  type LbGiftRoll,
  type LbGiftTier,
  type LbGhost,
  type LbGhostDay,
  type LbGhostPoint,
  type LbGroupDoc,
  type LbGroupMember,
  type Look,
  type RunEntry,
} from './schema.js';
import { decodeDeltas, decodeEntries, gapOk, plausibleValues } from './timeline.js';

export { LB_GIFTS };

export const LB_TAB_TODAY = 'today';
export const LB_TAB_BEST = 'best';
export type LbBoardTab = typeof LB_TAB_TODAY | typeof LB_TAB_BEST;

export type LbRunMode = 'free' | 'versus' | 'weekly' | string;

export interface LbSubmittedRun {
  id: string;
  score: number;
  hoops: number;
  cs: number;
  endTs: number;
  mode: LbRunMode;
  /** Optional timeline; required by the server for a notable run. */
  tl?: string;
  fl?: string;
}

/** `lbSubmitRun` request (1–10 queued runs per call). */
export interface LbSubmitRunRequest {
  runs: LbSubmittedRun[];
  name?: string;
  look?: Look;
  card?: string;
  platform?: 'android' | 'ios';
  /** 1 = debug / profile / tester / e2e: hidden from every board. */
  t?: 0 | 1;
}

export interface LbDroppedRun {
  id: string;
  reason: string;
}

export interface LbGroupRef {
  id: string;
  end: number;
  bracket: number;
}

export interface LbRankChange {
  before: number | null;
  after: number | null;
}

export interface LbSubmitRunResult {
  accepted: string[];
  dropped: LbDroppedRun[];
  group?: LbGroupRef | null;
  rank?: LbRankChange | null;
  board?: LbBoardPayload | null;
  gifts?: LbGiftDoc[] | null;
}

/** One opaque board row; `rid` never exposes a uid or a ghost marker. */
export interface LbBoardRow {
  rid: string;
  rank: number;
  name: string;
  look: Look;
  card?: string;
  points: number;
  best?: number;
  lastAt?: number;
  playingNow?: boolean;
}

export interface LbBoardPayload {
  tab: LbBoardTab;
  rows: LbBoardRow[];
  me?: LbBoardRow | null;
  floor?: number | null;
  approximate?: boolean;
  group?: Pick<LbGroupDoc, 'bracket' | 'start' | 'end'> | null;
  gifts?: Array<Pick<LbGiftDoc, 'gid' | 'tier' | 'boardRank' | 'claimedAt'>>;
}

export interface LbGetBoardRequest {
  tab?: LbBoardTab;
}

export interface LbGetBoardResult {
  today: LbBoardPayload;
  best: LbBoardPayload;
  bestAllTime?: number | null;
}

export interface LbClaimGiftRequest {
  id: string;
}

export interface LbClaimGiftResult {
  ok: boolean;
  id?: string;
  tier?: LbGiftTier;
  prize?: LbGiftRoll;
}

export interface LbSettleResult {
  groups: number;
  gifts: number;
  ghostDays: number;
}

// endregion LB3 public shapes

// region PRD-2.6 LB1 — brackets, groups and ghosts

const DAY_MS = 24 * 60 * 60 * 1000;

/** A group document lives three days after its 24 h race (PRD LB3). */
export const LB_GROUP_TTL_MS = 3 * DAY_MS;
/** The server allows up to a minute of client clock skew. */
export const LB_RUN_CLOCK_SLACK_MS = 60 * 1000;
/** An old timeline may still improve BEST for this long (LB3). */
export const LB_BEST_RAISE_MS = 7 * DAY_MS;
/** The largest plausible run duration: one full group day. */
export const LB_MAX_RUN_CS = 24 * 60 * 60 * 100;

export type LbGhostPools = Readonly<Record<number, readonly LbGhostDay[]>>;

/** A pool candidate may carry the private flag the schema does not expose. */
export interface LbGhostCandidate extends LbGhostDay {
  hidden?: boolean;
}

export interface LbGhostSelectionOptions {
  bracket: number;
  slots: number;
  pools: LbGhostPools;
  /** The viewer and every real member: neither can be a ghost. */
  excludeUids: Iterable<string>;
  nowMs: number;
  groupStartMs: number;
  /** Injected for deterministic tests; defaults to Math.random. */
  random?: () => number;
}

/** Highest bracket whose threshold the server-verified best reaches. */
export function bracketForVerifiedBest(best: number): number {
  return bracketFor(Number.isFinite(best) && best > 0 ? Math.floor(best) : 0);
}

/**
 * The bracket search order: own first, then ±1, then ±2. Lower brackets lead
 * on each side, matching the versus pool search's deterministic ordering.
 */
export function ghostBracketOrder(bracket: number): number[] {
  const order = [bracket];
  for (let distance = 1; distance <= 2; distance++) {
    if (bracket - distance >= 0) order.push(bracket - distance);
    if (bracket + distance <= 10) order.push(bracket + distance);
  }
  return order;
}

function millis(v: Timestamp | number): number {
  return typeof v === 'number' ? v : v.toMillis();
}

function epochDay(ms: number): number {
  return Math.floor(ms / DAY_MS) * DAY_MS;
}

function dayMillis(day: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return null;
  const ms = Date.parse(`${day}T00:00:00.000Z`);
  return Number.isFinite(ms) ? ms : null;
}

function shuffle<T>(items: T[], random: () => number): T[] {
  for (let i = items.length - 1; i > 0; i--) {
    const j = Math.min(i, Math.floor(random() * (i + 1)));
    const tmp = items[i];
    items[i] = items[j];
    items[j] = tmp;
  }
  return items;
}

/**
 * Fill empty group places from real players' earlier days. Supply falls from
 * the own bracket to ±1 and ±2; when every eligible pool is exhausted the
 * group simply has fewer rows. One uid can appear only once.
 */
export function selectGhosts(opts: LbGhostSelectionOptions): LbGhost[] {
  const target = Math.max(0, Math.min(LB_GROUP_SIZE, Math.floor(opts.slots)));
  if (target === 0) return [];
  const excluded = new Set<string>();
  for (const uid of opts.excludeUids) if (uid) excluded.add(uid);
  const selected: LbGhost[] = [];
  const startDay = epochDay(opts.groupStartMs);
  const nowDay = epochDay(opts.nowMs);

  for (const bracket of ghostBracketOrder(opts.bracket)) {
    if (selected.length >= target) break;
    const rows = (opts.pools[bracket] ?? []) as readonly LbGhostCandidate[];
    const byUid = new Map<string, LbGhostCandidate>();
    for (const row of rows) {
      const uid = typeof row.uid === 'string' ? row.uid : '';
      const at = dayMillis(row.day);
      if (!uid || excluded.has(uid) || row.hidden === true || at === null) continue;
      // Ghost days are earlier days only; at most 14 days before the race.
      // `row.day` is the UTC midnight of the day; the race starts later that
      // same day, so compare whole days rather than the timestamp (`<= 14`).
      const ageDays = Math.floor((startDay - at) / DAY_MS);
      if (at >= startDay || ageDays > 14 || nowDay - at > LB_GHOST_MAX_AGE) continue;
      if (!Array.isArray(row.runs) || row.runs.length === 0) continue;
      const old = byUid.get(uid);
      // Keep the newest eligible day of a player before the random shuffle.
      if (old === undefined || row.day > old.day) byUid.set(uid, row);
    }
    const bucket = shuffle([...byUid.values()], opts.random ?? Math.random);
    for (const row of bucket) {
      if (selected.length >= target) break;
      if (excluded.has(row.uid)) continue;
      excluded.add(row.uid);
      selected.push({
        uid: row.uid,
        runs: row.runs.map((point) => [point[0], point[1]] as LbGhostPoint),
        name: row.name,
        look: row.look,
        ...(row.card === undefined ? {} : { card: row.card }),
        platform: row.platform,
      });
    }
  }
  return selected;
}

export interface LbJoinMember {
  points: number;
  best: number;
  runs: number;
  lastMs: number;
  name: string;
  look: Look;
  card?: string;
  platform: 'android' | 'ios';
}

export interface LbJoinGroupInput {
  uid: string;
  bracket: number;
  nowMs: number;
  /** The start of the first run in the request; back-dated at most 6 h. */
  runStartMs: number;
  member: LbJoinMember;
  /** The caller's current open group, if known. */
  group?: LbGroupDoc | null;
  pools?: LbGhostPools;
  /** Hidden players never join a public group. */
  hidden?: boolean;
  random?: () => number;
  /** Callers may supply the doc id; the deterministic default is test-friendly. */
  gid?: string;
}

export interface LbJoinGroupResult {
  created: boolean;
  joined: boolean;
  hidden: boolean;
  group: LbGroupDoc | null;
  ref: LbGroupRef | null;
  removedGhost: LbGhost | null;
}

function groupKey(bracket: number, startMs: number): string {
  return `${bracket}_${startMs.toString(36)}`;
}

function makeMember(input: LbJoinMember): LbGroupMember {
  return {
    t: Math.max(0, Math.floor(input.points)),
    b: Math.max(0, Math.floor(input.best)),
    n: Math.max(0, Math.floor(input.runs)),
    last: Timestamp.fromMillis(Math.floor(input.lastMs)),
    name: input.name,
    look: input.look,
    ...(input.card === undefined ? {} : { card: input.card }),
    platform: input.platform,
  };
}

function freshGroup(input: LbJoinGroupInput): LbGroupDoc {
  const earliest = input.nowMs - LB_OFFLINE_BACKDATE;
  const start = Math.min(input.nowMs, Math.max(earliest, Math.floor(input.runStartMs)));
  const end = start + LB_GROUP_MS;
  const uid = input.uid;
  const memberUids = [uid];
  const members: Record<string, LbGroupMember> = { [uid]: makeMember(input.member) };
  const ghosts = selectGhosts({
    bracket: input.bracket,
    slots: LB_GROUP_SIZE - 1,
    pools: input.pools ?? {},
    excludeUids: memberUids,
    nowMs: input.nowMs,
    groupStartMs: start,
    random: input.random,
  });
  return {
    bracket: input.bracket,
    start: Timestamp.fromMillis(start),
    end: Timestamp.fromMillis(end),
    memberUids,
    members,
    ghosts,
    ghostUids: ghosts.flatMap((ghost) => (ghost.uid === undefined ? [] : [ghost.uid])),
    settled: false,
    expireAt: Timestamp.fromMillis(end + LB_GROUP_TTL_MS),
  };
}

/**
 * Join an existing group until it has 50 real members. A group with under
 * three hours left, a full group, a settled group, or a group of another
 * bracket opens a fresh 24 h race. Every real join drops its lowest-ranked
 * shown ghost row.
 */
export function joinGroup(input: LbJoinGroupInput): LbJoinGroupResult {
  if (input.hidden === true) {
    return { created: false, joined: false, hidden: true, group: null, ref: null, removedGhost: null };
  }
  const uid = input.uid;
  if (!uid) throw new Error('joinGroup needs a uid');

  const current = input.group ?? null;
  const currentStart = current === null ? 0 : millis(current.start);
  const currentEnd = current === null ? 0 : millis(current.end);
  const hasRoom = current !== null && current.memberUids.length < LB_GROUP_SIZE;
  const enoughTime = current !== null && currentEnd - input.nowMs >= LB_MIN_LEFT_MS;
  const sameBracket = current !== null && current.bracket === input.bracket;
  // An existing member stays in the running group even when it is full or
  // inside its final three hours; those limits apply to a new joiner only.
  const stillRunning = current !== null && !current.settled && currentEnd > input.nowMs;
  if (stillRunning && current !== null) {
    const group = current;
    const existing = group.members[uid];
    if (existing !== undefined) {
      return {
        created: false,
        joined: true,
        hidden: false,
        group,
        ref: { id: input.gid ?? groupKey(group.bracket, currentStart), end: currentEnd, bracket: group.bracket },
        removedGhost: null,
      };
    }
    if (sameBracket && hasRoom && enoughTime) {
      const ghosts = [...group.ghosts];
      const ownGhost = ghosts.findIndex((ghost) => ghost.uid === uid);
      const rankedGhosts = rankToday(group, input.nowMs, { includeHidden: true })
        .filter((entry) => entry.ghost)
        .map((entry) => entry.uid);
      const lowestShownGhost = rankedGhosts.length === 0 ? null : rankedGhosts[rankedGhosts.length - 1];
      const removeIndex =
        ownGhost >= 0
          ? ownGhost
          : lowestShownGhost === null
            ? ghosts.length - 1
            : ghosts.findIndex((ghost) => ghost.uid === lowestShownGhost);
      const removedGhost = removeIndex >= 0 ? ghosts.splice(removeIndex, 1)[0] : null;
      const memberUids = [...group.memberUids, uid];
      const members = { ...group.members, [uid]: makeMember(input.member) };
      const next: LbGroupDoc = {
        ...group,
        memberUids,
        members,
        ghosts,
        ghostUids: ghosts.flatMap((ghost) => (ghost.uid === undefined ? [] : [ghost.uid])),
      };
      return {
        created: false,
        joined: true,
        hidden: false,
        group: next,
        ref: {
          id: input.gid ?? groupKey(group.bracket, currentStart),
          end: currentEnd,
          bracket: group.bracket,
        },
        removedGhost,
      };
    }
  }

  const group = freshGroup(input);
  const start = millis(group.start);
  const end = millis(group.end);
  return {
    created: true,
    joined: true,
    hidden: false,
    group,
    ref: { id: input.gid ?? groupKey(group.bracket, start), end, bracket: group.bracket },
    removedGhost: null,
  };
}

/**
 * Points a ghost has reached at [atMs]. Each recorded run appears at the
 * first occurrence of its UTC time of day at or after the group start; its
 * score is added to the running total, exactly like a real member's runs.
 */
export function ghostProgress(
  runs: readonly LbGhostPoint[],
  groupStartMs: number,
  groupEndMs: number,
  atMs: number,
): { points: number; best: number; reachedAtMs: number | null; lastAtMs: number | null } {
  const firstDay = epochDay(groupStartMs);
  const sorted = runs
    .filter((point) => Array.isArray(point) && point.length >= 2)
    .filter((point) => Number.isFinite(point[0]) && Number.isFinite(point[1]) && point[1] > 0)
    .map((point) => {
      const todMs = Math.floor(point[0]) * 1000;
      let at = firstDay + todMs;
      if (at < groupStartMs) at += DAY_MS;
      return { at, score: Math.max(0, Math.floor(point[1])) };
    })
    .filter((point) => point.at < groupEndMs)
    .sort((a, b) => a.at - b.at);
  let points = 0;
  let best = 0;
  let reachedAtMs: number | null = null;
  let lastAtMs: number | null = null;
  for (const point of sorted) {
    if (point.at > atMs) break;
    points += point.score;
    best = Math.max(best, point.score);
    reachedAtMs = point.at;
    lastAtMs = point.at;
  }
  return { points, best, reachedAtMs, lastAtMs };
}

export interface LbRankedEntry {
  uid: string;
  ghost: boolean;
  hidden: boolean;
  rank: number;
  name: string;
  look: Look;
  card?: string;
  platform: 'android' | 'ios';
  points: number;
  best: number;
  reachedAtMs: number | null;
  lastAtMs: number | null;
  playingNow: boolean;
}

export interface LbRankTodayOptions {
  hiddenUids?: Iterable<string>;
  /** Prize settlement ranks hidden members to keep their place reserved. */
  includeHidden?: boolean;
}

function compareRanked(
  a: Pick<LbRankedEntry, 'points' | 'best' | 'reachedAtMs' | 'uid'>,
  b: Pick<LbRankedEntry, 'points' | 'best' | 'reachedAtMs' | 'uid'>,
): number {
  if (a.points !== b.points) return b.points - a.points;
  if (a.best !== b.best) return b.best - a.best;
  const at = (a.reachedAtMs ?? Number.MAX_SAFE_INTEGER) - (b.reachedAtMs ?? Number.MAX_SAFE_INTEGER);
  if (at !== 0) return at;
  return a.uid.localeCompare(b.uid);
}

/**
 * Rank TODAY: total points, then the best run today, then who reached that
 * total first. Real players last less than five minutes ago are PLAYING NOW;
 * ghosts never are.
 */
export function rankToday(group: LbGroupDoc, atMs: number, opts: LbRankTodayOptions = {}): LbRankedEntry[] {
  const groupStart = millis(group.start);
  const groupEnd = millis(group.end);
  const hidden = new Set(opts.hiddenUids ?? []);
  const memberUids = new Set(group.memberUids);
  const entries: LbRankedEntry[] = [];

  for (const uid of group.memberUids) {
    const member = group.members[uid];
    if (member === undefined) continue;
    const isHidden = hidden.has(uid);
    if (isHidden && opts.includeHidden !== true) continue;
    const lastAtMs = millis(member.last);
    const age = atMs - lastAtMs;
    entries.push({
      uid,
      ghost: false,
      hidden: isHidden,
      rank: 0,
      name: member.name,
      look: member.look,
      ...(member.card === undefined ? {} : { card: member.card }),
      platform: member.platform,
      points: member.t,
      best: member.b,
      reachedAtMs: lastAtMs,
      lastAtMs,
      playingNow: age >= 0 && age < LB_PLAYING_NOW_MS,
    });
  }

  const seenGhosts = new Set<string>();
  for (const ghost of group.ghosts) {
    const uid = ghost.uid;
    if (!uid || hidden.has(uid) || memberUids.has(uid) || seenGhosts.has(uid)) continue;
    seenGhosts.add(uid);
    const progress = ghostProgress(ghost.runs, groupStart, groupEnd, atMs);
    // A ghost with no run yet still holds one of the group's 50 places; it
    // simply has 0 points until its first replayed run. Dropping the row
    // would shrink the board and let a real joiner pass the ghost's place.
    entries.push({
      uid,
      ghost: true,
      hidden: false,
      rank: 0,
      name: ghost.name ?? '',
      look: ghost.look ?? { bird: 'classic', gear: 'none', hat: 'none', hoop: 'pink', trail: 'flame' },
      ...(ghost.card === undefined ? {} : { card: ghost.card }),
      platform: ghost.platform ?? 'android',
      points: progress.points,
      best: progress.best,
      reachedAtMs: progress.reachedAtMs,
      lastAtMs: progress.lastAtMs ?? groupStart,
      playingNow: false,
    });
  }

  entries.sort(compareRanked);
  entries.forEach((entry, i) => {
    entry.rank = i + 1;
  });
  return entries;
}

function opaqueRid(gid: string, uid: string): string {
  return createHash('sha256').update(`${gid}\u0000${uid}`).digest('hex').slice(0, 16);
}

/** A TODAY row deliberately omits BEST (O62) and any ghost marker. */
export function todayBoard(
  group: LbGroupDoc,
  viewerUid: string,
  atMs: number,
  opts: LbRankTodayOptions & { gid?: string } = {},
): LbBoardPayload {
  const gid = opts.gid ?? groupKey(group.bracket, millis(group.start));
  const ranked = rankToday(group, atMs, { hiddenUids: opts.hiddenUids });
  const rows = ranked.map((entry) => ({
    rid: opaqueRid(gid, entry.uid),
    rank: entry.rank,
    name: entry.name,
    look: entry.look,
    ...(entry.card === undefined ? {} : { card: entry.card }),
    points: entry.points,
    ...(entry.lastAtMs === null ? {} : { lastAt: entry.lastAtMs }),
    ...(entry.playingNow ? { playingNow: true } : {}),
  }));
  const meEntry = ranked.find((entry) => entry.uid === viewerUid);
  return {
    tab: LB_TAB_TODAY,
    rows,
    me: meEntry === undefined ? null : rows[meEntry.rank - 1] ?? null,
    group: { bracket: group.bracket, start: group.start, end: group.end },
    gifts: [],
  };
}

// endregion PRD-2.6 LB1

// region PRD-2.6 LB1 — BEST RUN ranking

export interface LbRankedBest extends LbBestRow {
  rank: number;
}

export interface LbBestBoardOptions {
  hiddenUids?: Iterable<string>;
  gid?: string;
  floor?: number | null;
  totalPlayers?: number;
}

/** Rank verified best runs; equal scores go to the earlier bestAt. */
export function rankBestRuns(rows: readonly LbBestRow[], hiddenUids: Iterable<string> = []): LbRankedBest[] {
  const hidden = new Set(hiddenUids);
  const byUid = new Map<string, LbBestRow>();
  for (const row of rows) {
    if (!row.uid || hidden.has(row.uid)) continue;
    const old = byUid.get(row.uid);
    if (
      old === undefined ||
      row.best > old.best ||
      (row.best === old.best && millis(row.bestAt) < millis(old.bestAt))
    ) {
      byUid.set(row.uid, row);
    }
  }
  return [...byUid.values()]
    .sort((a, b) => {
      if (a.best !== b.best) return b.best - a.best;
      const at = millis(a.bestAt) - millis(b.bestAt);
      if (at !== 0) return at;
      return a.uid.localeCompare(b.uid);
    })
    .map((row, i) => ({ ...row, rank: i + 1 }));
}

/** BEST RUN: top 50 plus the caller's pinned row, with an optional approximate flag. */
export function bestBoard(
  rows: readonly LbBestRow[],
  viewerUid: string,
  opts: LbBestBoardOptions = {},
): LbBoardPayload {
  const gid = opts.gid ?? 'global';
  const ranked = rankBestRuns(rows, opts.hiddenUids ?? []);
  const toRow = (entry: LbRankedBest): LbBoardRow => ({
    rid: opaqueRid(gid, entry.uid),
    rank: entry.rank,
    name: entry.name,
    look: entry.look,
    ...(entry.card === undefined ? {} : { card: entry.card }),
    points: entry.best,
    best: entry.best,
    lastAt: millis(entry.bestAt),
  });
  const top = ranked.slice(0, LB_BEST_SIZE).map(toRow);
  const mine = ranked.find((entry) => entry.uid === viewerUid);
  return {
    tab: LB_TAB_BEST,
    rows: top,
    me: mine === undefined ? null : toRow(mine),
    floor:
      opts.floor ??
      (ranked.length > 0 ? ranked[Math.min(ranked.length, LB_BEST_SIZE) - 1].best : null),
    approximate: (opts.totalPlayers ?? ranked.length) >= LB_HIST_FROM,
  };
}

// endregion PRD-2.6 LB1 BEST RUN

// region PRD-2.6 LB2 — O65 podium prizes

export interface LbPrizeAward {
  uid: string;
  gid: string;
  tier: LbGiftTier;
  boardRank: 1 | 2 | 3;
}

/**
 * O65: the full board's places 1–3 map to gold / silver / bronze. A ghost or
 * hidden member keeps its place, so that tier is awarded to nobody; no one
 * moves up and places 4+ never receive a box.
 */
export function prizeAwards(ranked: readonly LbRankedEntry[], gid: string): LbPrizeAward[] {
  const tiers: readonly LbGiftTier[] = ['gold', 'silver', 'bronze'];
  const awards: LbPrizeAward[] = [];
  for (let i = 0; i < Math.min(LB_PRIZE_PLACES, ranked.length); i++) {
    const entry = ranked[i];
    if (entry.ghost || entry.hidden) continue;
    awards.push({
      uid: entry.uid,
      gid,
      tier: tiers[i],
      boardRank: (i + 1) as 1 | 2 | 3,
    });
  }
  return awards;
}

/** Settlement helper: rank the complete board (hidden members included) and pay O65. */
export function settlePrizeAwards(
  group: LbGroupDoc,
  gid: string,
  atMs: number,
  hiddenUids: Iterable<string> = [],
): LbPrizeAward[] {
  return prizeAwards(rankToday(group, atMs, { hiddenUids, includeHidden: true }), gid);
}

// endregion PRD-2.6 LB2 prizes

// region PRD-2.6 LB2 — gift table and roll

export type LbGiftRarity = 'common' | 'rare';

/** A shop item the server may grant from a gold box (versus cards excluded). */
export interface LbGiftShopItem {
  id: string;
  price: number;
  rarity: LbGiftRarity;
}

export interface LbGiftRollOptions {
  /** Injected random source; a seeded source keeps claims replayable in tests. */
  random?: () => number;
  /** Stored alongside the roll so a claim can be debugged without the RNG. */
  seed?: string;
  ownedItems?: Iterable<string>;
  shopItems?: readonly LbGiftShopItem[];
  feathersHeld?: number;
  piecesHeld?: number;
  /** Direct overrides for a claim already checked against the player's state. */
  canTakeFeather?: boolean;
  canTakePiece?: boolean;
}

/** Deterministic PRNG for tests and for reproducing a stored seed. */
export function seededRandom(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function randomStep(min: number, max: number, step: number, random: () => number): number {
  const steps = Math.floor((max - min) / step) + 1;
  const index = Math.min(steps - 1, Math.max(0, Math.floor(random() * steps)));
  return min + index * step;
}

function rollCoins(tier: LbGiftTier, random: () => number): number {
  const table = LB_GIFTS[tier];
  return randomStep(table.coinsMin, table.coinsMax, table.coinStep, random);
}

function chooseItem(
  items: readonly LbGiftShopItem[],
  owned: Set<string>,
  random: () => number,
): LbGiftShopItem | null {
  const eligible = items.filter(
    (item) => item.price >= 0 && item.price <= LB_GIFTS.gold.itemMaxPrice && !owned.has(item.id),
  );
  if (eligible.length === 0) return null;
  const common = eligible.filter((item) => item.rarity === 'common').sort((a, b) => a.id.localeCompare(b.id));
  const rare = eligible.filter((item) => item.rarity === 'rare').sort((a, b) => a.id.localeCompare(b.id));
  let bucket: LbGiftShopItem[];
  if (common.length > 0 && rare.length > 0) {
    bucket = random() * 100 < LB_GIFTS.gold.commonPct ? common : rare;
  } else {
    bucket = common.length > 0 ? common : rare;
  }
  if (bucket.length === 0) return null;
  return bucket[Math.min(bucket.length - 1, Math.floor(random() * bucket.length))];
}

/**
 * Roll one free gift box. Bronze and silver are coin ranges in steps of 5.
 * Gold first rolls its prize class, then always pre-rolls 100–300 fallback
 * coins. The O68 fallback chain is: unowned item → coins; feather the player
 * cannot hold → piece; piece at its limit → the pre-rolled coins.
 */
export function rollGift(tier: LbGiftTier, opts: LbGiftRollOptions = {}): LbGiftRoll {
  const random = opts.random ?? Math.random;
  const seedPart = opts.seed === undefined ? {} : { seed: opts.seed };
  if (tier === 'bronze' || tier === 'silver') {
    return { kind: 'coins', coins: rollCoins(tier, random), ...seedPart };
  }

  const classRoll = random() * 100;
  // Every gold roll carries fallback coins, whichever class won.
  const fallback = rollCoins('gold', random);
  const featherOk = opts.canTakeFeather ?? (opts.feathersHeld ?? 0) < 3;
  const pieceOk = opts.canTakePiece ?? (opts.piecesHeld ?? 0) < 4;
  const coinsRoll = (): LbGiftRoll => ({ kind: 'coins', coins: fallback, ...seedPart });
  const pieceRoll = (): LbGiftRoll => ({ kind: 'piece', coins: fallback, ...seedPart });

  if (classRoll < LB_GIFTS.gold.coinsPct) return coinsRoll();
  if (classRoll < LB_GIFTS.gold.coinsPct + LB_GIFTS.gold.featherPct) {
    if (featherOk) return { kind: 'feather', coins: fallback, ...seedPart };
    return pieceOk ? pieceRoll() : coinsRoll();
  }
  if (classRoll < LB_GIFTS.gold.coinsPct + LB_GIFTS.gold.featherPct + LB_GIFTS.gold.piecePct) {
    return pieceOk ? pieceRoll() : coinsRoll();
  }

  const item = chooseItem(opts.shopItems ?? [], new Set(opts.ownedItems ?? []), random);
  if (item === null) return coinsRoll();
  return {
    kind: 'item',
    coins: fallback,
    item: item.id,
    rarity: item.rarity,
    ...seedPart,
  };
}

// endregion PRD-2.6 LB2 gifts

// region PRD-2.6 LB3 — accepted-run checks

export const LB_DROP_REASONS = [
  'shape',
  'low_score',
  'max_score',
  'duplicate',
  'time',
  'overlap',
  'old',
  'bounds',
  'timeline',
  'daily_cap',
] as const;
export type LbDropReason = (typeof LB_DROP_REASONS)[number];

export interface LbRunInterval {
  id?: string;
  startMs: number;
  endMs: number;
}

export interface LbRunCheckContext {
  /** Server clock, Unix milliseconds. */
  nowMs: number;
  /** Server-verified personal best before this batch. */
  best: number;
  /** Last accepted scores, oldest first, for the soft jump signal. */
  hist?: readonly number[];
  /** Start of the current group; a run ended before it is `old`. */
  groupStartMs?: number | null;
  /** BEST RUN top-50 floor. */
  floor?: number | null;
  /** Accepted run ids already in the player's rate document. */
  seenIds?: Iterable<string>;
  /** Accepted run intervals already in the player's rate document. */
  intervals?: readonly LbRunInterval[];
  /** Latest accepted run end, shorthand for one interval boundary. */
  lastEndMs?: number | null;
  /** Accepted-run counts keyed by UTC day (`utcDay`). */
  dailyCounts?: Readonly<Record<string, number>>;
  /** Count for the current UTC day when a map is not supplied. */
  dailyCount?: number;
  /** `t: 1`: accepted privately, never ranked, pooled or rewarded. */
  hidden?: boolean;
  /** Override the seven-day BEST-raise window. */
  bestWindowMs?: number;
}

export interface LbBestUpdate {
  score: number;
  atMs: number;
  /** A hard anomaly updates the owner's BEST but leaves the public shadow best behind. */
  shadow: boolean;
}

export interface LbRunCheck {
  id: string;
  accepted: boolean;
  reason?: LbDropReason;
  /** Score that may enter TODAY; a clamped run never reaches BEST. */
  counted: number;
  notable: boolean;
  clamped: boolean;
  hidden: boolean;
  shadow: boolean;
  timelineVerified: boolean;
  bracket: number;
  bestUpdate: LbBestUpdate | null;
  anomaly?: Anomaly | null;
  passes?: number;
  passBound?: number;
}

export interface LbRunBatchResult {
  results: LbRunCheck[];
  accepted: string[];
  dropped: LbDroppedRun[];
  bracket: number;
  dailyCounts: Record<string, number>;
}

interface TimelineVerified {
  ok: boolean;
  reason?: LbDropReason;
  anomaly?: Anomaly | null;
  facts?: RunFacts;
}

const LB_RUN_LOOK: Look = { bird: 'classic', gear: 'none', hat: 'none', hoop: 'pink', trail: 'flame' };

function isSafeInt(value: unknown, min: number, max: number): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= min && value <= max;
}

function validRunShape(input: unknown): input is LbSubmittedRun {
  if (input === null || typeof input !== 'object') return false;
  const run = input as Record<string, unknown>;
  return (
    typeof run.id === 'string' &&
    run.id.length >= 1 &&
    run.id.length <= 128 &&
    isSafeInt(run.score, 0, Number.MAX_SAFE_INTEGER) &&
    isSafeInt(run.hoops, 0, Number.MAX_SAFE_INTEGER) &&
    isSafeInt(run.cs, 1, LB_MAX_RUN_CS) &&
    isSafeInt(run.endTs, 0, Number.MAX_SAFE_INTEGER) &&
    (run.mode === 'free' || run.mode === 'versus' || run.mode === 'weekly') &&
    (run.tl === undefined || (typeof run.tl === 'string' && run.tl.length <= 16384)) &&
    (run.fl === undefined || (typeof run.fl === 'string' && run.fl.length <= 8192))
  );
}

function scoreOnlyBoundsOk(run: LbSubmittedRun): boolean {
  if (run.hoops < 1 || run.hoops > passBound(run.cs)) return false;
  return run.score <= run.hoops * (run.hoops + 11);
}

function verifyTimeline(run: LbSubmittedRun, ctx: LbRunCheckContext): TimelineVerified {
  if (run.tl === undefined && run.fl === undefined) return { ok: false };
  if (run.tl === undefined || run.fl === undefined) return { ok: false, reason: 'timeline' };
  const deltas = decodeDeltas(run.tl);
  if (deltas === null) return { ok: false, reason: 'timeline' };
  const timelineCs = deltas.reduce((sum, delta) => sum + delta, 0);
  const endCs = run.cs - timelineCs;
  if (endCs < 0 || endCs > 65535) return { ok: false, reason: 'bounds' };
  const best = Math.max(run.score, ctx.best);
  const entry: RunEntry = {
    runId: run.id,
    score: run.score,
    best,
    ts: Timestamp.fromMillis(run.endTs),
    name: 'LeaderboardRun',
    avatar: '',
    look: LB_RUN_LOOK,
    platform: 'android',
    tl: run.tl,
    end: endCs,
    fl: run.fl,
  };
  const entries = decodeEntries(run.fl);
  if (entries === null) return { ok: false, reason: 'timeline' };
  if (entries.flags.length !== deltas.length) return { ok: false, reason: 'timeline' };
  if (entries.values.reduce((sum, value) => sum + value, 0) !== run.score) {
    return { ok: false, reason: 'bounds' };
  }
  if (!plausibleValues(entries.flags, entries.values) || !gapOk(deltas, entries.flags)) {
    return { ok: false, reason: 'bounds' };
  }
  const anomaly = scoreRun(entry, [...(ctx.hist ?? [])]);
  const facts = runFacts(entry) ?? undefined;
  return { ok: true, anomaly, facts };
}

function initialDailyCounts(ctx: LbRunCheckContext): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const [day, count] of Object.entries(ctx.dailyCounts ?? {})) {
    if (Number.isFinite(count) && count > 0) counts[day] = Math.floor(count);
  }
  if (ctx.dailyCount !== undefined) {
    const day = utcDay(ctx.nowMs);
    counts[day] = Math.max(counts[day] ?? 0, Math.max(0, Math.floor(ctx.dailyCount)));
  }
  return counts;
}

function intervalStart(run: LbSubmittedRun): number {
  return run.endTs - run.cs * 10;
}

function initialIntervals(ctx: LbRunCheckContext): LbRunInterval[] {
  const out = (ctx.intervals ?? []).filter(
    (i) => Number.isFinite(i.startMs) && Number.isFinite(i.endMs) && i.endMs >= i.startMs,
  );
  if (ctx.lastEndMs !== undefined && ctx.lastEndMs !== null && Number.isFinite(ctx.lastEndMs)) {
    out.push({ startMs: ctx.lastEndMs - 1, endMs: ctx.lastEndMs });
  }
  return out;
}

function overlapsAny(intervals: readonly LbRunInterval[], start: number, end: number): boolean {
  return intervals.some((i) => start < i.endMs && end > i.startMs);
}

function emptyCheck(id: string, bracket: number, reason: LbDropReason, hidden: boolean): LbRunCheck {
  return {
    id,
    accepted: false,
    reason,
    counted: 0,
    notable: false,
    clamped: false,
    hidden,
    shadow: false,
    timelineVerified: false,
    bracket,
    bestUpdate: null,
  };
}

/**
 * Validate one upload request's runs (processed oldest first by the client).
 * The batch shares one wall-clock allowance: the sum of run durations may
 * not exceed the time from the earliest run start to `now` plus 60 s.
 */
export function checkLbRuns(runs: readonly unknown[], ctx: LbRunCheckContext): LbRunBatchResult {
  const bracket = bracketForVerifiedBest(ctx.best);
  const hidden = ctx.hidden === true;
  const dailyCounts = initialDailyCounts(ctx);
  const seen = new Set(ctx.seenIds ?? []);
  const intervals = initialIntervals(ctx);
  const results: LbRunCheck[] = [];
  const accepted: string[] = [];
  const dropped: LbDroppedRun[] = [];

  const shaped = runs
    .map((input, index) => ({ input, index, id: validRunShape(input) ? input.id : '' }))
    .sort((a, b) => {
      if (!validRunShape(a.input) || !validRunShape(b.input)) return a.index - b.index;
      return intervalStart(a.input) - intervalStart(b.input) || a.index - b.index;
    });

  const duplicateIndexes = new Set<number>();
  const batchIds = new Set(seen);
  const aggregateStarts: number[] = [];
  let aggregateCs = 0;
  for (const item of shaped) {
    if (!validRunShape(item.input)) continue;
    const run = item.input;
    if (batchIds.has(run.id)) {
      duplicateIndexes.add(item.index);
      continue;
    }
    batchIds.add(run.id);
    if (run.score > LB_MAX_SCORE || run.score < MIN_SCORE) continue;
    const start = intervalStart(run);
    if (start < 0 || run.endTs > ctx.nowMs + LB_RUN_CLOCK_SLACK_MS) continue;
    const old = ctx.groupStartMs !== undefined && ctx.groupStartMs !== null && run.endTs < ctx.groupStartMs;
    const timeline = verifyTimeline(run, ctx);
    if (run.tl !== undefined || run.fl !== undefined ? !timeline.ok : !scoreOnlyBoundsOk(run)) continue;
    if (!old && (dailyCounts[utcDay(run.endTs)] ?? 0) >= LB_MAX_RUNS_DAY) continue;
    aggregateStarts.push(start);
    aggregateCs += run.cs * 10;
  }
  const aggregateEarliestStart = aggregateStarts.length === 0 ? ctx.nowMs : Math.min(...aggregateStarts);
  const aggregateElapsed = Math.max(0, ctx.nowMs - aggregateEarliestStart);
  const aggregateTimeBad = aggregateCs > aggregateElapsed + LB_RUN_CLOCK_SLACK_MS;

  for (const item of shaped) {
    if (!validRunShape(item.input)) {
      results.push(emptyCheck(item.id, bracket, 'shape', hidden));
      dropped.push({ id: item.id, reason: 'shape' });
      continue;
    }
    const run = item.input;
    const pushDrop = (reason: LbDropReason): void => {
      results.push(emptyCheck(run.id, bracket, reason, hidden));
      dropped.push({ id: run.id, reason });
    };

    if (run.score > LB_MAX_SCORE) {
      pushDrop('max_score');
      continue;
    }
    if (run.score < MIN_SCORE) {
      pushDrop('low_score');
      continue;
    }
    if (seen.has(run.id)) {
      pushDrop('duplicate');
      continue;
    }
    if (duplicateIndexes.has(item.index)) {
      pushDrop('duplicate');
      continue;
    }
    const start = intervalStart(run);
    const end = run.endTs;
    if (start < 0 || end > ctx.nowMs + LB_RUN_CLOCK_SLACK_MS) {
      pushDrop('time');
      continue;
    }

    const notable =
      run.score > ctx.best ||
      run.score > Math.max(500, ctx.best * 2) ||
      ((ctx.floor ?? 0) > 0 && run.score >= (ctx.floor as number));
    const clampTo = Math.max(500, ctx.best * 2);
    const old = ctx.groupStartMs !== undefined && ctx.groupStartMs !== null && end < ctx.groupStartMs;
    const timeline = verifyTimeline(run, ctx);
    const overlaps = overlapsAny(intervals, start, end);
    const day = utcDay(end);
    const dailyCapped = (dailyCounts[day] ?? 0) >= LB_MAX_RUNS_DAY;
    if (old) {
      let bestUpdate: LbBestUpdate | null = null;
      if (
        !hidden &&
        timeline.ok &&
        !overlaps &&
        !aggregateTimeBad &&
        run.score > ctx.best &&
        ctx.nowMs - end <= (ctx.bestWindowMs ?? LB_BEST_RAISE_MS)
      ) {
        const hard = timeline.anomaly !== null && timeline.anomaly !== undefined && !timeline.anomaly.soft;
        bestUpdate = { score: run.score, atMs: end, shadow: hard };
      }
      const result: LbRunCheck = {
        ...emptyCheck(run.id, bracket, 'old', hidden),
        timelineVerified: timeline.ok,
        notable,
        anomaly: timeline.anomaly ?? null,
        ...(timeline.facts === undefined
          ? {}
          : { passes: timeline.facts.passes, passBound: timeline.facts.passBound }),
        bestUpdate,
      };
      results.push(result);
      dropped.push({ id: run.id, reason: 'old' });
      continue;
    }

    if (run.tl !== undefined || run.fl !== undefined) {
      if (!timeline.ok) {
        pushDrop(timeline.reason ?? 'timeline');
        continue;
      }
    } else if (!scoreOnlyBoundsOk(run)) {
      pushDrop('bounds');
      continue;
    }

    if (aggregateTimeBad) {
      pushDrop('time');
      continue;
    }
    if (overlaps) {
      pushDrop('overlap');
      continue;
    }

    if (dailyCapped) {
      pushDrop('daily_cap');
      continue;
    }

    if (run.tl !== undefined || run.fl !== undefined) {
      const hard = timeline.anomaly !== null && timeline.anomaly !== undefined && !timeline.anomaly.soft;
      const bestUpdate =
        !hidden && run.score > ctx.best && ctx.nowMs - end <= (ctx.bestWindowMs ?? LB_BEST_RAISE_MS)
          ? { score: run.score, atMs: end, shadow: hard }
          : null;
      const counted = hard ? Math.min(run.score, clampTo) : run.score;
      const result: LbRunCheck = {
        id: run.id,
        accepted: true,
        counted,
        notable,
        clamped: hard || counted < run.score,
        hidden,
        shadow: bestUpdate?.shadow === true,
        timelineVerified: true,
        bracket,
        bestUpdate,
        anomaly: timeline.anomaly ?? null,
        ...(timeline.facts === undefined
          ? {}
          : { passes: timeline.facts.passes, passBound: timeline.facts.passBound }),
      };
      results.push(result);
      accepted.push(run.id);
      seen.add(run.id);
      intervals.push({ id: run.id, startMs: start, endMs: end });
      dailyCounts[day] = (dailyCounts[day] ?? 0) + 1;
      continue;
    }

    // A notable run without a timeline still counts for TODAY, but only at
    // the 2 × best (minimum 500) clamp and never reaches BEST.
    const result: LbRunCheck = {
      id: run.id,
      accepted: true,
      counted: hidden ? run.score : notable ? Math.min(run.score, clampTo) : run.score,
      notable,
      clamped: !hidden && notable,
      hidden,
      shadow: false,
      timelineVerified: false,
      bracket,
      bestUpdate: null,
      anomaly: null,
    };
    results.push(result);
    accepted.push(run.id);
    seen.add(run.id);
    intervals.push({ id: run.id, startMs: start, endMs: end });
    dailyCounts[day] = (dailyCounts[day] ?? 0) + 1;
  }

  return { results, accepted, dropped, bracket, dailyCounts };
}

/** Convenience wrapper for one run; identical to a one-run batch. */
export function checkLbRun(run: unknown, ctx: LbRunCheckContext): LbRunCheck {
  return checkLbRuns([run], ctx).results[0];
}

// endregion PRD-2.6 LB3 run checks
