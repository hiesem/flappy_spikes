/** Shared emulator-test helpers (ARCH §7.2). Run under `firebase emulators:exec`. */
import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { encodeDeltas, encodeFlags } from '../src/timeline.js';
import type { Look, PlayerDoc, RunEntry } from '../src/schema.js';

export const PROJECT = process.env.GCLOUD_PROJECT ?? 'demo-flappy-spikes';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error('Run the tests through `npm test` (firebase emulators:exec); FIRESTORE_EMULATOR_HOST is not set.');
}

if (getApps().length === 0) initializeApp({ projectId: PROJECT });
export const db = getFirestore();
export const auth = getAuth();

export const DAY = 24 * 3600 * 1000;

export const LOOK: Look = { bird: 'classic', gear: 'none', hat: 'none', hoop: 'classic', trail: 'none' };

let counter = 0;
export function uniq(prefix: string): string {
  counter++;
  return `${prefix}-${Date.now().toString(36)}-${counter}-${Math.floor(Math.random() * 1e6)}`;
}

export interface RunOpts {
  runId?: string;
  score?: number;
  best?: number;
  deltas?: number[];
  flags?: number[];
  tsMs?: number;
  name?: string;
  platform?: 'android' | 'ios';
  end?: number;
}

/** A plain plausible run: one point per score, 1.2 s apart, no flags. */
export function makeRun(o: RunOpts = {}): RunEntry {
  const score = o.score ?? 12;
  const deltas = o.deltas ?? Array.from({ length: score }, () => 120);
  const flags = o.flags ?? deltas.map(() => 0);
  return {
    runId: o.runId ?? uniq('run'),
    score,
    best: o.best ?? score,
    ts: Timestamp.fromMillis(o.tsMs ?? Date.now()),
    name: o.name ?? 'SwiftKiwi482',
    avatar: '',
    look: LOOK,
    platform: o.platform ?? 'android',
    tl: encodeDeltas(deltas),
    end: o.end ?? 80,
    fl: encodeFlags(flags),
  };
}

export function makePlayer(o: { best: number; bestRun?: RunEntry | null; recent?: RunEntry[] }): PlayerDoc {
  const now = Date.now();
  return {
    name: 'SwiftKiwi482',
    avatar: '',
    platform: 'android',
    look: LOOK,
    best: o.best,
    level: 0,
    bestRun: o.bestRun ?? null,
    recent: o.recent ?? [],
    uploads: { day: '', count: 0 },
    updatedAt: Timestamp.fromMillis(now),
    expireAt: Timestamp.fromMillis(now + 60 * DAY),
  };
}

export async function poolEntries(pid: string) {
  const snap = await db.collection('pools').doc(pid).get();
  return (snap.data()?.entries ?? []) as Array<Record<string, any>>;
}

export async function waitFor<T>(fn: () => Promise<T | undefined | null | false>, timeoutMs = 20000): Promise<T> {
  const t0 = Date.now();
  for (;;) {
    const v = await fn();
    if (v) return v as T;
    if (Date.now() - t0 > timeoutMs) throw new Error('waitFor timed out');
    await new Promise((r) => setTimeout(r, 150));
  }
}

/** Unsigned JWT; the functions emulator decodes tokens without verifying them. */
export function fakeJwt(payload: Record<string, unknown>): string {
  const b = (o: unknown) => Buffer.from(JSON.stringify(o)).toString('base64url');
  return `${b({ alg: 'none', typ: 'JWT' })}.${b(payload)}.`;
}
