# PRD-2 sound pack (WP-3h) — new sounds

Every sound below is **new in WP-3h** — 88 one-shot `Sfx` plus 4 looping `SfxLoop`. The 58 files
WP-0b already shipped (the `// region WP-0b` block in `lib/game/sound.dart`) stay untouched. All of
the new ones were made with
`design/menu_v2/gen_sfx15.py` — the same family as the approved sounds (short, bright, arcade;
peak ≈ −1.4 dBFS):

```bash
cd design/menu_v2 && python3 gen_sfx15.py   # writes sfx/<name>.wav + sfx/<name>.mp3
```

Output contract: one-shots ship as **mp3** in `flappy_spikes/assets/audio/`; loops (`*`) ship as
**wav** so the loop is seamless (mp3 padding clicks) and plays on iOS. Nothing plays through bare
`FlameAudio.play`: every cue is an `Sfx`/`SfxLoop` in `lib/game/sound.dart` and goes through the
preloaded low-latency `AudioPool` (`SoundService.play` / `SoundService.loop`).

**Swapping a sound later:** replace the file in `design/menu_v2/sfx/` + `assets/audio/` with the
same name, or point the `_files` entry in `lib/game/sound.dart` at a new file (and keep
`test/run/sound_pack_test.dart` / `test/menu/sfx_assets_test.dart` green). Durations below are the
shipped mp3/wav lengths; `SoundService` uses them to release the pooled player.

### §5.8 versus intro — `gen_sfx15.py::versus_intro()`

| Sfx | file | use | length |
|---|---|---|---|
| `vsWhoosh` | `vs_whoosh.mp3` | Intro: the two panels slide over the home screen | 0.60 s |
| `vsTick` | `vs_tick.mp3` | One per name-reel step; the pitch falls as the reel slows | 0.06 s |
| `vsChime` | `vs_chime.mp3` | MATCH FOUND: rising 4-note chime + sparkle | 1.00 s |
| `vsRocket` | `vs_rocket.mp3` | The three fireworks launch from the seam | 0.50 s |
| `vsPop` | `vs_pop.mp3` | Firework pops + crackle | 0.70 s |
| `vsThud` | `vs_thud.mp3` | VS punches in (low thud + click) | 0.60 s |
| `vsBoing` | `vs_boing.mp3` | Level-emblem pop-in, taunt flip / double-hop | 0.30 s |

### §5.17 saw rings (hums) — `gen_sfx15.py::loop_mix()`

| Sfx | file | use | length |
|---|---|---|---|
| `sawWireHum*` | `saw_wire_hum.wav` | Live Wire approach hum (swells as the ring nears) | 4.00 s |
| `sawFrostHum*` | `saw_frost_hum.wav` | Frost Ring approach: cold band-whistle + ice bed | 4.00 s |
| `sawHoleHum*` | `saw_hole_hum.wav` | Black Hole approach: beating sub + low rumble | 4.00 s |

### §5.17 saw rings (deaths) — `gen_sfx15.py::saw_hums_and_deaths()` / `::saw_extra()`

| Sfx | file | use | length |
|---|---|---|---|
| `sawWireZap` | `saw_wire_zap.mp3` | Live Wire death: thunder crack + zap + 14 spark crackles | 1.50 s |
| `sawWireThunder` | `saw_wire_thunder.mp3` | The forked strike flare while approaching (thunder crack) | 1.60 s |
| `sawWireCrackle` | `saw_wire_crackle.mp3` | Per-twitch spark during the electrified hold | 0.10 s |
| `sawFrostCrunch` | `saw_frost_crunch.mp3` | Frost death start: freeze crunch + cold hiss | 0.90 s |
| `sawFrostHiss` | `saw_frost_hiss.mp3` | Freezing-fog hiss as the ring approaches | 0.70 s |
| `sawFrostCrack` | `saw_frost_crack.mp3` | The ice block cracks (0.38 s into the death) | 0.40 s |
| `sawFrostTink` | `saw_frost_tink.mp3` | Ice-tip glint bed while approaching | 0.25 s |
| `sawFrostShatter` | `saw_frost_shatter.mp3` | The frozen bird drops and shatters (deep thud + glass) | 1.60 s |
| `sawHoleInhale` | `saw_hole_inhale.mp3` | Black Hole inhale before it takes the bird | 1.20 s |
| `sawHoleRoar` | `saw_hole_roar.mp3` | Black Hole falling roar (death start) | 1.80 s |
| `sawHoleBoom` | `saw_hole_boom.mp3` | The boom + white shock ring when it swallows the ring | 1.40 s |
| `sawHoleSubdrop` | `saw_hole_subdrop.mp3` | The sub drop under the pull | 1.00 s |

### §5.18 FEVER — `gen_sfx15.py::fever()`

| Sfx | file | use | length |
|---|---|---|---|
| `feverPass` | `fever_pass.mp3` | FEVER pass: ignition whoosh + low boom + bright 4-note chord (on top of `perfect_3`) | 1.40 s |
| `feverLoop*` | `fever_loop.wav` | Burning crackle bed while the bird is on fire (looped) | 4.00 s |
| `feverOut` | `fever_out.mp3` | Fire out: short sizzle with the graze sound | 0.50 s |

### §5.19 switch rings — `gen_sfx15.py::switch_rings()` (`clear()` = the shared chord)

| Sfx | file | use | length |
|---|---|---|---|
| `swLockTouch` | `sw_lock_touch.mp3` | Lockdown: switch touched (key jingle, 3 triangle notes + shimmer) | 0.40 s |
| `swLockOpen` | `sw_lock_open.mp3` | Lockdown: opening (lock click, chain rattle + clunk, clear chord) | 1.20 s |
| `swLockCrash` | `sw_lock_crash.mp3` | Lockdown: missed switch (metal clang + chain rattle) | 0.90 s |
| `swLaserTouch` | `sw_laser_touch.mp3` | Laser Gate: switch touched (button click + beep) | 0.20 s |
| `swLaserOpen` | `sw_laser_open.mp3` | Laser Gate: opening (power-down sweep 720→55 Hz + clear chord) | 1.10 s |
| `swLaserCrash` | `sw_laser_crash.mp3` | Laser Gate: missed switch (crackling zap + buzz + sparks) | 1.00 s |
| `swIrisTouch` | `sw_iris_touch.mp3` | Power Iris: switch touched (lever clack) | 0.20 s |
| `swIrisOpen` | `sw_iris_open.mp3` | Power Iris: opening (rising zip + 8 bulb ticks + whirr + clear chord) | 1.30 s |
| `swIrisCrash` | `sw_iris_crash.mp3` | Power Iris: missed switch (heavy metal thud + ring) | 0.70 s |
| `swSnoozeTouch` | `sw_snooze_touch.mp3` | Snoozer: switch touched (alarm-bell trill) | 0.90 s |
| `swSnoozeOpen` | `sw_snooze_open.mp3` | Snoozer: opening (yawn sweep + chord) | 1.40 s |
| `swSnoozeCrash` | `sw_snooze_crash.mp3` | Snoozer: missed switch (grumble "hmpf" + boing) | 0.60 s |
| `swGiftTouch` | `sw_gift_touch.mp3` | Gift Wrap: switch touched (snip) | 0.15 s |
| `swGiftOpen` | `sw_gift_open.mp3` | Gift Wrap: opening (snip-snip, paper rip, pop, sparkle + clear chord) | 1.20 s |
| `swGiftCrash` | `sw_gift_crash.mp3` | Gift Wrap: missed switch (drum boing + paper crinkle) | 0.60 s |
| `swClear` | `sw_clear.mp3` | The shared "it is open" cue (C-E-G-C triangle chord + high sparkle) | 1.10 s |

### §5.20 pair gifts — `gen_sfx15.py::pair_gifts()`

| Sfx | file | use | length |
|---|---|---|---|
| `pairBoxOpen` | `pair_box_open.mp3` | The gift box opens (short pop) | 0.30 s |
| `pairShield` | `pair_shield.mp3` | Shield taken: bright chime chord + soft low swell | 1.20 s |
| `pairComet` | `pair_comet.mp3` | Comet taken: rising whoosh + chord | 1.10 s |
| `pairCoins` | `pair_coins.mp3` | +10 coins: fast coin-ping cascade | 1.00 s |
| `pairScore` | `pair_score.mp3` | +5 score: rising 5-note arpeggio | 1.10 s |
| `pairFever` | `pair_fever.mp3` | FEVER taken: ignition whoosh + low boom + chord | 1.50 s |
| `pairSkipped` | `pair_skipped.mp3` | Ring skipped: soft falling blip | 0.45 s |

### §5.21–§5.25 special hoops — `gen_sfx15.py::special_hoops()`

| Sfx | file | use | length |
|---|---|---|---|
| `trainNote1` | `train_note1.mp3` | Ring Train ring 1 (C5 triangle) | 0.50 s |
| `trainNote2` | `train_note2.mp3` | Ring Train ring 2 (E5 triangle) | 0.50 s |
| `trainNote3` | `train_note3.mp3` | Ring Train ring 3 (G5 triangle) | 0.50 s |
| `trainFinish` | `train_finish.mp3` | Ring Train finish: high C + C-major chord + rising whistle | 1.30 s |
| `springUp` | `spring_up.mp3` | Spring Ring UP: sine sweep 160→720 Hz + triangle overtone | 0.50 s |
| `springDown` | `spring_down.mp3` | Spring Ring DOWN: sine sweep 480→140 Hz + triangle overtone | 0.50 s |
| `bullThunk` | `bull_thunk.mp3` | Bullseye hit: dart thunk (low-pass noise + 190→60 Hz) | 0.30 s |
| `bullChord` | `bull_chord.mp3` | Bullseye hit: bright chord | 0.70 s |
| `luckyTick` | `lucky_tick.mp3` | Lucky Spin: one tick per slice (spins at 7 rad/s) | 0.10 s |
| `luckyWhoosh` | `lucky_whoosh.mp3` | Lucky Spin: short whoosh on the pass | 0.40 s |
| `luckyWin` | `lucky_win.mp3` | Lucky Spin: 4-note win chord | 1.00 s |
| `trailNote1` | `trail_note1.mp3` | Star Trail star 1 (C5) | 0.40 s |
| `trailNote2` | `trail_note2.mp3` | Star Trail star 2 (D5) | 0.40 s |
| `trailNote3` | `trail_note3.mp3` | Star Trail star 3 (E5) | 0.40 s |
| `trailNote4` | `trail_note4.mp3` | Star Trail star 4 (F5) | 0.40 s |
| `trailNote5` | `trail_note5.mp3` | Star Trail star 5 (G5) | 0.40 s |
| `trailNote6` | `trail_note6.mp3` | Star Trail star 6 (A5) | 0.40 s |
| `trailNote7` | `trail_note7.mp3` | Star Trail star 7 (B5) | 0.40 s |
| `trailNote8` | `trail_note8.mp3` | Star Trail star 8 (C6) | 0.40 s |
| `trailPop` | `trail_pop.mp3` | Star Trail: pop on a non-final star / "n / 8" | 0.30 s |
| `trailChord` | `trail_chord.mp3` | Star Trail: bright chord on 8 / 8 (PERFECT LINE) | 1.10 s |

### §5.26–§5.28 collectables + §3.0.4 rim — `gen_sfx15.py::collectables()`

| Sfx | file | use | length |
|---|---|---|---|
| `eggPickup` | `egg_pickup.mp3` | Egg picked up (chime) | 0.40 s |
| `eggCrack` | `egg_crack.mp3` | Egg gains a crack line on each ring (short band-pass noise) | 0.30 s |
| `eggHatch` | `egg_hatch.mp3` | HATCHED: hatch peeps + chord | 1.00 s |
| `eggPeep` | `egg_peep.mp3` | Chick peeps now and then while it flies with you | 0.20 s |
| `eggBye` | `egg_bye.mp3` | Chick lost: falling 3-note goodbye | 0.60 s |
| `piggyOink` | `piggy_oink.mp3` | Piggy Bank picked up (oink: two quick square dips) | 0.60 s |
| `piggyCoin` | `piggy_coin.mp3` | A coin caught in the piggy (clink; burst pool) | 0.30 s |
| `piggyMiss` | `piggy_miss.mp3` | A coin missed (soft blip) | 0.20 s |
| `piggySmash` | `piggy_smash.mp3` | Pay-out: smash + coin cascade + chord | 1.30 s |
| `jarPickup` | `jar_pickup.mp3` | Firefly Jar picked up (chime) | 0.50 s |
| `jarTwinkle` | `jar_twinkle.mp3` | One firefly in the jar (soft high twinkle) | 0.25 s |
| `jarEscape` | `jar_escape.mp3` | A firefly escapes (falling blip) | 0.25 s |
| `jarBreak` | `jar_break.mp3` | JAR BROKE: crack | 0.50 s |
| `jarFull` | `jar_full.mp3` | JAR FULL: bright chord (+25 coins) | 1.10 s |
| `rimTonk` | `rim_tonk.mp3` | Rim (hoop edge) touch: bounce + +1 (was `sk_tap` before WP-3h) | 0.20 s |

### §5.29–§5.31 powerup capsules — `gen_sfx15.py::powerups()`

| Sfx | file | use | length |
|---|---|---|---|
| `hourglassStart` | `hourglass_start.mp3` | Hourglass start: tape-slowdown sweep 700→110 Hz (music to ~72 %) | 1.00 s |
| `hourglassTick` | `hourglass_tick.mp3` | Hourglass tick-tock every 0.6 s | 0.50 s |
| `hourglassEnd` | `hourglass_end.mp3` | Hourglass end: speed-up sweep | 0.70 s |
| `miniStart` | `mini_start.mp3` | Mini Bird start: rising bubble blips then a falling whistle 1400→300 Hz | 0.70 s |
| `miniEnd` | `mini_end.mp3` | Mini Bird end: rising whistle + pop | 0.70 s |
| `frenzyStart` | `frenzy_start.mp3` | Coin Frenzy start: 5-note jackpot run + chord | 1.20 s |
| `frenzyRing` | `frenzy_ring.mp3` | Coin Frenzy: coin cascade on every ring | 0.60 s |
| `frenzyEnd` | `frenzy_end.mp3` | Coin Frenzy end: short falling tone | 0.60 s |

## Calls

- **Loops are `SfxLoop`, not `Sfx`.** `sawWireHum`, `sawFrostHum`, `sawHoleHum` and `feverLoop`
  (4.00 s wav) are sample-exact seamless: tone layers at integer cycles per 1/4 s with the filter
  run from 4.5 s so only the settled output is kept, and noise layers tail→head crossfaded.
- **Compound cues are folded into one file.** §5.17 describes "zap + thunder crack" (one
  `saw_wire_zap`), "crunch + hiss" (one `saw_frost_crunch`), "deep thud + glass" (one
  `saw_frost_shatter`) and "boom + shock ring" (one `saw_hole_boom`). The separate
  `sawWireThunder`, `sawFrostHiss`, `sawFrostTink` and `sawHoleSubdrop` cover the approach/ambient
  cues the mocks play on their own (`screen_hazard_hoops4.html`: `thunder`, `freeze`+hiss, `tink`,
  sub). If a later WP wants them split, the parts are one call each in `gen_sfx15.py`.
- **Pair gifts** mirror the mock's five reward sounds exactly (`pair_shield`/`_comet`/`_coins`/
  `_score`/`_fever`) plus the box pop and the skipped blip.
- **Shared "clear" chord** is its own cue (`swClear`) *and* mixed into each design's `*_open` at the
  point the mock plays it (0.5 s), so the game can play the whole opening as one file.
- **`rimTonk` replaces the `sk_tap` placeholder** of §3.0.4 (R-S-23).
- **A few extra cues** have no PRD-named file but the mocks play them; generating them now saves a
  round-trip later (e.g. `luckyTick`, `trailPop`, `hourglassTick`, `jarTwinkle`, `trailNote1..8`).
- **Loudness** is set per file in the generator (`save(peak=…)`); the pack is not re-normalised as a
  batch, so relative levels match the mocks (thunder/boom loud, ticks/tinks quiet).

