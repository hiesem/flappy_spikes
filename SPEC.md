# Flappy Spikes — Rebuild Specification (contract from the 2014 original)

Rebuild of the Objective-C/SpriteKit original (`../FlappySpikes/`) in Flutter + Flame.
All coordinates below are in **logical points** on the original 320×568 iPhone canvas.
The game uses a fixed virtual **width of 320 pt**; the world **height is 320/aspect
of the device screen, clamped to [568, 730] pt** (deviation 2026-07-19: the world
was fixed 320×568 with letterbox bars on tall screens — the user wants the full
screen as playfield). The spike strips are pinned to the true top/bottom edges, so
there are no bars on any phone up to ~21:9; layout stays centered on the taller
field, preserving all gameplay geometry. Portrait only.

## Assets (already in place)

- `assets/images/`: bird.png, bird_flap.png, bird_dead.png (93×59 px = 46.5×29.5 pt),
  pipe_top.png, pipe_bottom.png (176×1027 px = 88×513.5 pt), ground_spikes.png
  (768×144 px = 384×72 pt, horizontally tileable), background_score.png (366×366 px
  = 183×183 pt), title.png, gameover_title.png (549×295 px = 274.5×147.5 pt),
  pointsfield.png (483×164 px = 241.5×82 pt), replaybutton.png, sharebutton.png
  (483×77 px = 241.5×38.5 pt), soundbutton.png, mutebutton.png (60×60 px = 30×30 pt),
  gamcenter.png, gamecenter_gameover.png (leaderboard buttons), app_icon.png (512).
  NOTE: every sprite is drawn on a flat colored background and is TINTED with the
  current foreground color (original used colorBlendFactor 1.0) — implement tinting.
- `assets/audio/`: flap.mp3, point.mp3, gameover.mp3, click.mp3
- Fonts declared in pubspec: `LVDC Common2` (big score), `Opificio Neue` (all other text)

## Game states

1. **start** — world frozen (no gravity effect, no scrolling), bird at center-left
   playing idle 2-frame fly animation (0.5 s/frame). Shows: `title` sprite,
   "Best Score: N" and "Games Played: N" labels, sound on/off toggle button.
   First tap on empty area → state `playing` (start UI fades out 0.5 s) + immediate flap.
2. **playing** — gravity on, world scrolls, pipe spawner running, big score HUD visible
   (fades in 0.5 s). Every tap = flap.
3. **gameover** — world freezes instantly; death animation; game-over panel builds with
   staggered fade-ins: pointsfield (0.2 s) → replay button (0.2 s) → share button (0.2 s);
   overall node fades in 0.5 s; bird & HUD fade out 0.5 s. Panel shows current score,
   best score, games played. Taps only work on replay/share buttons.
4. **replay** — full scene reset with a 0.3 s white fade; state returns to `start`;
   bestScore/gamesPlayed/mute reloaded from persistence.

## Physics (Forge2D)

> DEVIATION (2026-07-19, user-requested, Flappy Bird feel): the 2014
> calibration (gravity ≈ 1350 pt/s², flap Δv ≈ 525 pt/s, rise 90–110 pt) made
> a single flap cross nearly the whole 105 pt gap. Retuned to a smaller pop
> per tap (~half the final gap) plus a terminal fall speed.

- Gravity: **1250 pt/s²** downward. Calibration tolerance: a single flap from
  rest must rise **45–65 pt** before falling.
- Flap: set velocity to zero, then apply upward impulse giving Δv ≈ **370 pt/s**
  (rise = v²/2g ≈ 55 pt). Plays 2-frame flap animation
  (bird_flap ↔ bird, 0.2 s/frame) + `flap.mp3`.
- Terminal velocity: downward speed is capped at **500 pt/s** while playing
  (the death tumble is uncapped).
- Bird: circle body, radius = sprite height / 2 (14.75 pt), sprite 46.5×29.5 pt,
  position x = 80 (= width/4), y = vertical center. No horizontal movement.
  allowsRotation = false (until death).
- Death: remove actions, texture → bird_dead, impulse up-right (40,40) scaled to world,
  restitution 0.1 (bounces off ground), spin 5π radians over 1 s, play `gameover.mp3`.
- Collision categories (mirror original bitmasks): bird=0x1, world(spikes)=0x2,
  pipe=0x4, scoreSensor=0x8. Bird collides with world|pipe; sensor is contact-only.
- Any contact with world or pipe → game over (fire exactly once).

## Scrolling

- World speed: **200 pt/s** leftward, constant, frame-rate independent.
- Ground spike strip: `ground_spikes` tiled to cover screen width (+2 tiles), 72 pt
  tall at the bottom edge of the playfield; **ceiling strip: same texture rotated
  180°**, 72 pt tall at the top edge. Both scroll synchronously with seamless wrap;
  both are static physics bodies spanning the full width. Because the playfield
  height follows the screen aspect (clamped [568, 730]), the strips sit at the
  TRUE screen edges — no letterbox bars. (Any slivers on screens beyond the clamp,
  e.g. tablets, are painted with the foreground tint so they read as an extension
  of the strips; the world background itself is an in-world backdrop rect.)

## Pipes

- Spawn every **1.5 s** → 300 pt horizontal spacing at 200 pt/s.
- Each pair: `pipe_bottom` + `pipe_top`, each 88×513.5 pt, tinted with current fg color,
  static rectangle bodies. Pair enters at x = 320 + 44, z behind bird.
- Gap ramps with the score (difficulty curve, deviation 2026-07-19 — the original
  had a constant 105 pt): **145 pt at score 0 → 105 pt from score 25 on**, linear
  (`Config.gapForScore`). Gap-bottom y (top edge of bottom pipe) uniform random in
  **[202, viewHeight − 72 − gap − 40]** for the gap at spawn time (ceiling strip 72 +
  min flyable window 130 … 40 pt clearance at the top; deviation: the original's
  lower bound 112 could tuck the gap under the ceiling leaving an unflyable
  40 pt window; with gap ≤ 130 the gap now never tucks under the ceiling).
  Consecutive pipes are additionally clamped to a **±140 pt**
  vertical jump (`Config.maxGapJump`) so every transition stays flyable.
- Score sensor: invisible, full-height rectangle, positioned **111 pt to the right of
  pipe center**; bird contact → +1 point, play `point.mp3`, update HUD, trigger color
  stage check. Score fires slightly AFTER the bird clears the pipe.
- Pipes removed when fully off-screen left.

## Color system

Every 5 points (stage = score mod 50), fade (0.5 s) background + foreground tints:

| stage | background | foreground |
|---|---|---|
| 0 (default) | #F1F1F1 | #828282 |
| 5  | #E5F2F9 | #667B84 |
| 10 | #F9EDE6 | #806A62 |
| 15 | #ECF6E5 | #767E67 |
| 20 | #ECEAF8 | #6E6880 |
| 25 | #747474 | #FFFFFF |
| 30 | #087990 | #0CD9FF |
| 35 | #197500 | #7EE400 |
| 40 | #001D89 | #0067FF |
| 45 | #921037 | #FF1F64 |
| 50 (=0 mod 50, i.e. 50,100…) | #FFB529 | #FFFFFF |

Foreground tint applies to: pipes, both spike strips, and the START-scene title
sprite. (Original quirk: only the newest pipe pair is recolored on stage change —
acceptable either way; simpler to recolor all.)
DEVIATION (2026-07-19): the GAME-OVER title and labels are NOT stage-tinted —
behind the frozen pipes they were unreadable. They use the fixed UI accent pink
**#FF4FB7** (the native artwork pink of the buttons/points field).

## HUD & UI

- Score HUD: font `LVDC Common2`, size 125 pt, centered at (160, centerY+35)
  (centerY = viewHeight/2), drawn
  BEHIND pipes; the number's color = current background color (watermark effect)
  over the `background_score` circle (183×183 pt, same position; in the original it
  sits at z −100 with the score at z −90, pipes at −10, UI at 20).
  DEVIATION (2026-07-19): the circle is NOT tinted with the raw foreground color —
  identical to the pipes, their outlines vanished against it. It uses
  `lerp(foreground, background, 0.45)`, always a lighter shade than the pipes.
- Start scene positions: title at (160, centerY − titleH/2 − 35); best-score label
  (160, centerY+120); games-played (160, centerY+150); both `Opificio Neue` 25 pt,
  fg color; sound toggle (`soundbutton`/`mutebutton`, 30×30) at (160, centerY).
- Game-over scene: `gameover_title` (UI accent pink #FF4FB7, NOT stage-tinted)
  at title position; `pointsfield`
  (241.5×82) centered at (160, centerY−41) with current-score label `Opificio Neue` 45 pt
  white inside, nudged 18 pt ABOVE the field center so it clears the "POINTS"
  caption; `replaybutton` at (160, centerY + 19.25 + 6); `sharebutton` at
  (160, centerY + 3×19.25 + 12); best/games labels same positions as start scene,
  but in the accent pink.
- Buttons play `click.mp3`. Sound toggle only on start scene.

## Audio & persistence

- shared_preferences keys: `bestScore` (int), `gamesPlayed` (int, ++ each game over),
  `muteSound` (bool). When muted: no sounds.
- Share button: capture screenshot of the game + share text
  `OMG! I got N points in Flappy Spikes!` via share_plus.

## App shell

- `main.dart`: portrait-only, fullscreen (hide status bar), `GameWidget` hosting the game.
- Services (added 2026-07-20, post-spec): Firebase Analytics events
  (`game_start`, `game_over`, `new_best`, `share_score`) and platform
  leaderboards (Google Play Games / Game Center, iOS ID
  `flappy_spikes_leaderboard` like the 2014 original), wrapped in
  `lib/services/game_services.dart` (no-op without native config). Leaderboard
  buttons use the original `gamcenter.png` / `gamecenter_gameover.png` sprites
  at their original positions. Privacy policy (GitHub Pages) linked on the
  start scene. No ads.

## Testing requirements

- Unit: palette stage = f(score), pipe gap/y-range math (incl. the score ramp),
  persistence round-trip, state machine transitions.
- Component (flame_test): flap zeroes velocity + rises into 45–65 pt band; terminal
  fall speed ≤ 500 pt/s; world scrolls at 200 pt/s; sensor contact scores exactly
  once; pipe contact → gameover once; pipes despawn off-screen; spawn interval
  1.5 s; spawned gap follows the score ramp; pipe sprites align with the physics
  gap; tall-layout geometry (strips edge-pinned, centered layout at 711 pt);
  autopilot survives past score 12 (easy-phase gate, run at 568 and 711).
- Calibration test: flap rise height within 45–65 pt (tune constants until green).
- `flutter analyze` clean, `flutter test` all green.
