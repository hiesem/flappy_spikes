# PRD-2.3.1 device QA — Pixel 6

2026-10-14, GPT-6.1 Sol. Branch `p231-qadev`, baseline `39ef4d1`.
Pixel 6 `<PIXEL6_SERIAL>`, Android 17, 1080 × 2400.

**Result: gameplay checks passed; signed-in acceptance is blocked by D-01.**
No confirmed production-code defect was found. This is not a complete sign-off
for the Play Games account switch or native achievement reporting.

Tested the installed **Play internal-testing 2.3.1 (20)** first
(`installerPackageName=com.android.vending`), then a debug build of the same
source with `FS_TUNING=true` and Google test ad IDs. No `FS_E2E` fake ads.
Debug setup/telemetry came from a temporary wrapper around the real `app.main()`;
its source is retained with the external evidence and removed from the worktree.
No production code or existing tests were changed.

External evidence prefix **E**:
`/home/killerhis/Projects/flappyspikes/.worktrees/briefs9/evidence/device/`.
Ten key PNGs are copied into [device/](device/); other PNGs, JSON snapshots,
recordings and logs remain outside git. Every copied PNG was visually inspected.

## Acceptance table

| Check | Result | Observation and evidence |
|---|---|---|
| Initial No Ads state | PASS | First launch already showed `No Ads: off`; the launch purchase sync returned zero purchases. No initial entitlement toggle needed. `E/02-noads-state.png`, `E/03-cleardata-launch.log`. Ads were wanted: a Play banner subsequently displayed. |
| §4.1 Play installation | PASS | 2.3.1, versionCode 20, Play installer verified before testing. `E/00-initial.png`. |
| §4.2–3 clear data, signed-in switch, fresh Firebase sign-in | BLOCKED | Data cleared and launch completed, but Play Games was not authenticated. Medal sign-in opened profile creation; cancelled under the account/settings restriction. No `link switched` occurred. Read-only Auth lookup: `<FIREBASE_TEST_UID>`, last sign-in `2026-10-13T11:52:44.875Z`, unchanged. `E/03-auth-after.json`, `E/04-medal-wait.png`, `E/05-versus.log`. D-01. |
| §4.4 rival and own name | PARTIAL | Play guest VERSUS START found `E2E bot`; own name was guest `SwiftParrot278`. No `rules` solo. The Play Games-name requirement remains blocked. `E/05-versus.mp4`, [waiting](device/play-waiting.png). |
| §4.5 relaunch without deletion/new guest | BLOCKED | Guest relaunch again found the rival and retained the guest display name, but the required post-switch server/account assertions cannot be certified without the switch. `E/07-relaunch.log`, `E/07-hint-repeat.mp4`. |
| §4.6 network cut during switch / guest fallback / next-launch switch | SKIPPED | No authenticated Play Games switch could be initiated. Network settings were left unchanged. D-01. |
| §5 Shop rewarded 75 | PASS — DEBUG | Row `FREE +75`; Google test rewarded completion credited wallet **0 → 75**, and the pill counted up. Cooldown then displayed. Only close controls used on the test ad's automatic store sheets; no install/advertiser CTA pressed. `E/12-shop75-before.json`, `E/13-google-test-rewarded.png`, `E/14-shop75-after.json`, [75 coins](device/shop75.png). |
| §6 Bullseye +3 | PASS — DEBUG | Forced Bullseye crossed at −10.45 pt; `BULLSEYE! +3 coins` displayed. Perfect pass plus bonus gave score **5**; the subsequent Star Trail added its separate reward. `E/16-bullseye.mp4`, `E/16-bullseye.log`, [banner](device/bullseye.png). |
| §7 six-ring rides | PASS — DEBUG | Fresh forced Cannon completed with **6 passes**, entry plus five ride rings. Volcano and Space also completed. `E/20-cannon-ended.json`, `E/20-cannon.log`, `E/33-volcano-ended.json`, `E/33-space-ended.json`. Ride geometry and ring passages visually checked. |
| §8 no GRAZE text | PASS — DEBUG | Five perfect debug passes built ×5; a real rim overlap produced `RimTouched`, streak reset to **0**, fire off, and no GRAZE notice. Existing feedback remained. `E/27-graze-no-text.png`, `E/27-graze-no-text.json`, `E/27-graze.log`. |
| §9 heart without grey panel | PASS | Dotted empty heart floats directly over normal stage, Big Hoops and ride backgrounds. `E/26-big-hoops-heart.png`, `E/31-space-hidden.png`, [normal](device/play-waiting.png), [ride](device/cannon-hidden.png). |
| §10 repeat instructions until hoop 0 | PASS — PLAY | Cleared data; first tap without more flaps died with score 0. Relaunched: full veil, red warning bands, path and hand returned. A later run passed hoop 0 (score 1); the following run had only the ordinary reminder. `E/06-died-before-hoop0.png`, `E/08-after-hoop0.png`, `E/09-reminder-only.mp4`; rechecked FREE FLY after restore (hoop 0 score 2, then reminder alone): `E/50-restored-pass-hoop0.png`, `E/51-reminder-long-wait.png`, [repeat](device/instructions-repeat.png), [after pass](device/reminder.png). |
| §11 waiting banner | PASS — PLAY + DEBUG | Real banner displayed after VS intro and before any flight tap; observed only. Debug FREE FLY also displayed the labelled Google test banner while waiting. No banner on the VS intro in the recording. `E/05-versus.mp4`, `E/15-debug-waiting.json`, [Play waiting](device/play-waiting.png). |
| §12.10.1 normal unlocks / results toasts | PASS LOCAL — DEBUG | A run with **no force, internal bot, god mode or start-index override** passed **12 hoops**, scored **17** and remained `countsForAchievements=true`. ADB taps controlled flight. The naturally rolled Big Hoops was taken with the temporary No Ads entitlement. BIG DEAL, STARLING, FIRST FLIGHT and EGG unlocked locally; queued results toasts showed one at a time, including FIRST FLIGHT and EGG. `E/36-normal-eligible.json`, `E/36-normal-progress.json`, `E/37-normal-achievements.json`, `E/37-achievements.mp4`, [FIRST FLIGHT](device/achievement-toast.png), `E/37-egg-toast.png`. |
| §12.10.1 Home medal / native list / platform popup | PARTIAL | Home medal exists without overlap and its tap invokes Play Games sign-in. Native unlocked list and platform popup blocked by the profile-creation prompt. Locally unlocked keys stayed unreported, as expected while signed out. `E/38-home-medal.png`, `E/04-medal-wait.png`, `E/37-normal-achievements.json`. D-01. |
| §12.10.2 signed-out unlock then sign-in sync | SKIPPED | No Play Games account/settings changes allowed; native sign-in prerequisite unavailable. D-01. |
| §12.10.3 forced run exclusion | PASS — DEBUG | Completed forced rides, FEVER, score/rank thresholds and a two-portal god-mode run left `achUnlocked=[]`. Local unlocks appeared only after the later eligible run. `E/20-cannon-ended.json`, `E/34-portal-cap.json`, `E/37-normal-achievements.json`. A natural ride's native unlock remains blocked by D-01. |
| §13 shield hidden with bird | PASS — DEBUG | Field Shield catch exercised first. Isolated starter-shield Cannon, Volcano and Space runs: hidden bird opacity **0**, shield active, `shieldPaints=false`; after reappearance opacity **1**, shield active, `shieldPaints=true`. PNGs inspected. `E/17-shield-caught.json`, `E/18-cannon-hidden.json`, `E/19-cannon-visible.json`, `E/31-volcano-hidden.json`, `E/32-volcano-visible.json`, `E/31-space-hidden.json`, `E/32-space-visible.json`, [barrel](device/cannon-hidden.png), [after shot](device/cannon-visible.png). |
| §14 No Ads revive / ad offer | PASS — DEBUG | After six Cannon passes, No Ads first offer **250**, no FREE or NO AD AVAILABLE label. Payment deducted exactly **250**; next offer **500**. UI No Ads off row restored the entitlement; a new non-owner run offered the rewarded heart. `E/21-noads-revive250.json`, `E/21-noads-paid250.json`, `E/22-noads-revive500.png`, `E/23-noads-off.json`, `E/24-nonowner-ad-offer.png`, [250](device/revive250.png). |
| §15 off-centre rim-free FEVER | PASS — DEBUG | Controlled crossing **19.375 pt** off centre at hoop 6, outside its normal ±18 pt band: `perfect=true`, `rim=false`, **2 coins/points**, fire on, streak **5**. [FEVER](device/fever.png), `E/25-fever.log`, `E/25-fever-offcentre.json`. |
| §16 comet layout | PASS — DEBUG | Forced at hoops **10 / 50 / 150**: **5 / 6 / 6** passes including entry; locked stations spaced **614.267 / 548.485 / 597.743 pt**, respectively, equal within each run. Each run passed the first normal hoop after control returned. `E/28-comet{1,2,3}-start.json`, `E/29-comet{1,2,3}-end.json`, `E/30-comet{1,2,3}-recovered.json`, matching PNGs and logs. |
| §17 at most two portals | PASS — DEBUG | In one run, Volcano and Space placed/completed. A further forced Storm was discarded; after four further passes `portalCount` remained **2**, with no Storm ride. `E/33-space-ended.json`, `E/34-portal-cap.json`, `E/34-portal-cap.log`. |
| Finish on Play (20) | PASS | Final package is **2.3.1 / versionCode 20 / com.android.vending**. Plain market reinstall first delivered public (2); the already-enrolled tester session's “Download test app” link exposed the internal update, which was installed. No account/settings changes. `E/44-test-download-link.png`, `E/45-restored-version.txt`, `E/47-restored-home.png`. |

## Finding D-01

**Blocker — acceptance prerequisite / device setup; PRD §4 and §12.10.**

Repro: on the Play-installed version 20, clear app data, launch, then tap the
Home medal. The native sheet says **“Een Play Games-profiel maken”** (create a
Play Games profile) and **“Geen profiel”** (no profile) for the default account.
The sign-in attempt logged `pgs_error op=sign_in code=timeout`.

Expected for this acceptance session: the owner's existing Play Games profile
is authenticated, enabling the account collision/switch and the native list.
Actual: profile creation is requested; no authenticated player or switch is
available. The existing target Firebase account's last sign-in remains old.
Evidence: `E/04-medal-wait.png`, `E/05-versus.log`, `E/03-auth-after.json`.

Rechecked after restoring Play (20): the same profile prompt and sign-in timeout
returned (`E/48-restored-pgs-check.png`, `E/48-restored-pgs-check.log`).
Cancelled the sheet. Did not create a profile, choose another account or change
Play Games settings. This is an observed device/setup blocker, **not a confirmed
regression in the switch implementation**. The corresponding rows remain
blocked/skipped; unit coverage is not substituted for signed-in device proof.

## Calls and limits

- Pixel 6 replaced the PRD's Pixel 8, as explicitly requested. Sound feel was
  not assessed: media volume stayed 0 (`E/media-volume-readonly.txt`).
- Play runs used no real rewarded/interstitial videos. To avoid an automatic
  interstitial on NEXT, Play relaunches used force-stop/start. Debug scene
  resets used the existing `replay()` API; native ad checks used Google test IDs.
- The No Ads debug row only turns ownership **off**. The temporary QA wrapper
  used `menu.setNoAds(true)` for owner-state tests; the UI off row restored it
  afterwards. No purchases or account/order changes were made.
- Forced feature checks used the existing force/slot/debug-pass APIs. FEVER
  offset and rim-contact setup positioned the bird, then let the actual collision
  and pass code judge the next frame; those runs were explicitly debug-excluded.
  Starter Shields isolated each ride after an actual field Shield catch.
- Signed-in switch, mid-switch outage/retry, native achievement list/reporting,
  signed-out-to-signed-in sync and a natural ride's platform unlock are outstanding
  because of D-01 and the no-account/settings-change rule. No network toggle was
  performed without an available switch to interrupt.
- The two-portal cap was exercised by forcing a third portal; no 170-hoop device
  soak or device revive-between-portals check was needed for that observation.
  Those additional planner/revive cases retain automated coverage.
- Test rewarded ads opened advertiser store sheets automatically; only their
  close controls were used. No ad creative, install button or advertiser CTA was
  tapped. No system volume, lock, account, Play Games setting, live Remote Config,
  store release or cloud deployment was changed. Notification permission was
  denied after resets, and the QA wrapper replaced reminders with `NoopReminders`.

## Validation and delivered scope

- `flutter pub get`: passed before work.
- `flutter analyze`: clean before QA; final clean-tree rerun recorded in
  `E/flutter-analyze-final.log`.
- `flutter test --concurrency=2 --reporter expanded`: **3,085 passed, 50 skipped**;
  `E/flutter-test-full.log`. One full-suite run; no test changes or additions.
- `npm --prefix functions ci` and build: passed. Default `npm --prefix functions
  test` met an occupied local Firestore port (8080, unrelated Python service).
  Reran the same npm test inside Firebase `emulators:exec` with Firestore 8193
  and the remaining normal ports, project `demo-flappy-spikes`: **144 passed**.
  `E/functions-test-isolated-final.log`. Temporary config removed; no deploy.
- Final phone state: Play-installed **2.3.1 (20)** restored, No Ads off, media
  volume 0, notification permission denied. The initial public-version detour was
  corrected through the existing internal-test download link, without re-enrolment
  or account/settings changes. A web remote-install attempt required reauthentication
  and was abandoned; no credentials or verification requests were submitted.
- Committed scope: this report and ten key screenshots only. Temporary QA Dart
  wrapper and emulator config removed; signing copies deleted. No push.
- Economy tuning, production fixes, release changes and integration with other
  WPs were outside this tester's scope. Main remaining acceptance risk is D-01.
