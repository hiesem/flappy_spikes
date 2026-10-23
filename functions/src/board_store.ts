/**
 * PRD-2.6 LB3 own leaderboard: Firestore-facing stubs.
 *
 * Wave 0 only installs the stable callable surface. The board work packages
 * replace these bodies (submit / join / settle / read / claim) without
 * touching the exports in `index.ts`.
 */
import type { Firestore } from 'firebase-admin/firestore';
import type {
  LbClaimGiftResult,
  LbGetBoardResult,
  LbSettleResult,
  LbSubmitRunResult,
} from './board.js';

/** `lbSubmitRun` body; the callable enforces App Check and sign-in. */
export async function lbSubmitRun(
  _db: Firestore,
  _uid: string,
  _data: unknown,
  _nowMs = Date.now(),
): Promise<LbSubmitRunResult> {
  return { accepted: [], dropped: [], group: null, rank: null, board: null, gifts: null };
}

/** `lbGetBoard` body; the callable enforces App Check and sign-in. */
export async function lbGetBoard(
  _db: Firestore,
  _uid: string,
  _data: unknown,
  _nowMs = Date.now(),
): Promise<LbGetBoardResult> {
  const empty = { tab: 'today' as const, rows: [], me: null, floor: null, group: null, gifts: [] };
  return { today: empty, best: { ...empty, tab: 'best' }, bestAllTime: null };
}

/** `lbClaimGift` body; the callable enforces App Check and sign-in. */
export async function lbClaimGift(
  _db: Firestore,
  _uid: string,
  _data: unknown,
  _nowMs = Date.now(),
): Promise<LbClaimGiftResult> {
  return { ok: false };
}

/** Scheduled `lbSettleGroups` body; idempotent in the real implementation. */
export async function lbSettleGroups(_db: Firestore, _nowMs = Date.now()): Promise<LbSettleResult> {
  return { groups: 0, gifts: 0, ghostDays: 0 };
}
