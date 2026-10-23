/**
 * PRD-2.6 LB3 hooks shared by Delete My Data and the name callables.
 *
 * Wave-0 stubs: they install the call sites now so the board work packages
 * can complete the cleanup / name propagation without editing the versus hot
 * spots again.
 */
import type { Firestore } from 'firebase-admin/firestore';

/** Remove every server-side lb trace of [uid], then leave a short tombstone. */
export async function deleteBoardData(_db: Firestore, _uid: string, _nowMs = Date.now()): Promise<void> {}

/** Refresh the server-derived display name on [uid]'s leaderboard data. */
export async function lbSyncName(
  _db: Firestore,
  _uid: string,
  _name: string,
  _nowMs = Date.now(),
): Promise<void> {}
