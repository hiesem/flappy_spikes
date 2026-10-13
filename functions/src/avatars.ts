/** PRD-2.3 §21.3 the versus pictures in Firebase Storage. */

/** The Storage path of a player's picture (mirrors `VersusConfig.avatarPath`). */
export function avatarPath(uid: string): string {
  return `avatars/${uid}.jpg`;
}

/**
 * The project's default Storage bucket: `FIREBASE_CONFIG.storageBucket` when
 * the runtime provides it, else `<project>.firebasestorage.app` (the default
 * bucket name of projects since 2024-10; the emulator accepts any name).
 */
export function avatarBucketName(): string {
  try {
    const cfg = JSON.parse(process.env.FIREBASE_CONFIG ?? '{}') as { storageBucket?: string; projectId?: string };
    if (cfg.storageBucket) return cfg.storageBucket;
    const project = cfg.projectId ?? process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? '';
    if (project) return `${project}.firebasestorage.app`;
  } catch {
    // fall through
  }
  const project = process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? 'demo-flappy-spikes';
  return `${project}.firebasestorage.app`;
}
