# PRD-2.2 §33: performance baseline (2.1) and audio library investigation

WP-33a, 2026-10-12. Branch `g7-wp33a` (feat/2.2 @ 120ec25 = the 2.1 gameplay + the ads commit, plus
516946d, which signs debug/profile builds with the upload key). This file feeds `REPORT.md`. The fixes
(§33.4) are built by the next WP.

## 1. Setup

| Item | Value |
|---|---|
| Device | Pixel 8 `38300DLJH004SD`, Android 17, USB through the hub (charging) |
| Build | `flutter build apk --profile --dart-define=FS_SOAK=true`, signed with the upload key, installed with `adb install -r` over the sideloaded 2.1.0 (8). The player's data is kept. |
| Display | 60 Hz during the run: Home and play both rendered 60 frames/s, display mode 1 = 60 Hz (smooth display not active). Brightness fixed manual 128/255; the old values (auto, 3) were restored afterwards. |
| Stay awake | `stay_on_while_plugged_in` = 7 (already set; left unchanged) |
| Start temperature | VIRTUAL-SKIN 25.8 °C, battery 24.0 °C, thermal status 0 |
| Soak | 20 games in a row, about 18 min of play plus 5 measurement holds. Total wall time 33 min including a 15 min cooling wait (see the note in §2). |
| Soak scope | The FS_SOAK build uses in-memory prefs (fresh player, the owner's saved data is not touched). It runs no Firebase / Play Games / versus / reminders, so the bot never writes analytics, leaderboard or pool data. Ads (test units in profile) and IAP init are real. |

### Repeat command (QA uses the same)

From the flappy_spikes worktree, with the PATH of CLAUDE.md "Commands" and `android/app/key.properties` plus `android/upload-keystore.jks` present (otherwise the install over the release app fails):

```bash
python3 -I tool/soak.py --label <name>          # builds, installs -r, plays 20 games, records
python3 -I tool/soak.py --label <name> --no-build   # reuse build/app/outputs/flutter-apk/app-profile.apk
python3 -I tool/soak.py --label <name> --no-banner  # S7-19 diagnosis: FS_SOAK_NO_BANNER, no gameplay banner
```

Output goes to `docs/p22/perf/<name>/`:
- `soak.csv` / `soak.json`: one row per measured game;
- `logcat.txt`: every `FS_SOAK` line;
- `raw/`: meminfo, gfxinfo, audio_flinger and cpuinfo dumps;
- `trace_g10.perfetto-trace`: gitignored, about 100 MB.

What the soak does:
- **In the app** ([lib/services/soak.dart](../../lib/services/soak.dart), `SoakDriver`, driven from `FlappySpikesGame.update`): each game goes Home → START → autopilot in god mode to 10 hoops → forced spikes death → revive offer → **No thanks** → results (count-up) → **NEXT** → Home.
  - Games 3/8/13/18 hold 3 feathers, giving the **balloon bonus**: 3 pops, then NO THANKS / NEXT.
  - Games 4/9/14/19 get their score lifted to the next level threshold, giving **LEVEL UP → CLAIM**.
  - Game 1 also levels up on its own (fresh player, EGG at 10).
  - After games 1, 2, 5, 10 and 20 the app holds 100 s on Home.
- **On the host** ([tool/soak.py](../../tool/soak.py)): follows logcat. On `FS_SOAK start` it resets gfxinfo, and at game 10 it starts a 40 s Perfetto trace. On `FS_SOAK hold` it records:
  - meminfo, `media.audio_flinger`, threads and gfxinfo;
  - 60 s of the app's CPU from `/proc/<pid>/stat` (utime+stime; % of one core);
  - thermal status and temperatures.
- **Frame times** come from the app (`SchedulerBinding.addTimingsCallback`, total span vsync → raster end). `dumpsys gfxinfo` reports 0 frames for this app because Flutter draws into a SurfaceView, not through HWUI, so it is not usable.
  - **Note:** "slow %" = frames over 12.5 ms (1.5 × a 120 Hz budget). On this 60 Hz run it is a strict early-warning measure, not dropped frames: p99 stays under 18.2 ms in every game, and frames over 25 ms are under 1 %.
- **Audio counters**: `CountingAudioPlatform` ([lib/game/audio_counter.dart](../../lib/game/audio_counter.dart)) wraps the audioplayers platform interface in FS_SOAK builds only. It counts:
  - `create` / `dispose` / `release`;
  - `resume` (= plays);
  - `getCurrentPosition` polls.

  `players` = live native players (created − disposed). `pooled` = players the `AudioPool`s still know about. `SoundService.debugStats()` prints them on every soak line.

## 2. Baseline 2.1 (FS_SOAK profile, 20 games)

Raw data: [perf/baseline-2.1/soak.csv](perf/baseline-2.1/soak.csv) and [logcat.txt](perf/baseline-2.1/logcat.txt).

| after game | 1 | 2 | 5 | 10 | 20 |
|---|---|---|---|---|---|
| PSS total (MB) | 445 | 420 | 440 | 429 | 433 |
| Native heap (MB) | 43.3 | 35.8 | 34.4 | 34.3 | 34.3 |
| Graphics (MB) | 209 | 196 | 210 | 211 | 214 |
| Java heap (MB) | 21.8 | 12.3 | 15.6 | 14.5 | 15.7 |
| **Live native audio players** (created − disposed) | 36 | 38 | 53 | 61 | **78** |
| … still owned by a pool | 32 | 34 | 41 | 43 | 44 |
| … **leaked** (released, never disposed) | 4 | 4 | 12 | 18 | **34** |
| SFX pools | 21 | 23 | 30 | 32 | 33 |
| audio_flinger tracks (active) | 11 (1) | 11 (1) | 11 (1) | 11 (1) | 12 (1) |
| Threads | 148 | 137 | 134 | 136 | 137 |
| **Home idle CPU, 60 s (% of one core)** | 79.7 | 80.5 | 81.4 | 83.1 | **84.4** |
| Home idle `getCurrentPosition` polls/s | 60 | 60 | 60 | 60 | 60 |
| Home idle frames p50 / p90 (ms), slow % | 9.9 / 11.9, 4.9 | 10.1 / 11.8, 4.6 | 10.0 / 11.9, 5.2 | 10.3 / 12.0, 5.7 | 10.6 / 12.4, 9.2 |
| Run frames p50 / p90 / p99 (ms) | 6.9 / 10.6 / 18.1 | 9.2 / 12.9 / 17.2 | 9.7 / 13.3 / 16.6 | 9.8 / 13.3 / 17.8 | 10.1 / 13.7 / 17.5 |
| Run slow % (> 12.5 ms) | 5.4 | 12.0 | 15.8 | 16.7 | 20.0 |
| Post-run (results / bonus) p90 (ms), slow % | 13.5, 18.9 | 13.0, 14.7 | 12.7, 11.9 | 13.3, 20.9 | 12.9, 16.0 |
| Thermal status | 0 | 0 | 0 | 0 | 0 |
| Battery temperature (°C) | 24.0 | 24.5 | 24.8 | 25.1 | 25.3 |

From the per-game log lines (all 20 games):
- **Plays and polls.** The 20 games made 1,303 SFX plays and 115,408 position polls; a poll costs 0.59 ms of main thread (§3). In a run the app polls ≈ 160 times/s; on Home it polls 60 times/s, which is the music's `FramePositionUpdater`.
- **Leaked players grow by the bursts.** They go up by +6 on every LEVEL UP / CLAIM game (the `bnCoin` burst outruns its 6-player pool), by +2 on balloon-bonus games, and by +0 to +2 on plain games. Plain games add new pools early on (the lazy pools of first-heard cues).
- **Run frames slow down over the session.** Run p50 goes 9.2 → 10.1 ms and slow frames 12 → 20 % from game 2 to game 20. Home idle p90 goes 11.8 → 12.4 ms and Home CPU 80.5 → 84.4 %. Game 1 starts lower (p50 6.9 ms); the cause was not investigated.
- **Temperature note.** `soak.json` shows a constant skin 31.27 °C because the first version of the script read Android's stale "Cached temperatures" block, so the 15 min cooling wait was wasted. The live HAL value just before the run was 25.8 °C. `tool/soak.py` now reads the live HAL block.

## 2b. After the §22 / §33.4 items 1–3 audio fixes (WP-22/33b)

Branch `g7-wp22` (feat/2.2 @ cc16f88 + the P22-22 commit): own fixed voice set per sound (`lib/game/sfx_pool.dart`),
stop times from `lib/game/sound_durations.g.dart`, position updates off for every SFX / loop / music player, one global
mixWithOthers context, idle pools evicted after 180 s (LRU above 40). Same phone, hub, brightness 128, same command:
`python3 -I tool/soak.py --label after-audio` (start: skin 27.4 °C, battery 25.2 °C, thermal 0). The Home idle-render
fix (§33.4 item 5, WP-33c) is **not** in this build. Raw data: [perf/after-audio/soak.csv](perf/after-audio/soak.csv),
[logcat.txt](perf/after-audio/logcat.txt).

| after game | 1 | 2 | 5 | 10 | 20 | 2.1 baseline at 20 |
|---|---|---|---|---|---|---|
| PSS total (MB) | 431 | 429 | 437 | 438 | 428 | 433 |
| Native heap (MB) | 59.5 | 56.8 | 43.4 | 43.9 | 41.5 | 34.3 |
| Graphics (MB) | 186 | 188 | 198 | 203 | 207 | 214 |
| **Live native audio players** (created − disposed) | 66 | 66 | 71 | 75 | **76** | 78 (and growing) |
| … owned by a pool (= live − music) | 65 | 65 | 70 | 74 | 75 | 44 (+ 34 leaked) |
| … leaked (released, never disposed) | 0 | 0 | 0 | 0 | **0** | 34 |
| SFX pools alive / evicted so far | 24 / 0 | 24 / 0 | 26 / 8 | 28 / 19 | 28 / 35 | 33 / – |
| Oldest-copy steals (cumulative) | 4 | 4 | 8 | 6¹ | 14¹ | – |
| audio_flinger tracks (active) | 9 (1) | 9 (1) | 12 (1) | 13 (1) | 13 (1) | 12 (1) |
| Threads | 158 | 148 | 149 | 154 | 157 | 137 |
| **Home idle CPU, 60 s (% of one core)** | 81.3 | 80.6 | 79.3 | 77.7 | **81.6** | 84.4 |
| **Home idle `getCurrentPosition` polls/s** | **0** | **0** | **0** | **0** | **0** | 60 |
| Home idle frames p50 / p90 (ms), slow % | 10.8 / 12.5, 10.3 | 10.9 / 12.5, 10.1 | 10.5 / 12.0, 5.4 | 10.5 / 12.3, 7.9 | 11.0 / 12.6, 11.5 | 10.6 / 12.4, 9.2 |
| Run frames p50 / p90 / p99 (ms) | 8.8 / 13.1 / 26.5 | 10.6 / 14.4 / 18.6 | 10.2 / 14.0 / 17.7 | 10.9 / 14.4 / 17.9 | 10.7 / 13.9 / 16.2 | 10.1 / 13.7 / 17.5 |
| Run slow % (> 12.5 ms) | 12.7 | 28.2 | 24.3 | 30.2 | 24.5 | 20.0 |
| Post-run p90 (ms), slow % | 13.4, 17.0 | 12.3, 7.6 | 12.2, 6.9 | 12.3, 8.8 | 14.8, 47.4² | 12.9, 16.0 |
| Thermal status | 0 | 0 | 0 | 0 | 0 | 0 |
| Battery temperature (°C) | 25.5 | 25.7 | 25.7 | 25.7 | 25.9 | 25.3 |

¹ Per live pool: the counter sums the pools alive at that moment (evicted pools take their count with them).
² Game 20 is a plain game; its post-run window is short (538 frames) and the next hold starts on Home. One outlier.

**Plays and polls.** 20 games, 1 273 plays (`resumes`), **0 position polls** (2.1: 115 408). In the game-10 trace the
`xyz.luan/audioplayers` channel traffic on the main thread fell from **4 423 calls / 2.61 s to 120 calls / 0.11 s**,
and the app's main-thread CPU in the 40 s window from 16.0 s to 12.9 s (−20 %). Raster thread 11.6 → 12.5 s.

**§22 full length on the phone.** The FS_SOAK build logs each > 0.6 s play when its stop timer fires
(`FS_SOAK sfx-stop`, 297 lines): `perfect_3` 160× at 2 400–2 412 ms, `perfect_2` 20× at 1 501–1 508, `perfect_1` 25×
at 1 000–1 006, `lv_up` 2 706, `lv_claim` 1 501–1 506, `gameover` 1 426–1 432, `bn_prize_m` 1 200–1 213: every one is the
table length + 100 ms (± 13 ms), none at 0.6 s. (A copy cut by an oldest-copy steal is not logged; steals stay rare,
14 counted on the live pools at game 20 out of 1 273 plays.)

**Against the §33.6 gate (audio part only):**
- **Live players:** bounded and leak-free (0 leaked; 2.1 leaked 34 and kept growing). From game 2 → 20 the count is
  66 → 76: the +10 are the lazy pools of cues first heard in later games (bonus / level-up / rare power-ups), held at
  ≈ 28 pools by the idle eviction (35 pools disposed over the session). Between game 10 and 20 it moved by 1. The hard
  bound is ≤ 40 pools × ≤ 6 players. The live count is higher than 2.1's early games because each pool now owns its
  full fixed voice set up front (no player is ever created mid-play).
- **Position polls on Home: 0/s** (was 60/s).
- **Memory:** PSS flat (428–438 MB, game 20 ≤ game 2). Native heap is higher in games 1–2 (57–60 MB) than in 2.1 and
  settles at 41–44 MB.
- **Home idle CPU:** 78–82 % of a core, about 3 points under 2.1 and flat over the session (2.1 crept 80 → 84 %). The
  rest is Flame rendering the unchanged Home at 60 fps: §33.4 item 5 (WP-33c), not audio.
- **Run frames:** no creep over the session (slow % 28 → 24 from game 2 to 20; 2.1 went 12 → 20), but the level is
  above 2.1: p90 13.9–14.4 ms vs 12.9–13.7 ms. The extra time sits on the raster thread (raster90 6.5–6.9 vs
  5.7–6.2 ms; build90 is equal), which the audio change does not touch; one run each, so this needs the QA re-soak
  after WP-33c to tell run-to-run noise from a real change. Rapid flaps / passes showed no stall: run max frame
  61–89 ms in games 2–20 (2.1: 58–83 ms), the 141 ms in game 11 and the first-game 713 ms (shader warm-up, 2.1:
  599 ms) are single frames.
- **Thermal:** status 0 throughout, battery 25.2 → 25.9 °C.

## 2c. After the §33.4 items 4–6 fixes (WP-33c): idle menus at 30 fps

Branch `g7-wp33c` (feat/2.2 @ e53b098 = the WP-22 audio fixes, plus the P22-33c commit). Idle menus (Home / Shop /
Skins / Levels on top, nothing over them, settled and untouched for 2 s) stop Flame's ticker between frames and draw
at `Config.idleMenuFps` = 30 instead of the display rate; any touch returns to 60 at once (`lib/game/idle_frames.dart`).
Home has continuous idle motion (bird bob / idle flap, START pulse and streak, NEW tag, trophy, coin glint), so
"no frames while nothing animates" never applies to it: the motion keeps its timing, only the frame count halves.
Same phone, hub, brightness 128, same command: `python3 -I tool/soak.py --label after-idle` (start: skin 27.4 °C,
battery 25.8 °C, thermal 0). Raw data: [perf/after-idle/soak.csv](perf/after-idle/soak.csv),
[logcat.txt](perf/after-idle/logcat.txt). (A first attempt was cut off after game 1 because another builder installed
over the app mid-hold; this is the complete rerun.)

| after game | 1 | 2 | 5 | 10 | 20 | after-audio at 20 | 2.1 baseline at 20 |
|---|---|---|---|---|---|---|---|
| PSS total (MB) | 425 | 427 | 459 | 456 | 445 | 428 | 433 |
| Native heap (MB) | 59.4 | 61.4 | 67.6 | 64.9 | 45.5 | 41.5 | 34.3 |
| Graphics (MB) | 180 | 189 | 215 | 217 | 218 | 207 | 214 |
| Live native audio players | 70 | 70 | 83 | 84 | 78 | 76 | 78 (growing) |
| SFX pools alive / evicted so far | 24 / 0 | 24 / 0 | 30 / 8 | 30 / 20 | 28 / 37 | 28 / 35 | 33 / – |
| audio_flinger tracks (active) | 10 (1) | 10 (1) | 10 (1) | 10 (1) | 10 (1) | 13 (1) | 12 (1) |
| Threads | 159 | 146 | 146 | 150 | 150 | 157 | 137 |
| **Home idle CPU, 60 s (% of one core)** | **48.0** | **48.7** | **54.4** | **51.0** | **55.2** | 81.6 | 84.4 |
| Home idle frames in the 100 s hold | 3 038 | 3 040 | 3 037 | 3 042 | 3 039 | 5 996 | ≈ 6 000 |
| Home idle `getCurrentPosition` polls/s | 0 | 0 | 0 | 0 | 0 | 0 | 60 |
| Home idle frames p50 / p90 (ms), slow % | 10.8 / 12.8, 14.6 | 10.9 / 12.9, 14.8 | 11.5 / 13.6, 27.7 | 11.2 / 13.4, 22.7 | 12.1 / 14.2, 40.9 | 11.0 / 12.6, 11.5 | 10.6 / 12.4, 9.2 |
| Run frames p50 / p90 / p99 (ms) | 7.7 / 11.4 / 46.8¹ | 8.6 / 11.8 / 19.1 | 8.6 / 11.3 / 16.1 | 9.1 / 11.8 / 18.3 | 9.2 / 13.1 / 19.7 | 10.7 / 13.9 / 16.2 | 10.1 / 13.7 / 17.5 |
| Run slow % (> 12.5 ms) | 4.9 | 7.4 | 4.2 | 6.1 | 13.0 | 24.5 | 20.0 |
| Run build90 / raster90 (ms) | 4.7 / 5.1 | 5.1 / 5.3 | 5.0 / 4.7 | 4.6 / 5.2 | 5.6 / 5.9 | 6.1 / 6.5 | – |
| Post-run p90 (ms), slow % | 14.6, 26.5 | 12.3, 8.9 | 12.2, 7.6 | 12.7, 12.6 | 13.4, 23.6 | 14.8, 47.4 | 12.9, 16.0 |
| Thermal status | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Battery temperature (°C) | 25.8 | 25.8 | 25.7 | 25.6 | 25.5 | 25.9 | 25.3 |

¹ Game 1 includes the first-run shader warm-up (max 470 ms; 2.1: 599 ms, after-audio: 713 ms).

**Against the §33.6 gate:**
- **Home idle CPU: 48–55 % of a core** (2.1: 80–84 %, after-audio: 78–82 %), about −30 points. The hold draws exactly
  30 frames/s (3 037–3 042 frames in 100 s) with 0 position polls. Per idle frame the span is ≈ 1 ms longer than at
  60 fps (lower CPU / GPU clocks at the lower load), and it drifts up over the session (p50 10.8 → 12.1 ms, CPU 48 → 55 %);
  the cause is not identified (temperature flat, PSS flat); QA's re-soak should show whether it is run-to-run noise.
- **Memory:** PSS at game 20 = 445 MB, +4.3 % over game 2 (427); the peak 459 MB at game 5 is +7.6 %. Within ≤ 10 %.
- **Live audio players:** bounded (70 → 84 → 78; the lazy pools come and go with the 180 s eviction, 37 evicted).
- **Thermal:** status 0 throughout, battery 25.5–25.8 °C.
- **Run frames:** better than both earlier soaks at every point (p90 11.3–13.1 ms vs 13.9–14.4 after-audio and
  12.9–13.7 on 2.1; slow % 4–13 vs 24–30 and 12–20). Game 20 is somewhat above game 1 (p90 11.4 → 13.1 ms, slow %
  4.9 → 13.0), with games 2–10 flat at 11.3–11.8; so "game 20 the same as game 1" is borderline on this one run, while
  "no worse than 2.1" holds clearly. The run itself is not frame-limited (60 fps in play); the run gain is not isolated
  (the shared scratch paints of §33.4 item 6, or run-to-run spread); one run each, QA repeats it.

## 3. Perfetto trace (game 10)

The 40 s window covers about 19 s of play, then death, results and Home idle. The trace is `docs/p22/perf/baseline-2.1/trace_g10.perfetto-trace`, 99.6 MB and gitignored, so it exists only in this worktree. It was analysed with the `perfetto` Python trace processor.

- **CPU by process.** The app used 33.4 s of CPU in 39.9 s (≈ 84 % of one core), surfaceflinger 13.9 s, system_server 7.0 s, mediaserver 4.8 s and audioserver 3.4 s.
- **Main thread** (`s.flappy_spikes`: platform and Dart UI merged, the Flutter default on Android now): 16.0 s.
  - `VsyncProcessCallback` (Dart frame): 9.7 s, 2,378 frames, 4.1 ms average, max 57.6 ms.
  - **`DartMessenger#handleMessageFromDart on xyz.luan/audioplayers`: 4,423 calls, 2.6 s.** That is 16 % of all main-thread time, 0.59 ms per call, 111 calls/s on average.
- **Raster thread**: 11.2 s (`GPURasterizer::Draw` 4.5 ms average, max 33.8 ms). The Impeller/Vulkan helper threads (`IplrVkResMgr`, mali, fence wait) add another ≈ 3 s.
- **Per 5 s window:**
  - in the run: 143–169 audioplayers calls/s, main thread 37–43 %, raster 23–34 % of one core;
  - on Home idle: **60 calls/s**, main 37–40 %, raster 27–29 %;
  - frames stay at 59–60/s with nothing moving.
- **The rest is small.** The `SoundPool_N` threads spend 0.6 s in binder transactions, which are the actual plays. Monitor contention with `pool-20-thread-1` on `MessageQueue.enqueueMessage` comes to 40 events, max 9 ms. GC is minor (one 50 ms explicit mark-compact on a binder thread, scavenges on DartWorker). Vibration calls total 41 ms.

## 4. §33 code-review list: confirmed or not

| # | Code-review claim | Result | Evidence |
|---|---|---|---|
| 1 | Sound players pile up every game (no cap; surplus `release()`d, not disposed) | **Confirmed** | Live players 36 → 78 over 20 games, `disposes = 0`. Leaked = live − pooled = 34 = exactly the `release` count. The jumps line up with LEVEL UP / CLAIM (+6) and bonus (+2) games. The audio_flinger track count stays flat (11–12): SoundPool shares its streams, so the leak is in the plugin's Java/Dart player objects and event channels, not in AudioTracks. |
| 2 | Every playing sound polls its position each frame | **Confirmed, the largest audio cost** | 60 polls/s on Home (the music, all session), ≈ 160/s in a run. 2.6 s of the 16 s of main-thread time in the game-10 trace, 0.59 ms each. SoundPool can't even answer (`getCurrentPosition` = null). |
| 3 | Lazy sound pools never disposed | **Confirmed (bounded in practice)** | 8 prewarmed → 33 pools after 20 games, still growing slowly (+1 between game 10 and 20). Each holds 1–6 players. |
| 4 | Versus avatars cached at full size | **Not measured** | The soak runs without versus (no Firebase in FS_SOAK, by design). The code is unchanged and still decodes without a target size (`avatars.dart` l. 102). Covered by the §33.7 unit test instead. |
| 5a | Home renders at full rate with nothing moving | **Confirmed, the biggest single cost** | Home idle = 80–84 % of one core: 60 frames/s with ≈ 4 ms Dart + 4.5 ms raster each, plus the music polls. That is the "phone feels slower" and the battery drain while sitting on Home. |
| 5b | Engine not paused in background | Not measured (no background phase in the soak) | `lifecycleStateChange` mutes / pauses state but never calls `pauseEngine`. |
| 5c | `Rumble.fired` grows forever, share image, `CollectText` cache, per-frame `Paint`s | Not separately measurable | Java / native heap and PSS are **flat** (PSS 420–445 MB, native 34 MB from game 2), so none of these is a measurable leak over 20 games. They are hygiene items. |
| new | Memory does not grow | **Finding** | PSS is noise ± 15 MB with no trend. The slowdown is CPU work, not memory. |
| new | Frame time creeps up over the session | **Finding** | Run p50 +0.8 ms and slow frames 12 → 20 % from game 2 to 20, Home idle CPU +4 points. This is consistent with the growing player / pool count (more Dart objects, event-channel subscriptions and timers). Thermal stays at 0 and the battery at 25 °C, so the creep is not thermal throttling. |
| new | Every new pool player rewrites global audio settings | **Code finding** (investigation, §5) | `WrappedPlayer.updateAudioContext` writes `audioManager.mode` / speakerphone for every player whose context differs from the default. We pass `mixWithOthers` per player. Fix: set it once on `AudioPlayer.global`. |
| new | `gfxinfo` is useless for this app | **Tooling** | Flutter draws into a SurfaceView, so the §33.6 frame gate must use the in-app FrameTiming stats (`FS_SOAK death … p90= jank=`). |

**Pass-criteria notes for the next WP (§33.6):**
- Use the in-app frame stats.
- The "slow %" metric is fixed at 12.5 ms, so later runs stay comparable to this baseline.
- The Home idle CPU target should drop well below 80 %. That needs §33.4 item 5 (Home idle rendering), not only the audio fixes: the audio polling alone is ≈ 60 × 0.6 ms ≈ 3.5 % of a core on Home.

## 5. Library investigation (§33.5)

Read-only, 2026-10-12. Local sources are in `~/.pub-cache/hosted/pub.dev/audioplayers-6.8.1`, `audioplayers_android-5.3.0` and `flame_audio-2.12.2`.

**Versions.**
- audioplayers 6.8.1 (2026-06-27), audioplayers_android 5.3.0, audioplayers_darwin 6.5.0 and flame_audio 2.12.2 are the **latest** on pub.dev. No newer release fixes any of the issues.
- Since 2023, `AudioPool` has only had #1963 (the `playerMode` option plus release timers) and #1954 (`getDuration`).
- Unreleased on main: #1995 PlayingStateUpdate (breaking) and #2017 ReleaseMode.release. Neither touches pool growth or polling.
- Open issues: #1862 (memory with many small sounds), #1311 (lowLatency plus dispose breaks replay), #1628, #994. Open PRs: #2023 and #1930. None of them fixes the pool.

**AudioPool (audio_pool.dart).**
- `start()` → `_createNewOrReserveAnAvailablePlayer()` (l. 179–184) creates a player whenever none is free. There is **no cap**: `maxPlayers` only caps the *idle* list.
- On stop, a surplus player is only `release()`d (l. 125–126). It keeps its event-channel subscription, Dart streams and the native `WrappedPlayer` with `EventChannel("xyz.luan/audioplayers/events/<id>")`. The native player map drops an entry only on `dispose` (AudioplayersPlugin.kt l. 192–195).
- In low-latency mode no completion listener is attached, so a player returns only when the caller stops it.
- `FlameAudio.createPool` never passes `playerMode` (it would build MediaPlayer pools). We call `AudioPool.create` directly, which is correct.

**Position polling.**
- The `AudioPlayer` constructor installs `FramePositionUpdater` (audioplayer.dart l. 171). `resume` starts it, and `_tick` calls `getCurrentPosition` and schedules another frame callback every frame (position_updater.dart l. 72–77). `stop` and `pause` add one more call each.
- **It can be switched off with public API:**
  - `player.positionUpdater = null` (a nullable public setter, l. 465–468; `onPositionChanged` then becomes an empty stream);
  - or `TimerPositionUpdater(interval:)`.
- The music player is reachable as `FlameAudio.bgm.audioPlayer` (a public field), and `FlameAudio.bgmFactory` allows a custom `Bgm`.

**SoundPool (audioplayers_android 5.3.0).**
- `getDuration()` = null (SoundPoolPlayer.kt l. 153–154). This is the cause of the 0.6 s cut in §22.
- There is one SoundPool per audio-attributes set, with `MAX_STREAMS = 32` hard-coded. Over 32, Android drops the oldest stream (every play uses priority 0).
- A sound is decoded once per URL and shared; `release` unloads only on the last player of a URL.
- **Race:** a player that attaches while the first load of the same file is still running can stay silent (null `soundId`). Create the players of one file sequentially.
- **Re-arming:** a finished SoundPool stream cannot be re-triggered without `stop()` first. Stop → `seek(0)` clears `streamId`, which is how the pool re-arms a player.
- **Global writes:** `updateAudioContext` writes the global AudioManager mode / speakerphone when a player's context differs from the default. It returns early when it matches, so set `AudioPlayer.global.setAudioContext(mixWithOthers)` once and do not pass a context per player.
- iOS (paused): `setPlayerMode` is a no-op, so every pool player is a full AVPlayer. The same leak exists there, with heavier objects.

**Alternatives.**

| Package | Status | Fit |
|---|---|---|
| **flutter_soloud 5.2.0** (2026-10-10) | Very active, 613 likes, ≈ 159 k downloads/30 d. Native SoLoud on miniaudio (AAudio), with Android, iOS, web and desktop support. | The best technical fit: decode once, play by handle over FFI (no platform channel per play), configurable voice cap. Risks: earlier Android latency reports (#202, #184, closed; 5.0 added render-ahead), "out of voices" after backgrounding on a Pixel 7 (#383), the 5.x build-hook migration, several MB of native libraries per ABI, and a rewrite of music plus 6 loops. |
| just_audio 0.10.6 | Popular, maintained | One ExoPlayer per player, each with its own threads and buffers. Built for music and streams; a pool of them is heavier than SoundPool. Not recommended. |
| soundpool 2.4.1 | **Discontinued** (last release 2023-08) | Ruled out. |
| audioplayers_android_exo 0.1.4 | New, very young | Not aimed at low-latency SFX. |

### Recommendation: configure plus our own small wrapper (no upgrade available, no fork, no switch now)

No upstream fix exists or is in the pipeline. Every problem sits on the Dart side and is avoidable through **public** audioplayers API. A fork would mean owning Kotlin and Swift code. A switch to flutter_soloud is the strongest plan B, but it is a larger, riskier change to every sound path (SFX, 6 loops, music) for a release; §33.5 allows a switch only when it is *clearly* better on the phone.

What the next WP should build in `SoundService`:
1. **One global audio context at start:** `AudioPlayer.global.setAudioContext(AudioContextConfig(focus: mixWithOthers).build())`. No per-player context.
2. **Our own fixed-size voice ring per sound** in place of `AudioPool` (this also gives §22's cap):
   - Create the N players once, sequentially per file: `AudioPlayer()..audioCache = FlameAudio.audioCache`, then `positionUpdater = null` **immediately**, then `setPlayerMode(lowLatency)`, `setReleaseMode(ReleaseMode.stop)`, `setSource(AssetSource(file))`.
   - N = 2 by default, 3 for sounds over 1 s (§22), 4 for legacy and up to 6 for burst sounds.
   - Play on a free slot (one whose last start is older than the table length + 100 ms). When none is free, **stop the oldest and restart it**.
   - Never create a player mid-run, never `release()`, and `dispose()` only on teardown or pool eviction.
   - Keep the `poolFactory` test seam, returning the ring.
3. **Durations from the §22 table**, never `getDuration()`.
4. **Music and loops:** `positionUpdater = null` on `FlameAudio.bgm.audioPlayer` right after `initialize()`, and on every `_LoopPlayer`.
5. **Pool LRU (§33.4 item 3):** dispose the rings of cues not heard for a while, except `prewarmed`, with a cap on live rings.
6. **Verify with this soak:**
   - `players` must stay flat from game 2 on;
   - `posPolls` per second on Home must be ≈ 0;
   - no stalls on rapid flaps.

   If the wrapper still shows stalls on the Pixel 8, take the flutter_soloud spike next.

The Home idle CPU (§33.4 item 5) is the larger, separate win: most of the 80 % of a core is Flame rendering an unchanging Home at 60 fps (main ≈ 38 % plus raster ≈ 28 % in the trace, plus the Vulkan helper threads).

## 2d. Final merged-build device QA (2026-10-12, `g7-qadev`)

Production revision `a92835f`. Same Pixel 8 / Android 17 / hub / charging / 60 Hz setup, profile `FS_SOAK`, brightness 128. Start skin **26.86 °C**, battery **25.3 °C**, thermal **0** (baseline live skin 25.8 / battery 24.0). Native game prefs remain in memory. Every game reached 10 hoops; bonus games 3/8/13/18 and CLAIM paths are in the log. Driver duration **1,215.4 s**. Brightness restored to auto (1), value 3.

The merged build includes the native test banner and test interstitials. The legacy driver required the host to close interstitial × buttons: seven close taps, including end-card closes, recorded in `device/interactions.jsonl` and `device/soak_ad_watch.txt`. No ad-content, consent, billing or sign-in taps. This is an intentional test of the complete merged flow; the 2.1 baseline had no interstitial flow.

Raw evidence: [CSV](perf/final-qa/soak.csv), [JSON](perf/final-qa/soak.json), [logcat](perf/final-qa/logcat.txt), [raw dumps](perf/final-qa/raw/), [commands](device/commands.md). The 40 s game-10 Perfetto trace is retained locally at `perf/final-qa/trace_g10.perfetto-trace` (gitignored). `device/soak` links to this dataset.

| Metric | QA 1 | QA 2 | QA 5 | QA 10 | QA 20 | 2.1 at 20 |
| --- | --- | --- | --- | --- | --- | --- |
| PSS total (MB) | 439.1 | 446.0 | 491.0 | 495.3 | 509.2 | 432.7 |
| Native heap (MB) | 62.3 | 62.6 | 60.1 | 51.3 | 51.3 | 34.3 |
| Graphics (MB) | 187.3 | 193.1 | 220.6 | 221.9 | 227.4 | 213.5 |
| Java heap (MB) | 20.9 | 21.7 | 26.5 | 27.7 | 30.5 | 15.7 |
| Live native players | 70 | 76 | 82 | 94 | 96 | 78 |
| Pool voices | 69 | 75 | 81 | 93 | 95 | 44 |
| Pools | 24 | 26 | 28 | 34 | 35 | 33 |
| Evictions | 0 | 0 | 15 | 24 | 44 | – |
| Threads | 163 | 159 | 163 | 167 | 168 | 137 |
| Home idle CPU (% of one core) | 50.0 | 55.6 | 55.8 | 50.1 | 56.5 | 84.4 |
| Home position polls/s | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 60.0 |
| Run p90 (ms) | 12.79 | 13.29 | 14.36 | 15.89 | 14.73 | 13.72 |
| Run slow frames (>12.5ms, %) | 11.7 | 13.5 | 18.3 | 23.4 | 20.0 | 20.0 |
| Thermal status | 0 | 0 | 0 | 0 | 0 | 0 |
| Battery temperature (°C) | 25.2 | 25.3 | 25.4 | 25.9 | 26.5 | 25.3 |

| §33.6 criterion | 2.1 comparison | **Final QA verdict (new gate column)** |
| --- | --- | --- |
| PSS ≤10% above game 2 | 419.8 →432.7 MB (+3.1%) | **FAIL:** 446.0 →509.2 MB, **+14.17%**, limit 490.6 MB. Game 5 already +10.11%, game 10 +11.07%. |
| Native player count flat from game 2 | 38 →78, 34 leaked voices at game 20 | **FAIL literally:** **76 →82 →94 →96**. Bounded but not flat. Live = pool voices +1 music at every hold; **no unowned/leaked voices observed**. 44 pool evictions /123 native disposals. |
| Home CPU clearly below 2.1; no audio polling | 80.5% at 2, 84.4% at 20; 60 polls/s | **PASS:** 50.0–56.5%; game 20 **56.5%** (−27.9 points), **0 polls/s** at every hold and 0 total position polls. |
| No moderate thermal status | status 0 at every sample | **PASS:** all five samples **0**; battery 25.2–26.5 °C, final skin 28.22 °C. |
| Game-20 p90 / slow% same as game 1 and no worse than 2.1 | 2.1: 10.57 →13.72 ms; 5.4 →20.0% slow | **FAIL as measured:** QA **12.79 →14.73 ms (+15.17%)**, **11.7 →20.0%** slow. Final p90 **+7.36%** vs baseline game 20; slow% equal to baseline. |

**Release gate: FAIL (3 of 5 criteria).** No production fix in this tester work package. See `QA_DEVICE.md`, S7-19. Player-count variation follows lazy-pool warming/eviction and is not evidence of the old release-only leak. The criterion is judged literally without inventing a tolerance. One final run establishes the measured failure, not a statistical diagnosis or its cause.

Flutter frame timings are the run metric. Unlike the old baseline, HWUI now reports some frames (the native banner); they are not substituted for the Flutter surface timings. At game 20 build90 /raster90 are 4.41 /5.21 ms; the greater total-span p90 is not attributed to a component without trace analysis.

§22 native stop evidence in this soak: `perfect_3` **12 copies, 2,400–2,411 ms**; `perfect_2` 20, 1,500–1,506 ms; `perfect_1` 59, 1,000–1,017 ms; `lv_claim` 4, 1,500–1,504 ms. No 0.6 s truncation for these cues. Oldest-copy steals on burst pools are counted separately (327 at game 20).

## 2e. Final fix round R1-b (S7-19): session sound set, re-soak (2026-10-12, `g7-fin-soak`)

**Phase 1, causes from the data and the code.**
- **Players not flat (76 → 82 → 94 → 96).** No leak (live = pool voices + music at every hold), but the live set
  followed the run-to-run mix of lazily created pools: cues first heard in later games (bonus, level-up, rides,
  power-ups) were created, then evicted 180 s later, so the count at each hold depended on the last few games.
  **Fix (`P22-FINAL-33`):** `SoundService.warmSession()` pins a session set (`sessionWarm`: post-run count-up / coins /
  ticks, balloon bonus, LEVEL UP / CLAIM, feather slots, star trail; 25 pools) next to the 8 core pools and creates it
  once on Home; pinned pools are never evicted. Every other pool is run-scoped: `replay()` (Home arrival) calls
  `endRun()`, which disposes them at once, or via `maintain()` (each frame, no work when nothing is pending) once their
  last copy has finished. `Config.sfxMaxLivePools` 40 → 56 (33 pinned + room for one run). Tests:
  `test/p22/s33_session_pools_test.dart` (20 simulated games with fake voices: the live count on Home is identical after
  every game; ringing pools wait; a re-played pool stays; 6 real soak-driver games in the game).
- **Run frames.** Not our Dart or raster work: in the final-qa game-10 trace build90 / raster90 stay 4–5 ms while the
  total span p90 is ≈ 15 ms. The main thread (with Flutter 3.47 the Android platform thread **is** the Dart UI thread;
  `MergedPlatformUIThread=disabled` is rejected on Android by an `FML_CHECK`) runs Android view `traversal` +
  `draw-VRI[MainActivity]` + `postAndWait` for the **§7.5 banner's platform view** (the AdWidget, TLHC): 208 traversals
  of ≈ 7.3 ms in 40 s, in bursts of ≈ 0.62 s (38 frames) every 5.0 s from the first flight until the Home arrival (the
  Google test creative animates every 5 s). The after-idle trace (no banner) has none. Frames overlapping a traversal are slower (final-qa trace, span
  from the Dart frame start to the raster end, a proxy of the in-app metric): 76 % over 12.5 ms vs 43 % for the others. The final-qa window also had **Telegram** using 22.2 s of
  CPU in the 40 s trace (the owner's app in the background; final-fix: Signal 12.4 s).
- **Memory.** Java heap grows only with the banner (22 → 27 MB with it, 19–20 MB flat without); graphics grows
  ≈ +25 MB from game 2 to 5 in **every** soak (2.1 too: GL 82 → 96 MB), with or without the banner, then plateaus: the
  first bonus (game 3) and LEVEL UP (game 4) warm Impeller's GPU caches. The banner and interstitials are already
  disposed after each run (`_releaseRunBanner`, `_dispose` after every show), so no Dart-side ad object leaks.

**Phase 2, re-soak.** `python3 -I tool/soak.py --label final-fix` (build `8379282` = feat/2.2 `b26e121` + the
P22-FINAL-33 commit), same phone / hub / charging / 60 Hz / brightness 128 (restored to auto, 3), stay-awake 7
(unchanged). Start skin 28.7 °C, battery 27.9 °C, thermal 0. The host closed 7 Google **test** interstitials by
their × button (same watcher rules as final-qa). Raw data: [perf/final-fix/soak.csv](perf/final-fix/soak.csv),
[logcat.txt](perf/final-fix/logcat.txt), [raw/](perf/final-fix/raw/).

| after game | 1 | 2 | 5 | 10 | 20 | final-qa at 20 | 2.1 at 20 |
|---|---|---|---|---|---|---|---|
| PSS total (MB) | 440.9 | 454.9 | 487.1 | 486.8 | **499.9** | 509.2 | 432.7 |
| Native heap (MB) | 64.2 | 48.3 | 49.5 | 46.9 | 48.2 | 51.3 | 34.3 |
| Graphics (MB) | 182.0 | 192.8 | 217.2 | 217.9 | 218.1 | 227.4 | 213.5 |
| Java heap (MB) | 21.2 | 22.0 | 22.6 | 23.1 | 26.9 | 30.5 | 15.7 |
| Code (MB) | 73.6 | 41.6 | 37.8 | 29.8 | 29.2 | – | – |
| **Live native players** | **93** | **93** | **93** | **93** | **93** | 96 | 78 |
| Pools alive / evicted so far | 33 / 2 | 33 / 8 | 33 / 15 | 33 / 27 | 33 / 55 | 35 / 44 | 33 / – |
| Threads | 175 | 170 | 171 | 173 | 177 | 168 | 137 |
| Home idle CPU (% of one core) | 55.0 | 52.0 | 49.0 | 55.4 | 50.5 | 56.5 | 84.4 |
| Home position polls/s | 0 | 0 | 0 | 0 | 0 | 0 | 60 |
| Run p90 (ms) | 12.81 | 14.48 | 15.00 | 15.78 | 14.74 | 14.73 | 13.72 |
| Run slow % (> 12.5 ms) | 11.7 | 25.0 | 23.1 | 24.5 | 25.9 | 20.0 | 20.0 |
| Run build90 / raster90 (ms) | 3.70 / 4.67 | 4.08 / 5.50 | 4.20 / 4.95 | 3.77 / 5.15 | 4.22 / 5.14 | 4.41 / 5.21 | – |
| Thermal status | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Battery temperature (°C) | 27.6 | 27.4 | 27.5 | 28.0 | 29.0 | 26.5 | 25.3 |

In-run the live count rises by the run-scoped pools (95–102 at the deaths) and is back to 93 (= 92 pinned voices +
the music player) at every Home arrival; 155 disposals, 0 leaked. Run p90 per game: 12.8, 14.5, 15.0, 16.1, 15.0,
15.4, 14.5, 14.3, 14.5, 15.8, 15.2, 16.6, 16.6, 16.1, 15.2, **12.1, 12.2**, 14.8, 15.5, 14.7 ms; the quiet games 16–17
(slow 8–9 %) show the spread from outside the game.

**Diagnosis run without the banner** (`--no-banner`: the soak-only define `FS_SOAK_NO_BANNER`, never in release;
10 games, otherwise identical; [perf/diag-no-banner/](perf/diag-no-banner/soak.csv)): run p90 / slow % per game
12.5/9.9, 12.7/11.7, 11.6/4.9, 11.4/3.5, 11.8/5.7, 12.8/12.3, 12.5/10.1, 12.7/11.0, 13.3/13.6, 12.2/8.3: flat, game 10
≤ game 1, and every game under 2.1's game-20 value (13.72 ms / 20.0 %). No Android view traversals in its game-10 trace. Players 93 at every hold; PSS
447.5 → 491.0 MB at game 10 (+9.7 %, graphics 187 → 220 MB); Java heap flat (19–20 MB); Home CPU 53–55 %.

| §33.6 criterion | final-fix (this round) | verdict |
|---|---|---|
| PSS ≤ 10 % above game 2 | 454.9 → 499.9 MB = **+9.9 %** (limit 500.4); game 5 +7.1 %, game 10 +7.0 % | **PASS** (narrow; the graphics warm-up of games 3–4 is +24 MB of it) |
| Native player count flat from game 2 | **93 at every hold** (games 1, 2, 5, 10, 20) | **PASS** |
| Home idle CPU clearly below 2.1, no audio polling | 49.0–55.4 % (2.1: 80.5–84.4 %), 0 polls/s | **PASS** |
| No moderate thermal state | status 0 at every sample, battery ≤ 29.0 °C | **PASS** |
| Game-20 p90 / slow % = game 1 and no worse than 2.1 | 12.81 → 14.74 ms, 11.7 → 25.9 %; vs 2.1 at 20: +7.4 % p90, 25.9 vs 20.0 % | **FAIL** — caused by the §7.5 banner platform view (without it, 10 games: flat and under 2.1's game 20) |

**Release gate: 4 of 5 pass; the frame criterion fails because of the gameplay banner.** Removing or changing the
banner is outside this round (§7.5 is a product decision, and the look must not change). Options for the owner:
accept the banner's frame cost; measure with real (not test) creatives; or move the banner out of the Flutter view
(a native view still runs on the same main thread with the merged threads, so this needs a spike first).
