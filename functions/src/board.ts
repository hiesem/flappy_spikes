/**
 * PRD-2.6 LB3 own leaderboard: pure request / response shapes shared by the
 * callables and the Firestore store. No Firestore access belongs here.
 *
 * The wave-0 implementation lives in `board_store.ts`; the later board work
 * packages can replace that module without changing `index.ts`.
 */
import type { LbGiftDoc, LbGiftRoll, LbGiftTier, LbGroupDoc, Look } from './schema.js';

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
