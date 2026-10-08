# QA round P4/P5 — PRD-2 meta, reminders and versus

Independent review of `g6-qa4`, product baseline `1c86664`, 2026-10-08.
PRD: `/home/killerhis/Projects/flappyspikes/PRD-2-gameplay.md`.
Contracts reviewed: ARCH §6 and as-built §§24–28, REQ-MATRIX, VERSUS-BACKEND,
SUBMISSION §6, workspace AGENTS.md and CLAUDE.md.

**Seven confirmed defects: four major, three minor; no blocker found.**
Product code was not changed. All seven regressions are recorded with
`skip: 'S6-xx open'`; enabling them produces assertion failures described below,
not compilation or setup failures. The extra opt-in emulator reproduction of
S6-60 is skipped with the same reason.

## Findings

| ID | Severity | File:line | What's wrong | Repro / observed | Expected (PRD §) |
|---|---|---|---|---|---|
| S6-60 | major | `lib/versus/upload_queue.dart:73`, `:105`; `lib/services/firebase_versus_backend.dart:118`; `functions/src/pools.ts:152` | The client limits non-best runs on enqueue day, but flushes the entire multi-day backlog on one upload day. It removes each run on Firestore transaction success before the trigger verdict. The server rejects excess runs, and the queue has already forgotten them. | Queue three non-best score-3 runs on each of two offline UTC days; reconnect on day three and flush. Six documents pass the real emulator rules (HTTP 200). The real trigger accepts three and rejects three with `reason: rate`. The queue contains **zero**, not three retryable entries. Also reproduced with the compiled server logic and the real Dart queue/write builder. | At most three non-best uploads per UTC day, with queued runs retried when online; a new best remains exempt. Pace the backlog or retain rate-rejected runs for a later day (§3.13 upload/offline rules; ARCH §6.1). |
| S6-61 | major | `functions/src/pools.ts:233`; `functions/src/index.ts:52`; `lib/components/delete_data_popup.dart:59` | Deletion can fail after deleting part of the online data, while the failure popup asserts that nothing was deleted. The player and rate deletes, pool rewrites and Auth delete are separate operations. | Invoke the actual compiled `deletePlayerData` over a Firestore fault seam that succeeds at deleting `players/qa`, then rejects the rate-document delete. The operation fails, the player document is gone, and the rate document remains. An Auth-delete failure likewise occurs after Firestore deletion. | The requested failure contract is “on failure nothing is deleted”; the UI must not promise intact online data after a partial delete. Successful deletion must cover the player, every pool membership, Auth account and Analytics ID, retaining phone progress (§3.13 / Q22; SUBMISSION §6). |
| S6-62 | major | `lib/run/items/puzzle.dart:75`; `lib/game/storage.dart:344` | Puzzle payout and mask/round persistence are independent, unawaited writes with no recovery record. A completed picture can be cleared and advanced even though its coin credit never reached disk. | Collect the actual fourth pickup with mask `7`, round `2`, coins `100`. Stop the real preferences platform immediately before the coin write, allowing subsequent mask/round writes. Reload its actual saved data: mask **0**, round **3**, coins **100**, no pending payout. The earned bonus is lost. | The 4/4 credit is retained if the app closes, pays exactly once, and mask reset + round advance + payout form a recoverable completion (§3.16 reward/persistence; §7; ARCH §28). |
| S6-63 | minor | `lib/run/screens/bonus_screen.dart:77` | Whole-page bonus scaling changes bottom-button spacing and shrinks NEXT on a short screen. It also transforms the ad button and NO THANKS with the content. | Open the real balloon page at 568 pt. Transform the reference NEXT rectangle through `content`: bottom gap **86.38 pt** instead of **99 pt**, width **224.98 pt** instead of **292**, height **38.52 pt** instead of **50**. | Bottom buttons retain their reference bottom distance; NEXT keeps its §5.14 geometry across 568–730 pt (§3.0.1 Screen heights, §5.14). The as-built scaling choice does not supersede the PRD. |
| S6-64 | minor | `lib/run/screens/versus_intro.dart:775`; `lib/run/hud/versus_bar.dart:133`; `lib/run/screens/results_screen.dart:929` | Avatars are stored but never loaded or rendered; intro, HUD and results always draw a neutral person glyph. This is acknowledged as “not done” in ARCH §26 but marked done with a caveat in REQ-MATRIX R-3.13-3. | Supply an opponent with an avatar URL and put a solid-red avatar image in the game image cache under that URL. Freeze the locked intro and rasterize its actual plate: an avatar-region pixel is grey **[130,130,130]**, not image red **[255,0,0]**. Source review confirms no avatar image path in the other two screens. | Signed-in players show their Play Games avatar; the neutral avatar is the fallback while an image is unavailable, rather than permanent output (§3.13 Who plays, §5.8 avatars). |
| S6-65 | minor | `lib/game/flappy_game.dart:978`; `lib/run/screens/results_screen.dart:304`, `:311` | The own-player name is hardcoded to “You”, ignoring the available generated nickname / Play Games profile. | Give `FakeVersusService.me` the name `SwiftKiwi482` and start a real VS intro. The own name plate shows **You**. Results likewise constructs both solo and versus own columns with the literal **You**. | The own plate shows the player's name, using the persistent nickname or Play Games display name (§3.13 identity, §5.8 Your plate, §5.10 versus card). |
| S6-66 | major | `lib/services/versus_service.dart:274`, `:350`, `:401`; `lib/main.dart:102` | If anonymous-auth startup fails, `ready` remains false. The normal Home prefetch and run-submit/flush paths never retry initialization, so network recovery does not restore matching or uploads during that app session. | Start the real service with a backend that throws offline from `start`; restore connectivity; submit a valid new-best run; call Home prefetch and flush. The backend has no successful auth start and the run remains queued. A restart or an explicit second `initialize` is required, neither wired to normal recovery. | Offline failures fall back to solo and queued runs retry when the phone is online; first-start auth must recover without requiring an app restart (§3.13 upload/offline rules; R-3.13-2, -8). |

## Verification

| Check | Result |
|---|---|
| `flutter pub get` | Passed; tracked lockfile unchanged. |
| Baseline `flutter analyze` | Clean. |
| Baseline `flutter test -j 3 --reporter expanded` | **1,767 passed, 3 skipped**, all green. |
| `npm --prefix functions ci` | Installed the locked dependencies; tracked files unchanged. |
| `npm --prefix functions test` | **78 passing**; build + type-check + Auth/Firestore/Functions demo emulators. |
| `bash tool/versus_emulator_test.sh` | **2 passing**, client documents/rules, real trigger, matching/replay, foreign owner rejection and callable App Check rejection. The tracked shell script has no executable bit, so it was invoked through bash. |
| New P45 file, normal execution | **10 passing journeys**, seven open regressions skipped. |
| New P45 open cases, `--run-skipped --plain-name S6-` | **7 expected assertion failures**, one per finding. |
| Extra S6-60 emulator probe | Expected queue-retention assertion fails after all six real writes pass rules and the real trigger reports three rate rejections. |
| S6-05, S6-06, S6-07 targeted recheck | **3 passing**: current-zone travel, seven-day horizon after skipped slots, failed-plan rotation rollback. |
| Final `flutter analyze --no-pub` | Clean. |
| Final full Flutter gate | **1,777 passed, 10 skipped**, all green (the seven open cases plus three existing opt-in cases). |

The backend fault probe runs **compiled product logic** against an in-memory
Firestore seam, with no Firebase app initialization or network. The additional
S6-60 probe runs against the **real local emulators** and rules/trigger. S6-61 is
an injected backend failure, not a claim that the happy-path emulator delete
fails. S6-62 uses the actual fourth-piece pickup and records the actual
preferences writes; it does not invent a manual restart snapshot.

Logs: `/tmp/p45-{pubget,analyze,flutter,functions,emulator,e2e-final,repros-final,backlog-emulator,reminder-fixes,analyze-final,flutter-final}.log`.
Untracked logs and generated screenshots outside the worktree were ignored.

## Journeys and contract review

- At **568 and 711 pt**: collect the third feather, die, accept the real revive,
  finish phoenix with frozen runClock, die again, decline the next offer, pop
  balloons, leave for results. Feather count resets only on bonus entry;
  wallet pays per tap; locked input rejects another pop; YOUR REWARD excludes
  balloon credits. Games remain one run across revival.
- At both heights: collect one real missing piece per run across **four runs**,
  returning Home between them and reloading persistence after each pickup.
  Tangerine round 7 advances to round 8/Pink on completion; mask resets; a
  single 50–250 step-5 payout is counted in run reward and results. Full unit
  suites independently verify all eight exact colour themes, random payout
  bounds, slot chimes and no second scheduled pickup after revival.
- Jackpot **250** is credited at tap. The ad and No-ads-owner journeys each
  allow one refill, six total pops and NEXT with three hidden tiles. The owner
  path uses no ad call. An unavailable ad leads directly to NEXT after three
  pops. The existing bonus tests exercise ad completion/failure and analytics.
- A real versus intro precedes a **Space portal ride + comet + actual
  Hourglass capsule** in one run. Pause freezes runClock in the ride; ride
  points carry the ride flag; the opponent goes out; the final duel is WIN
  with +10 in YOUR REWARD and one versus_result. Existing versus suites cover
  unskippable taps, real lock/name/emblem, the documented **~7.34 s** timing,
  pause/revive/phoenix/Hourglass replay, all WIN/LOSE/DRAW outcomes and +10/+5.
  The timing call in ARCH §26 is accepted, not filed as a 6.3-second defect.
- The squeeze journey holds the squeeze across both scheduled pickup windows:
  no feather/piece is consumed or spawned until it clears, then both spawn
  in separate free gaps. This uses test state to extend the hold; normal
  squeeze timing and real wall physics remain covered by the baseline suite.
- The new **30-day spring-DST** reminder journey recreates storage/service
  daily, reschedules twice per session, simulates OS delivery, covers all 20
  messages, checks ten-day repeat exclusion, quiet hours, two-hour skip and
  the fixed seven-calendar-day horizon. Existing spring/autumn journeys and
  S6-05/06/07 pass. Notification permission is requested once. Channel/name,
  inexact alarms, POST_NOTIFICATIONS, boot receiver and keep resource reviewed;
  shipped `notif_chime.ogg` is byte-identical to approved **B · Perfect chime**.
- Dart matching mirrors `functions/src/matching.ts`, with shared JSON fixtures
  passing on both sides: same level below best → any → solo; own/seen runs
  excluded; platform unused for matching; no fabricated opponent fallback.
  Nickname lists, ≤14-character words, 000–999 suffix and persistence match.
  Queue tests cover minimum score 3, best exemption, UTC rollover, cap 12 and
  oldest non-best eviction; S6-60 and S6-66 expose integration gaps.
- Client documents were compared with `firestore.rules` and ARCH §6.1:
  one new recent[0], unchanged old recent entries, ≤5 recent runs, bestRun
  identical to the new best entry, nondecreasing best, levelFor(best), field
  lengths, timeline counts/flags, platform, server updatedAt and 60-day
  expireAt. Both standard emulator tests pass; the backlog probe proves
  valid documents alone do not imply backend acceptance.
- Delete Settings row, confirmation/cancel, error/success texts, exact local
  reset and retention of wallet/skins/levels/feathers/puzzle are covered by
  baseline tests. Online success deletion and delayed-trigger suppression
  pass backend tests. S6-61 concerns partial failure. Analytics-reset errors
  are also swallowed after online deletion (`versus_service.dart:450`).
- Identity review found no launch `GameAuth.signIn()` and no executable use of
  `GameAuth.isSignedIn`. Identity uses the live player stream; getAuthCode is
  caught and timed out; versus backend calls are caught and bounded by the
  service timeout; optional iOS identity remains paused. A real Play Games
  credential/link and production Play Integrity enforcement were not tested.
- Analytics call paths and baseline assertions cover feather_collected,
  bonus_shown/pop/ad_offered/ad_completed/declined, puzzle_piece_collected/
  completed, versus_matched/skipped/result, reward sources bonus/puzzle/
  win_bonus, rewarded placement bonus_feathers, notif_permission/opened and
  cross-feature portal/comet/powerup events. Level source `level_reward` and
  aggregated per-run coin events are documented ARCH decisions.
- SUBMISSION §6 matches the player/pool/rate document schema, both platforms,
  retention model and deletion set. This review did not inspect or edit live
  Console data-safety answers, deployed TTL or App Check settings.

## Visual comparison

All baseline screenshot generators ran. Inspected generated **568 and 711 pt**
meta/versus/results shots against PRD-approved images in `design/menu_v2/`:

- `balloon_start/pop/offer/next.png` against
  `build/shots/run/meta_collect/balloon_*_{568,711}.png`;
- `feather_field/fly/complete.png` and `puzzle_field/fly/complete.png` against
  the corresponding meta_collect shots;
- `versus_lv_spin/lock/vs.png` against
  `build/shots/run/versus/vs_{spin,lock,hold}_{568,711}.png`;
- `results_lv_up/claim/after/newbest/lose.png` against
  `build/shots/run/results/results_*_{568,711}.png`, plus the actual duel
  WIN/LOSE/DRAW shots in `build/shots/run/versus/`;
- `settings_v3.png` against `build/menu_shots/settings_{568,711}.png`, including
  the authorized new DELETE MY DATA row and existing confirmation/result shots.

The balloon layout at 711 is close to the approved mock. S6-63 records the
short-screen anchoring/size error. S6-64 records permanent neutral avatars.
Feather/puzzle use the shared course, score disc and HUD; solo content and
stage/score/prize/skin/animation-frame differences are not additional defects.
The final BONUS UNLOCKED! copy correctly supersedes the exploration mock's
BONUS CHESTS UNLOCKED. Emblems and CLAIM's gold coin reflect the settled shared
art and earlier P2 fixes. These are visual inspections, not pixel-golden tests.
Comparison contact sheets are `/tmp/p45-compare-{0,1,2,3,4,5,6}.png`.

## Reproduce

Use the SDK/JDK environment line from AGENTS.md, then:

```bash
npm --prefix functions ci
npm --prefix functions run build
flutter test --no-pub -j 3 test/e2e/p45_gameplay_e2e_test.dart
flutter test --no-pub --run-skipped test/e2e/p45_gameplay_e2e_test.dart --plain-name S6-
flutter test --no-pub test/e2e/p1_gameplay_e2e_test.dart --name 'S6-0[567]'
bash tool/versus_emulator_test.sh
firebase emulators:exec --project demo-flappy-spikes --only auth,firestore,functions \
  'FS_EMULATOR_TESTS=1 flutter test --no-pub --run-skipped test/e2e/p45_emulator_probe.dart'
```

`--run-skipped` is expected to exit nonzero while the findings remain open.
The optional probe has a `.dart` filename without `_test` so routine discovery
never opens HTTP or requires emulators. It is still explicitly skipped as
S6-60 until requested with `--run-skipped` inside the demo emulator session.

No physical-device, live Firebase, production deployment, iOS or hardware
notification/audio check was performed. The Pixel 8 was not used.
