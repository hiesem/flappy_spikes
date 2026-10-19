# PRD-2.3 device QA — final Resume-2

2026-10-13, `p23-qadev`, tested revision **72188a1** (FIX3 and **2.3.0+10**), owner's **Pixel 6 / Android 17**, `<PIXEL6_SERIAL>`, 1080×2400, 90 Hz. Earlier retained visual/journey samples are from f5bf640; the interrupted P2 checkpoint was d273d04. This report replaces its secure-lock statuses with the resumed results and explicit owner tasks.

**Functional resume: PASS within the stated muted/account limits. Formal device sign-off: FAIL — S8-15's sampled §19 frame criterion and the already reported §17.6 bonus-frequency shortfall.** S8-14 is resolved on the actual Android edge gesture. No production fix is delivered by this tester.

The phone stayed unlocked; no power/sleep input, lock/unlock or screen-off scenario was performed. Media/ring/notification volume stayed muted. Notification permission (granted at arrival), icon style and soak brightness were restored; DND and stay-awake 15 were retained. Only debug notification broadcasts were sent. Share sheets were cancelled; no real purchase, rating, message, interactive sign-in, account change, deployment or push.

Raw evidence root (**E/**): `/home/killerhis/Projects/flappyspikes/.worktrees/briefs8/evidence/device/`. Native system/account sheets remain there. Only this report and three game images are committed.

## Gates

| Gate | Final result | Evidence |
|---|---|---|
| Current device e2e, live versus, `--no-uninstall` | **PASS 8 / 85 PNGs; live upload/read/delete** | E/resume2-e2e.log; E/resume2-e2e-release.tar |
| `flutter analyze`, restored source | **PASS clean** | E/resume2-final-analyze.log |
| Full `flutter test --concurrency=3` | **PASS 2,868 / 23 skipped** | E/resume2-full-suite.log |
| Focused P23/share, concurrency 3 | **PASS 359 / 20 skipped** | E/resume2-focused.log |
| Functions build + emulator tests | **PASS 144** | E/resume2-functions-build.log; E/resume2-functions-test.log |
| §19 profile | **FAIL sampled per-item criterion; heavy PASS** | E/resume2-skinperf-log.txt; table below |
| Short soak, 5 games | **PASS completion / memory / players / thermal; high Home CPU recorded** | E/resume2-soak/soak.json, soak.csv, logcat.txt, raw/; not a 20-game release-gate pass |

No tests or goldens were added/changed in this resume. FIX3's merged three regressions account for the full-suite increase from 2,865 to 2,868. The original e2e first-tap adapter already belongs to checkpoint 9a303b0. Temporary native QA instrumentation/receipt fixtures were restored out of the checkout; helper sources/APKs stay in E/.

## Final device checks

| PRD / item | Result | Evidence / qualification |
|---|---|---|
| §6.3 results share: native PNG + approved text/link | **PASS** | E/results-share-01.png … -20.png; image caches in E/share-cache-*.tar. No recipient was selected. |
| §6.3 twenty shares, variation and memory | **PASS, sampled** | Marker→chooser-start **120–166 ms** (includes input transport, excludes chooser animation). PSS KB at shares 1/2/5/10/20: **711090 / 704489 / 705834 / 710312 / 714885**; +1.48% from share 2, no accumulating image-sized rise. E/share-latency.json; E/share-memory.json. |
| §6.3 fresh Invite: both newcomer cards | **PASS** | E/fresh-invite-sheet-1.png … -6.png show Dodge and Flock with varying approved banners/texts. |
| §6.3 Invite after a positive run | **PASS** | E/after-run-invite-spotlight.png: last run 2, best 2; Spotlight and score text. |
| §6.3 `/get` on Android / messenger delivery | **PASS direct route; OWNER TASK message delivery** | E/resume2-get-route.png: actual Google Play Flappy Spikes/Duo Leads page. No message or recipient selected; messenger delivery remains excluded. |
| §6.3 / §9 circle launcher, themed icon, splash, Recents | **PASS** | Default circle retained; E/resume2-themed-flappy-shortcut.png; E/resume2-cold-start.mp4 (frame 009); E/resume2-final-recents.png. Whole bird in each. Android 17 Icons → Minimal was reverted to Standard; both temporary shortcuts were removed. |
| §6.3 / §14 first-gate flow | **PASS, limited sample** | Fresh runs 1–3 only showed permitted normal hoops. In the later gate-3 run, Bullseye/Star Trail also appeared (both gate 0). All gate thresholds have focused automated coverage. |
| §14.6 RUN DEBUG counter | **PASS** | Actual row cycles 4→9→14→19→24→0, then 0→5→10→15→20. E/run-debug-gates-*.png; E/run-debug-runs-*.png. |
| §6.3 / §14.8 full-run analytics | **PASS live** | DebugView has `coins_per_hoop`, `perfect_rate`, `opening_end`, `speed_end`, `games_played`. The 30-point / 7-hoop run reports **3.57 coins/hoop**, including the versus win reward. E/debugview-coins-per-hoop.txt and PNG. |
| §6.3 / §15 live tuning, two launches | **PASS** | `coin_jar=9 [remote]`, curve opening `[[1,96],[100,72]]`; native hoop 1 = **96**, hoop 0 still 118. E/tuning-valid-page-*.png; E/tuned-opening-state.json. Native completion fixture gives **+9** and “20 fireflies · +9 coins”: E/tuned-jar-reward.json; E/tuned-jar-full-9.png. |
| §6.3 / §15 malformed JSON and restoration | **PASS** | E/resume2-malformed-state.json; E/resume2-malformed-tuning-page-2.png visibly shows `curve_opening … [default*]`. Cloud defaults restored at version 10; E/resume2-remote-restored.txt confirms unrelated keys/salt unchanged. Final client activation: E/resume2-final-client-defaults.json. |
| §6.3 / §15 production/no flag | **PASS flag-off build/UI** | Current revision release APK, neither tuning nor App Check debug defines: E/resume2-production-noflag.apk; E/resume2-build-release.log; E/resume2-release-title-longpress.png. Long press opens no panel. Flag-off no-tuning-backend regressions pass; this is not a packet-level network capture. |
| §10.4 first-run hint, fixed hoop and frozen wait | **PASS** | E/first-run-hint.png: full warnings, chevrons, path/labels and hand; ring x290/opening118. After 5 s the run clock is zero, bird waiting, opponent zero. HUD clears the P1-corrected upper warning. |
| §10.4 first hoop flyability | **PASS** | First manual flying attempt: three timed taps, no bot/god, one perfect pass, score 2. Hoop 1 opening 88. E/first-hoop-manual-pass.png; E/first-hoop-manual-state.json. |
| §10.4 later-run reminder and pause | **PASS** | Run 2 has the hand/banner only after the wait; pause keeps `waiting=true`, clock 0; RESUME returns to the wait. E/run2-tap-reminder.png; E/waiting-pause-before-flap.png. |
| P2 S8-09…S8-13 device rechecks / first-START sync feel | **PASS fixes; native fixtures and regressions** | See the separate recheck table below. E/resume2-native-p2.json; E/resume2-launch-sync.json. The delayed receipt is a fake store with the native app/banner stack; no purchase or real entitlement delivery. |
| §10.4 real edge-back while waiting | **PASS FIX3 / S8-14 resolved** | Actual `input swipe 2 1200 400 1200 150` in FREE FLY and live VERSUS leaves `waiting=true`, clock 0. E/resume2-s14-edge.json; E/resume2-s14-versus.json; [key capture](device/resume2-waiting-back.png). A separate playfield tap starts flight. |
| §13.5 music/lifecycle/ads/notifications | **PASS foreground muted dispatch; owner audio/lifecycle limits** | Five notification and five short MEDIA broadcasts on each of Home/run/results: 30/30 music on afterward, zero own-music latches. Continuous log has all 30 native ding starts and 15 notification end/resume pairs (max 1 ms). Five shade + five 10 s Home/background returns also recover. E/resume2-music-final-continuous.log; E/resume2-music-final-music-state.json; E/resume2-music-state.json. Billing/ad checks below; screen-off omitted by hard rule. |
| §16.6 seamless loop, muted | **OWNER TASK audible/seam recording** | All streams stayed muted. A silent playback capture cannot certify waveform/onset/click/listening criteria; retained mixer-counter results are in MUSIC.md. Hourglass and revive-duck wraps, headphones and listening remain owner checks. |
| §17.6 repeated big bonuses / visible clearing / portal entry | **PASS sampled native entries** | Three recordings begin before the force/spawn. E/resume2-portal-{1,2,3}.mp4; E/resume2-portal-states.json (maximum open-big count 1); E/resume2-portal-entry-contact.png; [entry frames](device/resume2-portal-edge.png). Reviewed edge entry of beam/particles, no visible pop-in, second open big bonus or clearing in this sample. Earlier repeated pig/jar samples retained. |
| §17.6 bonus frequency | **Target NOT met, known** | Focused soak: 6.66 vs 7.87 big bonuses / 50 hoops, **−15.4%**, against ≤10%; the builder's larger soak reports ≈−18%. P2 S8-11 waiting-path fix is merged; the builder re-soak is still **−17.6%** (6.64 vs 8.06 / 50 hoops, 1,600 runs), per SPEC. The resume focused tiny sample is −20.8%; its sample guard does not certify the ≤10% target. Neither rate is labelled a pass. |
| §19 all 60 new items / all four tabs | **PASS visual sample** | E/skin-list.json; E/skin-*.png; E/skin-contact-{hat,gear,hoop,trail}.png; warmed trail captures. Compared with approved JS/Flutter contact sheet `SKINS_PORT.png`; no additional shape defect. |
| §19 heaviest look and each legendary, profile | **FAIL literal frame-rate criterion: S8-15** | Baseline, heavy combination and every new legendary each ran 120 s in profile mode. Heavy passes; six individual phases have rare >16.7 ms frames above the baseline rate. Full table below; E/resume2-skinperf-log.txt; E/resume2-skinperf-summary.json. |
| §20.5 Settings layout / all rows / footer | **PASS** | Approved layout retained; native installed footer now **v2.3.0 (10)**. E/resume2-final-settings.png; original E/settings-device.png covers row/layout checks. |
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
| §25.4 rematch rotation | **PASS exact run-id/LRU audit** | Public service calls prime 23 usable non-own run IDs; four actual STARTs each choose exactly `metBefore[0]`, remove it there and append it to the end. Every START has a VS scene and rival. E/resume2-rematch-audit.json; E/resume2-rematch-log.txt. Original 20 rapid STARTs remain the broader UI sample. |
| §26.4 fresh Shop/Skins lock / blocked content / bright controls | **PASS native bright art and retained lock flow** | Native locked/open Shop and Skins back pixels both `(236,0,140,255)`. E/resume2-bright-back-pixels.json; E/resume2-{locked,open}-{shop,skins}.png; [key capture](device/resume2-locked-shop.png). Back gestures work. Earlier fresh lock/input and completed-best-30 silent unlock samples retained. |
| §26.4 unlock from a completed best ≥25 | **PASS** | Native bot/god run ends at best **30**; both screens then open, no unlock popup; only the normal results level reward. E/unlock-results-30.png; E/unlocked-home.png; E/unlocked-shop.png; E/unlocked-skins.png. |

| Additional resumed check | Result | Evidence / limit |
|---|---|---|
| Native Play Billing sheet, cancel only, music | **PASS 5 native sheets cancelled; music on afterward** | E/resume2-billing-cancel.json; E/resume2-billing-cancel-log.txt. No confirmation/payment control pressed. |
| Current native test interstitial music | **PASS native test ad: music held during, on after close** | E/resume2-interstitial-music.json and .log; no creative content tap. |
| Final installation/settings | **PASS normal debug 2.3.0+10 installed; restored settings/defaults** | E/resume2-final-device.txt; E/resume2-audio-after.txt; E/resume2-final-client-defaults.json. |

## S8-09…S8-14 rechecks

| Finding | Result on resumed revision |
|---|---|
| S8-09 periodic/run-end playtime | **PASS native**: waiting counted/persisted **13/10**, **26/20**; flight **42/40**; results **43/43** before NEXT. Four finished runs throughout waiting/flight, five at results. All gaps ≤10 s; E/resume2-native-p2.json. |
| S8-10 premature preload | **PASS native**: no request with four finished runs during the fifth flight. Instrumented native request at **11:22:13.925**, after the forced death at **11:22:13.218**; it becomes eligible at the fifth run end. E/resume2-native-p2-log.txt. |
| S8-11 cooldown waiting | **PASS regression** over 60 seeds; native one-open-bonus and three portal-entry samples pass. Debug force is setup and does not prove an optional random cooldown draw by itself. The separate frequency target is still unmet. |
| S8-12 back brightness | **PASS native** locked/open comparison for Shop and Skins, plus actual back gesture; exact RGBA above. |
| S8-13 launch ownership / first-START wait | **PASS native app/banner + delayed-store fixture**: START remains on Home while the store is held; reply at about 0.47 s reaches a waiting run by **0.76 s**, No Ads true, no banner. Never-answering query reaches the waiting run by **1.77 s** with its banner, without a hang. Times include adb transport/polling (initial input ≈0.23 s); the configured game-time budget is 1.5 s. Real restored receipts remain a store/owner task. E/resume2-launch-sync.json and .log. |
| S8-14 edge-back started flight | **RESOLVED FIX3**: both actual FREE FLY and live VERSUS edge swipes retain `waiting=true`, clock **0**, and opponent score **0**. The separate playfield tap starts it. The prior repro/finding is preserved in E/resume2-report-before.md. |

## S8-15 — minor — sampled legendary phases exceed today's rare slow-frame rate

**PRD §19.6:** each new legendary, like the heavy look, must keep the existing frame budget with no extra frames over 16.7 ms beyond today's rate.

**Repro:** upload-signed profile `integration_test/skins_perf_main.dart` on this Pixel 6. Baseline, heavy Sunburst + Disco + Aurora + Supernova, and all eight new legendaries each run **120 s**, trail forced active, real rendering/autopilot, no ads/services, separate `skinperf.` preference prefix. The temporary harness changes only the baseline duration; `SKINPERF_SHORT=120` extends all individual phases. Source restored afterward.

**Expected:** each phase's >16.7 ms rate ≤ the baseline. **Actual:** heavy, Crystal and Disco meet it; Planet, Sunburst, Atom, Aurora, Supernova and Paint exceed the baseline **11/10,664 = 0.103%**. These are rare misses, not a demonstrated art-code cause. Courses/activities vary between phases, and this single run does not establish a statistically isolated regression. The literal sampled criterion is failed rather than silently relaxed.

| Phase (120 s each) | Frames | Build / raster p90 ms | >16.7 ms | Verdict versus baseline |
|---|---:|---:|---:|---|
| baseline | 10,664 | 5.56 / 7.56 | 11 (0.10%) | baseline |
| heavy | 10,742 | 5.89 / 10.24 | 4 (0.04%) | PASS rate |
| planet | 10,585 | 5.96 / 7.84 | 22 (0.21%) | FAIL rate |
| sunburst | 10,599 | 5.90 / 8.30 | 25 (0.24%) | FAIL rate |
| crystal | 10,763 | 3.56 / 10.90 | 5 (0.05%) | PASS rate |
| atom | 10,697 | 5.96 / 8.90 | 12 (0.11%) | FAIL rate |
| disco | 10,716 | 5.75 / 8.02 | 9 (0.08%) | PASS rate |
| aurora | 10,584 | 5.87 / 7.89 | 19 (0.18%) | FAIL rate |
| supernova | 10,682 | 5.89 / 9.73 | 13 (0.12%) | FAIL rate |
| paint | 10,619 | 5.87 / 7.93 | 13 (0.12%) | FAIL rate |

All phases' build/raster p99 values are below 16.7 ms; worst individual durations range 21.98–76.87 ms. Evidence: E/resume2-skinperf-log.txt, E/resume2-skinperf-summary.json. The established harness measures whether **either build or raster** exceeds 16.7 ms; the soak separately reports total frame span. No production patch or threshold/golden rewrite is made here.

## Short soak and the 2.2 comparison

Unchanged `SoakDriver`, profile `FS_SOAK`, **5 games / 70 s holds**, 10 hoops each, the bonus path in game 3 and level reward path in game 4. The external copy of `tool/soak.py` only targets this serial, the saved APK and E/ output. Command: `python3 -I E/resume2_soak.py --label p23-final --serial <PIXEL6_SERIAL> --no-build --games 5 --hold 70`. A labelled Google test interstitial after game 5 was closed through its native **Sluiten** control (the post-run wall time includes waiting for that close). No ad content/Install tap.

Start skin **30.49 °C**, battery **27.6 °C**, thermal 0. Brightness manual 128 for measurement, restored to **auto (1), saved value 44**. Stay-awake 15 unchanged. Output: E/resume2-soak/ (JSON/CSV/logcat/raw dumps).

| After game | PSS MiB | Native players | Home CPU, one core % | Run p90 ms / >12.5 ms | Thermal |
|---|---:|---:|---:|---:|---:|
| 1 | 444.5 | 93 | 91.8 | 12.99 / 13.5% | 0 |
| 2 | 446.9 | 93 | 89.0 | 14.50 / 26.0% | 0 |
| 5 | 479.8 | 93 | 88.1 | 14.48 / 30.8% | 0 |

PSS **446.9 →479.8 MiB, +7.36%** from game 2 to 5 (within 10%); native players **93 at every Home hold**, 33 pools /92 pooled voices; position polling **0/s**; thermal **0**. Long stops include `perfect_3` **2,400–2,403 ms** and `lv_claim` **1,501 ms**. No accumulating unowned players observed.

[2.2 final-fix baseline](../p22/PERF.md#2e-final-fix-round-r1-b-s7-19-session-sound-set-re-soak-2026-10-12-g7-fin-soak), game 2→5: PSS **454.9→487.1 MB (+7.1%)**, players **93**, Home CPU **52.0→49.0%**, run p90 **14.48→15.00 ms**, slow **25.0→23.1%**. Current game 5: p90 **14.48 ms**, slow **30.8%**, Home CPU **88.1%**. **Home CPU is high** and is not called a pass/improvement. This is Pixel 6 /90 Hz versus Pixel 8 /60 Hz, with different course/ad grace/temperature; comparison is descriptive, not causal. Five games cannot certify the game-20 frame criterion or long-session memory behaviour.

## Calls, limits and integration

- Resume-2's **foreground-scene music scope** replaces the blocked lock/screen-off attempts; the longer original background/scenario-soak cases are listed below for another session. The incorrect-action initial batch and stale/background adapter snapshots are not accepted as passes. The first RC visual attempt hit MUSIC LOG because its QA coordinates used the wrong strip height; the corrected page is the evidence cited here. Cloud restore is confirmed after both attempts. The SDK fetch interval is one minute; after the soak, two later launches activated the restored values. The old report described notification permission as denied, but the actual pre-resume captures show granted; final cleanup follows the captures.
- The actual app is driven by adb taps/swipes. The temporary bridge provides state and fixtures through `code_cache`; publication is atomic. Receipt and blocked-store tests use a fake store with native game/banner services, not a purchased entitlement. Rematch priming uses `searchForStart()`/`takeOpponent()`; no pool documents are edited. Bot/god, best/run counters and force queues are explicit test setup.
- Media is muted: the Android playback list hides the ding early (notification holds are ≈180 ms), and may hide short MEDIA entirely. Recovery logs establish dispatch/state, not audible duration/quality or Spotify suppression. The separate audible tests remain unclaimed.
- Share memory/latency and earlier full visual coverage remain the initial sampled results; native latency includes transport and does not measure chooser-animation completion. No recipient was selected. New Settings/version and all previously secure-lock-blocked permitted checks are covered above.
- The §17.6 frequency target remains **FAIL, known**: builder's fixed waiting-path re-soak **6.64 versus 8.06 bonuses /50 hoops, −17.6% (1,600 runs)**, against ≤10%. This resume's focused tiny sample is −20.8% and is not a large re-soak. Report-and-continue is explicit in §17.6; no extra code defect is inferred from frequency alone.
- Integration must retain FIX3's tap-up start and the P2 persistence/preload/brightness/ownership fixes. S8-15 needs performance assessment with comparable courses/device conditions; do not turn these measured failures into passes by changing a tolerance. High Home CPU and the short soak's scope remain visible risks.
- No production source, tests, SPEC/ARCH contract, storage key, Config knob, iOS/design/store screenshot or backend deployment is changed by this tester commit. Cloud defaults/salt are restored; the App Check token remains registered (see Firebase console), with value only outside git.

## Owner tasks / checks not done

1. **Lock/unlock and every screen-off lifecycle case**: omitted by the new hard rule, including notification/shade returns that require a locked screen. No request to lock this phone is made.
2. **Audible music/seam/own-music/headphone/haptic checks**: media stays muted. Three loop wraps, Hourglass and revive-duck seams, an audible heads-up, Spotify suppression/recovery, and human rumble feel need a later owner session. Headphones were unavailable.
3. **Long background and music scenario soak**: original 10 min /≥30 min returns and 30-minute scenario cycling were not repeated in the foreground-only resume. Short 10 s returns and the requested five-game soak are complete; a 20-game performance gate remains separate.
4. **Message delivery / received WhatsApp link**: only native share sheets and direct `/get` route were checked; all sheets cancelled. No Messages/Gmail/WhatsApp sending.
5. **Real promo codes/orders/reinstall entitlement**: codes were not available for this run. No code redeemed or purchase confirmed; fake launch grants certify the ordering fixture only.
6. **Native in-app review/30-day return/submitted rating**: requires a Play internal-track installation, whereas this run leaves a sideloaded debug build; no rating submitted.
7. **Real Play Games picture/account-link conflict/ghost cleanup**: no interactive sign-in/account switch or owner-account changes. Bird fallback/name fit are native passes; cleanup/identity cases remain automated coverage.

**Final state:** Normal **debug 2.3.0+10**, `FS_TUNING=true` with the registered Pixel 6 App Check token, no e2e/soak/QA bridge target, verified on Home with **FREE FLY** restored; then force-stopped to remove scheduled reminder alarms, leaving the phone unlocked on its launcher. Sound/rumble ON and in-app music 25% retained; physical media/ring/notification mute remains true at volume 0. Notification permission restored **granted/user-set**, matching the actual pre-resume permission capture, icon Standard/circle and original Home layout restored, brightness auto, DND 1 and stay-awake 15 unchanged. Cloud defaults restored at version 10 and activated in the client. E/resume2-alarms-after-final-stop.txt records the reminder cleanup. Copied signing files deleted; no push.
