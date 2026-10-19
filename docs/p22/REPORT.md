# PRD-2.2 build report: 2.2.0 (9), internal test build

This is the report of the unattended build of `PRD-2.2-update.md`, started on the owner's "go" on 2026-10-12.
- **Branch:** `feat/2.2`, cut from `feat/ads-mediation` at 120ec25. All commits are local and **not pushed**.
- **Run log:** `.worktrees/briefs7/RUNLOG.md` in the workspace, outside the repo.

**Orchestration:**
- **Orchestrator:** Claude Opus 5.5.
- **Builders:** Opus 5.5 built the hard packages. Claude Haiku 5.5 at effort max built the well-defined ones: §8, §9 and §32.5; §12, §20 and §31; and the P3 fixes.
- **Tester:** GPT-6.1 Sol, through codex. It ran QA rounds P1, P2 and P3 and the final device playtest on the Pixel 8.

## 1. Result

All 30 items of PRD-2.2 §1 are built and merged on `feat/2.2`.

**2.2.0 (9) is rolled out on internal testing only**, at 09:38. It shows as "Available to internal testers". It is **installed on the owner's Pixel 8 from the Play Store**, and **a live versus match was played on that Play-installed build**: VS intro, the run, and YOU LOSE (0 vs 5) against the pool opponent "E2E bot". Screenshots are in `.worktrees/briefs7/release/play_06…11`.

Nothing went to closed or open testing or production, and the store listing was not changed.

**Gates that still fail** are listed in §2. Per PRD §6, they are reported here and the build was still delivered:
- the §33.6 frame-time criterion, caused by the gameplay banner;
- real ads on the owner's Pixel with the Play-signed build. See §7, item 1.

## 2. Gates

| Gate | Result | Evidence |
|---|---|---|
| `flutter analyze` | PASS, no issues | final gate @136bb63 |
| Full `flutter test` | PASS: **2489 passed**, 3 skipped (the existing opt-in emulator tests) | final gate @136bb63 |
| Backend `npm --prefix functions test` | PASS: **121 passing** | |
| Device e2e on the Pixel 8 | PASS, **8/8**: mode switch, FREE FLY, live VERSUS, journey, elements, six rides, reminders, upload/delete | `docs/p22/QA_DEVICE.md` |
| Feel checks by Sol on the Pixel 8 | PASS for every item. Each one, with its evidence, is in QA_DEVICE.md. | `docs/p22/QA_DEVICE.md`, `docs/p22/device/` |
| §8 back gesture with gesture navigation | PASS after the final fix, 34/34. One edge swipe or the back key closes the top menu or popup. Home and runs ignore it, and the app never closes. | `docs/p22/device/back_fix.md` |
| §7.5.7 banner performance gate | PASS: 0.08 % janky frames with the banner and 0.11 % without, with no bursts | `docs/p22/ADS.md` |
| §33.6 soak, 20 games: memory | PASS: +9.9 % from game 2 to game 20 (limit +10 %) | `docs/p22/PERF.md` §2e |
| §33.6 soak: native audio players flat | PASS: 93 at every hold. 2.1 grew 36 → 78. | PERF §2e |
| §33.6 soak: Home idle CPU below 2.1 | PASS: 49–55 % of one core (2.1: 80–84 %), 0 position polls per second | PERF §2e |
| §33.6 soak: thermal | PASS: status 0 throughout | PERF §2e |
| §33.6 soak: frames at game 20 same as game 1 and no worse than 2.1 | **FAIL**: p90 12.8 → 14.7 ms and slow frames 11.7 → 25.9 % (2.1 at game 20: 13.7 ms, 20 %). See §6. | PERF §2e |
| Live versus on the Play-installed internal build | **PASS** | `.worktrees/briefs7/release/` |

**QA rounds:**
- **Sol P1:** 6 findings (S7-01–06), all fixed.
- **Sol P2:** 7 findings (S7-07–13), all fixed. Two of the WP-V2 builder's calls were reverted because they went against the PRD: FEVER again lasts until the streak breaks, and ×3 fire no longer blocks FEVER rings.
- **Sol P3:** 3 minor findings (S7-14–16), all fixed. It also produced a coverage table of every §1 item against its tests (`docs/p22/QA_P3.md`).
- **Device playtest:** 3 findings. S7-18 (token in a debug log) and S7-20 (Android back) are fixed. S7-19 is the frame criterion above.

## 3. Store prices (§32), done first

- **Calculation:** `tools/pricing/pricing.py` uses the new rule with exchange rates fetched on 2026-10-12 from open.er-api.com. Its tests are `tools/pricing/test_pricing.py`, 8 tests, all OK.
- **Saved in Play Console:** all 5 products in 174 countries.
- **Verified:** after saving, every price editor was reopened and compared with the CSV. All 5 products match **174/174**, and Play rejected nothing (`tools/pricing/PLAY_VERIFY_2026-10-12.md`).
- **Price table:** the new 20-market table is in PRD-2.2 §32.3 and `tools/pricing/top20_2026-10-12.md`. It shows $/£/€ 0.99, 8.99, 14.99, 79.99 and 2.99 for NO ADS.
- **Moved since the 10-07 draft:** Mexico (MX$169 / 279 / 1 469 / 59), Taiwan (NT$2 560), India (₹1 499) and Türkiye (₺3 949.99).
- **Coarse local price steps:** in a few currencies the steps are far apart, so the 1 000-coin price lands well off USD × rate: DKK 9 (+36 %), NGN 900 (−32 %), CHF 1.00 (+22 %) and JOD 0.99 (+41 %). NO ADS in HKD is 28 (+19 %). **The owner may want to look at these.**
- **Not done:** the §32.4 device check of the Shop showing €0.99 and so on was not done separately. The Play build loaded all 5 products (`[IAP] query 5: found 5`).

## 4. Live changes made by the run (all allowed by §6)

- **Store prices:** see §3.
- **AdMob:**
  - New ad units: "Banner - gameplay" `ca-app-pub-2660521344509391/8797133596` and "Interstitial - after run" `ca-app-pub-2660521344509391/1357627279`.
  - New mediation groups: "Flappy Spikes Android - Banner" `7736442819` and "Flappy Spikes Android - Interstitial" `5294815708`, each with AdMob Network plus Unity Ads bidding.
  - Unity: the existing `Banner_Android` and `Interstitial_Android` bidding placements were reused. Nothing was created in Unity.
  - Test device "Owner Pixel 8" added in AdMob, by advertising ID.
- **Play declarations, saved:**
  - Ads: yes.
  - Advertising ID: used, for analytics and advertising.
  - Data safety: added device or other IDs (collected and shared, for advertising and analytics) and approximate location (for advertising).

  After that, the `AD_ID` `tools:node="remove"` block was removed from the manifest.
- **Versus backend:**
  - The Cloud Functions are deployed. They check timeline v2 value sums, reject v1 uploads, and cap bonus entries at 80 and puzzle-completion entries at 500.
  - The four 2.1 pool runs were converted to v2 in place. Nothing was deleted, and a second run shows all 4 as already v2.
  - A separate test account, "RapidParrot411", seeded five new runs: 8, 16, 28, 45 and 70 hoops, worth 27 to 293 points, at levels 1 to 4.
  - The pools now hold 9 runs, all v2.
- **Release:**
  - The 2.2.0 (9) AAB went into the internal-testing draft, replacing bundle 8. Release notes are en-US, and the release is rolled out to internal testing.
  - Play reported an `AD_ID` error for an older active build, most likely the pre-ads production 2.0.0. Bundle 9 itself contains the permission. The agent chose "Release without permission" for this release only.
  - **Nothing was sent for review.** Publishing overview still lists 2 changes waiting for the owner: the Ads declaration and Data safety.
  - The tester list "Flappy Spikes internal" holds killerhis@gmail.com.
- **Pixel 8 install:**
  - The local build was uninstalled, because Play signs with the app-signing key and local builds use the upload key.
  - 2.2.0 (9) was installed from the Play Store.
  - On first launch the notification prompt got "Don't allow", the same as before.
  - The consent form showed the Flappy Spikes logo. **No ad consent was given on the owner's behalf:** the run chose "Learn More → Confirm choices" with every consent off. The owner can change this under Settings → Privacy options.
  - The phone's "stay awake while charging" setting is restored to its old value (15).

## 5. Calls the run made (judgement calls, all logged)

- **§7.5 lowered strip:** `viewHeight` is the visible height + 20 pt, and the camera crops the bottom 20 pt. The numbers match the approved mock exactly, and none of the ~200 `viewHeight` reads had to change. The banner is 64 dp on the Pixel 8, so the visible run height is 661 pt, not the PRD's estimated 663.
- **§13.2 score size:** a 3-digit score at 125 pt is 203 pt wide, wider than the 183 pt circle. The font now uses the largest size up to 125 pt at which the widest number of that digit count fits, so 3-digit scores shrink a little.
- **§13.5 bonus caps:** bonus entries are capped at 80. Puzzle-completion entries get a new flag (16) with a cap of 500 (250 × 2 with the chick), so legitimate puzzle runs are not rejected.
- **§2 Home layout:** at 568 pt the emblem shrinks to about 0.71 to fit the mode button. START moved from 390 to 403 pt at 711.
- **§28 audio:** the game never requests audio focus, because that would duck Spotify. It detects other apps' audio from the active players, plus a stricter list while its own sounds play. Details are in `docs/p22/ADS.md`. A real phone call and Spotify were not tested; a ringtone, a timer and a test media track stood in.
- **§8 back:** while a menu or popup is open, the navigation bar is shown see-through, so one swipe closes it. With the bars hidden, Android spends the first swipe on showing them. Side effect: the gesture handle is visible over the bottom spike strip on menu screens only.
- **§33 audio:** our own fixed-size player set per sound replaces `AudioPool`, as the investigation recommended. No fork and no package switch. A session sound set (25 pools) plus the 8 core pools are created once; all other pools last one run.
- **§33 idle:** untouched menus draw at 30 fps after 2 s, which is how Home CPU fell from 84 % to about 50 %.
- **§7.6 interstitial:** it is only preloaded from game 4 on, because the first 3 runs never show one.
- **§25:** the portal ring is fixed at 118 pt. Before, it shrank like a normal ring. Saw rings needed no extra opening: all autopilot gates pass with 0.
- **§26:** piggy coins are 45 pt apart, as in the approved mock. They used to be about 27 pt.
- **Debug and profile signing:** local debug and profile builds are signed with the upload key when `key.properties` is present, so they install over the owner's app.

## 6. The open performance criterion (owner decision)

Run frame times get worse after the first game: p90 12.8 → 14.7 ms, slow frames 11.7 → 25.9 %.

**Cause:** the cause is the gameplay banner from §7.5, not something that builds up over the session.
- The banner is a native Android view. In Flutter 3.47 the Android main thread is also the game's frame thread.
- Each banner redraw costs about 7 ms on that thread. Google's test ad animates in 0.6 s bursts every 5 s.
- A 10-game diagnostic soak without the banner had flat frame times: p90 11.4–13.3 ms, all under 2.1's game-20 value.

§7.5.7 says to ship with the banner. The options are:
- accept the cost;
- measure again with real ads, which are often static;
- try a different banner composition mode, which needs a spike first.

## 7. Open items for the owner

1. **Real ads on your Pixel 8 with the Play build. Don't tap them.**
   - AdMob's test-device hash is derived from ANDROID_ID, which Android keys per signing key. So the Play-signed build (hash `C8EDCAE2408A20189883DF41E7E998DA`) is not covered by the upload-key hash in the code.
   - **The code fix** (commit `ad5f31c`) is on `feat/2.2` but **not in build 9**.
   - The AdMob console test device "Owner Pixel 8", registered by advertising ID, had not taken effect 5 minutes later. It may need more time.
   - Mediated Unity ads are never test ads.
   - The next build carries the fix.
2. **Send the 2 pending changes for review** (Ads declaration and Data safety) in Play Console → Publishing overview, when you are ready for a public release.
3. **The `AD_ID` error on the older active build** clears once a build with the permission reaches production.
4. **Repo size before a push:** the QA evidence committed under `docs/p22/` (screenshots, screen recordings, raw performance dumps) is about **160 MB**. Consider moving `docs/p22/device/` and `docs/p22/perf/*/` out of the repo, or into Git LFS, before pushing `feat/2.2`. The branch is unpushed, so its history can still be rewritten. *(Run 17, 2026-10-20: the raw captures in `docs/p22/device/` were removed, see git history; `docs/p22/perf/` stays.)*
5. **Still owner-only (§7.2):**
   - the US state regulations message in AdMob;
   - the Unity payout profile;
   - DT Exchange (pending) and Moloco (after launch);
   - approving the 2.2 commits and any push.
6. **The store listing** (release notes and screenshots) is yours, and the store screenshots were not regenerated. The download size for new installs rose from 12.5 MB to 25.4 MB; Play showed a warning.
7. **The coarse price outliers** listed in §3.
8. **Not tested on the device:** 3-button navigation, a real phone call, Spotify, and the iOS side (iOS is paused; Android-side changes are noted in `PORT-IOS.md`).

## 8. Incident

`flutter test integration_test` **uninstalls the app after the run by default**.
- **What happened:** the §13.5 seeding run (about 05:50) uninstalled the app on the Pixel 8. That wiped the local data of the 2.1 test install: coins, skins and local bests.
- **What was not affected:** server-side data (leaderboard, versus runs) and Play purchases.
- **Since then:** every later device test command used `--no-uninstall`, and this is saved as a rule for future sessions.
- **Context:** the Play-Store install at the end needed an uninstall anyway, because of the different signing keys, so the local data would not have survived the deliverable step either. It should still have been announced first.

## 9. Documents

- `docs/p22/PERF.md`: performance baseline and every soak.
- `docs/p22/ADS.md`: ads, the `viewHeight` audit and the audio-focus approach.
- `docs/p22/QA_P1.md`, `QA_P2.md`, `QA_P3.md` and `QA_DEVICE.md`: the QA rounds.
- `docs/p22/device/back_fix.md`: the back-gesture fix and its device checks.
- `SPEC.md` (DEVIATION notes per section), `docs/gameplay-v2/ARCH.md` and `PORT-IOS.md`.
