# PRD-2.3 §13 + §16: the music (investigation, fix, seamless loop)

> **Update 2026-10-18: new music.** The HappyBeat loop below is replaced by the
> Flappy Spikes remix, looped as the owner's option E of
> `design/music_loop_remix/remix_loop.html` (crossfade select 80 ms). The
> playback architecture of this document is unchanged (just_audio
> `LoopMode.one` on Android, `LoopMusic` on iOS, `FlameAudio.bgm` on Linux);
> only the files changed. `tool/make_music_loop.py`, `make_music_loop_ios.py`
> and `loop_seam_check.py` (HappyBeat-specific: 146 BPM grid, silence-based
> seam detection) are removed; the HappyBeat sections below are history.
>
> ```
> python3 -I tool/make_music_loop_remix.py [--report out.json]
> ```
>
> | | |
> |---|---|
> | source | `tool/music_src/Flappy_spikes_remix.mp3` (sha256 asserted; not shipped), 48 kHz stereo, no gapless header: ffmpeg decodes 8 815 104 samples (183.648 s), as the page's `decodeAudioData` |
> | loop | START = 0.176 s = 8 448, END = 176.954 s = 8 493 792, **L = 8 485 344 samples = 176.778 s** (48 kHz, no resampling) |
> | the jump (as the page plays it) | each segment is queued back to back and plays 80 ms *past* END, gain 1 → 0 linear over [END, END + 80 ms]; the next segment starts at START, gain 0 → 1 linear over the same 80 ms; summed. The loop file is one period of that: `y[i] = x[START+i]·i/X + x[END+i]·(1 − i/X)` for i < X = 3 840, then `x[START+i]` |
> | OGG (Android / Linux) | `assets/audio/FlappySpikesRemix_loopE.ogg`, Vorbis q6, `ANDROID_LOOP=true`, last granule = L, decodes to L samples, 3.80 MB |
> | M4A (iOS) | `ios/Runner/FlappySpikesRemix_loopE.m4a`, AAC-LC 192k, 4.33 MB. The encoder gets 2048 samples of the loop's own end as pre-roll (a cold AAC start was −46 dBFS off for the first 50 ms); edit list media_time 3072 (1024 priming + 2048 pre-roll), duration L; stts = 3072 + L; padding r = 544. `LoopMusic`: `loopFrames` 8 485 344, `primingFrames` 3072, `remainderFrames` 544 |
> | wrap vs the page's own jump (±50 ms) | OGG −53.5 dBFS RMS difference, M4A −57.9; largest sample step at the wrap −42.9 / −38.6 dBFS, below the music's own steps in the 100 ms before (−36.6): no click |
> | loudness | loop −14.3 LUFS = remix MP3 −14.3 LUFS (no gain: the page applies none). The old HappyBeat loop was −13.7 LUFS, so the new music is 0.6 dB quieter |
> | first start | the file begins at the seam, so the very first play also has the 80 ms crossfade (the end of the breakdown fading out under the intro's first 41 ms of near-silence); every later wrap equals the page |

Build run 2026-10-13, branch `p23-music`. Test phone: Pixel 6 `24191FDF6008ZD`
(Android 17), media / ring / notification streams **muted on purpose** and
Do Not Disturb on (zen mode 1) for the overnight run. Raw evidence (logs,
`dumpsys` captures, sampler output) is in
`.worktrees/briefs8/evidence/music/`, not in git.

## Summary

| Item | Result |
|---|---|
| §16.3 the file | `assets/audio/HappyBeat_loop_56bars.ogg`: exactly 4 059 616 samples (56 bars at 146 BPM), every check of the script passes |
| §16.4 step 1 (audioplayers + OGG) | **Fails**: a **≈ 265 ms gap** at every wrap (the `MediaPlayer` loop stops and restarts its output track) |
| §16.4 step 2 (just_audio, Android) | **Built.** Wrap shift **−0.8 ms** (sampling noise), no underrun, the output track never stops; after a background pause / resume shortly before the wrap: **−0.2 ms** |
| §16.6 scrcpy playback recording | Records **silence** (−91 dBFS) on the muted phone: owner task (below) |
| §13 root cause | 2.2's `AudioWatch` counted listed players without checking that they still play and re-evaluated only on playback callbacks; notification usages were not handled at all; a false "own music" answer stuck until the next scene change. See "Root cause" |
| §13 fix | `lib/game/music_guard.dart` + `AudioWatch` changes, all §13.4 requirements, tests in `test/p23/s13_music_test.dart` |

## §16.3 The file (`tool/make_music_loop.py`)

```
python3 -I tool/make_music_loop.py --report <file> [--page <workspace>/design/music_v23]
```

Report of the shipped file:

| | |
|---|---|
| decoded MP3 | 4 060 800 samples (asserted) |
| end (last sample above −50 dBFS, + 1) | 4 060 800 |
| L = round(56 × 240 / 146 × 44 100) | 4 059 616 |
| start = end − L | 1 184 (26.8 ms); samples [0, 1 184) all below −50 dBFS (asserted) |
| crossfade | last 221 samples (5 ms), equal power into x[start − 221 + i] |
| duration | 92.054785 s |
| last Ogg page granule | **4 059 616** (= L); ffmpeg decodes 4 059 616 samples |
| Vorbis header | 44 100 Hz, 2 channels, comment `ANDROID_LOOP=true` |
| size | 2 252 781 bytes (≈ 196 kb/s, q6) |
| loudness | −13.7 LUFS, MP3 −13.7 LUFS |
| first / last 221 samples vs the float cut | RMS difference −126.8 / −53.9 dBFS (< −40) |
| seam: first downbeat after the wrap | **−0.010 ms** from the 146 BPM grid (±2 ms) |
| seam: silence | 23.02 ms = the cut's own lead-in 23.06 ms, **−0.05 ms extra** (< 10 ms) |
| seam: click | none (largest jump at the seam −44.5 dBFS) |

**Call (seam silence):** the approved version 3 starts with the MP3's own
lead-in: 1 012 samples (22.9 ms) of digital silence before the first downbeat,
because the MP3 ends 1 012 samples before bar 56 is complete. That silence is
part of the approved music (version 3 plays it too), so "no silence of 10 ms or
more at the seam" is checked as silence *beyond* the reference cut's own
silence. `tool/loop_seam_check.py` applies the same rule to phone recordings.

**Call (RMS):** "RMS difference below −40 dB" is read as an absolute level
(dBFS).

The comparison page `design/music_v23/loop_test.html` has the new card
**4 · The shipped file** (the generated OGG embedded, with the same Seam / Loop
buttons and beat clicks). Its build source `loop_test_src.html` has a second
placeholder for the OGG; `make_music_loop.py --page` rebuilds the page.
Originals backed up to `design/_backup_2.3/music_v23/`.

## §16.4 / §16.6 On the phone

### The scrcpy recording is silent (owner task)

`scrcpy 5.0.1 --no-video --audio-source=playback --audio-codec=raw
--record=probe.wav` (installed in `~/opt/scrcpy-linux-x86_64-v5.0.1`; no sudo
for pacman) records −91 dBFS while the music plays: on this phone the muted
stream volume mutes the track at the source ("mutedState: streamVolume
portVolume" in `dumpsys audio`), so playback capture gets silence. The PRD
forbids unmuting, so the recording goes to the owner (below).

### Objective measurement without audio: the mixer's frame counter

`dumpsys media.audio_flinger` lists the music's output track with its
**Server** frame counter (frames the mixer has consumed, at the track's
44 100 Hz), its ready frames and its underrun count. A muted track is still
mixed, so the counter runs at exactly 44 100 frames/s while the music plays.
A device-side loop sampled it every ≈ 70 ms across a wrap; for every sample,
`lag = wall clock × 44 100 − consumed frames` (in ms). A seamless wrap keeps
the lag flat; a gap adds its length to the lag. (`af_gap.py` in the evidence
folder; sampling jitter ≈ ±15 ms per sample, so the means of the ~150
samples before and after the wrap are compared.)

| Player | Lag before the wrap | Lag after | **Shift = gap** | Underruns | Track at the wrap |
|---|---|---|---|---|---|
| audioplayers `MediaPlayer`, OGG (step 1) | −16.9 ms | +247.6 ms | **+264.5 ms** | 0 → 1 920 frames | stalled at exactly 4 059 616 frames, ran dry (`FrmRdy 0`), `AT::remove` / `AT::add` |
| just_audio ExoPlayer `LoopMode.one` (step 2) | −5.8 ms | −6.6 ms | **−0.8 ms** | 0 → 0 | continuous, never removed |
| just_audio, background pause 3 s + resume, then the wrap | −8.0 ms | −8.2 ms | **−0.2 ms** | 0 → 0 | continuous |

The step 1 result also shows that the counter stalls at exactly 4 059 616
frames, the length of the file: the file is right, the `MediaPlayer` loop
(seek to 0, decoder flush, a new output start) is the gap, and
`ANDROID_LOOP=true` does not change it. **Step 1 fails (gap ≥ 10 ms), so
step 2 is built:** `lib/game/music_backend.dart`, `JustAudioMusic`:

- just_audio 0.10.6 (+ audio_session 0.2.4) for the music only; sound effects
  and loops stay on audioplayers as tuned in 2.2;
- `AudioPlayer(handleInterruptions: false, handleAudioSessionActivation:
  false, androidApplyAudioAttributes: false)`, then
  `setAndroidAudioAttributes(USAGE_GAME, CONTENT_TYPE_MUSIC)` before the source
  (ExoPlayer `setAudioAttributes(…, handleAudioFocus = false)`);
- `dumpsys audio`: the music is an `AudioTrack` with `usage=USAGE_GAME
  content=CONTENT_TYPE_MUSIC`, and the audio focus stack stays empty while it
  plays;
- `LoopMode.one`; pause → `pause()`, resume → `play()` (position kept);
  volume / duck → `setVolume(musicVolume × duck)`; Hourglass → `setSpeed`;
- no `positionStream`: only `playerStateStream` (the watchdog's state);
- the FS_SOAK counter counts it as one music player;
- Linux desktop (no just_audio backend) keeps `FlameAudio.bgm`
  (`AudioplayersMusic`). iOS (round 2, 2026-10-15) plays the same loop as AAC
  (`tool/make_music_loop_ios.py` → `ios/Runner/HappyBeat_loop_56bars.m4a`) on
  the runner's `LoopMusic` (`AVAudioPlayerNode`, segments back to back;
  `NativeLoopMusic`); see PORT-IOS.md §3.

**Not measured on the phone** (needs a run on the device, the counter method
works the same): a wrap during an Hourglass slow-down and a wrap while the
revive shop ducks the music. The code path is the same player (ExoPlayer
`setSpeed` / `setVolume` do not touch the loop). Listed for the owner's
listening check.

## §13 Investigation

### What the phone allows

The phone stays silent (muted media / ring / notification streams, DND). So no
notification makes a sound, and the public playback list hides muted players:
the game's own music and another app's muted media player are not listed (the
2.2 comment in `MainActivity.kt` already noted this). The new debug broadcast
was used (no real notifications, PRD §0):

```
adb -s 24191FDF6008ZD shell am broadcast -a com.flappyspikes.DEBUG_NOTIFICATION \
    [--es player notification|media] [--ei ms 1500] [--ei linger 8000]
```

It posts a heads-up notification on a channel with sound (needs the
notification permission) and, with `player`, plays the notification tone
itself with `USAGE_NOTIFICATION` (or `USAGE_MEDIA`, the plain-`MediaPlayer`
case) for `ms`, then keeps the paused player listed for `linger` before
releasing it (a finished, unreleased player).

### Evidence

1. **Paused and stopped players stay in the playback list.** `dumpsys audio`
   0.7 s into the ding and 3 s later (5 runs, `dumpsys_notif_*`):
   ```
   piid:175 type:android.media.MediaPlayer state:started usage=USAGE_NOTIFICATION   (during)
   piid:175 type:android.media.MediaPlayer state:paused  usage=USAGE_NOTIFICATION   (after the ding)
   piid:167 type:android.media.MediaPlayer state:paused  usage=USAGE_GAME           (2.2-style music, paused)
   ```
   2.2's `AudioWatch.interrupted()` / `otherMediaListed()` counted every listed
   player of a usage, whatever its state, and only re-evaluated on a playback
   callback. A finished, unreleased player therefore kept its answer until the
   *next* playback change (in the owner's report: the Settings tab click).
2. **The player state is readable.** The hidden
   `AudioPlaybackConfiguration.getPlayerState()` works by reflection on
   Android 17 for this app: the `FS-Music` log shows `watch [5:1]` (usage 5 =
   `USAGE_NOTIFICATION`, state 1 = playing). The new `AudioWatch` counts only
   playing players (and falls back to "listed" + `isMusicActive()` / a 5 s cap
   where the state cannot be read).
3. **Notification usages were not handled.** 2.2's interruption set had no
   `NOTIFICATION*` usage, so the effect of a notification depended on how the
   sending app played it: a `NOTIFICATION_RINGTONE`-style usage held the music
   as an interruption (and needed a later callback to end); a plain
   `MediaPlayer` (`USAGE_MEDIA`) counted as "the player's own music" at the
   next foreground check.
4. **"Own music" stuck until a scene change.** `ownMusicSkipped` was cleared
   only at Home arrival / run start, so any false "yes" (a notification's
   `MEDIA` player, the previous app's last moment of video, an ad's player)
   kept Home silent until START: the owner's first report.
5. **The new behaviour on the phone** (debug ding, Home, 5 times,
   `notif_home_5x.log`):
   ```
   03:18:57.184 notify     | … notif=1 | watch [5:1] music=1 | player playing
   03:18:57.184 pause      | … notif=1 on=0
   03:18:57.369 notify-end | … notif=0 | watch []
   03:18:57.370 resume     | … on=1
   ```
   The music pauses the moment the notification player starts and resumes as
   soon as it is no longer playing. (On this muted phone the system hides the
   muted ding from the public list after ≈ 180 ms, so it resumes earlier than
   it would with sound; with sound it resumes at the ding's end, at the latest
   0.5 s later through the re-check.) Sound effects are not touched.
6. **Heads-up banner:** with the permission granted for the test (and
   restored to denied / user-set afterwards), the banner under DND produced
   no lifecycle change at all (no `inactive`). Whether an audible heads-up
   makes Flutter report `inactive` could not be checked silently; the fix makes
   it harmless either way (`inactive` no longer pauses the music, and a
   foreground check needs two "yes" answers).
7. **A media blip at launch:** the log showed another `USAGE_MEDIA` player
   (an `AAudio` stream of the app's own process, not the music) opening and
   closing within 11 ms after the start. A foreground media sound now holds the
   music only after 0.3 s (`Config.musicMediaSoundDebounce`), so such blips
   never stutter the music.
8. **Return from the background:** `check-foreground-0:no` 1 s after the
   return, then `foreground` / `resume` (`af_wrap3` run).

### Root cause

The owner's two reports fit the same mechanism: **a hold whose reason had
already ended, kept because nothing re-checked it**:
- an "own music" skip from one false "yes" (a `MEDIA` notification player or
  the previous app's audio at the foreground check), cleared only by the next
  scene change (START), and
- an interruption from a notification player that stays listed after its sound
  ended, cleared only by the next playback callback (opening Settings plays a
  tab click).

Not reproduced audibly on the phone (it must stay silent); the `dumpsys`
evidence (1), the readable player state (2) and the code paths (3, 4) are the
proof. The suspects "late ad suspend" and "dead player" are covered by the 5 s
suspend timeout and the watchdog, and logged if they ever happen.

## §13.4 The fix

`lib/game/music_guard.dart` (stepped with the game clock), `AudioWatch` in
`MainActivity.kt`, `SoundService` holds:

- **Notification sounds** (`NOTIFICATION`, `NOTIFICATION_EVENT`,
  `NOTIFICATION_COMMUNICATION_*`, or a `MEDIA` / `UNKNOWN` sound that starts
  in the foreground and plays ≥ 0.3 s): the music pauses (position kept) and
  resumes within 1 s after it ends, on any screen, mid-run included. Sound
  effects keep playing. Never "own music" unless a media sound keeps playing
  for 2 s (`Config.musicMediaSoundOwnAfter`).
- **Only playing players count**; while the music is held for an interruption
  or a notification it re-checks every 0.5 s.
- **"Own music"** needs two "yes" answers 1 s apart (launch; on a return from
  the background the check runs 1 s after it, the music stays held until
  then). While the game's own music plays, only the playback list is asked
  (`isMusicActive()` would count the game's music).
- **Re-check every 2 s** while skipped on Home / a menu / the results page;
  back within 3 s of the other music stopping, no scene change. Never mid-run.
- **Ad suspend** with no ad showing for more than 5 s is cleared on any screen.
- **Watchdog** every 5 s on a menu: the game thinks the music plays but the
  player is stopped / completed / paused / disposed (after a 1 s grace) → the
  music restarts from the start of the loop, logged `player_dead`.
- **`inactive`** (banner, shade, system sheet) is not the background.
- **Diagnostics:** `SoundService.musicLog`, the last 50 entries (event, hold
  flags, the raw playback list `usage:state` + `isMusicActive`, the player's
  real state), logcat tag `FS-Music` (release builds too), the debug panel's
  MUSIC LOG page. `music_held` (`reason`: own_music / suspend / interrupted /
  background / player_dead; `source`: launch / foreground / scene) once per
  Home visit after 10 s held with the music volume above 0.
- Kept from 2.2: the player's own music keeps the game music off while it
  plays; calls, alarms and ads pause it; the background pauses it; no
  audio-focus request.

## Owner tasks

1. **Listening check (§16.6 / §0):** with the phone's media volume up, listen
   on Home through 3 wraps and through one run that crosses a wrap (the first
   wrap comes 92 s after the music starts); include a wrap during an Hourglass
   and one with the revive shop open. It must sound like card 3 / 4 of
   `design/music_v23/loop_test.html`. Optional objective recording:
   `~/opt/scrcpy-linux-x86_64-v5.0.1/scrcpy -s 24191FDF6008ZD --no-video
   --audio-source=playback --audio-codec=raw --record=music.wav
   --time-limit=300`, then `python3 -I tool/loop_seam_check.py music.wav`.
2. **The notification case with sound (§13.5 device list):** with sound on
   (DND off), a heads-up from Google Messages / Gmail / WhatsApp on Home,
   mid-run and on the results page: the music pauses for the ding and is back
   within 1 s with no tap. `adb logcat -s FS-Music` shows the holds.
3. **Own music:** Spotify (or any music app) playing keeps the game music off;
   stopping it brings the game music back on Home within 3 s. (Not testable
   with the media stream muted: muted players are hidden from the list.)
4. **Soak:** a 30-minute session cycling these; the `FS-Music` log must show
   no silent menu time without a matching hold.
