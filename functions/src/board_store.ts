/**
 * PRD-2.6 LB3 own leaderboard: Firestore-facing callables and settlement.
 *
 * `board.ts` owns every rule (run validation, groups, ghosts, ranking and the
 * O65 prize placement). This module loads the documents those rules need,
 * commits the resulting writes transactionally and serves client payloads.
 *
 * Idempotency:
 * - accepted run ids live in `lbPlayers/{uid}.rate.runIds`;
 * - settlement is guarded by the group's `settled` flag;
 * - a gift roll is written before it is returned, so a repeat claim is a read.
 */
import { createHash, randomInt } from 'node:crypto';
import { DocumentReference, DocumentSnapshot, Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import {
  bestBoard,
  bracketForVerifiedBest,
  checkLbRuns,
  joinGroup,
  LB_BEST_RAISE_MS,
  LB_GROUP_TTL_MS,
  LB_MAX_RUN_CS,
  LB_TAB_BEST,
  LB_TAB_TODAY,
  rankToday,
  rollGift,
  seededRandom,
  settlePrizeAwards,
  todayBoard,
  type LbBoardPayload,
  type LbClaimGiftResult,
  type LbGetBoardResult,
  type LbJoinGroupResult,
  type LbGiftShopItem,
  type LbRunCheck,
  type LbRunInterval,
  type LbSettleResult,
  type LbSubmitRunResult,
} from './board.js';
import { pruneGhostPools, stripGroups } from './board_delete.js';
import { poolCustomName } from './customname.js';
import { versusName } from './nickname.js';
import {
  LB_BEST_COLLECTION,
  LB_BEST_SIZE,
  LB_FLAGS_COLLECTION,
  LB_GHOST_MAX_AGE,
  LB_GHOST_POOL_COLLECTION,
  LB_GHOST_RUNS,
  LB_GIFTS_COLLECTION,
  LB_GIFT_TTL,
  LB_GROUPS_COLLECTION,
  LB_GROUP_SIZE,
  LB_HIST_FROM,
  LB_OFFLINE_BACKDATE,
  LB_OPEN_COLLECTION,
  LB_OPEN_SHARDS,
  LB_PLAYER_TTL,
  LB_PLAYERS_COLLECTION,
  LB_MIN_LEFT_MS,
  LB_TOMB_COLLECTION,
  NAMES_COLLECTION,
  POOL_MAX_BYTES,
  utcDay,
  validLook,
  type LbBestDoc,
  type LbBestRow,
  type LbFlagDoc,
  type LbGhostDay,
  type LbGhostPoint,
  type LbGhostPoolDoc,
  type LbGiftDoc,
  type LbGroupDoc,
  type LbGroupMember,
  type LbOpenDoc,
  type LbPlayerDoc,
  type Look,
  type NameDoc,
} from './schema.js';
import { validCard } from './card.js';
import { docSize } from './size.js';

const DAY_MS = 24 * 60 * 60 * 1000;
const BEST_CACHE_MS = 60 * 1000;
const FLAG_TTL_MS = 60 * DAY_MS;
const MAX_RUNS = 10;
const MAX_INTERVALS = 50;
const GHOST_SHARDS = 4;
const MAX_GHOST_ENTRIES = 200;
const HIST_BUCKET = 100;
const GIFT_ID_RE = /^[A-Za-z0-9_-]{1,180}$/;
const DEFAULT_LOOK: Look = { bird: 'classic', gear: 'none', hat: 'none', hoop: 'pink', trail: 'flame' };

// Paid common/rare items from lib/skins/catalog.dart; mirrored by a test.
// Ownership and capacity fallbacks are resolved locally using the stored coins.
export const GIFT_SHOP_ITEMS: readonly LbGiftShopItem[] = [
  ...'sky lime grape tangerine mint lemon slate coral snow'.split(' ').map((id) => ({ id: `bird:${id}`, price: 150, rarity: 'common' as const })),
  ...'robin toucan chick penguin owl duck flamingo puffer zebra buzz'.split(' ').map((id) => ({ id: `bird:${id}`, price: 750, rarity: 'rare' as const })),
  ...'shades bowtie stache scarf bandana snorkel necktie bandaid gum lei'.split(' ').map((id) => ({ id: `gear:${id}`, price: 250, rarity: 'common' as const })),
  ...'hearts monocle sneakers windup carpet balloon backpack skates swimring cape'.split(' ').map((id) => ({ id: `gear:${id}`, price: 750, rarity: 'rare' as const })),
  ...'cap beanie party band bucket sprout cone egg paperboat phones'.split(' ').map((id) => ({ id: `hat:${id}`, price: 250, rarity: 'common' as const })),
  ...'tophat cowboy prop chef viking fishbowl cupcake raincloud antennae sharkfin'.split(' ').map((id) => ({ id: `hat:${id}`, price: 750, rarity: 'rare' as const })),
  ...'sky lime violet night sunset lemon bamboo rope cloud'.split(' ').map((id) => ({ id: `hoop:${id}`, price: 250, rarity: 'common' as const })),
  ...'candy polka checker donut tire melon zipper tape pearls vine'.split(' ').map((id) => ({ id: `hoop:${id}`, price: 750, rarity: 'rare' as const })),
  ...'blue toxic hot shadow sunset leaves snow petals ink'.split(' ').map((id) => ({ id: `trail:${id}`, price: 250, rarity: 'common' as const })),
  ...'sparkle bubbles hearts laser confetti planes popcorn fireworks steps fish'.split(' ').map((id) => ({ id: `trail:${id}`, price: 750, rarity: 'rare' as const })),
];

interface StoredRate {
  day: string;
  count: number;
  runIds: string[];
  days?: Record<string, number>;
  intervals?: LbRunInterval[];
}

interface StoredMember extends LbGroupMember {
  runs?: LbGhostPoint[];
}

interface HistogramDoc {
  bins: Record<string, number>;
  updatedAt: Timestamp;
}

interface SubmitInput {
  runs: unknown[];
  name: string;
  look: Look;
  card?: string;
  platform: 'android' | 'ios';
  hidden: boolean;
}

interface PlayerState {
  best: number;
  bestAt: number;
  shadow: number;
  hist: number[];
  seen: string[];
  intervals: LbRunInterval[];
  dailyCounts: Record<string, number>;
  hidden: boolean;
}

interface AcceptedRun {
  id: string;
  score: number;
  counted: number;
  startMs: number;
  endMs: number;
}

interface Candidate {
  group: LbGroupDoc | null;
  gid: string | null;
  ref: DocumentReference | null;
  pointerRef: DocumentReference | null;
  pointerUsable: boolean;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

interface StoredPoint {
  t: number;
  s: number;
}

function storePoint(point: LbGhostPoint): StoredPoint {
  return { t: Math.floor(point[0]), s: Math.max(0, Math.floor(point[1])) };
}

function loadPoint(value: unknown): LbGhostPoint | null {
  if (Array.isArray(value)) {
    const t = Number(value[0]);
    const score = Number(value[1]);
    return Number.isFinite(t) && Number.isFinite(score) ? [Math.floor(t), Math.max(0, Math.floor(score))] : null;
  }
  if (!isObject(value)) return null;
  const t = Number(value.t);
  const score = Number(value.s);
  return Number.isFinite(t) && Number.isFinite(score) ? [Math.floor(t), Math.max(0, Math.floor(score))] : null;
}

function loadPoints(value: unknown): LbGhostPoint[] {
  return Array.isArray(value)
    ? value.map(loadPoint).filter((point): point is LbGhostPoint => point !== null)
    : [];
}

function storeGroup(value: LbGroupDoc): LbGroupDoc {
  const members: Record<string, LbGroupMember> = {};
  for (const [uid, member] of Object.entries(value.members)) {
    const stored = member as StoredMember;
    members[uid] = {
      ...member,
      ...(Array.isArray(stored.runs) ? { runs: stored.runs.map(storePoint) } : {}),
    } as unknown as LbGroupMember;
  }
  return {
    ...value,
    members,
    ghosts: value.ghosts.map((ghost) => ({ ...ghost, runs: ghost.runs.map(storePoint) })),
  } as unknown as LbGroupDoc;
}

function loadGroup(value: unknown): LbGroupDoc | null {
  if (!isObject(value)) return null;
  const members: Record<string, LbGroupMember> = {};
  if (isObject(value.members)) {
    for (const [uid, member] of Object.entries(value.members)) {
      if (!isObject(member)) continue;
      members[uid] = {
        ...(member as unknown as LbGroupMember),
        ...(member.runs === undefined ? {} : { runs: loadPoints(member.runs) }),
      } as unknown as LbGroupMember;
    }
  }
  const ghosts = Array.isArray(value.ghosts)
    ? value.ghosts.filter(isObject).map((ghost) => ({
        ...(ghost as unknown as LbGroupDoc['ghosts'][number]),
        runs: loadPoints(ghost.runs),
      }))
    : [];
  return { ...(value as unknown as LbGroupDoc), members, ghosts };
}

function storeGhostDay(entry: LbGhostDay): LbGhostDay {
  return { ...entry, runs: entry.runs.map(storePoint) } as unknown as LbGhostDay;
}

function loadGhostPool(value: unknown): LbGhostDay[] {
  if (!isObject(value) || !Array.isArray(value.entries)) return [];
  return value.entries.filter(isObject).map((entry) => ({
    ...(entry as unknown as LbGhostDay),
    runs: loadPoints(entry.runs),
  }));
}

function millis(value: unknown): number {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return 0;
}

function at(ms: number): Timestamp {
  return Timestamp.fromMillis(Math.floor(ms));
}

function count(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0;
}

function strings(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string') : [];
}

function numbers(value: unknown): number[] {
  return Array.isArray(value)
    ? value.filter((v): v is number => typeof v === 'number' && Number.isFinite(v))
    : [];
}

function hash32(text: string): number {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
  return h >>> 0;
}

function openShard(uid: string): number {
  return hash32(`open:${uid}`) % Math.max(1, LB_OPEN_SHARDS);
}

function ghostShard(uid: string, day: string): number {
  return hash32(`${uid}:${day}`) % GHOST_SHARDS;
}

function ghostPoolId(bracket: number, shard: number): string {
  return `${bracket}_${shard}`;
}

function openId(bracket: number, shard: number): string {
  return `${bracket}_${shard}`;
}

function freshGroupId(bracket: number, startMs: number, uid: string, nowMs: number): string {
  const clampedStart = Math.min(startMs, nowMs);
  return `${bracket}_${clampedStart.toString(36)}_${hash32(`group:${uid}`).toString(36)}`;
}

function giftId(uid: string, gid: string): string {
  return `${uid}_${gid}`;
}

function deleted(): never {
  throw new HttpsError('permission-denied', 'Leaderboard data was deleted.');
}

function badInput(message: string): never {
  throw new HttpsError('invalid-argument', message);
}

function entryScore(run: unknown): number {
  return isObject(run) ? count(run.score) : 0;
}

function entryEnd(run: unknown): number {
  return isObject(run) && typeof run.endTs === 'number' && Number.isFinite(run.endTs)
    ? Math.floor(run.endTs)
    : 0;
}

function entryCs(run: unknown): number {
  return isObject(run) && typeof run.cs === 'number' && Number.isFinite(run.cs)
    ? Math.max(1, Math.floor(run.cs))
    : 1;
}

function readInput(data: unknown): SubmitInput {
  if (!isObject(data)) badInput('Invalid submission.');
  if (!Array.isArray(data.runs) || data.runs.length < 1 || data.runs.length > MAX_RUNS) {
    badInput('runs must contain 1-10 runs.');
  }
  if (!validLook(data.look)) badInput('Invalid look.');
  if (!validCard(data.card)) badInput('Invalid card.');
  const look = data.look;
  const card = (data.card ?? look.card) as string | undefined;
  if (card !== undefined && !validCard(card)) badInput('Invalid card.');
  if (data.platform !== 'android' && data.platform !== 'ios') badInput('Invalid platform.');
  if (data.t !== undefined && data.t !== 0 && data.t !== 1) badInput('Invalid t.');
  const name = typeof data.name === 'string' && data.name.length <= 32 ? data.name : '';
  return {
    runs: data.runs,
    name,
    look,
    ...(card === undefined ? {} : { card }),
    platform: data.platform,
    hidden: data.t === 1,
  };
}

function loadPlayer(doc: LbPlayerDoc | undefined, input: SubmitInput): PlayerState {
  const rate = doc?.rate as StoredRate | undefined;
  const dailyCounts = isObject(rate?.days) ? { ...(rate!.days as Record<string, number>) } : {};
  if (rate !== undefined && typeof rate.day === 'string' && rate.day) {
    dailyCounts[rate.day] = Math.max(dailyCounts[rate.day] ?? 0, count(rate.count));
  }
  const intervals = Array.isArray(rate?.intervals)
    ? rate!.intervals.filter(
        (i) =>
          isObject(i) &&
          typeof i.startMs === 'number' &&
          Number.isFinite(i.startMs) &&
          typeof i.endMs === 'number' &&
          Number.isFinite(i.endMs),
      )
    : [];
  return {
    best: count(doc?.best),
    bestAt: millis(doc?.bestAt),
    shadow: doc?.bestShadow === undefined ? count(doc?.best) : count(doc.bestShadow),
    hist: numbers(doc?.hist).slice(-10),
    seen: strings(rate?.runIds),
    intervals,
    dailyCounts,
    hidden: doc?.hidden === true || input.hidden,
  };
}

function displayName(uid: string, input: SubmitInput, nameDoc: NameDoc | undefined): string {
  return poolCustomName(nameDoc?.customName) || versusName(input.name, uid);
}

function provisionalStart(runs: unknown[], nowMs: number): number {
  let earliest = nowMs;
  for (const run of runs) {
    if (!isObject(run) || typeof run.endTs !== 'number' || typeof run.cs !== 'number') continue;
    const start = Math.floor(run.endTs - run.cs * 10);
    if (Number.isFinite(start)) earliest = Math.min(earliest, start);
  }
  return Math.min(nowMs, Math.max(nowMs - LB_OFFLINE_BACKDATE, earliest));
}

function isSafeInteger(value: unknown, min: number, max: number): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= min && value <= max;
}

/** Mirrors `validRunShape` in board.ts for choosing among duplicate raw ids. */
function validRunInput(input: unknown): input is Record<string, unknown> {
  if (!isObject(input)) return false;
  return (
    typeof input.id === 'string' &&
    input.id.length >= 1 &&
    input.id.length <= 128 &&
    isSafeInteger(input.score, 0, Number.MAX_SAFE_INTEGER) &&
    isSafeInteger(input.hoops, 0, Number.MAX_SAFE_INTEGER) &&
    isSafeInteger(input.cs, 1, LB_MAX_RUN_CS) &&
    isSafeInteger(input.endTs, 0, Number.MAX_SAFE_INTEGER) &&
    (input.mode === 'free' || input.mode === 'versus' || input.mode === 'weekly') &&
    (input.tl === undefined || (typeof input.tl === 'string' && input.tl.length <= 16384)) &&
    (input.fl === undefined || (typeof input.fl === 'string' && input.fl.length <= 8192))
  );
}

/**
 * The exact raw run the validator chose for [id]. Validation orders valid
 * runs by start time (then raw position) and drops a duplicate id before it
 * can be accepted, so the earliest valid occurrence is the authoritative one.
 */
function validatedRun(runs: readonly unknown[], id: string): Record<string, unknown> | undefined {
  let selected: Record<string, unknown> | undefined;
  let selectedStart = Infinity;
  for (const candidate of runs) {
    if (!validRunInput(candidate) || candidate.id !== id) continue;
    const start = entryEnd(candidate) - entryCs(candidate) * 10;
    if (selected === undefined || start < selectedStart) {
      selected = candidate;
      selectedStart = start;
    }
  }
  return selected;
}

function acceptedRuns(runs: readonly unknown[], checks: LbRunCheck[]): AcceptedRun[] {
  const out: AcceptedRun[] = [];
  for (const check of checks) {
    if (!check.accepted) continue;
    const run = validatedRun(runs, check.id);
    if (run === undefined) continue;
    const endMs = entryEnd(run);
    out.push({
      id: check.id,
      score: entryScore(run),
      counted: Math.max(0, Math.floor(check.counted)),
      startMs: endMs - entryCs(run) * 10,
      endMs,
    });
  }
  return out.sort((a, b) => a.startMs - b.startMs || a.endMs - b.endMs);
}

function memberRuns(member: LbGroupMember | undefined): LbGhostPoint[] {
  const runs = (member as StoredMember | undefined)?.runs;
  return Array.isArray(runs)
    ? runs
        .filter(
          (p): p is LbGhostPoint =>
            Array.isArray(p) &&
            p.length >= 2 &&
            typeof p[0] === 'number' &&
            Number.isFinite(p[0]) &&
            typeof p[1] === 'number' &&
            Number.isFinite(p[1]),
        )
        .map((p) => [Math.floor(p[0]), Math.max(0, Math.floor(p[1]))])
    : [];
}

function timeOfDaySec(ms: number): number {
  return Math.floor((((ms % DAY_MS) + DAY_MS) % DAY_MS) / 1000);
}

function makeMember(
  input: SubmitInput,
  name: string,
  points: number,
  best: number,
  runCount: number,
  lastMs: number,
  history: LbGhostPoint[],
): StoredMember {
  return {
    t: Math.max(0, Math.floor(points)),
    b: Math.max(0, Math.floor(best)),
    n: Math.max(0, Math.floor(runCount)),
    last: at(lastMs),
    name,
    look: input.look,
    ...(input.card === undefined ? {} : { card: input.card }),
    platform: input.platform,
    runs: history.slice(-LB_GHOST_RUNS),
  };
}

function rankOf(group: LbGroupDoc, uid: string, nowMs: number, hidden: boolean): number | null {
  if (hidden) return null;
  return rankToday(group, nowMs, {}).find((entry) => entry.uid === uid && !entry.ghost)?.rank ?? null;
}

async function tombstoneIn(tx: Transaction, db: Firestore, uid: string): Promise<boolean> {
  return (await tx.get(db.collection(LB_TOMB_COLLECTION).doc(uid))).exists;
}

async function tombstoneNow(db: Firestore, uid: string): Promise<boolean> {
  return (await db.collection(LB_TOMB_COLLECTION).doc(uid).get()).exists;
}

async function currentGroup(
  tx: Transaction,
  db: Firestore,
  player: LbPlayerDoc | undefined,
): Promise<{ group: LbGroupDoc | null; gid: string | null; ref: DocumentReference | null }> {
  const gid = typeof player?.groupId === 'string' && player.groupId ? player.groupId : null;
  if (gid === null) return { group: null, gid: null, ref: null };
  const ref = db.collection(LB_GROUPS_COLLECTION).doc(gid);
  const snap = await tx.get(ref);
  return { group: snap.exists ? loadGroup(snap.data()) : null, gid, ref };
}

function running(group: LbGroupDoc | null, uid: string, nowMs: number): boolean {
  return (
    group !== null &&
    group.settled !== true &&
    millis(group.end) > nowMs &&
    Array.isArray(group.memberUids) &&
    group.memberUids.includes(uid)
  );
}

function joinable(group: LbGroupDoc | null, uid: string, bracket: number, nowMs: number): boolean {
  if (group === null || group.settled === true || millis(group.end) <= nowMs) return false;
  if (group.memberUids.includes(uid)) return true;
  return (
    group.bracket === bracket &&
    group.memberUids.length < LB_GROUP_SIZE &&
    millis(group.end) - nowMs >= LB_MIN_LEFT_MS
  );
}

async function readPointer(
  tx: Transaction,
  db: Firestore,
  uid: string,
  bracket: number,
): Promise<Candidate> {
  const pointerRef = db.collection(LB_OPEN_COLLECTION).doc(openId(bracket, openShard(uid)));
  const pointerSnap = await tx.get(pointerRef);
  if (pointerSnap.exists) {
    const pointer = pointerSnap.data() as LbOpenDoc;
    if (typeof pointer.gid === 'string' && pointer.gid) {
      const ref = db.collection(LB_GROUPS_COLLECTION).doc(pointer.gid);
      const snap = await tx.get(ref);
      if (snap.exists) {
        return { group: loadGroup(snap.data()), gid: pointer.gid, ref, pointerRef, pointerUsable: true };
      }
    }
  }
  return { group: null, gid: null, ref: null, pointerRef, pointerUsable: true };
}

async function readPools(
  tx: Transaction,
  db: Firestore,
  bracket: number,
): Promise<Record<number, LbGhostDay[]>> {
  const brackets: number[] = [bracket];
  for (let distance = 1; distance <= 2; distance++) {
    if (bracket - distance >= 0) brackets.push(bracket - distance);
    if (bracket + distance <= 10) brackets.push(bracket + distance);
  }
  const pools: Record<number, LbGhostDay[]> = {};
  for (const b of brackets) {
    pools[b] = [];
    for (let shard = 0; shard < GHOST_SHARDS; shard++) {
      const snap = await tx.get(db.collection(LB_GHOST_POOL_COLLECTION).doc(ghostPoolId(b, shard)));
      if (!snap.exists) continue;
      const doc = snap.data() as LbGhostPoolDoc;
      pools[b].push(...loadGhostPool(doc));
    }
  }
  return pools;
}

function rowFromPlayer(uid: string, player: LbPlayerDoc): LbBestRow | null {
  const best = count(player.bestShadow);
  if (best <= 0 || player.hidden === true) return null;
  return {
    uid,
    best,
    bestAt: at(millis(player.bestAt)),
    name: player.name,
    look: player.look ?? DEFAULT_LOOK,
    ...(player.card === undefined ? {} : { card: player.card }),
    platform: player.platform ?? 'android',
    bracket: count(player.bracket),
  };
}

function mergeBestRows(rows: readonly LbBestRow[], extra: LbBestRow | null): LbBestRow[] {
  const byUid = new Map<string, LbBestRow>();
  for (const row of rows) {
    if (!row || typeof row.uid !== 'string') continue;
    const current = byUid.get(row.uid);
    if (
      current === undefined ||
      row.best > current.best ||
      (row.best === current.best && millis(row.bestAt) < millis(current.bestAt))
    ) {
      byUid.set(row.uid, row);
    }
  }
  if (extra !== null) {
    const current = byUid.get(extra.uid);
    if (
      current === undefined ||
      extra.best > current.best ||
      (extra.best === current.best && millis(extra.bestAt) < millis(current.bestAt))
    ) {
      byUid.set(extra.uid, extra);
    }
  }
  return [...byUid.values()].sort((a, b) => {
    if (a.best !== b.best) return b.best - a.best;
    const when = millis(a.bestAt) - millis(b.bestAt);
    return when !== 0 ? when : a.uid.localeCompare(b.uid);
  });
}

function flagDoc(uid: string, check: LbRunCheck, nowMs: number, score: number, best: number): LbFlagDoc | null {
  const anomaly = check.anomaly;
  if (!anomaly || !isObject(anomaly.signals)) return null;
  const signals: Record<string, number> = {};
  for (const [key, value] of Object.entries(anomaly.signals)) {
    if (typeof value === 'number' && Number.isFinite(value)) signals[key] = value;
  }
  if (Object.keys(signals).length === 0) return null;
  return {
    uid,
    runId: check.id,
    score: Math.max(0, Math.floor(score)),
    best: Math.max(0, Math.floor(best)),
    signals,
    ...(anomaly.soft === true ? { soft: true } : {}),
    ts: at(nowMs),
    expireAt: at(nowMs + FLAG_TTL_MS),
  };
}

async function writeFlags(db: Firestore, flags: LbFlagDoc[]): Promise<void> {
  for (const flag of flags) {
    try {
      const id = `${flag.uid}_${flag.runId}`.replace(/\//g, '_');
      const flagRef = db.collection(LB_FLAGS_COLLECTION).doc(id);
      const tombRef = db.collection(LB_TOMB_COLLECTION).doc(flag.uid);
      const written = await db.runTransaction(async (tx) => {
        // A submission that was already in flight when Delete My Data began
        // must not recreate a flag after the tombstone exists.
        if ((await tx.get(tombRef)).exists) return false;
        const snap = await tx.get(flagRef);
        if (!snap.exists) tx.set(flagRef, flag);
        return true;
      });
      if (!written) continue;
      logger.info('lbFlag', {
        uid: flag.uid,
        runId: flag.runId,
        score: flag.score,
        signals: flag.signals,
        soft: flag.soft === true,
      });
    } catch (error) {
      logger.error('lbFlag', { uid: flag.uid, runId: flag.runId, error: String(error) });
    }
  }
}

function nextRate(
  nowMs: number,
  checks: ReturnType<typeof checkLbRuns>,
  accepted: AcceptedRun[],
  state: PlayerState,
): StoredRate {
  const allIntervals = [
    ...state.intervals,
    ...accepted.map((run) => ({ id: run.id, startMs: run.startMs, endMs: run.endMs })),
  ].slice(-MAX_INTERVALS);
  const today = utcDay(nowMs);
  return {
    day: today,
    count: count(checks.dailyCounts[today]),
    runIds: [...new Set([...state.seen, ...checks.accepted])].slice(-50),
    days: checks.dailyCounts,
    intervals: allIntervals,
  };
}

function addHistogram(previous: HistogramDoc | undefined, oldScore: number, newScore: number, nowMs: number): HistogramDoc {
  const bins: Record<string, number> = {};
  if (isObject(previous?.bins)) {
    for (const [key, value] of Object.entries(previous!.bins)) {
      if (typeof value === 'number' && Number.isFinite(value) && value > 0) bins[key] = Math.floor(value);
    }
  }
  if (oldScore > 0) {
    const key = String(Math.floor(oldScore / HIST_BUCKET) * HIST_BUCKET);
    const left = (bins[key] ?? 0) - 1;
    if (left > 0) bins[key] = left;
    else delete bins[key];
  }
  if (newScore > 0) {
    const key = String(Math.floor(newScore / HIST_BUCKET) * HIST_BUCKET);
    bins[key] = (bins[key] ?? 0) + 1;
  }
  return { bins, updatedAt: at(nowMs) };
}

interface SettleOutcome {
  settled: boolean;
  gifts: number;
  ghostDays: number;
  giftsLost: number;
}

async function settleGroup(db: Firestore, gid: string, nowMs: number): Promise<SettleOutcome> {
  const groupRef = db.collection(LB_GROUPS_COLLECTION).doc(gid);
  const outcome = await db.runTransaction(async (tx) => {
    const groupSnap = await tx.get(groupRef);
    if (!groupSnap.exists) return { settled: false, gifts: 0, ghostDays: 0, giftsLost: 0 };
    const group = loadGroup(groupSnap.data());
    if (group === null) return { settled: false, gifts: 0, ghostDays: 0, giftsLost: 0 };
    if (group.settled === true || millis(group.end) > nowMs) {
      return { settled: false, gifts: 0, ghostDays: 0, giftsLost: 0 };
    }

    const playerRefs = group.memberUids.map((uid) => db.collection(LB_PLAYERS_COLLECTION).doc(uid));
    const playerSnaps = await Promise.all(playerRefs.map((ref) => tx.get(ref)));
    const players = new Map<string, LbPlayerDoc | undefined>();
    playerSnaps.forEach((snap, index) => players.set(group.memberUids[index], snap.exists ? (snap.data() as LbPlayerDoc) : undefined));
    const hidden = new Set<string>();
    for (const uid of group.memberUids) {
      const player = players.get(uid);
      if (player === undefined || player.hidden === true) hidden.add(uid);
    }

    const ranked = rankToday(group, millis(group.end), { hiddenUids: hidden, includeHidden: true });
    const awards = settlePrizeAwards(group, gid, millis(group.end), hidden);
    const giftRefs = awards.map((award) => db.collection(LB_GIFTS_COLLECTION).doc(giftId(award.uid, gid)));
    const giftSnaps = await Promise.all(giftRefs.map((ref) => tx.get(ref)));

    const day = utcDay(millis(group.start));
    const poolEntries = new Map<number, LbGhostDay[]>();
    let ghostDays = 0;
    for (const uid of group.memberUids) {
      if (hidden.has(uid)) continue;
      const member = group.members[uid];
      if (member === undefined) continue;
      const runs = memberRuns(member);
      if (runs.length === 0) continue;
      const shard = ghostShard(uid, day);
      const entries = poolEntries.get(shard) ?? [];
      entries.push({
        uid,
        day,
        runs: runs.slice(-LB_GHOST_RUNS),
        name: member.name,
        look: member.look,
        ...(member.card === undefined ? {} : { card: member.card }),
        platform: member.platform,
      });
      poolEntries.set(shard, entries);
      ghostDays++;
    }
    const poolRefsByShard = new Map<number, DocumentReference>();
    for (const shard of poolEntries.keys()) {
      poolRefsByShard.set(shard, db.collection(LB_GHOST_POOL_COLLECTION).doc(ghostPoolId(group.bracket, shard)));
    }
    const poolSnapsByShard = new Map<number, DocumentSnapshot>();
    for (const [shard, ref] of poolRefsByShard) poolSnapsByShard.set(shard, await tx.get(ref));
    let gifts = 0;

    for (let i = 0; i < awards.length; i++) {
      if (giftSnaps[i].exists) continue;
      tx.set(giftRefs[i], {
        uid: awards[i].uid,
        gid,
        tier: awards[i].tier,
        boardRank: awards[i].boardRank,
        expireAt: at(nowMs + LB_GIFT_TTL),
      } satisfies LbGiftDoc);
      gifts++;
    }

    const first = ranked[0];
    if (first !== undefined && !first.ghost && !first.hidden) {
      tx.set(
        db.collection(LB_PLAYERS_COLLECTION).doc(first.uid),
        { topBird: true, topBirdAt: at(millis(group.end)) },
        { merge: true },
      );
    }

    const cutoff = utcDay(nowMs - LB_GHOST_MAX_AGE);
    const lastDay = utcDay(millis(group.end));
    [...poolEntries.entries()].forEach(([shard, entries]) => {
      const ref = poolRefsByShard.get(shard)!;
      const poolSnap = poolSnapsByShard.get(shard)!;
      let merged = (poolSnap.exists ? (poolSnap.data() as LbGhostPoolDoc).entries : []).filter(
        (entry) => typeof entry?.day === 'string' && entry.day >= cutoff && entry.day < lastDay,
      );
      for (const entry of entries) {
        merged = merged.filter((row) => !(row.uid === entry.uid && row.day === entry.day));
        merged.unshift(storeGhostDay(entry));
      }
      merged = merged.slice(0, MAX_GHOST_ENTRIES);
      const shell = { bracket: group.bracket, shard, updatedAt: at(nowMs), entries: merged };
      while (merged.length > 1 && docSize(ref.path, shell as unknown as Record<string, unknown>) > POOL_MAX_BYTES) {
        merged.pop();
      }
      tx.set(ref, { ...shell, entries: merged } satisfies LbGhostPoolDoc);
    });

    tx.set(groupRef, storeGroup({ ...group, settled: true }));
    const lost = ranked
      .slice(0, 3)
      .filter((entry) => entry.ghost || entry.hidden).length;
    return { settled: true, gifts, ghostDays, giftsLost: lost };
  });
  if (outcome.settled) {
    logger.info('lbSettle', { gid, groups: 1, gifts: outcome.gifts,
      gifts_lost_to_ghosts: outcome.giftsLost, ghostDays: outcome.ghostDays });
  }
  return outcome;
}

async function submit(
  db: Firestore,
  uid: string,
  input: SubmitInput,
  nowMs: number,
): Promise<Omit<LbSubmitRunResult, 'gifts'> & { gifts: LbGiftDoc[] | null }> {
  const playerRef = db.collection(LB_PLAYERS_COLLECTION).doc(uid);
  const bestRef = db.collection(LB_BEST_COLLECTION).doc('global');
  const histRef = db.collection(LB_BEST_COLLECTION).doc('hist');
  const result = await db.runTransaction(async (tx) => {
    if (await tombstoneIn(tx, db, uid)) deleted();
    const playerSnap = await tx.get(playerRef);
    const bestSnap = await tx.get(bestRef);
    const histSnap = await tx.get(histRef);
    const nameSnap = await tx.get(db.collection(NAMES_COLLECTION).doc(uid));
    const player = playerSnap.exists ? (playerSnap.data() as LbPlayerDoc) : undefined;
    const bestData = bestSnap.exists ? (bestSnap.data() as LbBestDoc) : undefined;
    const state = loadPlayer(player, input);
    const name = displayName(uid, input, nameSnap.exists ? (nameSnap.data() as NameDoc) : undefined);
    const current = await currentGroup(tx, db, player);
    const isRunning = running(current.group, uid, nowMs);
    const floor = typeof bestData?.floor === 'number' && bestData.floor > 0 ? bestData.floor : null;
    const base = {
      nowMs,
      best: state.shadow,
      hist: state.hist,
      floor,
      seenIds: state.seen,
      intervals: state.intervals,
      dailyCounts: state.dailyCounts,
      hidden: state.hidden,
      bestWindowMs: LB_BEST_RAISE_MS,
    } as const;

    let checks = checkLbRuns(input.runs, {
      ...base,
      groupStartMs: isRunning ? millis(current.group!.start) : provisionalStart(input.runs, nowMs),
    });
    const potentialBest = Math.max(state.shadow, ...checks.results.map((entry) => entry.bestUpdate?.shadow ? 0 : (entry.bestUpdate?.score ?? 0)));
    const bracket = isRunning ? current.group!.bracket : bracketForVerifiedBest(potentialBest);
    const candidate: Candidate = state.hidden
      ? { group: null, gid: null, ref: null, pointerRef: null, pointerUsable: false }
      : isRunning
        ? { group: current.group, gid: current.gid, ref: current.ref, pointerRef: null, pointerUsable: false }
        : await readPointer(tx, db, uid, bracket);

    const willJoin = !state.hidden && (isRunning || joinable(candidate.group, uid, bracket, nowMs));
    if (!isRunning && willJoin && candidate.group !== null) {
      const pointerStart = millis(candidate.group.start);
      checks = checkLbRuns(input.runs, { ...base, groupStartMs: pointerStart });
    }
    const runs = acceptedRuns(input.runs, checks.results);
    const shouldJoin = !state.hidden && runs.length > 0;
    const pools = shouldJoin && !willJoin ? await readPools(tx, db, bracket) : {};

    const beforeRank = candidate.group === null ? null : rankOf(candidate.group, uid, nowMs, state.hidden);
    const lastEnd = runs.length > 0 ? Math.max(...runs.map((run) => run.endMs)) : nowMs;
    const points = runs.reduce((sum, run) => sum + run.counted, 0);
    const bestToday = runs.reduce((max, run) => Math.max(max, run.counted), 0);
    const oldMember = (willJoin ? candidate.group?.members?.[uid] : undefined) as StoredMember | undefined;
    const oldRuns = memberRuns(oldMember);
    const newRuns = runs.map((run) => [timeOfDaySec(run.endMs), run.counted] as LbGhostPoint);
    const history = [...oldRuns, ...newRuns].slice(-LB_GHOST_RUNS);
    const joined: LbJoinGroupResult | null = shouldJoin
      ? joinGroup({
          uid,
          bracket,
          nowMs,
          runStartMs: runs.length > 0 ? Math.min(...runs.map((run) => run.startMs)) : nowMs,
          member: {
            points: points,
            best: bestToday,
            runs: runs.length,
            lastMs: lastEnd,
            name,
            look: input.look,
            ...(input.card === undefined ? {} : { card: input.card }),
            platform: input.platform,
          },
          // A stale pointer (full, settled or inside its last three hours)
          // must not name the fresh group: joinGroup would reuse that id and
          // overwrite the old group document.
          group: willJoin ? candidate.group : null,
          pools,
          random: Math.random,
          gid: willJoin
            ? (candidate.gid ?? undefined)
            : freshGroupId(
                bracket,
                Math.max(nowMs - LB_OFFLINE_BACKDATE, runs.length > 0 ? Math.min(...runs.map((run) => run.startMs)) : nowMs),
                uid,
                nowMs,
              ),
        })
      : null;
    const joinedGroup = joined?.group ?? (isRunning ? current.group : null);
    let finalGroup: LbGroupDoc | null = joinedGroup;
    let finalGid: string | null = joined?.ref?.id ?? (isRunning ? current.gid : null);
    // Read the gift before any write: Firestore transactions only allow reads
    // before the first write.
    const giftSnap = finalGid === null ? null : await tx.get(db.collection(LB_GIFTS_COLLECTION).doc(giftId(uid, finalGid)));
    if (shouldJoin && joined?.group !== null && joined !== null && joinedGroup !== null && finalGid !== null) {
      finalGroup = {
        ...joinedGroup,
        memberUids: joinedGroup.memberUids.includes(uid)
          ? joinedGroup.memberUids
          : [...joinedGroup.memberUids, uid],
        members: {
          ...joinedGroup.members,
          [uid]: makeMember(
            input,
            name,
            (oldMember?.t ?? 0) + points,
            Math.max(oldMember?.b ?? 0, bestToday),
            (oldMember?.n ?? 0) + runs.length,
            lastEnd,
            history,
          ),
        },
        settled: false,
        expireAt: at(millis(joinedGroup.end) + LB_GROUP_TTL_MS),
      };
    }

    let localBest = state.best;
    let localShadow = state.shadow;
    let localShadowAt = state.bestAt;
    const flags: LbFlagDoc[] = [];
    for (const check of checks.results) {
      if (check.anomaly !== undefined && check.anomaly !== null) {
        const flag = flagDoc(uid, check, nowMs, entryScore(validatedRun(input.runs, check.id)), localShadow);
        if (flag !== null) flags.push(flag);
      }
      const update = check.bestUpdate;
      if (update === null) continue;
      if (update.score > localBest) {
        localBest = update.score;
      }
      if (!update.shadow && update.score > localShadow) {
        localShadow = update.score;
        localShadowAt = update.atMs;
      }
    }
    // Repeated hidden submissions also retry a cleanup that failed after the
    // player document was already marked hidden.
    const removePublicBest = state.hidden && (
      player?.hidden !== true ||
      (Array.isArray(bestData?.rows) && bestData.rows.some((row) => row.uid === uid))
    );
    const publicBestChanged = !state.hidden && localShadow > state.shadow;
    // Refill the top 50, including boundary ties, when a public row disappears.
    // This single-field paged query also works without an additional index.
    let replacementRows: LbBestRow[] = [];
    if (removePublicBest) {
      let cursor: DocumentSnapshot | undefined;
      while (true) {
        const query = db.collection(LB_PLAYERS_COLLECTION).orderBy('bestShadow', 'desc').limit(100);
        const page = await tx.get(cursor ? query.startAfter(cursor) : query);
        for (const doc of page.docs) {
          if (doc.id === uid) continue;
          const row = rowFromPlayer(doc.id, doc.data() as LbPlayerDoc);
          if (row !== null) replacementRows.push(row);
        }
        replacementRows = mergeBestRows(replacementRows, null);
        const last = page.docs.at(-1);
        if (page.size < 100 || (replacementRows.length >= LB_BEST_SIZE &&
          count(last?.data()?.bestShadow) < replacementRows[LB_BEST_SIZE - 1].best)) break;
        cursor = last;
      }
    }
    const nextPlayer: LbPlayerDoc = {
      ...player,
      best: localBest,
      // best may contain a private anomaly; bestAt belongs to bestShadow.
      bestAt: at(localShadowAt),
      bestShadow: localShadow,
      name,
      look: input.look,
      ...(input.card === undefined ? {} : { card: input.card }),
      platform: input.platform,
      bracket: bracketForVerifiedBest(localShadow),
      groupId: state.hidden ? null : shouldJoin ? finalGid : (player?.groupId ?? null),
      groupStart: state.hidden ? null : shouldJoin ? (finalGroup?.start ?? null) : (player?.groupStart ?? null),
      groupEnd: state.hidden ? null : shouldJoin ? (finalGroup?.end ?? null) : (player?.groupEnd ?? null),
      rate: nextRate(nowMs, checks, runs, state) as unknown as LbPlayerDoc['rate'],
      hist: [...state.hist, ...runs.map((run) => run.score)].slice(-10),
      lastRunAt: runs.length > 0 ? at(lastEnd) : (player?.lastRunAt ?? null),
      hidden: state.hidden,
      src: player?.src ?? 'play',
      expireAt: at(nowMs + LB_PLAYER_TTL),
    };
    if (playerSnap.exists || runs.length > 0 || localBest > state.best) tx.set(playerRef, nextPlayer);

    if (state.hidden && playerSnap.exists) {
      if (current.group !== null && current.ref !== null) {
        const memberUids = current.group.memberUids.filter((id) => id !== uid);
        const members = { ...current.group.members };
        delete members[uid];
        const ghosts = current.group.ghosts.filter((ghost) => ghost.uid !== uid);
        const ghostUids = current.group.ghostUids.filter((id) => id !== uid);
        tx.set(current.ref, storeGroup({ ...current.group, memberUids, members, ghosts, ghostUids }));
      }
    } else if (shouldJoin && finalGroup !== null && finalGid !== null) {
      const groupRef = db.collection(LB_GROUPS_COLLECTION).doc(finalGid);
      tx.set(groupRef, storeGroup(finalGroup));
      if (candidate.pointerRef !== null && candidate.pointerUsable) {
        tx.set(candidate.pointerRef, {
          gid: finalGid,
          bracket: finalGroup.bracket,
          updatedAt: at(nowMs),
        } satisfies LbOpenDoc);
      }
    }

    if (publicBestChanged || removePublicBest) {
      const own: LbBestRow = {
        uid,
        best: localShadow,
        bestAt: at(localShadowAt),
        name,
        look: input.look,
        ...(input.card === undefined ? {} : { card: input.card }),
        platform: input.platform,
        bracket: bracketForVerifiedBest(localShadow),
      };
      const merged = removePublicBest ? replacementRows : mergeBestRows(bestData?.rows ?? [], own);
      const rows = merged.slice(0, LB_BEST_SIZE);
      tx.set(bestRef, {
        rows,
        floor: merged.length >= LB_BEST_SIZE ? merged[LB_BEST_SIZE - 1].best : 0,
        updatedAt: at(nowMs),
      } satisfies LbBestDoc);
      tx.set(histRef, addHistogram(histSnap.exists ? (histSnap.data() as HistogramDoc) : undefined, state.shadow, removePublicBest ? 0 : localShadow, nowMs));
    }

    const board: LbBoardPayload =
      finalGroup === null || finalGid === null
        ? { tab: LB_TAB_TODAY, rows: [], me: null, floor: null, group: null, gifts: [] }
        : todayBoard(finalGroup, uid, nowMs, { gid: finalGid, hiddenUids: state.hidden ? [uid] : [] });
    const gifts = giftSnap?.exists ? [giftSnap.data() as LbGiftDoc] : [];
    board.gifts = gifts.map((g) => ({ gid: g.gid, tier: g.tier, boardRank: g.boardRank, claimedAt: g.claimedAt ?? null }));
    if (state.hidden) board.me = null;
    return {
      value: {
        accepted: checks.accepted,
        dropped: checks.dropped,
        group:
          finalGroup === null || finalGid === null
            ? null
            : { id: finalGid, end: millis(finalGroup.end), bracket: finalGroup.bracket },
        rank: { before: beforeRank, after: finalGroup === null ? null : rankOf(finalGroup, uid, nowMs, state.hidden) },
        board,
        gifts: gifts.length > 0 ? gifts : null,
      } satisfies LbSubmitRunResult,
      flags,
      publicBestChanged: publicBestChanged || removePublicBest,
      hidden: state.hidden,
      cleanupGid: typeof player?.groupId === 'string' && player.groupId ? player.groupId : null,
    };
  });
  if (result.hidden) {
    // Hidden players must disappear from every board immediately: embedded
    // ghosts in other groups and their copied day entries in all pool shards
    // are cleaned with the same idempotent routines Delete My Data uses.
    await stripGroups(db, uid, result.cleanupGid);
    await pruneGhostPools(db, uid, nowMs);
    await stripGroups(db, uid, null);
  }
  await writeFlags(db, result.flags);
  if (result.publicBestChanged) bestCache.delete(db);
  return result.value;
}

/** `lbSubmitRun` body; the callable enforces App Check and sign-in. */
export async function lbSubmitRun(
  db: Firestore,
  uid: string,
  data: unknown,
  nowMs = Date.now(),
): Promise<LbSubmitRunResult> {
  if (await tombstoneNow(db, uid)) deleted();
  const input = readInput(data);
  const playerSnap = await db.collection(LB_PLAYERS_COLLECTION).doc(uid).get();
  const player = playerSnap.exists ? (playerSnap.data() as LbPlayerDoc) : undefined;
  if (typeof player?.groupId === 'string' && player.groupId) {
    const groupRef = db.collection(LB_GROUPS_COLLECTION).doc(player.groupId);
    const groupSnap = await groupRef.get();
    if (groupSnap.exists) {
      const group = loadGroup(groupSnap.data());
      if (group !== null && group.settled !== true && millis(group.end) <= nowMs) {
        await settleGroup(db, player.groupId, nowMs);
      }
    }
  }
  return submit(db, uid, input, nowMs);
}

function emptyBoard(tab: 'today' | 'best'): LbBoardPayload {
  return { tab, rows: [], me: null, floor: null, group: null, gifts: [] };
}

interface CachedBest {
  rows: LbBestRow[];
  floor: number | null;
  at: number;
}

const bestCache = new WeakMap<Firestore, CachedBest>();

async function readBest(db: Firestore, nowMs: number): Promise<LbBestDoc | null> {
  const cached = bestCache.get(db);
  if (cached !== undefined && nowMs - cached.at < BEST_CACHE_MS) {
    return { rows: cached.rows, floor: cached.floor ?? 0, updatedAt: at(cached.at) };
  }
  const snap = await db.collection(LB_BEST_COLLECTION).doc('global').get();
  if (!snap.exists) {
    bestCache.set(db, { rows: [], floor: null, at: nowMs });
    return null;
  }
  const doc = snap.data() as LbBestDoc;
  const rows = Array.isArray(doc.rows) ? doc.rows : [];
  bestCache.set(db, { rows, floor: doc.floor ?? null, at: nowMs });
  return { ...doc, rows };
}

async function visibleCount(db: Firestore): Promise<number> {
  try {
    return (await db.collection(LB_PLAYERS_COLLECTION).where('hidden', '==', false).count().get()).data().count;
  } catch {
    return 0;
  }
}

async function histogramRank(db: Firestore, best: number): Promise<number | null> {
  const snap = await db.collection(LB_BEST_COLLECTION).doc('hist').get();
  if (!snap.exists) return null;
  const bins = (snap.data() as HistogramDoc).bins;
  if (!isObject(bins)) return null;
  const bucket = Math.floor(best / HIST_BUCKET) * HIST_BUCKET;
  let above = 0;
  let same = 0;
  for (const [key, value] of Object.entries(bins)) {
    const start = Number(key);
    if (!Number.isFinite(start) || typeof value !== 'number' || !Number.isFinite(value) || value <= 0) continue;
    if (start > bucket) above += Math.floor(value);
    else if (start === bucket) same += Math.floor(value);
  }
  return Math.max(1, above + Math.max(1, Math.ceil(same / 2)));
}

async function exactRank(db: Firestore, uid: string, best: number, bestAt: number): Promise<{ rank: number | null; approximate: boolean }> {
  if (best <= 0) return { rank: null, approximate: false };
  const total = await visibleCount(db);
  if (total >= LB_HIST_FROM) {
    return { rank: await histogramRank(db, best), approximate: true };
  }
  const col = db.collection(LB_PLAYERS_COLLECTION).where('hidden', '==', false);
  const greater = await col.where('bestShadow', '>', best).count().get();
  const equal = await col.where('bestShadow', '==', best).get();
  let ties = 0;
  for (const doc of equal.docs) {
    if (doc.id === uid) continue;
    const other = doc.data() as LbPlayerDoc;
    const otherAt = millis(other.bestAt);
    if (otherAt < bestAt || (otherAt === bestAt && doc.id.localeCompare(uid) < 0)) ties++;
  }
  return { rank: greater.data().count + 1 + ties, approximate: false };
}

async function boardBest(db: Firestore, uid: string, player: LbPlayerDoc | undefined, nowMs: number): Promise<LbBoardPayload> {
  const doc = await readBest(db, nowMs);
  const own = player === undefined ? null : rowFromPlayer(uid, player);
  const rows = mergeBestRows(doc?.rows ?? [], own);
  const hidden = player?.hidden === true ? [uid] : [];
  const payload = bestBoard(rows, uid, {
    floor: doc?.floor ?? null,
    hiddenUids: hidden,
    gid: 'global',
  });
  if (own !== null) {
    // The pinned row is the owner's own view. A hard anomaly raises the
    // private `best` but deliberately leaves `bestShadow` (and therefore all
    // public rows and the rank) on the verified score.
    const privateBest = Math.max(count(player?.best), count(player?.bestShadow));
    const exact = await exactRank(db, uid, count(player?.bestShadow), millis(player?.bestAt));
    if (exact.rank !== null) {
      payload.me = {
        rid: createHash('sha256').update(`global\u0000${uid}`).digest('hex').slice(0, 16),
        rank: exact.rank,
        name: own.name,
        look: own.look,
        ...(own.card === undefined ? {} : { card: own.card }),
        points: privateBest,
        best: privateBest,
        lastAt: millis(own.bestAt),
      };
      payload.floor = payload.floor ?? count(player?.bestShadow);
    }
    payload.approximate = exact.approximate || payload.approximate;
  }
  return payload;
}

/** `lbGetBoard` body; the callable enforces App Check and sign-in. */
export async function lbGetBoard(
  db: Firestore,
  uid: string,
  data: unknown,
  nowMs = Date.now(),
): Promise<LbGetBoardResult> {
  if (await tombstoneNow(db, uid)) deleted();
  const requested = isObject(data) ? data.tab : undefined;
  if (requested !== undefined && requested !== LB_TAB_TODAY && requested !== LB_TAB_BEST) {
    badInput('Invalid tab.');
  }
  const playerSnap = await db.collection(LB_PLAYERS_COLLECTION).doc(uid).get();
  const player = playerSnap.exists ? (playerSnap.data() as LbPlayerDoc) : undefined;
  let group: LbGroupDoc | null = null;
  let gid: string | null = null;
  if (typeof player?.groupId === 'string' && player.groupId) {
    gid = player.groupId;
    const ref = db.collection(LB_GROUPS_COLLECTION).doc(gid);
    let snap = await ref.get();
    if (snap.exists) {
      group = loadGroup(snap.data());
      if (group !== null && group.settled !== true && millis(group.end) <= nowMs) {
        await settleGroup(db, gid, nowMs);
        snap = await ref.get();
        group = snap.exists ? loadGroup(snap.data()) : null;
      }
    }
  }
  const giftsSnap = await db.collection(LB_GIFTS_COLLECTION).where('uid', '==', uid).limit(50).get();
  const gifts = giftsSnap.docs.map((doc) => doc.data() as LbGiftDoc);
  const hidden = player?.hidden === true ? [uid] : [];
  const today =
    group === null || gid === null
      ? emptyBoard(LB_TAB_TODAY)
      : todayBoard(group, uid, nowMs, { gid, hiddenUids: hidden });
  today.gifts = gifts.map((gift) => ({
    gid: gift.gid,
    tier: gift.tier,
    boardRank: gift.boardRank,
    claimedAt: gift.claimedAt ?? null,
  }));
  if (player?.hidden === true) today.me = null;
  const best = await boardBest(db, uid, player, nowMs);
  return {
    today,
    best,
    bestAllTime: best.rows.length > 0 ? best.rows[0].points : null,
  };
}

/** `lbClaimGift` body; the callable enforces App Check and sign-in. */
export async function lbClaimGift(
  db: Firestore,
  uid: string,
  data: unknown,
  nowMs = Date.now(),
): Promise<LbClaimGiftResult> {
  if (!isObject(data) || typeof data.id !== 'string' || !GIFT_ID_RE.test(data.id)) return { ok: false };
  if (await tombstoneNow(db, uid)) deleted();
  const direct = db.collection(LB_GIFTS_COLLECTION).doc(data.id);
  const owned = db.collection(LB_GIFTS_COLLECTION).doc(giftId(uid, data.id));
  const byGid = await db.collection(LB_GIFTS_COLLECTION).where('gid', '==', data.id).limit(10).get();
  const candidates = [direct, owned, ...byGid.docs.map((doc) => doc.ref)];
  const ref = await db.runTransaction(async (tx) => {
    if (await tombstoneIn(tx, db, uid)) deleted();
    for (const candidate of candidates) {
      const snap = await tx.get(candidate);
      if (snap.exists && (snap.data() as LbGiftDoc).uid === uid) return candidate;
    }
    return null;
  });
  if (ref === null) return { ok: false };
  return db.runTransaction(async (tx) => {
    if (await tombstoneIn(tx, db, uid)) deleted();
    const snap = await tx.get(ref);
    if (!snap.exists || (snap.data() as LbGiftDoc).uid !== uid) return { ok: false };
    const gift = snap.data() as LbGiftDoc;
    if (gift.rolled !== undefined) return { ok: true, id: ref.id, tier: gift.tier, prize: gift.rolled };
    const seed = String(randomInt(1, 0x7fffffff));
    const prize = rollGift(gift.tier, { random: seededRandom(Number(seed)), seed, shopItems: GIFT_SHOP_ITEMS });
    tx.update(ref, { rolled: prize, claimedAt: at(nowMs) });
    return { ok: true, id: ref.id, tier: gift.tier, prize };
  });
}

/** Scheduled `lbSettleGroups` body; lazy reads call the same routine. */
export async function lbSettleGroups(
  db: Firestore,
  nowMs = Date.now(),
  onlyGid?: string,
): Promise<LbSettleResult> {
  const ids =
    onlyGid !== undefined
      ? [onlyGid]
      : (
          await db
            .collection(LB_GROUPS_COLLECTION)
            .where('settled', '==', false)
            .where('end', '<=', at(nowMs))
            .orderBy('end')
            .limit(100)
            .get()
        ).docs.map((doc) => doc.id);
  let groups = 0;
  let gifts = 0;
  let ghostDays = 0;
  for (const gid of ids) {
    const result = await settleGroup(db, gid, nowMs);
    if (!result.settled) continue;
    groups++;
    gifts += result.gifts;
    ghostDays += result.ghostDays;
  }
  return { groups, gifts, ghostDays };
}
