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
