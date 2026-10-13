# PRD-2.3 build report: 2.3.0 (10)

**Run:** 2026-10-13, unattended, run under PRD-2.3 §0. The owner paused it once, and it waited once for the owner's "go" after a memory kill.
**Branch:** `feat/2.3`, local commits only, **not pushed**.
**Released:** **2.3.0 (10) on Play internal testing** (10:41). It is the tester build, built with `FS_TUNING=true`.
**Installed from Play on the Pixel 6:** versionCode 10, installer `com.android.vending`.
- Launcher shows the 17C icon; Home shows FLAP FAST, FLY FAR.
- The debug panel opens. The TUNING page shows "Fetch: success" and every key as `default`: the first fetch is activated at the next start (§15.2).
- Consent was given as no consent on your behalf: everything off, including the legitimate-interest toggles. Notifications were denied.
**Run log:** `.worktrees/briefs8/RUNLOG.md`. Raw evidence is in `.worktrees/briefs8/evidence/` (outside git).

## Gates

| Gate | Result |
|---|---|
| `flutter analyze` | clean |
| `flutter test` (full suite, feat/2.3 tip) | **2,868 passed**, 23 skipped (the skips existed before this run) |
| `npm --prefix functions test` | **144 passing** |
| Autopilot playability gate (§14.4) | passes with the PRD default opening 88 → 66; no fallback set needed (`REPORT_tune.md`) |
| Device e2e on the Pixel 6, including live VERSUS | **8/8 pass** |
| Website §6.2 domain checks (live, through Cloudflare) | **59/59 pass** |
| Sol QA | Code rounds P1 (8 findings) and P2 (5 findings), all fixed and re-verified. Device round: 2 findings (S8-14 fixed; S8-15 minor, reported). See `QA_P1.md`, `QA_P2.md`, `QA_DEVICE.md` |

## What was built (PRD §1 items 1–25)

Every summary item is implemented and tested; the coverage table is in `QA_P2.md`.

**Share and invite (§2–§4)**
- Spotlight and new-player share cards, approved texts, `flappyspikes.com/get` links, Invite tile.

**Website (§5, §11, §12)**
- flappyspikes.com is live: every page, the updated privacy policy, `/delete-data`, `/support`, 404, `app-ads.txt`, the SEO/GEO work and the five content pages.

**App (§9–§26)**
- §9: 17C launcher icon (adaptive + themed + iOS), splash, Play listing icon.
- §10: waiting start, fixed hoop 0, first-run hint, tap reminder.
- §12: the tagline is now "Flap fast, fly far".
- §13: music guard and watchdog (`MUSIC.md` has the root cause).
- §14 and §15: economy and difficulty rebalance, and remote tuning: 90 keys, TUNING page, `tool/tuning_sync.dart` (`TUNING.md`).
- §16: seamless 56-bar OGG loop. Step 1 failed with a 264.5 ms gap at the wrap, so Android music now plays through `just_audio` (−0.8 ms at the wrap).
- §17: one big bonus on screen.
- §18: new-player ad grace.
- §19: 60 new skin items, ported 1:1 (`SKINS_PORT.png`).
- §20: new Settings screen.
- §21: versus names, pictures and looks. Firebase Storage, `pg` self-match guard with the salt in Remote Config.
- §22: gift codes. The gift products are active in Play.
- §23: rating prompt.
- §24: No-Ads popup schedule.
- §25: versus never a silent solo.
- §26: Shop/Skins unlock at a best of 25.

## Live changes made by the run

**Firebase**
- Hosting deployed, with custom domains `flappyspikes.com` and `www`.
- Default Storage bucket `flappy-spikes-a2b55.firebasestorage.app` created (EUROPE-WEST1). The functions service account got `roles/storage.objectAdmin` on it.
- Storage rules, Firestore rules and functions deployed (`onPlayerRunWrite`, `deleteMyData`, `sweepPools`), from the final tip.
- Remote Config published: 90 tuning defaults plus `versus_pg_salt`, a random 32-byte value that is never in the repo.
- App Check debug token "Pixel 6 e2e 2.3" registered.

**Cloudflare** (record and rule IDs are in `briefs8/live2_results.md`)
- DNS records, proxied.
- SSL set to Full.
- Redirect rules 1, 3 and 4 on; rule 2 written but off.
- Three cache rules.
- Always Use HTTPS on; email obfuscation on.
- AI bots allowed; managed robots.txt off.

**Google Search Console**
- Domain verified, sitemap submitted, indexing of `/` requested.

**Play Console**
- Gift products `gift_coins_10000` and `gift_noads_coins_10000` created and **active**, at the minimum price in every country (USD/EUR 0.05; full table in `briefs8/live1_results.md`).
- **Saved, not sent for review:**
  - privacy policy URL;
  - Data safety (delete-data URL, profile picture);
  - the 17C store icon.
- 2.3.0 (10) released on internal testing:
  - Opt-in link: https://play.google.com/apps/internaltest/4701523506275249660
  - Play showed the AD_ID error for an older active build. The run chose "Release without permission", the same as for 2.2.

## Calls and deviations for the owner to review

**Design and texts**
1. **Texts written by the build** (PRD §0 item 11): the support FAQ, the 404 page, the five content pages, the homepage FAQ/intro/facts, the privacy and delete-data text, the gift popup, and the "NO RIVAL FOUND" plate with the "FLY SOLO" banner.
2. **Website rule 2** now reads "Fly through without touching the rim for a perfect", because the 2.3 perfect rule changed. **Rule 3** is kept as written, though in the game a heart only saves you once you have 3 of them.
3. **Versus intro plates** use Fredoka SemiBold 18 instead of Opificio 22, so generated names with digits always fit (§21.2).
4. **Aurora hoop glow** is drawn as one blurred layer instead of 22 shadows. This fixed a 36 % slow-frame rate, and no visual difference was found.
5. **First-run "AVOID THE SPIKES" top band** sits just under the HUD row, so the heart and pause buttons don't cover it.
6. **Store badges** are drawn at equal height on the share card, per the store guidelines.

**Gameplay and performance**
7. **§17 bonus count:** **−17.6 %** big bonuses per 50 hoops against the no-rule baseline; the target was within 10 %. The cause is rule 4: while one bonus waits, further big draws fall back to non-big ones. This is reported as §17.6 asks; a fix would need a PRD change.
8. **S8-15 (minor):** in a 120 s profile run on the Pixel 6, six new legendaries showed about 0.1 % frames over 16.7 ms against a lower baseline. These are rare misses, and no art-code cause was shown.
9. **First START after launch** waits up to 1.5 s for the Play purchase sync, so a No-Ads owner's first run gets no banner (S8-13).

**Economy**
10. **Coin budget:** the bot earns 2.125 coins per hoop, almost all from perfect passes, against 2.495 in 2.2. A real player is estimated at about 1.6 against the 1.5 target; check it live with `run_end.coins_per_hoop`.

## Owner tasks (everything left for you)

**Play Console and AdMob**
1. **Play → Store settings → Website → `https://flappyspikes.com`.** Play only offers "Save and publish" for this field, so the run did not change it.
   - Then start AdMob's `app-ads.txt` check.
   - **Urgent:** AdMob currently reads duoleads.com, which has no file, so the app is on limited ad serving.
2. **Send the 4 pending Play changes for review when you're ready:** 17C icon, privacy URL, Data safety, ads declaration.
   - Confirm the icon's AI-content answer first; the run chose "Don't label assets".
3. **Closed testing:** the "Alpha" track has no testers, and its first release needs a review send, so the run didn't use it. If you want it: pick a tester list, promote 2.3.0 (10) and send for review.
4. **Promo codes:** the first code needs **Play → Promo codes → accept the Terms of Service**. After that Claude can make the 3 test codes (`no_ads`, `gift_coins_10000`, `gift_noads_coins_10000`), and the real redeem, consume and restore can be checked on the phone.

**Website and search**
5. **Cloudflare Crawler Hints:** turn it on in the dashboard; the API token was refused.
6. **Bing Webmaster Tools:** sign in, import the Search Console property, submit the sitemap.
7. **Search Console:** recheck the sitemap state and indexing in a day.
8. **GitHub Pages "moved" note:** `docs/index.html` is updated on the branch, but needs a push to `main` to go live. Push only after you've checked the new site.
9. **Keep the GitHub `app-ads.txt` copy** until AdMob verifies flappyspikes.com.

**Device checks only you can do** (details in `QA_DEVICE.md`)
10. **Listening checks:** three loop wraps on Home, a run across a wrap, the Hourglass and revive-duck seams, a real notification sound, Spotify alongside, and rumble feel.
11. **Lock/unlock and screen-off music cases:** they need your PIN.
12. **Share to Messages/Gmail/WhatsApp** and open the link there.
13. **The in-app review sheet** from the Play-installed build.
14. **Real Play Games picture and account-link clean-up.**

**When iOS launches**
15. Fill in and turn on Cloudflare redirect rule 2, and point the website's App Store badges at the App Store.

**Branch**
16. `feat/2.3` is **not pushed**. Before pushing, decide whether to keep the evidence images under `docs/p23/device/` (about 1.4 MB).

## Docs from this run
- `docs/p23/MUSIC.md`: §13 root cause and §16 measurements.
- `TUNING.md` and `remote_config_template.json`: §15.
- `REPORT_tune.md`: gate history and coin budget.
- `SKINS_PORT.png`: §19 port contact sheet.
- `QA_P1.md`, `QA_P2.md`, `QA_DEVICE.md`.
- `docs/SUPPORT.md`, with the gift-code rules.
- `docs/promo_codes_log.md`: no codes made yet.
