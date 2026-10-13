# PRD-2.3 final device QA

Tested revision **f5bf640**, branch `p23-qadev`, on the owner's **Pixel 6 / Android 17**, serial `24191FDF6008ZD`, 1080×2400, 90 Hz. Media, ring and notification streams stayed muted. The initial DND and stay-awake settings were retained. No real messages, notifications, purchases, sign-in, deployment or push. Share sheets were cancelled.

**Device sign-off: FAIL — S8-13.** QA P2's S8-09…S8-12 also remain open in this revision. This checkout has the P1 fix round; the P2 report appeared during this run in `../g8-qa2/docs/p23/QA_P2.md`. Finding numbers continue after S8-12. Store- and audible-audio-only checks remain explicitly limited below.

Raw evidence root, referred to as **E/** below:
`/home/killerhis/Projects/flappyspikes/.worktrees/briefs8/evidence/device/`.
Only this report and selected game images are committed. Native share sheets and system/account screens stay in external evidence.

## Gates

| Gate | Result | Evidence |
|---|---|---|
| Device `release_e2e_test.dart`, `FS_E2E` + live versus, `--no-uninstall` | **PASS: 8 tests**, 85 PNGs; journey, all elements, six rides, pending reminder plan, modes, live match and isolated anonymous upload/read/delete | E/e2e-first.log; E/e2e_release/; E/e2e-sweep.mp4 |
| Focused `test/p23` + `test/share`, concurrency 3 | **PASS: 340 passed / 20 skipped** | E/focused.log |
| Functions build and emulator tests | **PASS: 144 passed / zero pending** | E/functions-build.log; E/functions-test.log |
| Final `flutter analyze` | Pending final run | |
| Full `flutter test --concurrency=3` | Pending final run | |
| Profile skin performance | Pending device run | |
| Short soak | Pending device run | |

The e2e harness needed the §10 first playfield tap in `_start()` and the separate live-match path. The test-only patch is retained at **E/e2e-harness.patch**; application expectations and goldens were unchanged. Per the requested commit restriction, the harness patch and temporary device bridge are external evidence, not delivered source changes.

## Device checks

| PRD / item | Result | Evidence / qualification |
|---|---|---|
| §6.3 results share: native PNG + approved text/link | **PASS** | E/results-share-01.png … -20.png; image caches in E/share-cache-*.tar. No recipient was selected. |
| §6.3 twenty shares, variation and memory | **PASS, sampled** | Marker→chooser-start **120–166 ms** (includes input transport, excludes chooser animation). PSS KB at shares 1/2/5/10/20: **711090 / 704489 / 705834 / 710312 / 714885**; +1.48% from share 2, no accumulating image-sized rise. E/share-latency.json; E/share-memory.json. |
| §6.3 fresh Invite: both newcomer cards | **PASS** | E/fresh-invite-sheet-1.png … -6.png show Dodge and Flock with varying approved banners/texts. |
| §6.3 Invite after a positive run | **PASS** | E/after-run-invite-spotlight.png: last run 2, best 2; Spotlight and score text. |
| §6.3 `/get` on Android / messenger delivery | Pending direct link; **SKIP sending** | Google Messages/Gmail/WhatsApp sending is excluded by the owner's instruction. WhatsApp in-app received-link verification is consequently not claimed. |
| §6.3 / §9 circle launcher, themed icon, splash, Recents | Pending native checks | |
| §6.3 / §14 first-gate flow | **PASS, limited sample** | Fresh runs 1–3 only showed permitted normal hoops. In the later gate-3 run, Bullseye/Star Trail also appeared (both gate 0). All gate thresholds have focused automated coverage. |
| §14.6 RUN DEBUG counter | **PASS** | Actual row cycles 4→9→14→19→24→0, then 0→5→10→15→20. E/run-debug-gates-*.png; E/run-debug-runs-*.png. |
| §6.3 / §14.8 full-run analytics | **PASS live** | DebugView has `coins_per_hoop`, `perfect_rate`, `opening_end`, `speed_end`, `games_played`. The 30-point / 7-hoop run reports **3.57 coins/hoop**, including the versus win reward. E/debugview-coins-per-hoop.txt and PNG. |
| §6.3 / §15 live tuning, two launches | **PASS** | `coin_jar=9 [remote]`, curve opening `[[1,96],[100,72]]`; native hoop 1 = **96**, hoop 0 still 118. E/tuning-valid-page-*.png; E/tuned-opening-state.json. Native completion fixture gives **+9** and “20 fireflies · +9 coins”: E/tuned-jar-reward.json; E/tuned-jar-full-9.png. |
| §6.3 / §15 malformed JSON and restoration | Pending final validation | Only the two test parameters are changed; the pg salt and other keys are untouched. |
| §6.3 / §15 production/no flag | Pending release check | |
| §10.4 first-run hint, fixed hoop and frozen wait | **PASS** | E/first-run-hint.png: full warnings, chevrons, path/labels and hand; ring x290/opening118. After 5 s the run clock is zero, bird waiting, opponent zero. HUD clears the P1-corrected upper warning. |
| §10.4 first hoop flyability | **PASS** | First manual flying attempt: three timed taps, no bot/god, one perfect pass, score 2. Hoop 1 opening 88. E/first-hoop-manual-pass.png; E/first-hoop-manual-state.json. |
| §10.4 later-run reminder and pause | **PASS** | Run 2 has the hand/banner only after the wait; pause keeps `waiting=true`, clock 0; RESUME returns to the wait. E/run2-tap-reminder.png; E/waiting-pause-before-flap.png. |
| §10.4 real edge-back while waiting | **FAIL S8-13** | Starts the run and causes a death without a flap tap. E/waiting-after-edge-swipe.png; final plain-build reproduction below. |
| §13.5 music/lifecycle/ads/notifications | Pending scenario run | Native interstitial pauses music (`interstitial=true`, music false) and closing its × restores Home/music: E/interstitial-music.json. |
| §16.6 seamless loop, muted | Pending capture | Waveform/onset/click/listening validation cannot be claimed from silence. Existing builder's muted-phone measurements are in MUSIC.md. |
| §17.6 repeated big bonuses / visible clearing / portal entry | Pending final visual sample | Long native runs recorded repeated jar and piggy pickups; E/debugview-bonus-counts.txt. Jar reward completion uses the explicitly synthetic fixture described under Calls. |
| §17.6 bonus frequency | **Target NOT met, known** | Focused soak: 6.66 vs 7.87 big bonuses / 50 hoops, **−15.4%**, against ≤10%; the builder's larger soak reports ≈−18%. See QA P2 S8-11 and SPEC. Neither rate is labelled a pass. |
| §19 all 60 new items / all four tabs | **PASS visual sample** | E/skin-list.json; E/skin-*.png; E/skin-contact-{hat,gear,hoop,trail}.png; warmed trail captures. Compared with approved JS/Flutter contact sheet `SKINS_PORT.png`; no additional shape defect. |
| §19 heaviest look and each legendary, profile | Pending native measurements | |
| §20.5 Settings layout / all rows / footer | **PASS** | E/settings-device.png. Approved layout with the PRD's Redeem row replacing Rate. Footer reads installed metadata **v2.2.0 (9)**: the release version still needs the planned 2.3.0+10 bump. |
| §20.5 volume bar drag / audio tiles / rumble | **PASS dispatch** | In-app bar changes step through 0–8; music level restored to 25%, sound and rumble restored. Physical stream volume never changed. E/settings-volume-*.png; E/settings-level-restored-25.png; E/vibrator-settings-rumble.txt. Human haptic feel is not claimed. |
| §20.5 Support and Privacy links | **PASS** | Actual phone browser addresses `/support` and `/privacy`, correct live pages: E/settings-support-browser.png; E/settings-privacy-browser.png. |
| §20.5 Delete data text / back | **PASS, cancelled** | Confirmation names `flappyspikes.com/delete-data`; edge back cancels it without deleting. E/delete-data-confirm.png; E/delete-confirm-cancelled.png. |
| §20.5 Settings back | **PASS** | Required edge swipe returns to Home. E/settings-back-home.png. |
| §21.5 live opponent name / avatar | **PASS bird fallback** | Intro/loading, HUD and results names fit; generated digits remain whole; opponents use their own bird, not the person glyph. E/e2e_release/p22_live_versus_bar.png; E/vs20-*-waiting.png and -results.png. Real picture/account-link case is conditional and not claimed. |
| §21.5 account-link ghost cleanup | **SKIP account action** | No interactive Play Games sign-in/account switch. P1 held-identity and backend cleanup regressions pass locally; this does not certify the owner's account-link journey. |
| §22.6 Redeem row | **PASS destination, limited** | Opens Google Play's web redemption route in Brave, which asks for browser Google sign-in. Explicitly opening the installed Play handler delegates to the same web gate. Cancelled without sign-in/code. E/redeem-settled.png; E/redeem-explicit-native-settled.png. |
| §22.6 resume sync / Restore | **PASS** | `[IAP] sync` on browser/share returns; Restore shows spinner then “Nothing to restore.” E/manual-logcat.log; E/settings-restore-result.png; E/gift-popup-qa.png (the prior restore toast). |
| §22.6 real gift products/codes/orders/reinstall entitlement | **SKIP owner task** | No promo codes exist for this run; no purchase or redemption performed. |
| §22 gift popup edge-back | **PASS synthetic UI setup** | Displayed a coin gift using the native game's popup API; edge back closes it. E/gift-popup-qa.png; E/gift-popup-back.png. This does not test store grant delivery. |
| §23.5 native review sheet / 30-day return / submitted rating | **SKIP track/account task** | Requires a Play internal-track installation; this is a sideloaded tester build. No rating submitted. Focused trigger/cooldown/queue/run-5→6 tests pass. |
| §24.5 hour gap / five a day | **PASS controlled timestamps** | 59 min blocked; 60 min eligible through shows 2–5; show 6 blocked at 60 min. E/noads-hour-cap.json; E/noads-show-*-age-*.png. First session was ended by a relaunch; fixture `lastScore=10` makes the score guard eligible. |
| §24.5 No-Ads next run has no banner/interstitial | **PASS controlled ownership** | All 20 actual live runs had no banner/interstitial after setting the local test ownership flag. No purchase was made. |
| §25.4 twenty immediate deaths/restarts / small pool | **PASS** | Every START has a VS loading screen; every run reaches a waiting scene and a duel result. E/versus20.json; E/versus-contact.png; E/vs20-*.png; E/versus-log.txt. |
| §25.4 rematch rotation | Pending met-history audit | |
| §26.4 fresh Shop/Skins lock / blocked content / bright controls | **PASS input; known visual FAIL S8-12** | Both lock overlays show 25; back works and coin pill stays bright. Back artwork remains dim, confirming P2 S8-12. E/locked-shop.png; E/locked-skins.png. |
| §26.4 unlock from a completed best ≥25 | **PASS** | Native bot/god run ends at best **30**; both screens then open, no unlock popup; only the normal results level reward. E/unlock-results-30.png; E/unlocked-home.png; E/unlocked-shop.png; E/unlocked-skins.png. |

## S8-13 — major — Android edge-back starts the waiting run

- **PRD:** §10.1/§10.4: only the first playfield tap starts flight; back while waiting behaves as during a run. PRD-2.2 §8 keeps system back inert in run states.
- **Repro:** open a later VERSUS run; wait for the floating bird/reminder and clock 0. Execute the specified gesture, `adb -s 24191FDF6008ZD shell input swipe 2 1200 400 1200 150`, without any flap tap. Reproduced twice in the real app driven by the QA host bridge; a final plain-build reproduction is retained below.
- **Expected:** still waiting, clock 0, no `run_start`; first hint remains unseen if it was the first run.
- **Actual:** the first touch of the system gesture starts/flaps the bird. The run clock reaches **1.0655 s**, then the bird is dying with zero hoops. The first attempt also set `firstRunHintSeen=true` and saved a zero-point run.
- **Evidence:** E/run2-tap-reminder.png → E/waiting-after-edge-swipe.png; E/first-run-back-inert.png. Console snapshots before/after show `waiting:true, clock:0` → `waiting:false, state:dying, clock:1.0655153`.
- **Code clue, not a production fix:** `TapCatcher.onTapDown()` immediately calls `onPlayfieldTap()` before the OS cancels the pointer for a recognized back gesture. A later `handleSystemBack()` cannot undo the start. Unit/system-back method calls do not exercise this pointer sequence.

## Calls, limits and integration

- The main tester build uses `FS_TUNING=true` and the newly registered **“Pixel 6 e2e 2.3”** App Check token; its value is outside git (mode 600), and remains registered for the installed debug build.
- A temporary entry point calls the real `app.main()` and adds host setup/read-only state through `code_cache`. All product taps/swipes use adb, including the required edge gesture. The source is retained in E/ and removed from the delivered tree. Profile measurements use their separate existing harnesses, not this disk-polling bridge.
- Test setup includes bot/god, met-element and run-count controls, synthetic No-Ads ownership, a direct gift-popup display, stored popup-age fixtures, and a **paused jar/swarm-completion fixture** for the remote +9 payout. Do not mistake these for a real purchase, code grant, natural twenty-firefly collection, or a many-hour popup session.
- Native share latency is a transport-inclusive marker-to-chooser-launch measurement. It is not a frame-accurate measure of the fully animated chooser.
- The device is **90 Hz**; the 2.2 PERF table is a different **Pixel 8 at 60 Hz**. The skin baseline is the 2.2 look in this same 2.3 build, isolating art cost. Cross-device soak comparisons are descriptive, not evidence of a regression's cause.
- P2 fixes are not present at this tested revision. The default green automated gate does not certify S8-09…S8-12 or the documented §17 frequency shortfall as fixed.
- No gameplay/storage/module contract was changed, so SPEC/ARCH/Config/storage-key tables are untouched. No iOS/design/store screenshot changes are delivered.
- End-of-run cleanup and remaining owner checks are recorded after the final measurements.
