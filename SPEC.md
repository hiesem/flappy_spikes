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

## 2.0 menu (PRD-1) deviations

The 2.0 menu phase (PRD-1-menu.md, branch `feat/menu-v2`) replaces the 1.0 start
scene with a **home screen** and supersedes the start/replay flow in "Game
states" above. Everything else in this document still holds.

- **START-only run start.** Only the home screen's START button begins a run; a
  tap on the empty playfield no longer does (`onPlayfieldTap` is inert, and the
  `onScreenTap()` primary-action seam — used by tests and the keyboard — means
  START). Space/Enter = START and, during a run, flap; Esc = back.
  (`lib/components/home/home_screen.dart`, layout in
  `Config.home*For(viewHeight)`.)
- **Game-over replay → home.** The 1.0 game-over panel is kept, but its replay
  returns to the home screen (`goHome()`): a new arrival that re-rolls the
  powerup slot (slots also roll at launch). The run's physics bird waits
  invisibly at its spawn point while the home screen draws the equipped skin in
  its start block, and fades in on START.
- **Menu spike strips.** In menus the strips are drawn 28 pt shorter (44 pt, as
  in the approved mocks) and slide to their full 72 pt when a run starts —
  visual only; the strip bodies never move (`Config.menuSpikeInset`,
  `Config.menuSpikeHeight`).
- **Menus always stage 0.** Home, Shop, Skins and all dialogs/popups render at
  colour stage 0; only runs advance the colour stage.
- **Skin tint rule.** The bird is drawn from the equipped 2.0 look (bird + gear +
  hat, `LookPainter`). In menus and at stage 0 it shows its true colours; from
  stage 5 the whole look lerps 35 % toward the stage foreground
  (`Config.skinStageBlend`, a colour-matrix layer) — applied to every look, the
  default Classic included (a pure stage modulate made all skins grey). Hitbox and
  physics are unchanged.
- **Powerup slot = "watch ad → play with powerup"** (DEVIATION from PRD-1
  §3.6/§4.2, product-owner decision 2026-10-04). The gold slot always shows the
  video icon + label (No-ads owners: no icon) and has no armed / ✓ state.
  Tapping it plays a rewarded ad; on completion the offered powerup is armed and
  the run starts at once through START's path, which consumes it
  (`big_hoops_used` / `shield_armed`). A failed / unavailable ad toasts "No video
  available right now" and stays home with nothing armed; No-ads owners start
  immediately without an ad. Plain START never carries a powerup (a stale armed
  value is cleared at launch); the home screen takes no input while the ad
  plays. On Linux / desktop the fake ads show a visible "TEST AD" overlay
  (3 s countdown; Esc closes early without reward) — also used by Shop free
  coins.
- **Faster menu transitions** (product-owner feedback, 2026-10-04). Menu fades
  are 3x+ faster than 1.0: screens / home UI on START `Config.uiFadeDuration`
  0.15 s (was 0.5), popups / dialogs `Config.popupFadeDuration` 0.07 s (was
  0.2), stagger 0.07 s. Gameplay timing is unchanged: HUD, spike-strip slide,
  death fade and the game-over panel keep 0.5 s / 0.2 s stagger
  (`Config.gameplayFadeDuration`, `Config.gameOverStaggerDuration`); colour
  crossfade and the 0.3 s white replay flash are untouched.
- **Top row swapped: gear / back top-left, coin pill top-right** (DEVIATION
  from PRD-1 §4.1/§5, product-owner change 2026-10-04). On home the settings
  gear sits at x 14, y 58, 38×38; on Shop and Skins the back button takes the
  same rect. The coin pill keeps its internal order ("+" box, balance, coin)
  but is right-anchored: its right edge stays at 306 and it grows leftwards
  with the balance, re-laid out on every balance change
  (`Config.homeCoinPillPositionFor` / `menuScreenPillPositionFor` give its
  top-RIGHT corner). New alignment rules: gear/back left edge = Shop tile left
  edge = trophy left edge = 14; pill right edge = No-ads tile right edge = 306.
  Settings keeps its 1.0 bottom-centre back arrow.
- **No-ads buttons go straight to the store; the popup is launch-only**
  (DEVIATION from PRD-1 §5.1, product-owner change 2026-10-05). Tapping the
  home NO ADS tile or the Shop REMOVE ADS banner starts the `no_ads` purchase
  immediately (`Purchases.buy`; `noads_purchase_tapped` with `source`
  home_tile / shop_banner) and no longer opens the No-ads popup. The popup
  stays for the automatic session-start upsell only (schedule below,
  PRD-menu-v4 §8). While a No-ads purchase is pending both
  buttons are disabled and dimmed; owners keep the unchanged home-tile
  "Already ad-free" toast and the non-tappable AD-FREE banner.
- **Every menu back plays `click`** (DEVIATION from PRD-menu-v2 §8.3 "Back →
  sk_close", owner request 2026-10-07). The Shop and LEVELS back buttons (and
  Esc / Android back, which take the same path) play the same `Sfx.click` as
  the Skins and Settings back. Popup ✕ sounds are unchanged (`sk_close` on
  LEVEL UP ✕, purchase result, No-ads celebration; `click` on the No-ads
  popup).
- **"+N" coins line.** The game-over panel gains a small "+N" + coin line under
  the stats, showing the coins earned (interim rule: 1 coin per point, credited
  at game over; a fresh install starts at 0 coins).

Also in this phase: the home screen leads to the **Shop**
(`lib/components/shop/`, layout in `Config.shop*For`) and the **No-ads popup**
(`lib/components/noads_popup.dart`, `Config.noAds*`), both menu-only; store
purchases are granted by `lib/game/purchases.dart`. The popup is the automatic
session-start upsell. **DEVIATION (PRD-menu-v4 §8, owner decision 2026-10-07)
— replaces the PRD-1 rule (day ≥ 2, once a day, stop after three
dismissals):** it may show only on the home arrival at the start of a session
(app launch, or back after ≥ 30 min in the background; never between runs,
right after START, away from home or over another popup — the popup queue
orders it), at least 4 h after the later of the last show and the last close (wall
clock; S2-70 decision 2026-10-07, PRD-menu-v4 §8.5 "closing starts the
4-hour gap" — the close time is persisted as `noAdsPopupClosedMs`) and at most 2 times
per local calendar day, never in the install's first session, and only from
install day 2 or after 10 finished runs. Within that window it shows when ≥ 3
rewarded videos were completed since the last show (reason `videos`) or the
previous run reached a new level (`level`) / set a new best (`best`), else
once ≥ 24 h passed since the last show (`fallback`); never right after a run
under 6 points (the 24 h fallback stays measured from the last show).
Closing (✕ / dim / back / Esc) restarts the 4 h gap from the close — no
dismissal limit, back-off or lifetime cap; never to buyers. At most one offer
is ever pending: a session start while one is queued or on screen adds
nothing, and a queued offer re-checks the whole window (owner, gap, daily cap,
< 6 rule, home, no run this session) the moment it would show and is dropped
if it no longer holds (S1-70). The numbers are
`Config` constants (`sessionGap`, `noAdsPopup*`); `NoAdsPopupPolicy` holds the
rule, `noads_popup_shown` carries `reason`, and the debug panel's "NO-ADS
POPUP: force" bypasses it. The **Skins** screen (`lib/components/skins/`,
layout in `Config.skin*`) opens from the home tile or the Shop's featured row
(straight into that skin's unlock dialog); owned skins equip on tap, locked ones
open a coin unlock dialog that leads to the Shop's coin packs when the balance
is short, and Shop/Skins return to each other with back when one opened the
other, else home. Settings gains a RESTORE PURCHASES link; rewarded ads (AdMob,
test IDs), in-app purchases and the debug panel (debug builds + Linux) are also
2.0 additions. This supersedes the 1.0 "No ads" shell note (the app now shows
rewarded ads and sells a No-ads IAP), and the privacy-policy link lives on the
Settings screen rather than the start scene.

## 2.0 skin shop (PRD-menu-v2) deviations

Implements `PRD-menu-v2.md` on branch `feat/skin-shop` (off `feat/menu-v2`):
5-layer wardrobe (88 items), skin shop layout A, live home & Shop (§8).
Product-owner decisions 2026-10-06/07 and implementation notes:

- **Hoops and trails are preview-only** until PRD-2 lands: the 1.0 game still
  has pipes, so the Hoop and Trail layers are bought/equipped and shown in the
  skin shop's live preview only; runs, home and results show bird + gear + hat.
- **PRD-1 skins are reset** (Q-S6): the old `ownedSkins` / `equippedSkin` /
  `seenSkins` prefs are deleted on load, no grant, no refund.
- **No BUY confirmation** (Q-S5): try-on + the priced BUY button is the step.
- **Tap-twice buy** (decision 2026-10-07, WP-J2): the first tap on a locked
  tile tries it on and its price pill becomes a pulsing pink "BUY [coin] price"
  pill (scale 1.06 / 1 s like the preview BUY; grey #A0A0A0 and still when
  unaffordable; still under reduce motion); a second real tap on that tile buys
  it through the same path as the preview BUY (`item_purchase` gets
  `source: tile|button`). Not enough coins → the usual not-enough-coins
  feedback. Another tile moves the try-on; a tab switch clears it.
- **Menu list momentum** (decision 2026-10-07, WP-J1 + QA fix round 1): a
  press that travels > 6 pt (`Config.menuScrollSlop`) is a scroll and never a
  tap. A touch INSIDE a gliding / springing list only stops it; a control
  OUTSIDE the list (coin pill, back, tabs, preview BUY) stops it and acts
  (native behaviour, S1-51). Tall looks rest lower in the skin-shop preview
  so hats are never clipped (S2-51).
- **Bird #16 = Rubber duck** (decision 2026-10-07, id `duck`, Rare 750): own
  `rduck` shape (head bump over a boat body with an upturned tail, blue band,
  one glossy highlight, big #FF5722 bill) so it no longer reads as the Chick.
  Shapes may set `bl` (stern x for the wind-up key; defaults to `l`).
- **Stage blend kept** (DEVIATION from §5 "colours fixed"): see the skin tint rule.
- **Art in code:** every item is a Canvas port of `design/menu_v2/skin_art.js`
  (`lib/skins/art/`); no sprite assets. The PRD's "44 × 36 art box / 30 × 30
  body" are art units: in runs the art body centre (21, 18) sits on the physics
  body centre at `Config.lookScale` = 29.5 / 30; the hitbox stays the 1.0 circle
  (r 14.75).
- **Dead pose:** X eye, wing up, hat and gear stay attached, idle animations
  frozen (§6 proposal; the wind-up key stops turning).
  DEVIATION (2026-10-08, PRD-2 §3.0.9 #6, WP-0c): the dead X is now a white
  6 × 6 X with a 2 pt line replacing the eye (was a dark #212121 5 × 5 X, 1.5 pt,
  white only on dark bodies); on light bodies (white, yellow: luminance > 0.6)
  and on the owl's white eye patch it stays dark so it remains visible. The
  zombie's living X eye is unchanged.
- **Gold tier look** (PRD-2 §3.0.9 #5, WP-0c): `LookPainter.paint(gold: true)` /
  `LookComponent.goldTier` recolours the classic bird (body #FFB529, tail +
  wing #E08A00, beak #FFB529, eye white); other bird skins keep their art and
  get a gold glow outline.
- **Gear #10 = Wind-up key** (design change 2026-10-06, replaces the Sidekick).
- **One try-on at a time:** switching tabs clears it; equipping an owned item
  clears that layer's.
- **NEW tags** clear per item when tapped (also when opened tried-on from the
  Shop's featured row).
- **Shop featured row = featured item:** first unowned item of the update list
  (`kNewInUpdate`), else the cheapest unowned item, at its catalogue price
  (the PRD-1 200-coin featured skin is gone); hidden when all are owned.
- `sk_hoop` / `sk_fire` play only after the hoop/trail skin changes (primed with
  the equipped skins on open).
- **GET** (was WATCH) pulses only while claimable; the "+40" toast stays next to
  the coin-fly. START plays its own flap only when the run start is delayed (the
  run's first flap already plays it).
- **Reduce motion** (OS setting): no pulses, streaks, wobbles, wiggles, glints,
  flash, shake, rays or random bird actions; bob/flap and tap reactions stay.
  Idle animations also pause under popups, ads, fake ads and the debug panel.
- **SFX before warm-up are dropped**, never played through a one-shot player
  (audio invariant).

## Home v3 and levels (PRD-home-v3 §3–4) deviations

Implements the home part of `PRD-home-v3.md` (WP-H) on top of the 2.0 skin
shop build:

- **Home layout v3** replaces the PRD-1 / PRD-menu-v2 home layout: trophy box
  in the top row (x 60), emblem + bird stage (plate centre 160, 254 at 711),
  BEST / LAST flank, START 216 × 67 at y 390, slot 216 × 31; the leaderboard
  row and the Games Played stat left home (games now in the LEVELS header).
  Short screens scale the emblem stage down about its top edge (min emblem
  0.78 / bird 1.1) before the START gaps shrink; tiles stay bottom-anchored
  (149 pt above the edge at 711, 146 at 568). Numbers with 4+ digits shrink
  to 62 pt, clear of LEGEND's wings.
- **LAST** = the most recent run's score (`lastScore`, saved at game over);
  "—" before the first run.
- **LEVEL UP trigger (interim, Q-H1):** the popup opens once home has been up
  with nothing over it for 0.35 s while a level-up is owed — after a run's
  return home, and once on the first home after the update for players whose
  best already passed levels (all reached rewards added together). The no-ads
  launch popup goes first; never two popups. Until the claim, the home emblem
  shows the last claimed level; CLAIM / ✕ / Esc all claim, the reward coins fly
  and count up, and only then the emblem pops to the new one. The debug panel's
  LEVEL UP shows it at once.
- **Popup queue (never two popups):** the modal popups (no-ads session-start upsell,
  LEVEL UP, purchase CANCELLED/FAILED, No-ads celebration) open one at a time
  in arrival order; one that arrives while another is up waits until it closes.
  A purchase result or celebration delivered during a run (or while a run is
  starting) waits until the menus are back. The "Purchase pending…" toast is
  removed as soon as that product's purchase resolves.
- **Coin count-ups count only their own reward:** a reward credited before its
  animation (the No-ads +1 000, credited at purchase) is reserved on the pill,
  which shows wallet minus every not-yet-animated reward; each coin reward
  counts in just its own amount at its first landing.
- **No-ads celebration = a purchase started this session:** only a `purchased`
  No ads for a buy the player started in this app session celebrates and pays
  the +1 000. Any other `purchased` No ads (an old receipt replayed after a
  reinstall) restores ownership silently, like RESTORE. Never twice.
- **Reduce motion switched on mid-celebration** settles the No-ads card (no
  swing) and stops the AD icon wobble, rays and sparkles.
- **Reduce motion:** the LEVEL UP popup's emblem clock is frozen (no flags /
  stars / ring / rays motion, no sweep) and its header rays do not rotate.
- **LEVELS** has no coin pill (the mock's screen has none); the shared corner
  box stays as its back button. The dim of the LEVEL UP popup does not close it.

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
  (`Config.gapForScore`). Each pipe then adds a bounded random variance on top
  (deviation 2026-07-22 — neighbouring pipes no longer share one gap size;
  raised 2x from 25/10 to 50/20 later the same day on user request):
  gap = curve + rng × variance, the variance itself tapering **50 pt at score 0 →
  20 pt from score 25 on** on the same ramp schedule (`Config.gapVarianceForScore`,
  `Config.gapForPipe`); the curve value stays the MINIMUM gap. The draw is capped
  at `Config.maxGapFor(viewHeight)` = (viewHeight − 2×(72+20)) / 2 (**192 pt at
  568**, 273 at 730) — the largest gap where both pipe stubs can still be
  ≥ `Config.minPipeStub` (20 pt, lowered from 40 with the 2x variance so the
  bigger gaps still fit; 20 pt still clearly shows the pipe and its cap rim).
  Gap-bottom y (top edge of bottom pipe) uniform random in
  **[max(202, gap + 72 + 20), viewHeight − 72 − gap − 20]** for the gap at spawn
  time (`Config.gapBottomMinFor` / `Config.gapBottomMaxFor`): ≥ 20 pt stub at
  BOTH ends — the raised lower bound keeps the top stub ≥ 20 pt, so a pipe is
  always visible and never hides fully behind the ceiling spikes (deviations:
  the original's lower bound 112 could tuck the gap under the ceiling leaving an
  unflyable 40 pt window; the pre-variance fixed 202 could swallow a 145 pt
  gap's top stub entirely, top stub −15 pt).
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
  DEVIATIONS (2026-07-22): the sound toggle was REPLACED by a settings gear
  (`settings_gear.png`, same position/size) opening the new settings screen,
  and the privacy-policy link was REMOVED from the start scene (it now lives
  on the settings screen only).
- Game-over scene: `gameover_title` (UI accent pink #FF4FB7, NOT stage-tinted)
  at title position; `pointsfield`
  (241.5×82) centered at (160, centerY−41) with current-score label `Opificio Neue` 45 pt
  white inside, nudged 18 pt ABOVE the field center so it clears the "POINTS"
  caption; `replaybutton` at (160, centerY + 19.25 + 6); `sharebutton` at
  (160, centerY + 3×19.25 + 12); best/games labels same positions as start scene,
  but in the accent pink.
- Buttons play `click.mp3`.
- Settings screen (added 2026-07-22; `settings_panel.dart`, opened from the
  start scene's gear, fades in like other panels): "SETTINGS" title at
  (160, centerY−140); SOUND EFFECTS row at centerY−45 (speaker icon at x=85
  swapping soundbutton/mutebutton + label at x=115) toggling `muteSound`;
  MUSIC row at centerY+15 (music_note icon + 140-pt slider) setting the music
  volume live; "Music by ElectroBaptist" credit at centerY+60; back button
  (`back_arrow.png`) at centerY+115; privacy-policy link at the usual bottom
  position. A full-screen invisible blocker consumes stray taps so they cannot
  start the game behind the open panel; the start-scene bird fades with the
  panels.

## Audio & persistence

- shared_preferences keys: `bestScore` (int), `gamesPlayed` (int, ++ each game over),
  `muteSound` (bool; SFX only), `musicVolume` (double 0..1, default 0.6).
  When muted: no sound effects.
- Sound effects (`flap/point/gameover/click.mp3`) play from preloaded
  `AudioPool`s (`FlameAudio.createPool`, maxPlayers 3) — low latency, no
  per-play player churn (deviation note 2026-07-22: bare `FlameAudio.play`
  creates a new AudioPlayer per call; on the Pixel 8 that made flap sounds
  laggy and churned CPU/audio focus).
- Background music (added 2026-07-22): `HappyBeat_8-Bit_Retro_Game_Loop.mp3`
  (credit: ElectroBaptist) loops everywhere — menus and gameplay — via
  `FlameAudio.bgm` (auto pause on app background, resume on foreground).
  Volume = `musicVolume`, adjustable on the settings screen; independent of
  the SFX mute.
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

- Unit: palette stage = f(score), pipe gap/y-range math (incl. the score ramp
  and the gap-variance band), persistence round-trip, state machine transitions.
- Component (flame_test): flap zeroes velocity + rises into 45–65 pt band; terminal
  fall speed ≤ 500 pt/s; world scrolls at 200 pt/s; sensor contact scores exactly
  once; pipe contact → gameover once; pipes despawn off-screen; spawn interval
  1.5 s; spawned gap follows the score ramp (+ variance band, both pipe stubs
  ≥ 40 pt at 568 and 711); pipe sprites align with the physics
  gap; tall-layout geometry (strips edge-pinned, centered layout at 711 pt);
  autopilot survives past score 12 (easy-phase gate, run at 568 and 711).
- Calibration test: flap rise height within 45–65 pt (tune constants until green).
- `flutter analyze` clean, `flutter test` all green.

## PRD-2 shared parts (WP-0c, 2026-10-08)

- DEVIATION (PRD-2 §3.0.9 #1): the 2.0 spike strip art is the 44 pt master
  (26 pt band + 18 pt teeth, period 40, tips at x = 20 + 40k, flat stage
  foreground) drawn by `SpikeTeethPainter`. `SpikeStrip.defaultArt` stays
  `SpikeArt.sprite` (the 72 pt `ground_spikes.png`) until WP-1a switches it to
  `SpikeArt.teeth` together with `Config.spikeHeight` 72 → 44. The teeth tips sit
  on the same line as the sprite's (`spikeHeight − visualInset`), so in menus the
  new art reads exactly as today's inset 44 pt strip.
- Every other §3.0.9 master and the ARCH §3 shared effects live in
  `lib/run/effects/`, `lib/run/hoops/ring_painter.dart` and
  `lib/run/hud/{banners,collect_slot}.dart`; their knobs are in
  `lib/run/config/parts_config.dart`. They are not wired into runs yet (WP-1a/2b…).


## PRD-2 layout ramp, angled and moving rings (WP-1b, 2026-10-08)

- DEVIATION (PRD-2 §3.0.2 / §3.10 / §3.11): the 1.0 pipe layout (uniform gap
  height with a 140 pt max jump) is replaced by the §3.0.2 hoop layout ramp per
  hoop index (`lib/run/config/layout_config.dart`, read by the run director).
  Normal hoops can be tilted (−20°, −10°, +15°, +30°, +45°; from hoop 10) and
  moving (rail / swing from hoop 20; horizontal, diagonal, orbit, rock from 45),
  each with a dashed guide (§5.12). A moving ring's pose is a pure function of
  `runClock` (`lib/run/hoops/motion/hoop_motion.dart`), so it stops with the
  clock and is judged where it is at the crossing.
- Calls: a slide's travel is capped by the band rule (not the row's centre
  range); a slide with < 10 pt of travel left rocks in place instead. The orbit
  turns at 1.25 rad/s (path speed ≤ 39 pt/s on its 25 × 31 pt radii; the
  prototype's 1.4 reached 43 pt/s).
- Hearts are placed by the director (gap 3, then every 17–27) as a
  PLACEHOLDER pickup with no effect until WP-2a.
