# PRD-2.3 QA P2 — Sol

2026-10-13. Branch `p23-qa2`, baseline `f5bf640` (all sections merged). Audited §§17, 18, 23, 24 and 26 against the approved PRD, including §0's overrides, and rechecked S8-02…S8-08. No device work, deployment, purchases, account changes, messages or notifications.

**Five new findings: three major, two minor.** Application code is unchanged. Eight failing regression cases were run unskipped and then retained under `skip: 'S8-xx'` (group metadata for Flame widget tests, whose own `skip` argument accepts only a bool). Existing tests and golden references are unchanged.

## Findings

### S8-09 — major — Foreground time is not saved during runs or at run end

- **PRD:** §18.3: save every 10 s in the foreground and at run end; a crash loses at most 10 s.
- **Location:** `lib/game/flappy_game.dart:4454`, `:4116`; `lib/menu/ad_grace.dart:62`. The conflicting deviation is `SPEC.md:1129`.
- **Repro:** `test/p23/s18_qa_persistence_test.dart`, S8-09 group. Open a fresh waiting run and advance 25 s; repeat during flight. Separately fly 15 s, die, and reach results without NEXT. Allow preference operations to finish and read persisted `playtimeSeconds`.
- **Expected:** at most 10 s difference between counted and persisted time; run end saves the current count before NEXT.
- **Actual:** both 25 s cases persist zero (25 s lost on a crash). At results after the 15 s flight the key is still absent. The game passes `mayWrite: state == GameState.start`, and the advertised run-end flush actually runs on Home arrival. A waiting run can last indefinitely, making the deviation's “at most a few minutes” rationale incorrect too.
- **Integration:** save periodically in every resumed state outside full-screen ads, and flush when the run ends. A local SPEC deviation cannot replace the approved §18.3 requirement. Existing counter tests exercise the 10 s write on Home only.

### S8-10 — minor — Interstitial preload ends grace one finished run too early

- **PRD:** §18.2 and §18.5: the preload uses the same grace check; nothing loads during grace, which requires five **finished** runs or 300 s.
- **Location:** `lib/game/flappy_game.dart:3288`; existing contradictory assertion `test/p23/s18_ad_grace_test.dart:141` and `:150`.
- **Repro:** S8-10 group in `test/p23/s18_qa_persistence_test.dart`: start and flap with four finished runs and less than 300 s.
- **Expected:** zero preloads while the fifth run remains unfinished.
- **Actual:** one preload, because `_onFirstFlight` passes `storage.gamesPlayed + 1`. The NEXT/show guard correctly uses the actual finished count. This finding concerns the explicit preload requirement; it does not mean an interstitial is shown early.
- **Integration:** use the same finished-run grace predicate for preload and show; handle a gate crossed at run end without counting an unfinished run as finished. Update the existing tests that intentionally expect the premature load when fixing this.

### S8-11 — major — Cooldown-blocked gap bonuses are discarded instead of becoming due

- **PRD:** §17.3 rule 4: a big bonus picked while the open-bonus rule **or cooldown** blocks it becomes due and takes the first allowed slot; §17.3 rule 5 preserves section 14's frequency.
- **Location:** `lib/run/director/run_director.dart:1405`, `:1456`; analogous early-pool suppression at `:477`.
- **Repro:** `test/p23/s17_qa_waiting_test.dart`, seed 5, real default tables, only normal hoops and Piggy Bank enabled and already met, starting at hoop 30. The unblocked director draws a pig in that gap. Repeat the identical initial state with `activityEndedAtSlot: 31`, so gap 30 is in cooldown.
- **Expected:** no pig is placed in the blocked gap, but `waitingItem` is Piggy Bank; gap 31 gets that due pig before a new draw.
- **Actual:** `waitingItem` is null. `nextGap` skips the whole optional draw while `blocked`, so the rule-4 waiting logic cannot see a cooldown-blocked item. It only queues items blocked by another open bonus. The existing rule-4 tests use `bigBonusOpen`, omitting this other required blocker.
- **Integration:** preserve eligible draws during cooldown and queue at most one, while still preventing placement during the activity/cooldown. Recheck frequency after the change. This is a missing path distinct from the reported rate shortfall; this reproduction alone does not establish how much of that shortfall it explains.

### S8-12 — minor — Locked menus dim the back-button artwork

- **PRD:** §26.2: only back and the coin pill are above the overlay, fully bright and working.
- **Location:** `lib/game/flappy_game.dart:787`; `lib/components/menu_screen_chrome.dart:191`.
- **Repro:** S8-12 group in `test/p23/s26_qa_interplay_test.dart`: capture locked and unlocked Shop at both 568 and 711 pt, after transitions settle; compare the same interior pixel of the back-button box. Also visually checked the locked Skins capture.
- **Expected:** the back-button artwork has identical brightness in the open and locked states, like the coin pill.
- **Actual:** locked RGBA `[66,0,39,255]`, open `[236,0,140,255]`: exactly the overlay's darkening. The transparent back **tap target** has higher local priority, but its artwork is the shared `MenuCornerBox` at world priority 19, underneath the screen at 20 and its overlay. Back still works. The coin pill at 21 stays bright.
- **Evidence:** `qa2_lock_shop_568.png`, `qa2_open_shop_568.png`, `qa2_lock_shop_711.png`, `qa2_open_shop_711.png` in the evidence directory below; `p23_s26_skins_locked_711.png` from the existing screenshot test shows the same dim back arrow.
- **Integration:** fix the shared artwork's layer, preserving popup dimming, transitions, and the single shared chrome. Raising the invisible hit target alone does not fix rendering.

### S8-13 — major — A delayed launch No-Ads grant still gives the first run a banner

- **PRD:** §24.3: a restore or redeem at launch applies ownership before the first run, so even that run has no banner. This differs from an intentional purchase during a run, whose banner stays until run end.
- **Location:** `lib/game/flappy_game.dart:706`, `:1112`, `:3266`; `lib/game/purchases.dart:152`; startup `lib/main.dart:228`.
- **Repro:** S8-13 group in `test/p23/s26_qa_interplay_test.dart`. Hold the launch store sync's reply with a fake store that already owns a redeemed No-Ads gift; enable a fake banner. Once Home has loaded, press START before the store reply. Release the launch reply, wait for the grant to persist (`noAds=true`), then give the waiting run its first flap.
- **Expected:** the launch ownership is resolved before the first run reserves a banner; that first run has no banner slot or height reduction.
- **Actual:** the first run has `runHasBanner=true`, even though ownership has arrived before its first flap. Launch sync is fire-and-forget, START reserves immediately, and the grant is treated like a mid-run purchase. The owner gets a shrunken first run and its banner. Existing “restore at launch” tests seed `noAds=true`, bypassing the actual asynchronous launch ordering.
- **Integration:** coordinate initial ownership sync with first START/banner reservation, with bounded failure handling. Keep the separate rule for a real mid-run purchase. S8-05's receipt/grant confirmation fix prevents lost coins but does not close this scene-start race. No real store purchase or ad is used by the reproduction.

## P1 fix re-verification

| Finding | Result and evidence |
|---|---|
| S8-02 tuning changes a begun run | Fixed. `s15_qa_startup_test.dart` passes delayed activation and whole-set background-fetch immutability. `main.dart` bounds/awaits startup; `Tuning.beginRun` pins the active set even after that startup timeout. |
| S8-03 held self-match after identity change | Fixed. Both pg-arrival and uid-switch cases in `s21_qa_held_identity_test.dart` pass; `takeOpponent` revalidates held identity and in-flight searches use current identity. |
| S8-04 short MEDIA ding latches music off | Fixed. The 1.9 s boundary regression in `s13_qa_poll_boundary_test.dart` passes; current playback is checked before promotion. |
| S8-05 early gift consumed without grant | Fixed. `s22_qa_early_delivery_test.dart` passes no-listener, timeout/error, and later confirmed launch redelivery cases. Completion requires persisted grant confirmation. |
| S8-06 avatar survives TTL | Fixed locally. Four emulator cases in `functions/test/p23_qa_p1.test.ts` pass: TTL deletion, recreated-player protection, stale-orphan sweep, and default bucket listing. No live deployment verification in this round. |
| S8-07 onboarding warning under HUD | Fixed. All four solo/versus × 568/711 geometry cases in `s10_qa_hud_overlap_test.dart` pass. Viewed updated first-run reference: both chevrons and full text clear the controls. |
| S8-08 generated names lose digits | Fixed. Both exhaustive nickname cases in `s21_qa_generated_names_test.dart` pass across HUD, VS plate, results and share; generated digits remain intact. |

## Interplay and limits

- **§0 item 1:** existing `s23_rating_prompt_test.dart` covers run 5 requesting the sheet, NEXT skipping with `rating`, and the first interstitial on run 6. NEXT before 1.5 s uses no rating cooldown and allows normal ad rules. No-Ads owners are also asked.
- **Native rating/back:** two new cases hold the platform review future open, send inactive/resumed lifecycle events, and simulate the underlying game's back handling. Results survive, the cooldown stays stable, no duplicate request occurs, and NEXT shows no interstitial. The actual native sheet's gesture interception is an OS/plugin check reserved for a device round.
- **§0 item 2:** existing after-run gift collision and new simultaneous gift/owed-level case exercise gift-first ordering and suppression for the entire visit, including after both claims. The new case creates a concurrent catch-up level after results to keep that reward owed on Home, rather than claiming it on results. The No-Ads policy itself is eligible in this case, proving the visit guard suppresses a qualifying offer.
- **§18 × §10:** a never-tapped waiting run counts foreground seconds, does not increment `gamesPlayed`, does not preload, and remains in run-count grace. Persistence is separately failing as S8-09. Background and full-screen-ad exclusion, restart retention and Delete-my-data retention have existing coverage.
- **§24:** after-run/session analytics, exact gap/fallback/cap boundaries, first-session/warm-up/low-score guards, rating collision, post-interstitial offer and one offer per arrival are covered in `s24_noads_popup_test.dart` and `test/menu/noads_popup_policy_test.dart`. Persisted-owner tests cover no banner reservation/loading, no interstitial/offer, owned tile and next-run application of mid-run ownership. Existing “restore at launch” coverage seeds the already restored flag; delayed real fake-store launch delivery instead fails as **S8-13**. The restore-under-lock case passes.
- **§26:** both the existing lock suite and the new file restore production defaults explicitly; neither inherits the `flutter_test_config.dart` unlock bypass. New real pointer tests block tabs, try-on, and scrolling, then use the pill to enter locked Shop and system back to return through locked Skins to Home. Gift grants and Restore work below 25. Existing cases cover lock/NEW badges, tuned threshold/text, silent unlock from a run, No-Ads exemption and revive-shop exemption.
- **§17 × §14:** the existing forced scenarios cover pig missed/collected, comet/jar, portal/capsule, small items, off-screen creation reach and narrowed clearing. They and the short invariant soak pass. The full suite includes autopilot and forced-element gates, while controller gate tests explicitly set `ignoreGates=false`; most legacy gameplay helpers deliberately unlock all elements.
- **Bonus rate:** the builder reports **about −18% over 1,600 runs** (`SPEC.md` and external `briefs8/RUNLOG.md`). This QA's default soak independently measures **6.66 versus 7.87 big bonuses / 50 hoops**, **−15.4%** (63 in 473 versus 71 in 451 planned slots passed). The target is ≤10%; both the soak and director-count tests currently tolerate 20%. §17.6 explicitly says to report a larger drop and check waiting, so the shortfall is recorded here, without claiming the target passed. S8-11 identifies an untested waiting-path defect. The full 1,600-run soak was not repeated in P2; do so after the waiting fix.

## §1 coverage — all 25 summary items

Paths are relative to the worktree. Tests in this column are under `test/` unless otherwise stated. “Covered” means local automated coverage, not a claim that every platform/store check is complete.

| # | Summary item | Implementation | Tests / remaining gap |
|---|---|---|---|
| 1 | Spotlight share image | `lib/share/share_card.dart`, `share_content.dart`; results callback in `flappy_game.dart` | `p23/s2_share_test.dart`, `share/share_card_golden_test.dart`: own result/look, PNG dimensions, ten goldens and negative control. Native share-sheet delivery remains a device check. |
| 2 | Five challenge texts, one link | `lib/share/share_content.dart`, `lib/game/config.dart` | `p23/s2_share_test.dart`: exact texts, independent/uniform selection, one URL. |
| 3 | Device redirect at `/get` | Cloudflare redirect rules; landing in `hosting/public/` | `hosting/tools/domain_checks.sh`: live Android/www/iPhone/desktop/social-bot redirects and unchanged homepage; passed. iOS Store destination deliberately not enabled yet. |
| 4 | Invite shares score/new-player card | Home invite → `FlappySpikesGame.onInvite`, `ShareContent.invite` | `p23/s2_share_test.dart`: scored/new-player journeys and random cards/texts; invite goldens. |
| 5 | Install campaign tracking | Config/store badge URLs; Cloudflare Android redirect referrer | `p23/s2_share_test.dart`, `p23/s5_website_test.dart`, live domain redirect checks. Actual attributed install/report in Play Console is a store measurement gap. |
| 6 | Website/legal/support/delete-data/404/ads | `hosting/src/`, `hosting/build.py`, `firebase.json` | `p23/s5_website_test.dart`, build's static checks, 58 live domain checks. P1 retention defect fixed locally; deployment excluded from this round. |
| 7 | Link preview metadata/image | `hosting/build.py`, homepage OG/Twitter tags, `hosting/public/og.png` | Website/static checks; live metadata and PNG content type pass. Individual messenger cache refresh is not tested. |
| 8 | 17C icon/splash everywhere | `tool/render_app_icon.py`, Android/iOS generated resources, app/share/site assets | `p23/s2_share_test.dart`: icon dimensions/alpha and Android density/adaptive resources; share goldens/site checks. Native launcher/splash/store review and iOS runtime remain platform checks. |
| 9 | Waiting start, easy hoop 0, hint/reminder | `flappy_game.dart`, `first_run_config.dart`, `first_run_hint.dart`, director fixed-first slot | `p23/s10_waiting_start_test.dart`, `s10_qa_interplay_test.dart`, `s10_qa_hud_overlap_test.dart`, new `s18_qa_persistence_test.dart`: all modes, first tap, reminder/pause/back; goldens. |
| 10 | SEO/GEO and five content pages | `hosting/src/`, `hosting/build.py`, robots/sitemap/JSON-LD | `p23/s5_website_test.dart`, static build checks, live domain checks. Search Console/Bing account setup and ranking/AI citations are not verified by local tests. |
| 11 | New tagline | `Config.tagline`, Home, website content | `p23/s2_share_test.dart` and `s5_website_test.dart` scan app/site text; competitor title exception retained. |
| 12 | Music recovery/watchdog | `lib/game/music_guard.dart`, `lib/services/audio_focus.dart`, Android AudioWatch | `p23/s13_music_test.dart`, `s13_qa_poll_boundary_test.dart`; P1 boundary fixed. Actual focus/lifecycle playback remains a device check; prior evidence in `docs/p23/MUSIC.md`. |
| 13 | Economy/scoring/difficulty/rides/gates | `lib/run/config/`, director, run features, `lib/levels/` | `p23/s14_2_economy_test.dart`, `s14_4_difficulty_test.dart`, `s14_6_gates_test.dart`, `s14_qa_scoring_gates_test.dart`, `budget_report_test.dart`, autopilot/forced rides. Bonus frequency shortfall discussed above. |
| 14 | Tester remote tuning | `lib/services/tuning.dart`, tuning values/defaults, `lib/main.dart`, `tool/` tuning scripts | `p23/s15_tuning_test.dart`, `s15_qa_startup_test.dart`; P1 delayed activation fixed. Live console edits/release compiled-out behavior need build/device checks. |
| 15 | Seamless 56-bar music | OGG asset, `tool/make_music_loop.py`, `lib/game/music_backend.dart` | `p23/s16_music_loop_test.dart`: granule count, format, GAME attributes, loop/player lifecycle. Device seam evidence in `MUSIC.md`; scrcpy listening measurement and Hourglass/duck wrap remain documented gaps. |
| 16 | One open big bonus, no disappearance/pop-in | `RunDirector`, `RunSpawner`, per-element visual reach config | `p23/s17_one_big_bonus_test.dart`, `s17_soak_test.dart`, new `s17_qa_waiting_test.dart`; **S8-11** cooldown waiting fails; rate target not met. |
| 17 | Five-run/300-second ad grace | `lib/menu/ad_grace.dart`, storage and game update/preload/NEXT hooks | `p23/s18_ad_grace_test.dart`, new `s18_qa_persistence_test.dart`; **S8-09/10** fail. |
| 18 | 60 new accessories/art | `lib/skins/catalog.dart`, `lib/skins/art/`, Skins/featured Shop | `p23/s19_new_items_test.dart`, skin art/catalogue suites, visual contact sheet `docs/p23/SKINS_PORT.png`; browser blur/random particles are documented port differences. |
| 19 | Settings screen/links/audio tiles | `lib/components/settings_panel.dart`, Config layout/URLs, service interfaces | `p23/s20_settings_test.dart`, menu screenshot suite; tested layouts/drag/conditional rows, no Rate row; native URL/store opens remain platform checks. |
| 20 | Versus names/pictures/looks/self-match | `fit_name.dart`, HUD/VS/results, avatar cache/upload, `versus_service.dart`, Dart matcher and TS reference | `p23/s21_names_test.dart`, `s21_avatar_display_test.dart`, `s21_versus_identity_test.dart`, P1 generated/held identity regressions; backend schema/avatar tests. Platform picture fetch/account transition is a device check. |
| 21 | Gift codes and popup | `IapService.syncPurchases`, `Purchases`, Settings redeem link, gift queue, `docs/SUPPORT.md` | `p23/s22_gift_codes_test.dart`, `s22_qa_early_delivery_test.dart`, new locked gift/Restore/order cases. Actual promo-code redemption and product activation are not performed in QA. |
| 22 | Native rating prompt | `lib/services/rating_prompt.dart`, results settle hook, stored cooldown | `p23/s23_rating_prompt_test.dart`, new `s23_qa_native_sheet_test.dart`: triggers/timing/cooldown/overlays/run5→6/back/lifecycle/owners. Native sheet display/quota requires Play-installed build. |
| 23 | More No-Ads offers, none for owners | `lib/menu/noads_popup_policy.dart`, Home-arrival queue and owner banner/ad guards | `p23/s24_noads_popup_test.dart`, menu policy/ad suites, new gift/level ordering and delayed launch grant; **S8-13** first-run banner race fails. No real purchase or ad display in this round. |
| 24 | VS loading/rematches, never silent solo | `lib/versus/matcher.dart`, `versus_service.dart`, `versus_intro.dart`, TS reference | `p23/s25_versus_matching_test.dart`, `s25_vs_loading_screen_test.dart`, `s10_qa_interplay_test.dart`, shared matcher fixtures. Small live-pool rapid restart checks are a device gap. |
| 25 | Shop/Skins unlock at best 25 | `MenuState.locked`, `MenuScreen`, `MenuLockOverlay`, Home badges, game exemptions | `p23/s26_menu_lock_test.dart`, new `s26_qa_interplay_test.dart`; **S8-12** rendering fails. Runtime locks are tested with production defaults, including real pointer/back input. |

## Validation and handoff

- Tests checkpoint: `5820347` — `test/p23/s17_qa_waiting_test.dart`, `s18_qa_persistence_test.dart`, `s23_qa_native_sheet_test.dart`, `s26_qa_interplay_test.dart`. This report is committed separately after the final gate.
- `flutter pub get`: completed before testing.
- `npm --prefix functions ci && npm --prefix functions run build`: completed before Dart tests. `unset JAVA_HOME; npm --prefix functions test`: **144 passing, zero pending**, including all P1 retention cases.
- Baseline focused sections/P1 regression run: **100 passing**; P1 HUD overlap recheck: **4 passing**. Final new QA cases: **6 passing / 8 deliberately skipped**. Added **14 cases** across four test files; no existing tests changed.
- `flutter analyze`: **clean**. Final `flutter test --concurrency=3`: **2,855 passing / 31 skipped**, all tests passed (8 new finding reproductions and 23 pre-existing skips). Autopilot, forced elements, share goldens and screenshot suites are included.
- `bash hosting/tools/domain_checks.sh`: **58 PASS / 0 failed**, read-only against the live site.
- Big evidence/logs: `/home/killerhis/Projects/flappyspikes/.worktrees/briefs8/evidence/qa2/`. No evidence binaries, regenerated store screenshots, secrets or build output are committed.

**Calls:** PRD wins over the unapproved periodic-save deviation and premature-preload assertions; neither existing expectation was silently rewritten. The reported bonus-rate deviation is explicitly reported as §17.6 asks; S8-11 is the separate missing cooldown-wait path. Flame failing cases use group string-skip metadata. No production fix, storage-key change, Config knob, iOS edit, or SPEC/ARCH contract change belongs to this tester commit.

**Not done / risks:** no device, emulator app session, deploy or store-account work. Native sheets, real ad/restore delivery, frame budgets and OS gestures need the device round. The §17 full soak should be repeated after the waiting fix. A green default gate includes these eight deliberately skipped failures and the pre-existing skips; it does not certify the five findings as fixed.
