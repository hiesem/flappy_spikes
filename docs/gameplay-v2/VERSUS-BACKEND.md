# Versus backend runbook (PRD-2 §3.13, ARCH §6)

Firebase project **`flappy-spikes-a2b55`** (Blaze), Firestore `(default)` in **eur3**, Cloud Functions 2nd gen in
**`europe-west1`** (one of the eur3 regions), Node 22. Everything below is run from `flappy_spikes/` (the repo root).

## 1. What is in the repo

| Path | What |
|---|---|
| `firebase.json` | `firestore` (rules, indexes, eur3), `functions` (source `functions/`, nodejs22, build on predeploy), `emulators` (auth 9099, firestore 8080, functions 5001, hub 4400, logging 4500, eventarc 9299, UI off) |
| `.firebaserc` | default project `flappy-spikes-a2b55` |
| `firestore.rules` | `players/{uid}` owner-only with shape/size checks; `pools/*` read-only for signed-in users; everything else denied |
| `firestore.indexes.json` | no composite indexes; TTL + index exemption on `players.expireAt`; index exemptions on `players.bestRun`, `players.recent`, `pools.entries` (large nested values, never queried) |
| `functions/src/index.ts` | `onPlayerRunWrite` (Firestore trigger), `deleteMyData` (callable, App Check enforced), `sweepPools` (daily) |
| `functions/src/pools.ts` | pool logic (validate, rate, shard write, trims, delete) |
| `functions/src/timeline.ts` | timeline codec + cheat filter; `scoreAt` replay reference |
| `functions/src/matching.ts` | reference matcher + pool read plan for the Dart client (not called by the functions) |
| `functions/src/levels.ts` | level thresholds (must equal `lib/levels/levels.dart`; a test compares) |
| `functions/scripts/set_ttl.sh` | TTL policy via the Firestore Admin REST API |
| `functions/scripts/test.sh` | `npm test`: build + type-check + mocha inside the emulators |
| `test/fixtures/versus_matching.json` | matching cases shared with the Dart matcher test (WP-5b) |

Data model and the client write contract: ARCH §6.1 (one new run per write; timeline v2 since PRD-2.2 §13.5: entry values sum to the score, bonus / gift / ride / train entries gap-exempt).

## 2. Test locally (emulators)

```bash
cd functions && npm ci && cd ..
npm --prefix functions test          # tsc build + type-check + 77 mocha tests in the Emulator Suite
npm --prefix functions run build     # tsc only
```

`npm test` starts `firebase emulators:exec --project demo-flappy-spikes --only auth,firestore,functions` (a `demo-`
project never reaches real resources). Inside an already running emulator session (`FIRESTORE_EMULATOR_HOST` set) it
runs mocha directly. Needs Java ≥ 11 for the Firestore emulator (system Java or `~/opt/jdk-17*`). The local Node may be
newer than 22; the emulator only warns.

## 3. Deploy (the orchestrator / owner runs this; builders never deploy)

```bash
firebase login                       # once, as the project owner
cd functions && npm ci && cd ..
# check first: compiles the rules, builds and packages the functions, deploys nothing
firebase deploy --only firestore:rules,firestore:indexes,functions --project flappy-spikes-a2b55 --dry-run
# deploy
firebase deploy --only firestore:rules,firestore:indexes,functions --project flappy-spikes-a2b55
```

- The first functions deploy grants the Pub/Sub, Eventarc and compute service accounts their roles (the CLI says which).
- Rules only: `firebase deploy --only firestore:rules --project flappy-spikes-a2b55`.
- One function: `firebase deploy --only functions:onPlayerRunWrite --project flappy-spikes-a2b55`.
- The dry run of 2026-10-08 (WP-5a) already **enabled** `cloudscheduler.googleapis.com` and
  `firebaseextensions.googleapis.com` and created the Pub/Sub and Eventarc service identities (the CLI's dry run does
  this); nothing else was changed.
- Logs: `firebase functions:log --project flappy-spikes-a2b55` (every accept / reject is logged with its reason).

## 3a. PRD-2.6 WP-LB wave-0 deploy, import and cleanup

The own-leaderboard release adds nine server-only `lb*` collections and three callables. It ships **before any 2.6 app build reaches a device** (PRD-2.6 §4 wave 0, C8). 2.5 clients never call the new surface, so the deploy is backward compatible.

**Wave-0 order (owner / orchestrator only; builders never deploy):**

1. Deploy `firestore.indexes.json` and wait until the new composite indexes (`lbGroups`, `lbPlayers`) are **built**.
2. Deploy the rules (the LB3 note is comment-only; every `lb*` collection stays denied).
3. Deploy the functions together with the E4 / F9 / G4 / E6 changes (`lbSubmitRun`, `lbGetBoard`, `lbClaimGift`, `lbSettleGroups`).
4. Enable the TTL policies (`functions/scripts/set_ttl.sh enable`, or `firebase deploy --only firestore:indexes`).
5. With the owner's explicit OK on the day (C8), run the one-time import. Do it promptly: old `players` documents expire 60 days after their last write, while `lbPlayers` rows get a fresh 400-day TTL.

```bash
# Auth once with an owner account: gcloud auth application-default login
npx --prefix functions tsx functions/scripts/lb_import.ts   --project flappy-spikes-a2b55 --keep <hiesem-uid>,<hiesemie-uid>,<tester-uid>

# Preview first if desired; this variant writes nothing:
npx --prefix functions tsx functions/scripts/lb_import.ts   --project flappy-spikes-a2b55 --keep <uids> --dry-run
```

`lb_import.ts` never trusts the client-written `players/{uid}.best`. It imports the verified `bestRun` when `checkRun` accepts it; otherwise it takes the highest verified `recent[]` run; otherwise it skips the player. It writes `lbPlayers/{uid}` (`src: 'import'`, `expireAt` now + 400 days), rebuilds `lbBest/global` and writes `lbMeta/import` (`ranAt`, `count`, `keepUids`). A rerun updates imported rows but preserves any row already owned by live play (`src: 'play'`), and clears an earlier `cleanedAt` because that gate must be run again.

**Release-blocking cleanup (C9, before production — not needed for internal / closed testing):**

```bash
# 1. DRY RUN (default): review every deletion and the remaining top 50.
npx --prefix functions tsx functions/scripts/lb_cleanup_test.ts   --project flappy-spikes-a2b55 --keep <hiesem-uid>,<hiesemie-uid>,<tester-uids>

# 2. Apply exactly that plan, then confirm lbMeta/import.cleanedAt in the console.
npx --prefix functions tsx functions/scripts/lb_cleanup_test.ts   --project flappy-spikes-a2b55 --keep <hiesem-uid>,<hiesemie-uid>,<tester-uids> --apply
```

The cleanup deletes every **imported** `lbPlayers` row not on the keep-list, plus its `lbGifts`, ghost-pool entries and member/ghost rows in `lbGroups`; it rebuilds `lbBest/global`, sets `lbMeta/import.cleanedAt`, and prints the remaining top 50. It touches only the new `lb*` collections and never the versus `pools` (O7), `players` or other versus data. Rows created by live play are never deleted. Both scripts **require an explicit `--project`** and never fall back to a default project; the import runs unless `--dry-run` is passed, while the cleanup writes nothing unless `--apply` is passed.

## 4. TTL policy (60 days)

Firestore TTL deletes whole documents only, so the policy is on **`players.expireAt`** (the client writes now + 60 d on
every write; inactive players disappear 60 d after their last write). Pool entries and `recent` runs older than 60 d
are trimmed by `onPlayerRunWrite` on every write and by the daily `sweepPools`.

- `firebase deploy --only firestore:indexes` applies it (the `"ttl": true` field override).
- Or directly: `ACCESS_TOKEN=$(gcloud auth print-access-token) functions/scripts/set_ttl.sh enable`
  (`status` to check — `ttlConfig.state` goes `CREATING` → `ACTIVE` within minutes; `disable` to remove).
- Deletion happens within ~24 h after `expireAt`; TTL deletes count as document deletes on the bill and do **not**
  fire a function cleanup of pool entries (they age out of the pools on their own).

## 5. App Check (enforced)

- **Firestore:** Firebase console → App Check → APIs → Cloud Firestore → **Enforce** (after the 5b client sends tokens:
  check the "verified requests" metric first, or every unverified client goes solo).
- **Functions:** `deleteMyData` has `enforceAppCheck: true` in code (no console step). `onPlayerRunWrite` and
  `sweepPools` are not client-callable; the client write that triggers `onPlayerRunWrite` is covered by Firestore
  enforcement.
- **Android:** register the app with **Play Integrity** (App Check → Apps); add the Play-signing and upload SHA-256
  certificate fingerprints in the Firebase project settings.
- **Debug / e2e:** App Check → Apps → Manage debug tokens; pass the token with
  `--dart-define=FS_APPCHECK_DEBUG_TOKEN=…` (ARCH §6.5). Release builds never use the debug provider.
- **iOS (later):** App Attest with DeviceCheck fallback; rules and functions need no change.

## 6. Wipe test data

Production data is shared by every player: wipe only before launch or with the owner's go.

```bash
P=flappy-spikes-a2b55
firebase firestore:delete pools      --recursive --force --project $P
firebase firestore:delete versusRate --recursive --force --project $P
firebase firestore:delete players    --recursive --force --project $P
```

- A single tester: call **Delete my data** in the app (the `deleteMyData` callable), or delete `players/{uid}` and
  `versusRate/{uid}` in the console; their pool entries age out in 60 d or vanish on the next wipe.
- Anonymous test accounts: Firebase console → Authentication → Users (filter "anonymous", delete). Auth users are free.
- Emulator data never persists (no `--import/--export-on-exit` is configured).

## 7. Costs (Blaze, €5/month budget alert)

Billing account "Duo Leads" (EUR), Blaze, budget **€5/month with alerts only** (recorded as set up on 2026-10-08;
no spend cap). Expected at ≈ 5 000 daily players (§3.13):

| Item | Per day | Free tier | Expected cost |
|---|---|---|---|
| Firestore reads (one pool doc per session + profile) | ≈ 8 000 | 50 000/day | 0 |
| Firestore writes (player doc + pool + rate doc per accepted run) | ≈ 30–40 000 | 20 000/day | ≈ €0.02–0.04/day |
| Storage (44 pool docs ≤ 900 KB + player docs) | < 100 MB | 1 GB | 0 |
| Function invocations (`onPlayerRunWrite`, the daily sweep) | ≈ 15 000 | 2 M/month | 0 |
| Cloud Scheduler (1 job) | — | 3 jobs/month free | 0 |

Total ≈ **€0–1/month**. Guard rails: every function runs with `maxInstances: 10` and 256 MiB; rejected runs never
write a pool; the 3-a-day rate is enforced on the server. If a bill ever spikes: `firebase functions:delete
onPlayerRunWrite --region europe-west1 --project flappy-spikes-a2b55` stops all pool writes (the game falls back to
solo / old pools) without touching the app.

## 8. Privacy (Delete my data)

`deleteMyData` (callable, region `europe-west1`) removes `players/{uid}`, `versusRate/{uid}`, the caller's entries in
all 44 pool shards and the Firebase Auth user; it is idempotent. The client (4c/5b) also resets the Analytics ID,
regenerates the nickname and clears the upload queue. Data-safety answers: SUBMISSION.md (4c).

## PRD-2.2 §13.5 timeline v2 rollout (orchestrator, after the merge and the tests)

1. Deploy the functions: `cd functions && npm run build && firebase deploy --only functions --project flappy-spikes-a2b55`.
2. Convert the 2.1 pool runs (idempotent, logs the counts; DONE — the script was removed in audit 17, see git history):
   `cd functions && GCLOUD_PROJECT=flappy-spikes-a2b55 npx tsx scripts/convert_pools_v2.ts --dry-run`, then without `--dry-run`
   (needs `gcloud auth application-default login` with an owner account).
3. Live round trip from the Pixel 8 (debug build, App Check debug token):
   `flutter test integration_test/release_e2e_test.dart -d <PIXEL8_SERIAL> --dart-define=FS_E2E=true --dart-define=FS_LIVE_VERSUS=true --dart-define=FS_APPCHECK_DEBUG_TOKEN=<token>`
   (uploads a v2 run and replays every run in the level 0–2 pools, converted ones included).
4. Seed ~5 real 2.2 runs from the test account:
   `flutter test integration_test/seed_versus_runs_test.dart -d <PIXEL8_SERIAL> --dart-define=FS_SEED_VERSUS=true --dart-define=FS_APPCHECK_DEBUG_TOKEN=<token>`.
