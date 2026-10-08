/**
 * Firestore storage-size estimate (https://firebase.google.com/docs/firestore/storage-size),
 * used for the 900 KB pool cap (ARCH §6.1).
 */
import { Timestamp } from 'firebase-admin/firestore';

export function valueSize(v: unknown): number {
  if (v === null || v === undefined) return 1;
  if (typeof v === 'boolean') return 1;
  if (typeof v === 'number') return 8;
  if (typeof v === 'string') return Buffer.byteLength(v, 'utf8') + 1;
  if (v instanceof Timestamp || v instanceof Date) return 8;
  if (Array.isArray(v)) return v.reduce((s: number, x) => s + valueSize(x), 0);
  if (typeof v === 'object') {
    // Sentinels (FieldValue) count as 8: they only appear in top-level writes.
    if ((v as { constructor?: { name?: string } }).constructor?.name?.includes('FieldValue')) return 8;
    let s = 0;
    for (const [k, x] of Object.entries(v as Record<string, unknown>)) {
      s += Buffer.byteLength(k, 'utf8') + 1 + valueSize(x);
    }
    return s;
  }
  return 8;
}

/** Size of a document at [path] with [data]. */
export function docSize(path: string, data: Record<string, unknown>): number {
  const name = path.split('/').reduce((s, p) => s + Buffer.byteLength(p, 'utf8') + 1, 0) + 16;
  return name + valueSize(data) + 32;
}
