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
  hat, `LookPainter`) in its **true colours at every stage** (PRD-2.2 §20: the
  stage blend of this rule is removed, see the DEVIATION at the end). Only a
  themed death tints the look (`Bird.deathTint`, PRD-2 §5.17). Hitbox and
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
- **Android system back closes the menus** (DEVIATION from the Esc-only back,
  PRD-2.2 §8, owner decision 2026-10-10). The system back (the edge swipe with
  gesture navigation, or the 3-button back) does what the screen's own back
  arrow / ✕ does, and only on the menus and popups: Settings, Shop, Skins,
  LEVELS, the Home popups (NO ADS offer, LEVEL UP, purchase result, No-ads
  celebration), Delete my data, the debug panel. Topmost first; one close per
  gesture (a close still fading out ignores further backs). `back_gesture
  {screen}` is logged only when something closed. On Home with nothing open,
  in a run (every state but start, the pause settings included), on the bonus
  and results pages and while a video ad is up it does nothing. The app never
  closes or goes to the background on back. Esc is unchanged.
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

- **Hoops and trails** were preview-only until PRD-2 landed: with the 1.0 pipes
  still in place, the Hoop and Trail layers were bought/equipped and shown in the
  skin shop's live preview only; runs, home and results showed bird + gear + hat.
  **Superseded by PRD-2 (WP-1a):** pipes are gone and the equipped hoop skin +
  trail now render in runs — see "PRD-2 hoops replace pipes" below.
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
- **Stage blend removed** (PRD-2.2 §20, supersedes the 2.0 "stage blend kept"
  line): the run bird keeps its own colours at every colour stage; see the
  DEVIATION (PRD-2.2 §20) at the end of this file.
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
- **Preview trail always drawn** (owner bug, 2026-10-18). DEVIATION from PRD-menu-v2
  §4.2, which burned the preview trail for 1.7 s after each hoop pass and kept it
  only while the TRAILS tab was open: the equipped trail (or the one tried on) is
  drawn on every tab, between passes, on open and on re-entry, and after an equip.
  A new trail starts seeded with `Config.skinShopTrailSeedFrames` (120 frames), so
  the history trails (rainbow, afterimage, prism, paint) are full at once. The
  hoop loop (2.3 s, 120 pt/s, pulse ring) is unchanged.
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

> PRD-2 (WP-1a): the max fall speed, bird x, the death and the collisions below
> are superseded — see "PRD-2 hoops replace pipes" at the end.

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

> PRD-2 (WP-1a): superseded — the world scrolls at the bird's forward speed and
> the strips are the 44 pt master (see the end of this file).

- World speed: **200 pt/s** leftward, constant, frame-rate independent.
- Ground spike strip: `ground_spikes` tiled to cover screen width (+2 tiles), 72 pt
  tall at the bottom edge of the playfield; **ceiling strip: same texture rotated
  180°**, 72 pt tall at the top edge. Both scroll synchronously with seamless wrap;
  both are static physics bodies spanning the full width. Because the playfield
  height follows the screen aspect (clamped [568, 730]), the strips sit at the
  TRUE screen edges — no letterbox bars. (Any slivers on screens beyond the clamp,
  e.g. tablets, are painted with the foreground tint so they read as an extension
  of the strips; the world background itself is an in-world backdrop rect.)
  DEVIATION (WP-TAB, 2026-10-17): screens wider than 320:568 (tablets) are no longer
  letterboxed; see "Tablets: a wider world" at the end. Only screens wider than 3:4
  keep side slivers in the foreground tint.

## Pipes

> PRD-2 (WP-1a): pipes are removed; hoops replace them (see the end of this
> file). This section is the 1.0 history.

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

> PRD-2 (WP-1a): in runs the stage changes every 10 hoops passed (see the end
> of this file); the palettes are unchanged.

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
- DEVIATION (WP-SET, owner 2026-10-19): the footer credit reads "Melody by
  ElectroBaptist"; tapping the name opens https://soundcloud.com/electrobaptist
  in the in-app browser (Chrome Custom Tab / SFSafariViewController), as do
  Support and Privacy policy. Redeem code stays in the Play Store app. The
  footer's `Flappy Spikes v<version> (<build>)` shows on every open.

## Audio & persistence

- shared_preferences keys: `bestScore` (int), `gamesPlayed` (int, ++ each game over),
  `muteSound` (bool; SFX only), `musicVolume` (double 0..1, default 0.25:
  DEVIATION from 0.6, PRD-2.2 §9; a stored value always wins, and "Delete my
  data" clears the key).
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
- DEVIATION (PRD-2.3 §16, 2026-10-13): Android and the Linux desktop play
  `HappyBeat_loop_56bars.ogg` instead: the MP3 cut to exactly 56 bars at
  146 BPM (4 059 616 samples, 5 ms crossfade at the seam;
  `tool/make_music_loop.py`). On Android the music player is just_audio
  (ExoPlayer, `LoopMode.one`, `USAGE_GAME`, no audio focus): audioplayers'
  `MediaPlayer` loop left a 250–265 ms gap at every wrap (docs/p23/MUSIC.md).
  iOS (paused) keeps the MP3 on `FlameAudio.bgm`.
- DEVIATION (2026-10-18): the music is the Flappy Spikes remix
  (`tool/music_src/Flappy_spikes_remix.mp3`, 48 kHz) looped as the owner's
  option E of `design/music_loop_remix/remix_loop.html`: 0.176 s → jump at
  176.954 s back to 0.176 s, 80 ms linear crossfade at the jump (the
  outgoing audio plays on 80 ms past the jump fading out while the loop start
  fades in), 8 485 344 samples = 176.778 s, no gain change. Files:
  `assets/audio/FlappySpikesRemix_loopE.ogg` (Android just_audio, Linux) and
  `ios/Runner/FlappySpikesRemix_loopE.m4a` (iOS `LoopMusic`), both made by
  `tool/make_music_loop_remix.py`. The HappyBeat files are gone from the app.
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
## PRD-2 hoops replace pipes (WP-1a, 2026-10-08)

- DEVIATION (PRD-2 §3.1, §5.1): **pipes are removed**; the obstacle is the
  M0 hoop — a vertical ring 24 pt wide, stroke 7, height = opening + 2 × 7,
  drawn by `RingPainter` in two layers (back half behind the bird, front half
  over it), in the equipped hoop skin (default `#EC008C` / `#B0006B`), **not**
  stage-tinted. One `Hoop` component per slot with a kind (`NormalHoopKind`);
  the run director places them (§3.0.2 / §3.0.3): spacing **310 pt** plane to
  plane, the first hoop **60 pt past the right edge** at the first tap at the
  exact vertical centre (it scrolls in, ≈ 2.1 s to the bird), opening **118 pt
  at hoop 0, −0.32 % per hoop, floor 92 pt**, centre ≥ opening/2 + 7 + 18 pt
  from each tooth line (the same margin on both sides).
- DEVIATION (PRD-2 §3.0.1, §7, "2.0 physics"): Forge2D integrates **only the
  bird's vertical motion** (gravity 1250, a flap sets vy −370 — the 45–65 pt
  rise band is unchanged — **max fall 650 pt/s**, was 500). Bird x **70**
  (was 80). There is no fixed scroll speed: the bird has a real forward speed
  (cruise **150 pt/s, +3.5 % per minute of run time**; after a knock-back it
  recovers toward cruise at 2000 pt/s²) and the world — hoops, spike teeth —
  moves at that speed (the camera follows the bird). **No Forge2D contacts**:
  rim ends, the pass plane, the miss rule and the spike tooth lines are plain
  math (`lib/run/physics/`); the bird's fixture mask is 0.
- DEVIATION (PRD-2 §3.0.4, rim bounce): touching a rim **no longer kills**.
  Each ring has two rim-end circles (r 7) at local (0, ±(opening/2 + 7)),
  rotated with the tilt. On overlap the bird is pushed out along the contact
  normal and, when moving into the rim (relative to the rim's velocity), its
  velocity is reflected with restitution **0.85** (tangential part kept); the
  hoop is marked touched (that pass is not perfect), white sparks, a 360°
  spin over 0.35 s. The forward part of the bounce moves the camera (the world
  jolts back). No rim bounce while invulnerable.
- DEVIATION (PRD-2 §3.0.4 5 / §3.1, score trigger and miss rule): a point
  fires when the bird centre crosses the hoop plane forward **between the two
  rim-end centres** (|local y − ring| ≤ opening/2 + 7; a bird pressed against
  the inside of a rim end is through); crossings beside the ring decide
  nothing; a knock-back across the plane is not judged. **Miss** only when the
  bird is fully past the ring: centre − r > centre x + |sin tilt| × (largest
  ring offset + opening/2 + 7) + 7. Each hoop resolves once. (Replaces the
  sensor 111 pt right of the pipe centre.)
- NOTE (PRD-2.2 §30, moving rings — bug fix, no rule change; PRD-2
  §3.0.4 / §3.11): the crossing is judged **relative to the moving ring**:
  the bird's previous position is measured in the ring's pose of the
  previous physics step and its current position in the current pose, the
  local y interpolated to the crossing. A ring whose centre or rim ends move
  more than 2 pt in a step is tested in 4 sub-steps (pose and bird
  interpolated), for the plane and the rim ends alike, so neither can jump
  over the bird. Borderline crossings lean to the player (exactly at the
  reach passes; a pass in the step wins over a miss). Ring sizes, motions,
  speeds, the swing period, rim physics and the still-ring miss rule are
  unchanged.
- DEVIATION (PRD-2 §3.1 / §3.2 / §3.0.1, scoring): **+1 per hoop**; **a coin
  per hoop at the moment of the pass** through the menu wallet (1; **2 for a
  perfect pass** = no rim touched), shown by the gold "+N" coin popup; the
  1.0 / menu interim "1 coin per point at game over" (`CoinSource.play`) is
  gone. A non-perfect pass plays `point.mp3` and the §5.1 ring-outline pulse;
  perfect-pass sounds/effects belong to the streak (WP-2b). The **colour stage
  changes every 10 hoops passed**: index floor(hoopsPassed / 10) mod 11 over
  the 11 palettes in order (gold last: hoops 100–109, 210–219, …) —
  `stageForHoops`; `stageOf(score)` stays only for the 1.0 table.
- DEVIATION (PRD-2 §3.0.5, death tumble; replaces "impulse up-right,
  restitution 0.1, spin 5π"): at death the world eases to a stop over 0.4 s;
  the bird keeps its velocity + 180 pt/s along the contact normal (a plain
  miss: vy − 140), spins at clamp(forward / 25 + impact, ±12) rad/s, falls
  with gravity and −40 %/s air drag, bounces off the top strip (0.3), bounces
  on the floor tooth line (0.3, forward × 0.6, spin × −0.6) while landing
  faster than 140 pt/s, then rests at **tooth tips − r + 2**, slides to a stop
  and settles flat; it never leaves the screen (24 pt left / 30 pt right,
  × −0.3), passes through hoops and pickups, shows the white X eyes and stays
  lying there (drawn behind the tooth tips, not faded) through the results.
  The game state is `dying` meanwhile; the post-run flow (results) starts
  **1.5 s** after the hit or as soon as the bird rests. `gameover.mp3` plays
  at the hit. A spike save (invulnerable / extra life / shield) bounces off
  the tooth line instead (top: down at 30 %; floor: vy −222).
- DEVIATION (PRD-2 §5.13): a miss plays the "C · Shock ring" flash — the hoop
  flashes white (0.12 s, stroke 8, glow 24), a red `#FF1F3D` shockwave ring
  (1 → 2.6×, 0.55 s), one red edge glow pulse (0.7 s, drawn under the spike
  strips as in the mock), the hoop drains to a grey dashed ghost (0.12–0.52 s,
  alpha 1 → 0.35, dashed 6/6 from 30 %) that stays; `miss_shock` sound.
- DEVIATION (PRD-2 §3.0.9 #1, 44 pt strips): `Config.spikeHeight` **72 → 44**
  and `SpikeStrip.defaultArt` = `SpikeArt.teeth` (26 pt band + 18 pt teeth,
  period 40). Menus and runs show the same strip (`menuSpikeInset` 28 → 0;
  the menu list bleed uses the 18 pt tooth depth). The band between the tooth
  lines is 623 pt at 711 and 480 pt at 568. Spike contact = the bird circle
  reaching the tooth line (tips). The teeth scroll with the run camera.
- Tests: `autopilot_test` (hoop-aware bot ≥ 12 hoops at 568 and 711),
  `collision_test` (pass once / miss once / spikes once), `test/run/physics/*`
  (rim, pass/miss, tumble — pure), `test/run/flow/s3_1_hoop_flow_test.dart`,
  `test/run/flow/s3_0_1_hoop_spawner_test.dart`; `pipe_spawner_test` and
  `gap_variance_test` were replaced by the latter.


## PRD-2 hearts, extra life, shield, Big Hoops (WP-2a, 2026-10-08)

- DEVIATION (PRD-2 §3.3, "a mistake ends the run"): a mistake (missed hoop
  incl. a pair, spike touch, saw rim, closed switch) is first offered to the
  **saves**, in order: the **shield** (order 10), then the **extra life**
  (order 20). A save keeps the run going from where the bird is (no respawn,
  no tumble; the missed hoop gives no point / coin), gives **2 s of
  invulnerability** (every mistake is ignored, no rim bounce; the bird
  blinks 100 % ↔ 25 % every 0.1 s) and on a spike strip bounces the bird off
  the tooth line. Only an unsaved mistake starts the death tumble.
- Hearts (§3.3, §5.2): 32 pt `#FF3B5C` pickups (white outline, pulse 1.0 ↔
  1.14 over 1 s, hit radius 16) placed by the director; **3 hearts = one
  extra life** (does not stack; hearts are run-only). The extra life shows as
  a 34 pt heart badge ≈ 41 pt above the bird (bob ±4 pt), popping in 0.3 s
  after the 3rd heart; a save pops it into 12 small hearts.
- Shield (§3.7, §5.5): absorbs exactly one mistake, no timer; armed by the
  field pickup (from gap 12, max one per run), a pair's SHIELD gift or the
  home slot (active from the first frame). Shown as an 84 pt circle around
  the bird (gold 3.5 pt ring, 28 % soft-pink fill, dashed white inner ring
  turning 90°/s, ±5 % pulse); a hit shatters it into 12 gold / pink shards.
- DEVIATION (PRD-2 §3.6 / §3.0.1, Big Hoops; replaces the 1.0-era "1.5× for
  50 s"): the home-slot Big Hoops rolls **D = 30–40 s** of run time at the
  start; hoops spawned until D − 8 s are **1.5× taller** (capped to the band)
  and normal hoops are drawn gold (`#FFB529` / `#D48A00`); the multiplier
  eases 1.5 → 1.0 per newly spawned hoop over the last 8 s; a hoop keeps its
  size on screen; after D everything is normal. Boosted runs count for
  everything; no indicator.
- Tests: `test/run/items/s3_3_s3_7_lives_test.dart`,
  `test/run/items/s3_6_big_hoops_test.dart`, the Big Hoops cases of
  `test/autopilot_test.dart`; shots in `test/run/shots/lives_shots_test.dart`.
## PRD-2 perfect streak, ring tiers and run rumble (WP-2b + WP-2c, 2026-10-08)

- DEVIATION (PRD-2 §3.4 / §3.5, new mechanic): a **perfect pass** (no rim
  touch; every ride hoop) builds a streak, capped at tier 10 (IMMORTAL ×10);
  a graze, a saved mistake or a death resets it to 0. A perfect FEVER pass
  sets it to max(5, streak + 1) (§3.19). Each perfect pass shows the streak
  banner (y 190, 10 names), plays `perfect_1/2/3` instead of `point`, and a
  small burst at the bird; the whole ring field reflects the tier (tier 1
  sparkles, tier 2 gold rings + gold bird, tier 3+ bright gold + glow +
  flame flicks + the bird's trail). A graze with a streak shows
  "GRAZE · streak lost" (§5.3). No screen flash at any tier (§3.0.9 #13).
  The coins (+2 perfect) are unchanged from WP-1a.
- DEVIATION (PRD-2 §3.33): runs now vibrate — a 45 ms full shake on every
  perfect pass, a 15 ms knock on a non-perfect pass and on every pickup touch
  (one knock per 90 ms; a shake is never skipped and a knock in the same
  frame is dropped); only while the run is live, never for deaths, saves or
  screens. The RUMBLE switch also sends `setting_changed`.
- Tests: `test/run/items/s3_4_streak_test.dart`,
  `test/run/items/s3_33_rumble_test.dart`,
  `test/run/effects/s3_0_9_gold_glow_perf_test.dart`; shots
  `test/run/shots/streak_shots_test.dart`.

## PRD-2 HUD row, pause and revive v2 (WP-2d, 2026-10-08)

- DEVIATION (PRD-2 §5.7, HUD): the run HUD lives in `camera.viewport` (real
  time: the Hourglass does not slow it, run shakes do not move it): one top
  row at y 52 — the heart indicator (x 14, 38 × 38; empty dashed / ⅓ / ⅔ /
  full + pulse), the versus bar + name chips (only with an opponent) and a
  pink pause button (right edge 306). No coin total. The y-190 banner band
  and the graze notice moved into the HUD; the extra-life badge stays over
  the bird in the world but ignores the time scale.
- DEVIATION (PRD-2 §5.7 / §4, pause; 1.0 had none): the pause button, Esc
  and backgrounding the app (`paused` / `hidden` / `inactive`) pause a
  running run (state `paused`): the world gets dt 0 (Forge2D, bird, hoops,
  particles), runClock stops. The card offers RESUME (straight back in, **no
  3-2-1**), sound and settings (the settings panel over the paused run). No
  Quit. Not available during the tumble / revive / results.
- DEVIATION (PRD-2 §3.14 / §5.9, revive; 1.0 had none): a death with
  **≥ 6 hoops passed** brings up the revive offer after the tumble (state
  `reviving`) *before* the run ends — persistence, analytics and the versus
  upload run once per game, at the real end. One option per death from the
  per-game price ladder: rewarded ad (placement `revive`) → 250 → 500 →
  1 000 → doubling, no cap; no ad / no-ads owner on the 1st offer → "NO AD
  AVAILABLE" + 250. Not enough coins → grey locked heart + GET COINS (the
  Shop over the paused game, countdown paused, music × 0.5). 5 s drain + 1 s
  empty, then results. Paid → the 1.65 s phoenix rise (safe line = the next
  hoop's centre, drift to x 70), then straight back in with 2 s
  invulnerability; the next slot is a normal hoop. A death with ≤ 5 hoops
  goes to results as before and uses no ladder step.
- DEVIATION (PRD-2.3.1 §14, owner 2026-10-14; supersedes PRD-2.2 §7.7's free
  revive): **a NO ADS owner gets no free revive.** Their ad step is skipped for the
  game as in the "no ad available" path, but **without** the "NO AD AVAILABLE"
  label: 250 → 500 → 1 000 → 2 000 → 4 000 → 8 000, then no more revives (at most
  6 a run; everyone else keeps the ad + 6 coin steps). `ReviveOffer.free` /
  `ReviveKind.free` and the `revive_free_used` event are gone; their 250 revive
  logs as a normal coin revive.
- DEVIATION (PRD-2 §3.14): every death ends a running Egg / Piggy / Jar (no
  pay-out), a timed powerup (time scale and bird scale back to 1) and the
  fire; a revive resets a running squeeze to open (0.5 s) and rolls the next
  one 60–120 s later. Score, coins, hearts and feather / piece progress stay.
## PRD-2 results page (WP-2e, 2026-10-08)

- DEVIATION (PRD-2 §3.14 / §5.10; replaces the 1.0 game-over panel and the
  `gameOver` state, now `GameState.results`): after the tumble (and the revive
  offer / balloon bonus when they apply) an opaque stage-coloured **results
  page** covers the playfield between the strips (the strips are lifted over
  it): the card with your score (solo: you alone, centred; versus header and
  opponent column are WP-5b's), NEW BEST, your level (emblem + equipped bird,
  rank line, progress bar), YOUR REWARD (the run's coins incl. puzzle coins
  and the win / draw bonus, excl. the balloon bonus) and NEXT → home (a new
  arrival). The 1.0 title sprite, pointsfield, "Best Score / Games Played"
  labels, REPLAY and the 2× coins idea are gone; the leaderboard and share
  buttons are kept as two pink boxes flanking the reward pill (PRD-1 §3.7).
  The page uses the mock's fixed colours (plum / pink / gold, stage-grey
  labels) instead of `Config.uiAccent` — readable because the page is opaque.
  Buttons and the keyboard (Space / Enter / Esc = NEXT) take input after the
  0.3 s fade-in. On short screens (568) the 320 × 711 column scales down
  uniformly (≈ 0.8) about the top centre.
- DEVIATION (PRD-2 §3.0.1, results NEXT; `Fix P2 R1`, S6-23): NEXT is a
  bottom button, so it keeps the reference 65 pt gap to the screen bottom
  **and** its §5.10 292 × 50 size on every screen height 568–730 while the
  column above it scales; the uniform scaling down statement above applies
  to everything except the button, which is laid out in inverse scale.
- DEVIATION (PRD-2 §3.14, levels): a run that reaches new levels plays the
  LEVEL UP celebration on the results page and its reward is claimed there
  (CLAIM, or automatically on NEXT); the home LEVEL UP popup now only serves
  the catch-up of players updating with a best already past unclaimed levels
  (and the debug LEVEL UP). The owed reward is stored as
  `unclaimedLevelReward` at the run's end and credited silently at the next
  app start if the app was closed before claiming.

## PRD-2 portal roller-coaster rides (WP-3b, 2026-10-08)

- DEVIATION (PRD-2 §3.12 / §5.12b, new mechanic; 1.0 had none): from hoop
  25 (then every 40–60 hoops) a **portal** ring (purple / violet with a cyan
  inner rim and a light beam) replaces a slot. Flying through it counts as a
  normal pass and starts an automatic ride, one of six picked at random with
  equal chance, never the same twice in a row (also across runs,
  `lastPortalRide`): the cannon ride, Space trip, Volcano eruption, Deep sea
  dive, Pinball machine, Storm & tornado. The ride clears everything ahead
  (0.2 s fade, never judged), fades the spike strips out, ignores input and
  cannot end the run (mistakes, rims, spikes are off). The bird follows the
  ride path (from the live scroll speed to 480 pt/s over 2.2 s) through 11
  rings at equal arc length — each a perfect pass (+1 score, +2 coins,
  banner, tier sound, burst, shake), so a ride is +12 score / +24 coins with
  the portal; then the theme's exit moment, a launch flight (560 / −640
  pt/s, g 520, 1.7 s), the glide home to (70, viewHeight / 2) (2.5 s +
  0.6 s settle, `pu_land`) while the strips fade back in with their teeth
  racing right to left. Normal hoops resume so that the first one reaches the
  bird ≈ 1 s after the landing. The run clock keeps running; a running
  Hourglass / Mini / Frenzy is paused for the ride. Ride points carry the
  `ride` flag in the versus timeline.

### WP-3c — Bullseye, Ring Train, Spring Ring, Lucky Spin, FEVER (PRD-2 §3.19, §3.22–§3.25)

- DEVIATION (PRD-2 §3.22–§3.25): four new special hoops replace a normal
  hoop slot when the run director picks them. **Bullseye** (+3 coins when the
  bird centre crosses within ±12 pt of the ring centre), **Ring Train** (three
  rings 56 pt apart, one slot; all three passed → +3 coins), **Spring Ring**
  (a pass sets vy −770 up / +420 down and ignores flaps for 0.45 / 0.28 s;
  the next ring sits 240 pt away), **Lucky Spin** (a pre-rolled wheel prize
  of +2…+20 coins paid when the wheel stops ≈ 0.9 s after the pass). Each is
  otherwise a normal hoop (score, coins, streak, rim bounce).
- DEVIATION (PRD-2 §3.19): the **FEVER ring** — a perfect pass sets the
  streak to max(5, streak + 1) and sets the bird on fire (visual only) until
  the streak breaks (graze, save or death). A rim touch on it is a normal
  pass. The fire goes out at the rim contact itself, not when the pass
  resolves (Fix P3 R1, S6-40); ride rings never put it out.
- DEVIATION (PRD-2 §3.23, director): the spring's 240 pt room is checked
  against the band rule (tooth lines − opening/2 − 7 − 18), not the row's
  centre range, and the ring after a spring may leave that range — otherwise
  springs could never appear on 568 pt screens before hoop 50.
## PRD-2 comet boost (WP-3a, 2026-10-08)

- DEVIATION (PRD-2 §3.8 / §5.6, new powerup; 1.0 had none): from hoop 10–30
  (then every 45–60 hoops; never within 10 hoops of a portal, in the squeeze
  window, or while a timed powerup runs) a **comet star** hangs 20 pt past
  the plane of an upright, still normal hoop, at its centre (46 pt gold
  4-point star with a pink / gold tail, wobble ±14°, pulse ±8 %, hit radius
  18). Touching it (or a pair's COMET gift) starts a **10 s boost**: the
  scroll eases to **1.7 × cruise** in 0.45 s and back over the last 0.9 s;
  the bird rides inside a comet fireball (bird 90 %, gold shell with a pink
  rim, gold / pink tail, a gold countdown ring r 34 draining over the 10 s,
  "Ns" 50 pt below) and **flies itself** to the ring nearest its line of the
  next hoop (taps ignored, ±25° tilt); white speed streaks cross the screen.
  The boost is a ride: rims are ignored, mistakes (spikes, closed switches)
  are ignored, every hoop passed is a **perfect pass** (banner, burst, +2
  coins, tier sound, ring field), hoops spawned during it are upright and still at the
  curve size of their index (PRD-2.4 §2; was 118 pt). Sounds `pu_comet_get`, `pu_comet_loop` (30 %, from
  1.2 s, 0.3 s fade), `pu_comet_end`. At the end the bird pops back (white
  flash, squares, gold ring) at its current height and control returns; no
  invulnerability afterwards. The streak carries on; the shield and the
  extra life stay armed. Analytics `comet_collected {source: hoop | pair}`.
- Tests: `test/run/items/s3_8_comet_test.dart`,
  `test/run/items/s3_8_comet_autopilot_test.dart`; shots in
  `test/run/shots/comet_shots_test.dart`.

### WP-3d — saw rings, switch rings, pairs of powerup rings (PRD-2 §3.18, §3.20, §3.21)

- DEVIATION (PRD-2 §3.18 / §5.17, new mechanic): from hoop 20 a **saw ring**
  (Live Wire, Frost Ring or Black Hole, picked at random, never the same twice
  in a row per run) replaces a slot. Its rim is deadly: touching either rim-end
  circle (r 5, Black Hole 6) is a mistake (`saw`) instead of a bounce — the
  design's death moment plays (Live Wire held 0.6 s, Frost Ring ice block
  0.4 s, Black Hole 0.8 s and no body), then the usual tumble; an extra life /
  shield absorbs it and the ring counts as passed with no score. Its opening is
  +28 pt; a clean pass is an ordinary perfect hoop. The Black Hole pulls the
  bird toward its rim within 34 pt (260 pt/s², 570 at the inhale peak, 0.9 s
  every 3.4 s) and bends the spike strips (visual only). Rides ignore saw rims.
- DEVIATION (PRD-2.2 §25): saw rings have exactly the normal opening at that
  hoop (`sawExtraOpening = 0`, was +28 pt; Big Hoops still enlarges them), and
  the saw / FEVER decoration (glow, swirl, ripples, sparks, crystals, stars,
  plasma loops, beam, halo) scales by `ry / ryDesign` (designed at 146 pt saw,
  118 pt FEVER). Rim thickness, rim-end colliders and the 34 pt pull range are
  unchanged; the portal ring stays 118 pt.
- DEVIATION (PRD-2 §3.0.5, themed deaths): a themed death hands over to the
  revive offer / results after its moment + up to 1.5 s, at most 2.2 s (switch
  crashes have no held moment: 1.5 s); the Black Hole hands over 0.6 s after
  the swallow.
- DEVIATION (PRD-2 §3.20 / §5.19, new mechanic): from hoop 12 a **switch
  ring** (Lockdown, Laser Gate, Power Iris, Snoozer, Gift Wrap) spawns closed
  with its switch pickup in the gap before it. Touching the switch (hit radius
  18) opens the ring at once (animation ≤ 0.8 s) and gives +1 coin; reaching
  the plane while closed is a mistake (`closed_switch`, knock straight back,
  the red crash word); a save makes it count as passed with no score. A comet
  opens a closed ring by itself. The switch is always 70–100 pt above / below
  its ring centre **and** ≤ 110 pt from the previous hoop centre; when the
  ring's drawn height leaves no such spot the ring moves to the nearest
  band height that does (else the slot becomes a normal hoop) (Fix P3 R1,
  S6-45).
- DEVIATION (PRD-2 §3.21 / §5.20, new mechanic): from hoop 12 a **pair** of
  two rings (offset 230 × viewHeight / 711) holding gift boxes replaces a
  slot. Through one ring: a normal pass plus its gift (Shield arms the shield,
  Comet starts the boost, +10 coins, +5 score flagged `gift`, FEVER sets the
  streak to at least ×5 and lights the fire); through neither: a miss
  (`pair_missed`).

### WP-3g — spike squeeze (PRD-2 §3.17, §5.16)

- DEVIATION (PRD-2 §3.17 / §5.16, new mechanic; 1.0's spike strips never
  moved): at a random 60–120 s of `runClock` (again 60–120 s after each
  squeeze has opened; a moment inside a ride or a revive waits until it ends
  + 2 s) both spike walls warn (1.5 s: shake, red teeth, falling bits), close
  in over 3 s (ease-in-out), lock, hold a random 10–20 s (ticks in the last
  3 s) and open over 3 s. Each wall moves (band − open) / 2 with the open
  space 50 / 45 / 40 / 35 % of the screen for squeezes 1 / 2 / 3 / 4+, never
  under 230 pt (134 / 152 / 170 / 187 pt at 711; 98 / 112 / 125 / 125 at
  568). The moving tooth lines are the spikes (contact = a mistake; saves
  bounce off the squeezed line; the death tumble rests on the squeezed
  floor). From 3 s before the warning until open, new hoops and pickups fit
  the coming squeeze's band. A revive resets a running squeeze to open over
  0.5 s; the interrupted squeeze counts toward the tightening.

### WP-3f — powerup capsules: Hourglass, Mini Bird, Coin Frenzy (PRD-2 §3.30–§3.32)

- DEVIATION (PRD-2 §3.30–§3.32 / §5.29–§5.31, new powerups; 1.0 had none):
  from gap 10 (weight 20, ≥ 20 gaps apart, never while a timed powerup, a
  ride or the squeeze window runs) a **powerup capsule** (34 pt rounded
  square, bobbing in a pulsing ring, hit radius 18) floats mid-gap on the
  line between two hoops: Hourglass 35 %, Mini Bird 35 %, Coin Frenzy 30 %.
  Flying into it starts the powerup at once (banner with its name and one
  line, start sound, a timer pill near the top). Only one timed powerup
  (these three and the comet) runs at a time; its timer counts real time,
  stops while a portal ride pauses it (the effect is suspended for the ride)
  and a death ends it.
  - **Hourglass** (10–20 s, rolled at pickup): the whole world, bird
    included, runs at **45 %** (scroll, gravity, flap, spawns, moving rings,
    animations and every `runClock` timer), easing in / out over 0.2 s; the
    HUD stays real time; music at 72 %; blue tint + vignette, ghost birds, a
    clock ring with a turning hand, a tick every 0.6 s.
  - **Mini Bird** (8 s): the bird and its collider shrink to **52 %** (0.15 s
    ease; rims, spike strips, pickups); physics unchanged; it pops back at the
    end (a rim touched while growing bounces as usual).
  - **Coin Frenzy** (6 s): every ring not yet passed is a gold coin ring; each
    ring passed pays **+5 coins on top** of the normal ring coins (source
    `frenzy`), with a coin shower and a pulsing gold border.
- Analytics `powerup_started {type: hourglass / mini / frenzy, duration}`,
  `powerup_ended {type}` (never for the comet).
- Tests: `test/run/items/s3_30_s3_32_capsules_test.dart`,
  `test/run/items/s3_30_capsule_autopilot_test.dart`; shots in
  `test/run/shots/capsule_shots_test.dart`.
## PRD-2 collectables: Star Trail, Egg, Piggy Bank, Firefly Jar (WP-3e, 2026-10-08)

- DEVIATION (PRD-2 §3.26 / §5.25, new collectable; 1.0 had none): a **Star
  Trail** is 8 gold 4-point stars on an arc from 40 pt after to 40 pt before
  the next hoop, bulging 40 pt up, joined by a 2/6 dotted gold line (hit
  radius 10; a sparkle + the next C-major note per star). Touching all 8 in
  one trail adds 8 to `caught`; when the last star is behind the bird the
  trail ends — **all 8** shows PERFECT LINE "8 / 8 stars · +5 coins", pays
  +5 (`star_trail`) and plays the chord; fewer pops "n / 8" and pays
  nothing, and a single star pays nothing on its own.
- DEVIATION (PRD-2 §3.27 / §5.26, new collectable): an **Egg** pickup
  (mid-gap, on the line) goes on the bird's back ("EGG! hatches in 5
  rings"). Every ring passed — ride rings too — cracks it (countdown 4…1 +
  wobble); after 5 it hatches into a `golden` **chick** that flies ≈ 36 pt
  behind / 10 pt below the bird. While the chick lives **every** coin
  `RunContext.earn` pays is doubled (ring coins, bonuses — and the piggy
  pay-out), tracked as `coins_doubled`; a gold ×2 pill sits under the score.
  A rim touch scares the chick away ("bye!", "×2 LOST"); a crash before
  hatching breaks the egg; a save (shield / extra life) loses it; a
  revive-offer death loses it too (WP-2d clears `RunState.egg`).
- DEVIATION (PRD-2.2 §23, P22-G2): **any rim touch while still an egg
  breaks it** (also a graze the bird survives): the shell pieces (the
  hatch's shell triangles + yolk-yellow pieces) fall away with `egg_crack`,
  no banner, no other sound, `egg_broken {cause: rim, cracks}`; the touched
  hoop does not crack. A clean off-centre pass still cracks it. **Ride rings
  (portal and comet) neither crack nor break the egg.** After hatching, a
  crash, and the spawn rules are unchanged.
- DEVIATION (PRD-2 §3.28 / §5.27, new collectable): a **Piggy Bank** grab
  starts a bank ("PIGGY BANK") of exactly 20 coins — 4 in the piggy's own
  gap, then 4 per gap × 4. Caught coins go into the bank (they fly into the
  HUD piggy), uncaught ones are missed. When all 20 resolve the piggy
  smashes and pays **×2 of what was caught** (`piggy`) — the chick's ×2
  stacks on top. The HUD piggy shows "n / 20", a 90 pt bar and "n missed";
  a crash before the pay-out loses the bank (also with a revive), a save
  keeps it. A portal ride removes the on-screen (and planned) coins
  **without counting them missed**; the bank stays open and the director
  places those coins again after the landing — the pay-out only comes once
  all 20 are caught or missed (Fix P3 R1, S6-41). During a squeeze window
  no new bank coin fields or firefly swarms are placed; they wait for the
  reopening (§3.17, S6-46).
- DEVIATION (PRD-2.2 §26): bank coins are 16 pt (was 8) with a 14 pt catch
  radius (was 10; the miss rule uses it too); a caught coin leaves at 16 pt
  and shrinks into the HUD piggy over 0.35 s. Positions, spin and the 18 pt
  bulge are unchanged.
- DEVIATION (PRD-2 §3.29 / §5.28, new collectable): a **Firefly Jar** pickup
  (animated: bob ±5, sway ±7°, lime glow, rays, 4 fireflies inside) starts a
  jar ("FIREFLY JAR"); from then on each following gap has a swarm of 7
  fireflies weaving ±45 pt around the line (catch radius 16). Caught
  fireflies glow into the HUD jar ("n / 20" `#7CB518`); an uncaught one
  escapes and lights a red ✕. 20 caught = JAR FULL +25 (`jar`); 3 escaped =
  JAR BROKE, no reward; either way the jar and its fireflies are gone. A
  crash loses it (also with a revive), a save keeps it. A portal ride
  removes the swarms on screen without counting escapes.
- DEVIATION (PRD-2 §5.26 / §5.27, HUD placement): the collectable badges
  (`run_badges.dart`) are **left-aligned** under the score (x 46–172, y ≈
  216), matching `lab_piggy3`, while WP-2d's score circle is centred; the
  egg ×2 pill can therefore sit just above the circle rather than directly
  under it as in `lab_egg3` (the same call WP-2d made for the HUD row).
- DEVIATION (PRD-2 §5.25 / §5.26, the rising pop): the shared `TextPop` is
  centred on its `at` point, so "EGG! hatches in 5 rings" is anchored at
  the bird + (70, −36) and may run to the 320 pt edge; the mocks left-align
  their pops. No other collectable look differs from the mocks.
- Tests: `test/run/items/s3_26_star_trail_test.dart`,
  `s3_27_egg_test.dart`, `s3_28_piggy_test.dart`, `s3_29_jar_test.dart`,
  `s3_26_29_collect_autopilot_test.dart`; shots in
  `test/run/shots/collect_shots_test.dart`.
### WP-5b — versus client, VS intro, versus results (PRD-2 §3.13, §5.7, §5.8, §5.10)

- DEVIATION (PRD-2 §3.13, new mechanic; 1.0 runs were always solo): every
  run is a duel against a **real player's recorded run** when one is
  prefetched (a Firebase pool read at app start / home, matched locally:
  same level and below my best → any run → solo; never my own runs, no
  repeat within a session). START takes the prefetched opponent at once and
  plays the ≈ 7.3 s VS intro (not skippable, taps do nothing), then the run;
  with no opponent START goes straight into a solo run. Their score replays
  their timeline on my `runClock` (stops in pause, the revive offer and the
  phoenix, slows with the Hourglass) and their box dims when their run ends.
  At the end WIN (higher), LOSE (lower) or DRAW (equal) on the final scores;
  a win pays +10 coins, a draw +5 (`win_bonus`), credited before the summary
  so YOUR REWARD includes them. Runs (score ≥ 3; a new best always, others
  ≤ 3 per UTC day) are uploaded through a persisted queue, one run per
  write, retried when online. Every Firebase failure means a solo run.
- (`Fix P45 R1`) S6-60: the queue also paces non-best writes to 3 per UTC
  *upload* day (the server's rate day), so an offline backlog is written
  over the following days instead of being rate-rejected and lost; a new
  best is never held back. S6-66: a failed start-up auth recovers without a
  restart (background retries with doubling waits 5 s → 2 min, and at once
  on app resume, Home prefetch, a run submit and before every flush).
  S6-65: the own name on the VS plate, the HUD chip and the results card is
  the generated nickname (WP-AV; was: or the Play Games name) ("You" only with no
  identity at all). S6-64 (superseded by WP-AV sticker avatars): avatars (the
  Play Games icon image / the uploaded avatar URL) were drawn from one in-memory cache on the plates, the HUD and
  the results card; the neutral glyph shows while one is missing.
- DEVIATION (PRD-2.2 §2, P22-2): a **mode button** above START chooses
  VERSUS (the default) or FREE FLY (remembered in `homeMode`; "Delete my
  data" resets it to VERSUS). FREE FLY never takes the prefetched opponent:
  no VS intro, no versus bar, no WIN / LOSE / DRAW, no win / draw bonus, the
  solo results page; everything else (revive, bonus, level-up, collectables,
  coins) is the same, and the run is still queued for upload under the same
  rules. VERSUS is unchanged.
- DEVIATION (PRD-2.2 §3, P22-2): matching reads **every shard of the own
  level** (random order), then the other levels nearest first (lower before
  higher at each distance), stopping at the first shard with a usable
  opponent; ≤ 44 reads, a 6 s limit, once per Home visit (a new search after
  each run start). The candidate rules inside a shard are unchanged.
- NOTE (PRD-2.2 §4): a solo VERSUS START shows nothing extra; the reason is
  logged only (`versus_solo`, logcat, debug panel).

### WP-4c — "Delete my data" and the persistence audit (PRD-2 §3.13 Q22)

- DEVIATION (PRD-2 §3.13, new action; 1.0 had no online data): Settings gains a
  **DELETE MY DATA** row (between the credit and Privacy Policy, 565 pt at 711 /
  425 pt at 568 — clear of the 44 pt bottom spike strip) that opens a confirm
  card in the P1 popup style (trash glyph, CANCEL / DELETE) and, on DELETE,
  calls `VersusService.deleteMyData()`. The callable deletes the player doc,
  the pool entries and the Firebase account; the client then resets the
  Analytics ID and the local versus state (nickname regenerated, upload queue
  and daily counter cleared). **Coins, skins, levels, feathers, puzzle pieces
  and met elements are kept** (Q22) — nothing else on the phone is touched.
  Offline or a refused call deletes nothing, keeps the account and local state
  for a retry, and the card says so ("COULDN'T DELETE"); the server side is
  all-or-nothing (`Fix P45 R1`, S6-61: one transaction for the player, rate
  and pool data after an Auth reachability check); success shows
  "DATA DELETED". CANCEL, ✕, Esc and the dim dismiss without a call.
  `deleteMyData()` therefore returns `Future<bool>` (`true` = deleted).
- The local reset is `GameStorage.resetVersusData()` (region WP-4c); the versus
  keys and their defaults are unchanged (PRD §7 table) and the audit test
  checks every §7 key plus `levelRewardPayout` (the P2-fix recovery record).

### WP-4a — golden feathers, balloon bonus, puzzle pieces (PRD-2 §3.15, §3.16)

- DEVIATION (PRD-2 §3.15 / §5.14, new meta collectable; 1.0 had none): once
  per run (gap after a random hoop 3–12, pushed to the next free gap; never
  in a ride or the squeeze window; only while fewer than 3 are held) a
  **golden feather** floats 0.65 × spacing after a hoop and 64–200 pt above
  its centre (a detour, hit radius 18). Touching it **banks it at once**:
  the persistent `feathers` count (0–3) goes up, so a death or an app kill a
  second later keeps it; a revive is the same run (no second feather). It
  flies into a 3-slot feather tray on the HUD; the 3rd plays the
  set-complete celebration and the BONUS UNLOCKED! sticker. Feathers change
  nothing in the run (score, coins, streak, duel).
- DEVIATION (PRD-2 §3.15 / §5.14, new post-run screen): with 3 feathers the
  run ends on the **balloon bonus** before the results page (after a
  declined revive offer). Opening it sets `feathers` to 0. Nine balloons hide
  25, 25, 50, 50, 75, 75, 100, 150 and the 250 jackpot (shuffled); each tap
  uses one feather (taps ignored ≈ 1.1 s while a balloon opens) and credits
  the prize to the wallet **at once** (source `bonus`). Out of feathers: a
  once-per-screen rewarded ad (`bonus_feathers`) gives 3 more (superseded by
  PRD-2.2 §7.7 / §7.8 below: everyone watches the ad, and the offer waits up to
  5 s for one); NO THANKS (after 3 s) / NEXT go to
  the results; unpopped balloons are never revealed. The results' YOUR
  REWARD does not include these coins.
- DEVIATION (PRD-2 §3.16 / §5.15, new meta collectable): once per run (gap
  after a random hoop 14–25, placed like the feather, hit radius 22) a
  **puzzle piece** — always one the player does not hold yet — floats in
  the colours of the open round. Touching it banks it (persistent 4-bit
  `puzzlePieces`). The 4th piece pays **50–250 coins** (uniform, step 5,
  source `puzzle`) at that moment in the run — included in YOUR REWARD;
  doubled by the chick since PRD-2.2 §13.1 (P22-FIX1, S7-03) — and resets the mask to 0 with `puzzleRound` + 1 in
  the same step; the next round has the next of 8 colour themes (looped).
- DEVIATION (PRD-2 §3.0.1 / §5.14, balloon bonus; `Fix P45 R1`, S6-63): the
  bottom band (feather row, ad button, NO THANKS, NEXT — reference y ≥ 552)
  is unscaled and bottom-anchored on every height 568–730, so NEXT keeps
  292 × 50 and its 99 pt bottom gap; only the column above (pill, hero,
  grid, prompt) scales, into the space the band leaves (0.72 at 568).
- (`Fix P45 R1`, S6-62) the 4/4 completion is recoverable: a `puzzlePayout`
  record (the balance to reach) is written with the mask reset + round
  advance before the coin write and cleared after it; a kill in between is
  paid at the next start, exactly once.
- Call: the feather tray / puzzle pill sit at y 288 (not the PRD's 230) so
  they never overlap the y-190 banner band or the y-156 timer pill.
- Tests: `test/run/items/s3_15_feathers_test.dart`,
  `test/run/items/s3_16_puzzle_test.dart`,
  `test/run/screens/s3_15_bonus_screen_test.dart`,
  `test/run/items/s3_15_s3_16_collect_autopilot_test.dart`; shots in
  `test/run/shots/collect_shots_test.dart`.

## PRD-2.2 scoring: perfect zone, hoop rumble, points, results ticks, streak names (WP-G1, 2026-10-12)

- DEVIATION (PRD-2.2 §11, replaces PRD-2 §3.0.4 5 / §3.4 "perfect pass = no
  rim touched"): a pass is **perfect** only when no rim was touched **and**
  the bird's centre crosses the plane within ±min(24, 0.2 × opening) pt of the
  passed ring's centre (`PerfectConfig`, measured in the ring's moving frame
  at the crossing: `Hoop.passOffset`; pairs / trains per ring). Three
  outcomes: **perfect** (+2 coins, streak +1, banner, burst, tier sound,
  shake), **clean** (no rim, outside the zone: +1 coin, streak reset, no
  banner and no GRAZE notice, `point` + ring pulse, one knock) and **graze**
  (a rim was touched: +1 coin, streak reset, GRAZE notice, no rumble at the
  pass). Ride rings stay always perfect; only a perfect FEVER pass lights
  the fire; a bullseye is always also perfect (±12 lies inside the zone) and
  is judged on the same crossing offset (P22-FIX1, S7-04).
  `RunSummary.cleanPasses`, `run_end.clean_passes`.
- DEVIATION (PRD-2.2 §10, supersedes PRD-2 §3.33 on these points): a rim
  touch **knocks at the moment of contact** (`RimTouched`; a lethal saw touch
  or a touch in the frame of a death doesn't rumble), a graze pass adds
  nothing, a clean pass knocks, and the perfect-pass shake is **80 ms** at
  255 (was 45 ms). Throttle, pickups and "shake wins" unchanged. The plugin's
  `hasVibrator` / `hasAmplitudeControl` probe is logged once in debug builds.
- DEVIATION (PRD-2.2 §29, supersedes the PRD-2 §3.4 tier-name table and
  its 5 banner colours): the streak banner shows **50 bird-themed names**
  (`StreakConfig.names`: ×1 PERFECT, ×2 GREAT ×2, ×3 ON FIRE ×3, … ×50 FLAPPY
  GOD ×50; from ×51 FLAPPY GOD ×n) in **10 rotating colours**
  (`StreakConfig.colours`, streak n → colour ((n − 1) mod 10) + 1, white
  text). The banner font follows the long-name rule min(34, 300 /
  (characters × 0.72)) for every name (the approved
  `screen_streak_names.html`; the old fixed per-tier sizes are retired).
  Tier effects (cap 10), sounds, look, place and timing are unchanged;
  analytics keep sending the streak number.
- DEVIATION (PRD-2.2 §13, supersedes PRD-2 "+1 point per hoop", §3.0.4 5 /
  §3.4): the **score is points**. A non-perfect pass (graze or clean) is 1
  point, a perfect pass max(2, streak) with the streak *after* the pass (×3 =
  3, ×12 = 12, no cap; FEVER and ride rings follow their streak); every coin
  bonus (bullseye, train, pair +10, Lucky Spin, Star Trail, jar, piggy, Coin
  Frenzy, switch, puzzle) also pays its amount in points (`RunContext.earn`,
  `PointFlags.bonus`); the pair "+5 score" gift is +5; the chick doubles
  points like coins (the puzzle bonus too, in coins and points: P22-FIX1,
  S7-03); the versus win / draw bonus pays
  0 points. **Coins are unchanged** (1 / 2 per hoop + bonuses). The big
  circle shows points and counts up over 0.3 s (ease-out) with a small pop
  for gains above 1; its font is min(125 pt, the size at which the widest
  number of that digit count, measured with the real LVDCC metrics, fits the
  183 pt circle with a 12 pt side margin) (P22-FIX1, S7-01), so it changes
  only with the digit count and every score fits. NEW BEST, levels, the leaderboard and
  versus use points; colour stages, revive eligibility, the opening curve
  and the director still count hoops. `run_end` sends `score` (points),
  `hoops` and `max_streak`. The streak feature now runs before scoring.
- DEVIATION (PRD-2.2 §13.5, versus timeline **v2**): one entry per score
  change with its value (`fl` = version byte 2 + flag byte + uint16 value per
  entry; the 11 `RunEntry` keys and the rules are unchanged); the server
  checks sum of values == score, the 0.9 s gap per plain entry (ride / train
  / gift / bonus exempt; measured from the previous entry that is not a
  bonus, so a bonus never restarts the interval: P22-FIX1, S7-02) and a
  plausibility cap per entry (pass ≤ 2 × (pass entries so far + 5), bonus ≤
  80 = 2 × the 40-coin piggy, a puzzle completion entry — flag puzzle 16
  with bonus 8 — ≤ 500 = 2 × 250, gift ≤ 10: P22-FIX1, S7-05), and rejects v1 uploads
  (`version`); the client skips v1 pool entries. The 2.1 pool runs are
  converted once (value 1 per entry) by `functions/scripts/convert_pools_v2.ts` (one-off, removed in audit 17; in git history).
- DEVIATION (PRD-2.2 §14, supersedes the "—" sound at 0.45 s of the PRD-2
  §5.10 timeline): the results count-ups play **one `sk_tick` stream** —
  min(24, 8 + the largest running count: your points, the opponent's points,
  YOUR REWARD), spread along the eased count (at most one per frame), and the
  same rule on the claimed amount during the 0.9 s CLAIM count. A count of 0
  plays none; NEXT mid-count stops them.
- Tests: `test/p22/s14_results_ticks_test.dart`, `test/p22/s13_points_test.dart`, `test/p22/s13_versus_timeline_test.dart`,
  `test/p22/s13_score_circle_shots_test.dart`, `functions/test/timeline.test.ts`,
  `functions/test/convert.test.ts`, `test/p22/s11_perfect_zone_test.dart`,
  `test/p22/s10_hoop_rumble_test.dart`, `test/run/items/s3_33_rumble_test.dart`,
  `test/p22/s29_streak_names_test.dart`.

## PRD-2.2 gameplay banner and the video ad after a run (WP-7a, 2026-10-12)
- DEVIATION (PRD-2.2 §7.5, new; 1.0 had no banner): during a run with a banner
  the playfield is shorter by the banner strip (visible height = screen − banner,
  clamped to [`Config.minRunViewHeight` 500, 730] instead of [568, 730]). Menus
  keep the full height; it shrinks at START (before the VS intro) and grows back
  on the Home arrival. NO ADS owners, no consent, Test Lab and E2E builds: no
  banner, no resize (the 2.1 layout).
- DEVIATION (PRD-2.2 §7.5.4): in a run with a banner the bottom spike strip is
  lowered by `Config.bannerStripDrop` (20 pt): only its 18 pt teeth + 6 pt base
  show, and the deadly tooth line is 24 pt above the visible bottom edge
  (`bottomStripInset`). Implementation: `viewHeight` = visible + 20 and the
  camera shows only the top `visible` points, so every run layout keeps its
  44 pt strip arithmetic (this is how the approved mock frames were rendered).
  The top strip is unchanged.
- DEVIATION (PRD-2.2 §7.6, new): NEXT on the results page plays an
  interstitial before Home unless: NO ADS, `gamesPlayed <= 3`, a rewarded ad was
  displayed in the run, < 60 s since the last full-screen ad closed, none
  loaded, or the app is in the background.
- DEVIATION (PRD-2.3 §18, supersedes the `gamesPlayed <= 3` guard above): the
  new-player grace lasts until **5 finished runs or 300 s of foreground
  playtime since install**, whichever comes first (`ads_grace_runs`,
  `ads_grace_seconds`); no best-score gate. Nothing preloads during it. The
  playtime counts only while resumed and outside full-screen ads, is saved
  every 10 s in every foreground state (menus, waiting, flight, results), on
  going to the background and at run end, and is kept by "Delete my data"; a
  crash loses at most 10 s. The interstitial preload uses the same finished-run
  predicate as the show: a grace that ends with a run's finish loads at that
  run's end. Skip reason `new_player` replaces `first_runs`. (The earlier
  "write waits until Home" deviation was withdrawn by fix S8-09.)
- DEVIATION (PRD-2.3 §23, rating prompt): a run whose results page requests
  the store's rating sheet (run 5 — `rate_min_runs` — or a new best after it)
  has **no interstitial** (skip reason `rating`). The request waits 1.5 s
  after the results page has settled, with no overlay open; NEXT before that
  means no request and no cooldown. At most once per 30 days
  (`lastRatingRequestAt`). Native sheet only (`in_app_review`).
- DEVIATION (PRD-2.3 §24, No-Ads popup): the schedule checks every Home
  arrival after a run as well as the session start; the gap is 1 h from the
  last show (closing no longer restarts it), the cap is 5 a local day and the
  fallback 3 h. Never on the arrival of a run that requested the rating sheet
  or when a gift came up on that visit (PRD-2.3 §0 item 2); at most one offer
  per arrival.
- DEVIATION (PRD-2.3 §24.3, launch ownership; fix S8-13): the session's
  first START waits for the launch purchase sync still running (its grants
  applied), at most `Config.launchOwnershipStartWait` (1.5 s of game time),
  so a No Ads restored or redeemed at launch removes even the first run's
  banner. Once the sync has settled, START is immediate as before; a No Ads
  bought during a run still applies from the next run.
- DEVIATION (PRD-2.3 §26, Shop and Skins lock): below a best of
  `ui_unlock_best` (25) the Shop and Skins screens open dimmed under a lock
  overlay (#000000 at 72 %, two centred lines); only the back button and the
  coin pill work; the overlay leaves the back button's box undimmed (its
  artwork is the shared corner box below the screens, fix S8-12). The Home
  tiles show a lock badge and no NEW tag while
  locked. The revive shop's GET COINS is never locked. Unlocking is silent.
- Tests: `test/p22/s7_ads_test.dart`, `test/p22/s7_banner_layout_test.dart`
  (autopilot gate + run screens at 663 / 596 / 524); shots
  `test/p22/s7_banner_shots_test.dart` → `build/p22_banner_shots/`.

## PRD-2.2 run director: scroll-in, random opening, one bonus at a time (WP-G2, 2026-10-12)

- DEVIATION (PRD-2.2 §15, P22-G2): **nothing pops into view.** The run
  director plans **one slot ahead**: slot B (kind, centre, attached items,
  the gap after it) is planned when the hoop before it spawns, one full gap
  before B's own hoop spawns (still 60 pt past the right edge). Every line
  item between two hoops (heart, shield, capsule, Star Trail, …) and every
  attached item (the switch, the comet star) is created off-screen and
  scrolls in. Accepted side effect: decisions that react to the run state
  (a heart after a lost life, the Big Hoops multiplier, the squeeze window)
  are taken ≈ 1.5 s (one gap) earlier. A ride or a revive that starts after
  the planned-ahead slot was planned turns that slot into a plain hoop
  (§3.0.3 slot order 1–2 keep holding). The run's first slot is never a
  switch ring (its switch would be on screen). Feature follow-ups placed at
  a grab (the piggy's own coins, the jar's first swarm) that start inside
  the screen **pop in** (scale 0 → 1.15 → 1 over 0.25 s + a small sparkle);
  the director's follow-up fields come with the normal gaps, off-screen.
- DEVIATION (PRD-2.2 §19, P22-G2; supersedes PRD-2 §3.0.3 / §3.15 / §3.16
  table values): **a different opening every run.** The first heart comes at
  a **random gap 5–27** (then every 17–27, as before). Indices **4–9** make
  one equal-chance draw each from {Star Trail, Bullseye, angled ring,
  nothing} (instead of the special / optional rolls; Bullseye and the angled
  ring may come from 4 here; min distances still hold). The **golden feather
  and the puzzle piece come in ≈ 60 % of runs each** (rolled at run start),
  at a random gap 3–40, at most once, never in the same or a neighbouring
  gap; `run_end` carries `feather` / `piece` 0 / 1. **Single pickups**
  (heart, shield, capsule, egg, jar, piggy, feather, piece) sit at a random
  point **30–70 % along the gap, up to ±50 pt off the line** (replacing
  mid-gap, the heart / shield off-line offsets and the feather / piece
  detour), kept 40 pt inside the teeth; patterns keep their shape (a Star
  Trail's arc and a coin line's bulge stay inside the margin too), the
  piggy coins' and swarms' start moves inside the gap.
- DEVIATION (PRD-2.2 §27, P22-G2; supersedes PRD-2 §3.0.3 "Exclusivity" and
  "Rides and what is already spawned"): **one bonus at a time.** Activities
  are a comet ride, a portal ride, a Piggy Bank run, a Firefly Jar run and a
  capsule power-up (`RunState.activity`, derived from the features' state).
  While one runs and for **2 hoops** after it, no reward item is planned
  (heart, shield, feather, piece, egg, capsule, Star Trail, piggy, jar, the
  comet-star hoop, pair, Lucky Spin, FEVER, portal); obstacle rings still
  come. Scheduled items (hearts, the comet hoop, the portal, the owed
  feather / piece) wait for the first allowed slot / gap. When an activity
  starts, every reward item ahead fades out in 0.2 s; the planned-ahead slot
  becomes plain if it was a reward slot (a portal / comet hoop there stays
  due); a pair, Lucky Spin or FEVER ring on screen fades its reward parts and
  passes as a normal ring; a portal on screen fades out. The feather and the
  piece are owed and placed again; everything else is just back in the draw.
  Carrying the egg / chick, a shield, an extra life, Big Hoops, the fire and
  FEVER are not activities.
- Call (§19 / §26, P22-G2): piggy coins sit **45 pt apart** in a field
  (approved mock B), centred in it; the own-gap coins start 20 pt after the
  piggy, and when the piggy sits too late in its gap for them to end 40 pt
  before the next hoop they go in the gap after that hoop instead.
- Call (§25.1, P22-G2): the portal ring is a fixed **118 pt** at every hoop
  (it had taken the shrinking opening); PRD-2.4 §2.3: also with Big Hoops.
- DEVIATION (PRD-2.2 §21, P22-V2; supersedes PRD-2 §3.19 Q51 "only the
  FEVER ring lights the fire" and the PRD-2 §3.5 / `TierTrail` trail scale):
  the **3rd perfect pass in a row sets the bird on fire**; it burns until the
  streak breaks (graze at the rim contact, a §11 clean off-centre pass, a
  save, a death) and goes out with smoke + `fever_out` (no sizzle on a
  death); a revive starts without fire. One fire master
  (`FeverFeature` / `FireMaster`): flame teardrops from the bird's back
  (40 %), top (35 %) and bottom (25 %, half lift) edges, vx −130…−60,
  vy −80…−20 pt/s, life 0.3–0.55 s, with a warm halo, behind the bird
  (bird − 1, over the trail at bird − 2), no outline. Size by streak:
  ×3–×4 55/s 70 % (halo 34 pt / 22 %), ×5–×6 95/s 85 % (42 / 30 %), ×7+
  150/s 100 % (52 / 38 %). Colours: a flame-type trail's four colours,
  else white → #FFF3B0 → #FF9100 → #D50000. FEVER (ring / pair gift) is
  unchanged but shows this same fire at least at the ×5 size. Kept through
  portal rides (not drawn while the ride hides the bird), hidden inside the
  comet. Sound: one `fever_loop` player at 25 % while burning, at the FEVER
  volume (0.35) during FEVER, ramping (0.3 s) between them. Every equipped
  trail is drawn at 2× (k = 2 × lookScale; Pixel blocks 16–26 pt), emitted
  18 pt behind the bird (was 26), drifting at 0.7 × the forward speed.
- FEVER itself is unchanged (P22-FIX2, QA S7-07 / S7-08; reverts the two
  P22-V2 Calls "FEVER lasts 5 perfect passes" and "no FEVER ring / gift
  while any fire burns"): FEVER lit by the FEVER ring / pair gift runs
  until the streak breaks (`RunState.feverLit`, cleared when the fire goes
  out), the loop staying at the FEVER volume; it only ramps up from the
  25 % crackle when the bird already burned. The director's "no FEVER ring
  / FEVER gift" rule reads FEVER (`DirectorContext.fever`), as before 2.2:
  an ordinary ×3 fire is passive and blocks no reward (§27.1).
- Tests: `test/p22/s21_fire_test.dart`; shots
  `test/p22/s21_fire_screenshot_test.dart` (→ `build/shots/p22/`).
- Tests: `test/p22/s15_scroll_in_test.dart`,
  `test/p22/s19_random_opening_test.dart`,
  `test/p22/s27_one_bonus_test.dart`,
  `test/p22/s27_one_bonus_director_test.dart`; shots
  `test/p22/s15_s23_s27_screenshot_test.dart` (→ `build/menu_shots/p22/`).

## PRD-2.2 rides (P22-G3, 2026-10-12)

- DEVIATION (PRD-2.2 §16, supersedes the PRD-2 §3.8 / §5.6 autopilot
  steering and the "hoops spawned during the boost" heights): **comet
  zigzag.** Hoops the director plans during a comet ride (incl. the pair's
  COMET gift) sit alternately **70 pt above / below `viewHeight / 2`**
  (`CometConfig.zigzagAmp`, every run height), upright, still, at the curve size of their
  index (PRD-2.4 §2; was full size = 118);
  the first goes to the other side of the star's hoop (the bird's height for
  the gift). A hoop whose plane the bird reaches after the predicted end of
  the ride (boost + ease-out, `CometRide.predictEndTrackX`) gets a normal
  height. Hoops already on screen or planned ahead at the pickup keep their
  heights. The comet flies `y = y0 + (y1 − y0)·(1 − cos πu)/2` over track x
  from the last hoop's plane (or the pickup) to the next ring's centre at
  its crossing (level at each hoop); the tilt is the flight direction, max
  **±35°**, turning ≤ 240°/s (no snaps).
  - Call: a hoop less than 40 pt ahead when a curve starts (the star is
    caught just before its own hoop's plane) is flown through as it is; the
    first curve leads from the bird's height to the hoop after it.
  - Call: the zigzag replaces only the centre; the director still makes
    the normal layout draw for a ride slot, so the course after the ride
    keeps its random stream.
  - The planned-ahead slot (§15) when the comet starts keeps its height,
    tilt and motion (the curve size of its index, PRD-2.4 §2; the height is only
    clamped if the larger opening needs it) (`RunDirector.plainSlot(keepGeometry: true)`,
    P22-FIX2, QA S7-12); only its reward / special kind, gifts, attached
    items and comet star go (§27). A revive still makes it fully plain.
- DEVIATION (PRD-2.2 §17, supersedes the PRD-2 §3.8 "Ending" line on these
  points): **comet landing.** When control returns (`CometRide._finish`,
  every comet ride incl. the pair's COMET gift) the bird does one normal
  flap (`Bird.flap()`: the tap impulse, animation and `flap.mp3`), and the
  run world runs at **0.5× for 0.8 s, then eases (smoothstep) back to 1×
  over 0.7 s** of real time (`LandingSlowMo`, `CometConfig.landing*`): it
  slows what the Hourglass slows (`RunState.timeScale` / `RunClock`), but
  quietly (no vignette, tick-tock, sweep or ghost trail; the music keeps its
  pitch). No grace period; taps work at once. With the Hourglass at the same
  time the lower scale wins frame by frame (`RunState.hourglassScale` /
  `landingScale`); pause freezes it; a death, a revive or a portal ride ends
  it. The comet activity (§27) lasts until the landing is done
  (`RunState.cometLanding`). The ease-out, the pop, `pu_comet_end` and "no
  invulnerability afterwards" are unchanged.
- DEVIATION (PRD-2.2 §18, supersedes for portal rides the PRD-2 §3.12 /
  §5.12b layer order of the ride world and the score circle, the "control
  returns" moment and the first-ring timing): **portal rides polish.**
  - In all six rides the score circle (and the banners) sit **between the
    scene's backdrop and its objects** (`RideTheme.paintBackdrop` /
    `paintWorld`, `paintExitBackdrop` / `paintExit`) at **50 %** in the
    scene's colour with the digits in its dark tone (cannon #7C4DFF /
    #3B2A8A, space #6E5BD6 / #1F1252, volcano #C2410C / #2A140D, sea
    #7FC8EE / #0B3A6B, pinball #7C4DFF / #141640, storm #8C97AB / #252C3A);
    banners keep their colours at 50 %. At the ride start the normal circle
    fades out as the scene fades in; on the way back the circle and banners
    are drawn above the wash and crossfade to the normal look over the
    launch flight (`1 − smoothstep(ft / flyTime)`), normal at the glide
    start; the circle never disappears (visible ≥ 50 %).
  - Control returns with one normal flap (`Bird.flap()`), no slow motion,
    no text.
  - The first ring's plane reaches the bird **2.0 s after control returns**
    (`PortalConfig.firstRingAfterControl`, at cruise; was ≈ 1 s after the
    landing, i.e. ≈ 0.4 s after control).
  - Every ride sound plays: the pools of `pu_portal`, `pu_land`, `flap` and
    the theme's cues are created when the portal hoop spawns
    (`SoundPreloadFeature`); also the comet star's and the capsules' cues.
- Tests: `test/p22/s16_comet_zigzag_test.dart`,
  `test/p22/s17_comet_landing_test.dart`,
  `test/p22/s18_portal_rides_polish_test.dart`; shots
  `test/p22/s18_portal_rides_shots_test.dart` (→ `build/menu_shots/p22/s18/`).
## PRD-2.2 NO ADS, bonus offer, revive, audio (WP-7b, 2026-10-12)
- DEVIATION (PRD-2.2 §7.7, supersedes the PRD-2 §3.14 no-ads rule): a NO ADS
  owner's ad step of the revive ladder is a **free revive** (`ReviveOffer.free`,
  price 0, no ad, whatever the ad availability): the pink heart with REVIVE
  only (no video / coin icon, no "NO AD AVAILABLE"), straight to the phoenix
  (`ReviveKind.free`, `revive_free_used`). Then 250, 500, 1 000 … per game as
  usual. Normal players unchanged.
- DEVIATION (PRD-2.2 §7.7, supersedes PRD-2 §3.15 "no-ads owners get the 3
  extra feathers without an ad" and PRD-1 §3.5 "owners CLAIM free coins without
  an ad"): the balloon bonus "▶ feather ×3" and the Shop's 40 free coins need a
  watched ad for everyone, NO ADS owners included (GET chip with its video
  icon). The home power-up slot stays free for owners.
- DEVIATION (PRD-2.2 §7.8): the bonus offer appears after the 3rd pop whenever
  ads are possible (consent, not Test Lab / iOS), loaded or not. Without a
  loaded ad the button waits (dimmed, spinner, no taps) up to 5 s
  (`Config.bonusAdWait`) while a load is requested; it turns active when the ad
  arrives, else fades out to NEXT. NO THANKS keeps its 3 s delay.
- DEVIATION (PRD-2.2 §7.15, supersedes the PRD-2 §3.14 / §5.9 timeout): the
  revive offer never times out. The heart drains over 5 s with the urgency as
  before; when empty the page stays up, the heart keeps pulsing at the urgent
  beat and the red edge glow settles to a steady 35 % until REVIVE or No thanks
  (§24: the only taps that react, besides GET COINS when locked).
  `revive_timeout` is gone; `revive_offer_waited {seconds}`.
- DEVIATION (PRD-2.2 §28, new): at the moment of death every run loop stops
  (`SoundService.stopAllLoops` in `RunController._die`) and the chick only
  peeps while the run is live. While a full-screen ad (rewarded, interstitial,
  the desktop fake overlay) is displayed, game audio is suspended (music
  paused at its position, loops stopped, every `play` dropped) and resumed when
  it closes. Another app's call / ringtone / alarm / assistant pauses the music
  and mutes the SFX until it ends; the player's own music keeps mixing, and if
  it plays at launch / on foreground the game music stays off until a scene
  change finds it quiet (`docs/p22/ADS.md` "§28 audio focus").
- DEVIATION (PRD-2.3 §13, 2026-10-13): the music never stays silent on a
  menu without a reason that still holds (`lib/game/music_guard.dart`). A
  notification sound (any `NOTIFICATION*` usage, or a media sound that
  starts in the foreground) pauses only the music, which resumes within 1 s
  after it ends (SFX keep playing). "Own music" needs two "yes" answers 1 s
  apart (the foreground check runs 1 s after the return) and is re-checked
  every 2 s on a menu (still never mid-run). A held interruption / notification
  is re-checked every 0.5 s and only playing players count. An ad suspend
  with no ad showing clears after 5 s; a dead music player restarts within
  5 s on a menu. `inactive` (heads-up banner, shade, system sheet) no longer
  pauses the music; only `hidden` / `paused` do. Tests:
  `test/p23/s13_music_test.dart`.
- Tests: `test/p22/s7_7_noads_test.dart`, `test/p22/s7_9_privacy_options_test.dart`,
  `test/p22/s24_revive_taps_test.dart`, `test/p22/s28_audio_test.dart`,
  `test/run/screens/s3_14_revive_test.dart`, `test/run/screens/s3_15_bonus_screen_test.dart`.

## PRD-2.2 visual layering and colours (WP-V1, 2026-10-12)
- DEVIATION (PRD-2.2 §20, supersedes the 2.0 "skin tint rule" stage blend and
  the PRD-2 look-colour rule): **the bird keeps its own colours at every
  colour stage.** The run look (bird, gear, hat) is no longer lerped 35 %
  toward the stage foreground from stage 5 (`Config.skinStageBlend` and the
  skin blend of the colour crossfade are removed). It shows its shop colours
  in runs, portal rides, the comet, revive, results and the VS intro. Kept:
  the gold bird of the perfect streak (tier 2+, PRD-2 §3.5) and the themed
  death tints (charred, frozen, X-ray; PRD-2 §5.17), which are the only blend
  of the look (`Bird.deathTint` / `deathTintAmount`). Background, spike
  strips, score circle and HUD tints still follow the colour stage.
- Tests: `test/p22/s20_bird_colours_test.dart` (stages 0, 1, 5, 10 with the
  classic and an accessory look: the bird's solid pixels equal the stage-0
  pixels; gold tier 2 and the death tint keep working); `look_visual_test.dart`,
  `home_flow_test.dart` and `look_component_test.dart` updated to the new rule.
- DEVIATION (PRD-2.2 §12, supersedes the PRD-2 §5.4 layer order of the run
  banners and the collect stickers): **banners behind the gameplay.** Every
  run banner (streak tiers, FEVER, BULLSEYE, PERFECT LINE, Ring Train, Lucky
  Spin, jar, piggy, egg, timed power-ups, SAVED, the switch crash word) is
  drawn by the run's banner layer: a screen-space layer in the **world** at
  `RunLayer.banners` (−60). Order back to front: backdrop, score circle
  (−100), banner layer (−60), guides, hoop backs, pickups, spike strips, the
  bird, hoop fronts, hit effects (fx 15), then the HUD (viewport): top row
  (heart, pause, versus bar), feather tray / puzzle pill with their fetch
  flights, sparkles and rings, graze notice, timer pill, FEVER flash; then the
  pause / revive / results / popups. The collect stickers ("BONUS UNLOCKED!",
  "PICTURE COMPLETE") are in the banner layer. The banner band keeps real time
  (the Hourglass does not slow it), freezes while the run is paused, stays on
  its screen place during a camera shake, and is hidden with the HUD (settings,
  revive shop). Positions, sizes, colours, timings and texts are unchanged.
  **Fix P3-R1 (QA S7-14…16; supersedes the first call, which kept the labels
  in the HUD):** the puzzle's `CollectText` labels (`n/4` and the coin badge's
  `+N`) are drawn by the banner layer too (`CollectLabels`, a part of the collect
  layer), at the slot's centre and fade and on the slot's clock. The pill's
  opaque panel and the badge's white box stay in the HUD on top, each with a
  1 pt window over its text; the banner layer paints the same colour under the
  window (3 pt), so the text reads through the panel. The pill, its board,
  coins, fetch flights, sparkles and rings stay in the HUD. The banner layer
  fades as one group with the HUD row (`RunHud.rowOpacity`: in while the run
  plays, out on a death), also in a ride's scene at 50 %. A death takes the
  stickers of the collect slot's active and queued items with it.
- Tests: `test/p22/s12_banner_layer_test.dart` (order, every banner kind in the
  layer, the switch crash word surviving a death's clear, the top row in the
  HUD, pause freezes a banner, the Hourglass does not slow it, the band stays
  put under a shake, the bird in front of a COSMIC band at 568 and 711 pt);
  `test/run/items/s3_15_feathers_test.dart` and `s3_16_puzzle_test.dart` (the
  stickers are in the banner layer), `test/run/screens/s5_7_hud_pause_test.dart`
  (the host lives in the banner layer), `test/run/hoops/s3_20_switch_test.dart`
  (the switch banner uses the run's host); `test/p22/s12_collect_text_test.dart`
  (the labels in the layer, the pill's window and the badge's text in the
  composite, the fade and the death teardown) and the unskipped S7-14…16 in
  `test/p22/s12_s18_s20_s21_qa_p3_test.dart`.
- DEVIATION (PRD-2.2 §31, supersedes the PRD-2 §5.10 / §5.14 page colours and
  the §5.10 level-up rays): **the balloon bonus and the results page always
  use the approved grey,** whatever colour stage the run ended on: background
  `#F1F1F1`, foreground `#828282` (`kPostRunPalette` = stage 0), the spike
  strips and the banner strip under the page included (`#828282`). The next
  run starts on its stage colours as before; the revive page keeps the run's
  look.
  - **Squeeze walls never cover the pages.** While a bonus or results page is
    up (`FlappySpikesGame.postRunPageUp`) the two run strips draw their normal
    reach in the approved grey (`SpikeStrip.onPage`): the squeeze inset and the
    warning flash are ignored, so no squeezed wall overlaps the page content.
    The revive UI (viewport) stays above the walls.
  - **Level-up rays (results only):** the same 12 gold wedges, colours, speed
    and timing, but ≈ 280 pt long (`ResultsConfig.rayRadius`, scaled with the
    page), not clipped to the stage rectangle, and drawn by the page just above
    its background, so the card, banners, rank, bar, CLAIM, reward row and NEXT
    stay on top. Each ray fades radially: 35 % at the emblem, 19 % at 45 % of the
    length, 0 at the tip (`ResultsScreen.rayFade`).
- Tests: `test/p22/s31_postrun_grey_test.dart` (page palette and pixels on
  stage 30, the next run back on its stage colours, a squeeze death keeps
  normal strips on the page, the rays' length, fade and paint placement);
  `test/run/items/s3_3_s3_7_lives_test.dart` (the SAVED! banner goes to the
  run's banner host, §12).

## PRD-2.3 §14 / §15: economy, scoring and difficulty rebalance; remote tuning

Every value below is a tuning value of PRD-2.3 §15 (`lib/run/config/tuning_defaults.dart`,
key in backticks); the numbers are the baked values. DEVIATION (audit 17, 2026-10-19):
the remote tuning is removed. The values are plain constants (they equalled the live
Remote Config values, so none changed); no build reads them from Firebase any more.
Remote Config only serves `versus_pg_salt`. Key list: `docs/p23/TUNING.md`.

- DEVIATION (PRD-2.3 §14.2, supersedes PRD-2 §3.15–§3.32 / PRD-2.2 coin values):
  **fewer coins.** Hoop 1 / perfect 2 (unchanged, `coin_hoop` / `coin_perfect`);
  Piggy Bank: still 20 coins on screen, **every 2 caught pay 1** (max 10, was ×2 =
  max 40, `coin_piggy_per`); Firefly Jar **8** (was 25, `coin_jar`); Lucky Spin
  slices **[1, 2, 3, 5, 1, 2]** (was [2, 5, 10, 3, 20, 5], `coin_spin_slices`);
  Star Trail **2** (was 5); Bullseye **1** (was 3); Ring Train **1** (was 3); switch
  **0** (was 1); pair gift **"+3 COINS"** (was +10, `coin_pair_gift`); Coin Frenzy
  **+1 per ring** (was +5). Versus win / draw 10 / 5, the shop ad (40, 5 a day, 5 min)
  and the level ladder (10,350) are unchanged. Items still add their coin amount as
  points (`RunContext.earn`). The banner subtitles say the new amounts.
- DEVIATION (PRD-2.3 §14.2, golden feather / balloon bonus / puzzle): the feather and
  the piece spawn at a random **gap 10–40** (was 3–40), 60 % per run each, at most one
  per run, **never in two runs in a row** (`Storage.lastFeatherRun` /
  `lastPieceRun` = the `gamesPlayed` of the run that showed one, recorded at the run's
  end) and **never in the same run** (both roll → the feather wins). Balloon prizes
  **[25, 25, 25, 50, 50, 50, 75, 75, 150]** (jackpot 150, was 250). Puzzle reward
  **50–150** step 5 (was 50–250).
- DEVIATION (PRD-2.3 §14.2, revive): the ad revive (free for No-Ads owners), then
  **250, 500, 1000, 2000, 4000, 8000** coins (`revive_ladder`); **after 6 paid
  revives no revive is offered that run** (was: doubling without a cap). From 6 hoops
  as before.
- DEVIATION (PRD-2.3 §14.3, supersedes PRD-2.2 §11 "perfect zone"): **perfect = a
  pass with no rim touch, anywhere in the gap.** `PerfectConfig` (±0.2 × opening, max
  24 pt) is retired; a "clean" off-centre pass no longer exists. Points are unchanged
  (1, perfect `max(2, streak)`, no streak cap); the Bullseye keeps its ±12 pt band;
  rides stay always perfect.
- DEVIATION (owner 2026-10-13, after the 2.3 release; PRD-2.3 §14.3 + §15 remote
  tuning): **optional remote perfect band.** `point_perfect_band` (keyframe curve by
  hoop index, default `[[0,0]]`): v ≤ 0 → the §14.3 rule above, unchanged; v > 0 → a
  pass is perfect only with no rim touch **and** the bird centre crossing the hoop plane
  within ±v pt of the gap centre (ring-local, `Hoop.passOffset`, measured like the
  Bullseye); a rim-free pass outside the band is a "clean" pass again (streak reset, no
  graze notice). A rim touch is never perfect; rides stay always perfect.
  `point_bullseye_band` (number, default 12) replaces the fixed ±12 pt for the Bullseye
  **hit check only**; the guide lines / target stay drawn at ±12 pt
  (`BullseyeConfig.drawBand`). Both are read once per run (`Tuning.beginRun`).
  Tests: `test/p23/s14_perfect_band_test.dart`.
- DEVIATION (PRD-2.3.1 §15, owner 2026-10-14): **the FEVER ring ignores the perfect
  band.** Any pass through the FEVER ring without a rim touch is a full perfect pass
  (perfect coins, points, feedback, counters, `fever_ring_passed {perfect: 1}`), then
  FEVER as before (fire ≥ ×5, streak `max(5, streak + 1)`). Its points are `max(2,
  streak + 1)` with the streak *before* the FEVER boost, exactly like an ordinary perfect
  pass (a fresh FEVER pays +2, at streak 6 it pays +7; `RunState.pointStreak`). A rim touch on it is
  unchanged (no FEVER, fire out, streak reset). Every other hoop keeps the band.
  Tests: `test/p231/s15_fever_rim_free_perfect_test.dart`.
- DEVIATION (PRD-2.3 §14.3, supersedes PRD-2 §3.27 / PRD-2.2 §13.1 chick ×2): **the
  chick no longer doubles coins or points** (puzzle and piggy included). While it flies
  every hoop passed scores **+1 point** (`point_chick`, added with the pass, one
  timeline entry). `chick_lost {coins_doubled}` → `chick_lost {points_added}`; the HUD
  pill shows "+1", the banners "+1 point on every hoop …" / "+1 LOST".
- DEVIATION (PRD-2.3 §14.4, supersedes PRD-2 §3.0.1 speed / opening and PRD-2.2):
  **difficulty by hoop index.** Cruise speed is the keyframe table `curve_speed`
  `[[0,150],[50,172.5],[150,187.5]]` (replaces +3.5 % per minute of runClock; read at
  `RunState.hoopIndex`, so a revive keeps the speed). Opening: **hoop 0 is always 118**
  (also with Big Hoops, PRD-2.3 §0 item 3), from hoop 1 `curve_opening`
  `[[1,88],[100,66]]` (was 118 − 0.32 %/hoop → 92). Big Hoops ×1.5 from hoop 1 (132 at
  hoop 1); ride hoops and the portal ring 118; saw +0; every opening capped to the band.
  Moving-hoop chance `curve_moving` `[[19,0],[20,0.15],[35,0.40],[60,0.60],[80,0.75]]`
  (was .06 / .15 / .40 by row); tilt chance `curve_tilt` = the 2.2 rows as a step
  table. Spacing 310 unchanged (not tunable).
- DEVIATION (PRD-2.4 §1, supersedes the PRD-2.3 §14.4 opening curve `[[1,88],[100,66]]`
  and the PRD-2.3.1 §0 perfect band values): **the new hoop-size curve.** `curve_opening`
  = `[[1,118],[2,118],[6,114],[10,110.5],[16,105.5],[20,102],[25,98],[30,94.5],[35,90.5],
  [40,87.5],[50,81],[60,76.5],[75,72],[100,66]]`: hoops 0–2 are 118 pt, then an ease-out to
  66 pt at hoop 100, flat after. `point_perfect_band` = `[[1,18],[2,18],[6,17.4],[10,16.7],
  [16,15.8],[20,15.2],[25,14.5],[30,13.9],[35,13.2],[40,12.7],[50,11.6],[60,10.7],[75,10],
  [100,8]]`: the band stays about 30 % of the gap up to hoop 75. Unchanged: the Bullseye band
  `point_bullseye_band`, `curve_speed`, the Big Hoops ×1.5 and the saw. The in-app defaults
  are these values (offline, before the first fetch). Tests: `test/p24/s1_hoop_curve_test.dart`.
- DEVIATION (PRD-2.4 §2, supersedes the PRD-2.2 §16 "full size" rides, the PRD-2.2 §25.1
  "ride hoops 118" note and the PRD-2.3 §14.4 "ride hoops 118"): **one hoop size through
  rides.** Every hoop has the size of its index, also during and after a ride: comet hoops,
  hoops planned during a portal ride, the first hoop after a ride and every re-plan take
  `openingFor(index)` × the Big Hoops multiplier. The five ride rings of a portal ride take
  `openingFor(portal index)` × the multiplier (capped to the band); the rings of one ride
  share one size, fixed when the portal spawns (`PortalRide.rideRingOpening`). Exceptions:
  **hoop 0** (118, also with Big Hoops, PRD-2.3 §10.2); **the portal** (118 at every
  hoop, × Big Hoops as in 2.3.1, unchanged);
  the **saw**: `sawExtraOpening` stays 0 (PRD-2.2 §25: the saw is the normal opening; the
  PRD-2.4 text "keeps its +28 pt" describes the 2.0 value, so the saw is unchanged). Ride
  rings are still perfect passes and their rims are still ignored: ride difficulty and
  payouts are unchanged. `RunConfig.openingFor(hoopIndex)` has no `ride` parameter any more
  and `PortalConfig.ringOpening` is removed (`RunConfig.portalOpening` is the portal's 118).
  Tests: `test/p24/s2_ride_hoop_sizes_test.dart`, `test/p24/s2_no_jumps_test.dart`,
  `test/p24/s2_ride_art_test.dart`.
- DEVIATION (PRD-2.3 §14.4, squeeze, supersedes PRD-2 §3.17 timing): **counted in
  hoops**: the first at a random hoop **25–40**, each hold **5–10 hoops**, the next
  **25–45 hoops** after the previous one ended (no growing cooldown). A hoop count
  becomes runClock seconds at the cruise of those hoops (`RunConfig.secondsForHoops`:
  310 / cruise per hoop); the open-space steps (.50 → .35, min 230) and the phases are
  unchanged.
- DEVIATION (PRD-2.3 §14.5, rides): the comet comes with a **2 % chance per eligible
  normal hoop** from hoop 10, **at least 25 hoops** after the previous comet (layout
  stream; was the schedule 10–30, then every 45–60). The portal first at hoop **40–60**,
  then every **60–80** (was 25–50 / 40–60). The exclusions stay (no portal within 10
  hoops of a comet, the cool-downs). `ElementId.portal.firstPossible` is 40.
- DEVIATION (PRD-2.3 §14.6, new): **lifetime unlock gates.** An element can appear only
  once `Storage.gamesPlayed` reaches its gate (`gate_*`): 0 normal hoops, heart, star
  trail, bullseye; 3 switch, ring train; 5 comet, portal, capsules, shield; 8 spring,
  pair, egg; 10 golden feather / balloon bonus, puzzle, piggy, jar; 15 FEVER, lucky
  spin; 20 saw (`GatesConfig`). The director only sees open elements, so first-meet
  fires the first time a gate is open; a debug force ignores the gate. Not gated:
  difficulty, the squeeze, the home slot. RUN DEBUG has a "Runs: N (+5 / 0)" row.
  Tests, FS_E2E and FS_SOAK builds fly with every element (`RunSetup.ignoreGates`).
- DEVIATION (PRD-2.3 §14.8, analytics): `run_end` gets `coins_per_hoop`,
  `perfect_rate` (2 decimals), `opening_end`, `speed_end` and `games_played`; new event
  `coins_spent {amount, reason}` from `Wallet.spend` (`skin` for a shop item, `revive`, …).
- PRD-2.3 §15 remote tuning: REMOVED (audit 17). The **TUNING >** debug page is gone (its
  two run-stats rows moved to the debug panel main page). Tester builds use
  `--dart-define=FS_TESTER=true` (debug panel: god mode, autopilot bot, RUN DEBUG) and
  change no gameplay value.
- Tests: `test/p23/s14_2_economy_test.dart`, `s14_4_difficulty_test.dart`,
  `s14_6_gates_test.dart`, `s15_tuning_test.dart`; rewritten
  `test/p22/s11_perfect_zone_test.dart`; updated 2.2 pins in
  `test/run/config/tables_mirror_test.dart` (+ `test/fixtures/spawn_tables.json`),
  `test/run/director/s3_0_3_director_test.dart` and others listed in
  `docs/p23/REPORT_tune.md`.

## PRD-2.3 §10: the waiting start, the fixed first hoop, first-run instructions (P23-10)

- DEVIATION (PRD-2.3 §10.1, supersedes PRD-2 §3.0.1 "START = first tap"): **every new
  run waits for the first tap** (START on Home in VERSUS and FREE FLY, a run after the
  results). START only opens the run: the bird floats at its spawn point (x 70, the
  middle, gravity off) with a ±6 pt hover (`sin(t × 3)`) and a wing beat every 0.4 s;
  the clock stands still (`clock.running = false`), the world does not scroll, the score
  circle shows 0, hoop 0 already stands at its spot, the HUD row (versus bar, pause) is
  up. The **first playfield tap** does what START did: the banner ad (PRD-2.2 §7.4),
  `logGameStart`, `run_start`, `versus.onRunStart`, gravity on, the first flap (with
  `flap.mp3`), then `RunController.start()` (clock on, `RunStarted`). A tap on the pause
  button does not start it; back / pause while waiting work as in a run. Revive,
  phoenix and rides are unchanged. The test harness (`startRun`), `flyRun` and the
  autopilot give a waiting run one synthetic first tap.
- DEVIATION (PRD-2.3 §10.2, supersedes PRD-2.2 §15 "the first hoop scrolls in" for
  hoop 0 only): **hoop 0** of every run (not a `startHoopIndex` debug / e2e run) is
  placed at track x **290**, centre **`viewHeight / 2 + 16`**, opening **118** (also with
  Big Hoops), a plain still normal ring with nothing attached, before the first tap.
  Debug-forced slot elements wait for hoop 1. Hoop 1 follows at 310 (x 600); every later
  item still scrolls in. Reaching hoop 0 takes ≈ 0.6 s less than before (accepted; the
  versus timelines play on `runClock`, which starts at the tap for both sides).
- PRD-2.3 §10.3 the **first-run instructions** (design D) show on the very first run
  only (`Storage.firstRunHintSeen`, saved at its first tap; a save that has played
  before counts as seen); the first tap fades them out over 0.35 s.
- PRD-2.3 §10.3b the **tap reminder**: on every later run, if there is no tap
  `Config.tapReminderDelay` (4.0 s, remote key `ui_tap_reminder_s`) after the bird
  starts waiting (versus: after the VS screen), the hand and the TAP TO FLAP! banner fade
  in over 0.3 s (once per wait; a pause holds the count and hides it); the tap fades it
  out over 0.2 s. Analytics `tap_reminder_shown {mode}`.
- Tests: `test/p23/s10_waiting_start_test.dart` (+ goldens in `test/p23/goldens/`).
- DEVIATION (S8-14 device QA, PRD-2.3 §10.1 / PRD-2.2 §8, 2026-10-13): the **first
  tap of a waiting run fires on tap-up**, not on pointer-down. An Android back edge
  swipe first delivers a pointer-down and then cancels the pointer, and the first tap
  can't be undone; a cancelled pointer (back gesture, a drag past the touch slop) now
  leaves the run waiting (clock 0, no `run_start`, `firstRunHintSeen` unchanged).
  `TapCatcher` checks `game.runWaitingForFirstTap` on pointer-down. Every later flap
  stays on pointer-down (no added latency); Space / Enter and `onScreenTap` are
  unchanged. Tests: `test/p23/s10_back_gesture_test.dart`.

- DEVIATION (PRD-2.3 §25.3, supersedes the PRD-2.2 "START never waits; solo
  without an intro" rule): **in VERSUS every START shows the VS intro.** With an
  opponent held it is unchanged. Without one the intro is the loading screen:
  the reel cycles filler names for up to 3 s while the search runs, then lands
  on the found opponent, or on a NO RIVAL FOUND plate (grey person icon, no
  emblem) and a FLY SOLO banner, and the run starts solo. FREE FLY is
  unchanged (no intro). "Already met" opponents are a preference (met longest
  ago), not a block (§25.2).
- DEVIATION (PRD-2.3 §21.2/§21.3): every versus name tag follows one rule
  (shrink to 70 %, then "…"); avatar squares show the player's picture, else
  their own bird in their look (never the grey person icon for an opponent).
  WP-AV (2.4) replaces the pictures with sticker avatars (see the WP-AV note).
- Tests: `test/p23/s25_versus_matching_test.dart`,
  `test/p23/s25_vs_loading_screen_test.dart`, `test/p23/s21_names_test.dart`,
  `test/p23/s21_avatar_display_test.dart` (removed by WP-AV),
  `test/p23/s21_versus_identity_test.dart`, `functions/test/p23_s21.test.ts`.

## PRD-2.3 §17: one big bonus on screen (P23-17)

- DEVIATION (PRD-2.3 §17.3, adds to PRD-2.2 §27.2): **at most one open big bonus.**
  Big = Piggy Bank, Firefly Jar, comet star, Egg, the capsules, Star Trail, the reward
  rings (pair, Lucky Spin, FEVER) and the portal; small items (heart, shield, feather,
  puzzle piece) are not limited. A big bonus is open from its planning until it is
  collected, flown through or passed by the bird. While one is open the director plans
  no other (`DirectorContext.bigBonusOpen`, from `RunSpawner.bigBonusOpen`).
- DEVIATION (PRD-2.3 §17.3 rule 4): **a blocked bonus waits.** A big bonus drawn while
  rule 1 or the activity cool-down blocks it becomes the one waiting bonus and is placed
  at the first allowed slot / gap before any new big draw; the blocked draw (and any big
  draw while one waits) is drawn again from the non-big elements. A due portal and an
  owed comet keep their "stays due" path and count as the waiting bonus; the comet roll
  happens before the block check so the course stream stays the same. The director
  model drops the big-bonus rate ≈ 14 %, the in-run soak (1600 runs) ≈ 18 % (target ≤ 10 %;
  reported, PRD-2.3 §17.6). Fix S8-11: a gap blocked by the activity / cool-down is
  still drawn (nothing placed), so a big item drawn there waits too; the soak after it
  (1600 runs) measures 6.64 vs 8.06 big / 50 hoops, a 17.6 % drop. The remaining drop
  is the mandated "one waits, further big draws fall back to non-big" discard (about
  40 discarded big draws per 1 600 hoops in an instrumented soak).
- DEVIATION (PRD-2.3 §17.4, supersedes the fixed 60 pt for big bonuses): each slot's
  hoop is created at `max(60, visual reach + 8)` pt past the right edge (portal 66 + 12
  + 8; FEVER its decor-scaled beam; pair its gift tag; comet-star hoop the star's tail).
  Normal hoops and hoop 0 are unchanged.
- DEVIATION (PRD-2.3 §17.5, supersedes PRD-2.2 §27.3 for visible parts): when an
  activity starts, only reward items / slots that are **not visible yet** are cleared
  (owed as before; an off-screen portal hoop or comet star is owed again). Anything with
  a part of its drawing on screen stays and can be collected or flown through; the
  portal-on-screen fade and the reward-ring fade are gone for visible rings. The portal
  ride's own clear (`clearAhead` / `clearAll`) is unchanged.

### Owner requests 2026-10-13 (2.3.0+13)

- DEVIATION (owner 2026-10-13, supersedes the PRD-2.3 §14.2 Bullseye value): a Bullseye
  hit pays **2** coins (`coin_bullseye` default 2, was 1) and so +2 points via
  `RunContext.earn`; the banner reads "+2 coins".
- DEVIATION (owner 2026-10-13, amends PRD-2 §3.0.4 rim bounce): **soft rim bump from
  inside the hoop.** When the bird hits a rim end from inside the gap (the bird's centre
  between the two rim-end centres along the ring, the contact normal at least 60° from
  the ring plane — `RunConfig.rimSoftBumpMinAxis` 0.5 — pointing into the gap, and the
  bird moving toward that rim along the ring: the top rim while rising, the bottom rim
  while falling), the along-ring velocity toward the rim is replaced by
  `RunConfig.rimSoftBump` (60 pt/s) away from it (relative to the rim's own along-ring
  speed); the forward (local x) speed is kept, gravity and the forward recovery continue
  as normal. Hits from outside the gap and flat / head-on contacts keep the 0.85
  reflection. It is still a rim touch (no perfect, streak reset, tonk, spin, sparks).
  The autopilot uses the same `collideRims`, so its rollouts match.
- PRD-2.3 §26.2 (owner 2026-10-13): the Shop / Skins lock overlay covers the whole
  playfield incl. both spike strips at #000000 90 % (was 72 % between the strips);
  the back button and the coin pill stay bright above it.

## PRD-2.3.1 (owner 2026-10-13/14, version 2.3.1 (20))

- DEVIATION (PRD-2.3.1 §5, supersedes the PRD-2.3 §14.2 Shop value): the Shop
  free-coins ad pays **75** coins (`shop_ad_coins` default 75, was 40), and the row reads
  "FREE +75". The daily cap (5) and the cooldown (300 s) are unchanged, so Shop ads pay
  at most 375 coins a day (was 200).
- DEVIATION (PRD-2.3.1 §6, supersedes the owner 2026-10-13 Bullseye value of 2): a
  Bullseye hit pays **3** coins and **3** points (`coin_bullseye` default 3, was 2), on
  top of the pass; the banner reads "+3 coins". The hit band is still the remote
  `point_bullseye_band`; the guide lines stay drawn at ±12 pt. A rim touch does not
  change it.
- DEVIATION (PRD-2.3.1 §8, supersedes the PRD-2 §3.4 / §5.3 graze notice): a graze
  (or a clean off-centre pass) that breaks a running streak adds **no text**. The
  "GRAZE · streak lost" notice and its settings are removed. Everything else is
  unchanged: the streak, tier look, gold bird, trail and multiplier reset at once, the
  rim touch keeps its sparks, "tonk" and spin, and `streak_broken {length, cause}` stays.
- DEVIATION (PRD-2.3.1 §9, supersedes the PRD-2.2 §5.7 heart panel): the HUD heart at the
  top left has **no grey panel** (the 38 × 38 block at stage foreground 18 % over the
  background). It floats on the game: the empty heart is see-through with the same dotted
  outline (stage foreground, same width and dash); a partly filled heart (1 or 2 of 3) has
  its red fill rising from the bottom, the unfilled top see-through, and the dotted outline
  on the whole heart; full or extra life ready is unchanged (red, pulsing). Size (28 pt),
  position and the flying-heart landing point are unchanged. `HudConfig.heartPanelMix` is
  removed.
- DEVIATION (PRD-2.3.1 §10, supersedes the PRD-2.3 §10.3 "saved at its first tap"): the
  **full first-run instructions** show on **every** run until the run's first pass of
  hoop 0 (a graze counts; dying first, or quitting, does not). Only then is
  `firstRunHintSeen` saved `true`, once per run; from then on only the tap reminder shows
  (§10.3b). The first tap fades the instructions out but saves nothing. The full
  instructions write the key as `false` when they show, so a new player whose first run
  fails is not counted as seen by the `gamesPlayed > 0` fallback; the fallback covers only
  installs from before 2.3. Existing players (`firstRunHintSeen` true) keep the reminder
  only. VERSUS and FREE FLY follow the same rule.
- DEVIATION (PRD-2.3.1 §11, supersedes the PRD-2.2 §7.4 "the banner fades in on the first
  flight"): the **gameplay banner shows on the waiting screen**, the moment the run opens
  (the hovering bird, before the first tap). The strip is still reserved and empty during
  the VS intro, which is the only time before that; the ad fades in when it loads, as
  before. The interstitial preload, the new-player ad grace, `run_start` and `logGameStart`
  still happen on the first tap. NO ADS owners and every case without a wanted banner get
  none.

### PRD-2.3.1 rides and comet (2026-10-14)

- DEVIATION (PRD-2.3.1 §7, supersedes PRD-2 §3.12 "11 rings"): every portal ride has
  **6 rings: the portal + 5 ride rings** (`PortalConfig.rideRings` 5), at equal arc
  length from 190 pt to L − 260 pt (the same span); the cannon's rings are 950 pt apart
  (`PortalConfig.cannonRingStep`, was 380). Route, length, speed, camera, art, exit and
  timing are unchanged. A ride is 6 perfect passes (was 12): about half the coins and
  points (each ride ring still pays like a perfect pass).
- DEVIATION (PRD-2.3.1 §16, supersedes the 2.3.0 (19) "`ride_comet_hoop_gap` ahead while
  `trackX + gap ≤ end`" rule and PRD-2.2 §16.1 "already spawned / planned hoops keep
  their height"): at comet start the layout is locked. The hoops not yet visible (a hoop
  spawned past the right edge, the planned-ahead slot) become plain ride hoops in the
  comet layout; the pickups in their gaps are dropped unjudged; hoops on screen stay. The
  comet hoops are evenly spaced from the last hoop that stays to the predicted end −
  `ride_comet_tail` (100 pt) in `max(1, round(stretch / ride_comet_hoop_gap))` steps and
  zigzag ±70 pt; the first hoop after the comet is at ≥ the predicted end +
  `ride_comet_after_gap` (310 pt) at a normal height.
- DEVIATION (PRD-2.3.1 §17): at most `ride_portal_max` (2; 0 = no limit) portals per run;
  every placed portal counts (debug-forced and first-meet too, and one later turned plain
  or cleared by a revive / ride / activity: the count never goes down), a revive does not
  reset the count, and at the cap the portal schedule stops: nothing waits, nothing is
  owed, and a debug-forced portal is discarded (with cap 0 forcing is unrestricted).
  Comets are unaffected.

### PRD-2.3.1 §0: the live Remote Config tuning is the in-app default (P231-T, 2026-10-14)

- DEVIATION (PRD-2.3.1 §0, supersedes the PRD-2.3 §14 default values; the mechanics are
  unchanged): every `kTuningDefaults` key takes the owner's live Remote Config value
  (RC version 21), except `coin_bullseye` 3 (§6), `shop_ad_coins` 75 (§5) and the keys
  new in 2.3.1 (`ride_comet_tail` 100, `ride_comet_after_gap` 310, `ride_portal_max` 2).
  The changed defaults (2.3 value in brackets):
  - coins: `coin_piggy_per` 3 (2: 20 caught pay 6, was 10), `coin_jar` 5 (8),
    `coin_spin_slices` [1,2,3,1,2,1] ([1,2,3,5,1,2]);
  - perfect band `point_perfect_band` [[1,18],[25,15],[50,13],[75,10],[100,8]] ([[0,0]]:
    no band, any rim-free pass was perfect); Bullseye band `point_bullseye_band`
    [[1,12],[50,10],[100,8]] ([[0,12]]);
  - bonus / puzzle: `bonus_prizes` [25,25,25,40,40,40,50,50,100] (jackpot 100, was 150),
    `bonus_feather_gaps` and `puzzle_gaps` [5,30] ([10,40]), `puzzle_reward` [40,100,5]
    ([50,150,5]);
  - rides: comet 4 % (2 %) from hoop 8 (10), ≥ 18 (25) apart; portal first at hoop 12–25
    (40–60), then every 80–90 (60–80);
  - spawn: `spawn_special_chance` [[0,0],[3,0],[4,0.4],[15,0.5],[30,0.6],[50,0.7]],
    `spawn_item_chance` [[0,0],[2,0],[3,0.5],[20,0.55]], and every special / item row
    but the saw earlier and closer (e.g. Bullseye from 4, ≥ 2 apart; train from 5, ≥ 4;
    Star Trail from gap 3, ≥ 3; piggy from 8, ≥ 12; jar from 10, ≥ 12);
  - lifetime gates (`gate_*`, gamesPlayed): switch / train 0 (3); comet, portal, capsule,
    shield 2 (5); spring, pair, egg 4 (8); feather, puzzle, piggy, jar 6 (10); FEVER,
    Lucky Spin 8 (15); saw 12 (20).
  The full table is `docs/p23/TUNING.md`. Tests that measure a mechanism at its 2.3
  calibration pin the 2.3 values (`test/p231/tuning_23.dart`).

### PRD-2.4 §3: the lively run background (P24-W1, 2026-10-16)

- DEVIATION (PRD 2.4 §3; the 2014 game had a flat background in the stage's background
  colour): during a run (not on home, results or bonus pages) the background is a world of
  10 scenes joined by 10 seams (`docs/p24/endless_vertical.html`, ported 1:1 in
  `lib/run/backdrop/`), drawn in Sky & Hills greys and recoloured per colour stage by one
  colour matrix (#F1F1F1 → stage background, #828282 → stage foreground). It sits at world
  priority −999, just over the flat backdrop rectangle (−1000, which still shows on the
  menus), fades in over 0.3 s when the run opens and out over 0.3 s under a post-run page,
  and leaves with its run. It moves only with the run camera and the run clock (frozen on
  pause and death). Seam k is centred on hoop 40·k; hoops 0–39 are pure Nest Canopy; one
  loop is 400 hoops. Nothing else (bird, hoops, spikes, HUD, rides, physics) changes.

### PRD-2.4 §3.5: the portal ride hands back to the background (P24-R, 2026-10-16)

- DEVIATION (PRD 2.4 §3.5; replaces the 2.2 way-back wash of the five themed rides): around a
  portal ride the background follows the run camera (layer shares of its height sky .07 /
  far .17 / mid .32 / ground .5, capped 720 up / 100 down), holds on the exit, rushes with
  the launch camera and catches up in the glide at +410·e^(−1.35·t) pt/s, bumps
  6·share·e^(−4w)·sin(13w) on `pu_land` (tapered to 0 by the settle end). The cannon keeps
  its tint and its wash; on space, sea, volcano, pinball and storm the scene leaves over
  1.7 s (`smooth`) behind an edge in its own look and the world arrives per layer (lags
  0 / .1 / .25 / .4 s, 1.9 s `smoother`). The fly's wash now only tints the leaving scene;
  no wash in the glide. While a themed scene covers the screen the world is not drawn and
  is re-synced to its hoop schedule at the launch; after a cannon ride the world re-syncs
  at ≥ 0.6× (a seam right after it can land a few hoops early). Ride tracks, scenes,
  exits, poses, sounds and timings are unchanged.

### One level per run, stored level (WP-L, 2026-10-17)

- DEVIATION (owner 2026-10-17: one level per run, stored level; supersedes PRD-home-v3 §4.1
  / §11 "the level is derived from the best and never stored" and the PRD-2.3.1 §12.2 rank
  rule "the run's score passes the threshold"): the player level is stored
  (`playerLevel`, int 0 = unranked … 10, default 0; no migration — every install starts
  at 0 whatever its best, and `claimedLevels` grant nothing). When a run ends, if its score
  ≥ the threshold of level + 1 the level goes up by exactly one (never more, however high
  the score; LEGEND stays): from 0 a run of 100 gives EGG, the next 100 gives CHICK, a 30 at
  CHICK gives nothing. Each step owes that level's one-time reward through the unchanged
  LEVEL UP / CLAIM flow (`unclaimedLevelReward`, `claimedLevels`, the kill-safe claim and
  the catch-up of reached-but-unclaimed levels ≤ the stored one). Rank achievements unlock
  when the stored level reaches the rank (earned in the counting run's end batch, §19
  pacing unchanged). The stored level is what home, LEVELS, the results page (level before
  / after the run), the share card and versus (own level, `players/{uid}.level`) show;
  `levelFor(best)` remains only the server's pool level for matching and opponents. The
  LEVELS header reads "<threshold> TO <next>" (the score one run needs) over an empty bar;
  the results bar fills with the run's score toward the next threshold ("N TO <next>" = the
  points the run was short). "Delete my data" and the debug "Reset menu state" reset the
  level to 0 (the delete keeps `claimedLevels`, so a level reached again never pays twice).

### Sticker avatars from the player's own bird (WP-AV, 2026-10-17)

- DEVIATION (owner 2026-10-17, design C "Sticker"; supersedes PRD-2.3 §21.3 pictures and
  the S6-64 / S6-65 platform picture and name): every player picture (the VS intro plates,
  the versus HUD bar, the results card; yours and the opponent's, the solo results column
  too) is a **sticker avatar** drawn on the phone from the player's equipped bird, gear and
  hat: the game's own skin art, tilted 16° nose-up, animated items frozen at t = 0.6, a
  white sticker edge (4.5 % of the size, ≥ 2 px) and a soft shadow (28 % black, blur 5 %,
  3.5 % down), on a 9-point star blob turned 10° (radii 41 % / 33 %) in the bird's colour
  mixed 72 % to white (rainbow #FF5252, snow / ghost #90A4AE). The opponent's faces left.
  It is rendered once per (bird, gear, hat, pixel size) into an image and cached (LRU 16),
  never drawn per frame. The avatar squares' colours and sizes are unchanged; the reel's
  filler ticks and NO RIVAL FOUND keep the grey person glyph.
- No photos and no platform names: the Play Games / Game Center picture and display name are
  never read; nothing is uploaded to Firebase Storage (the `avatar` field of a run / player
  doc is always '', kept only for the rules' key set and older apps); Storage rules deny
  everything. Everyone's versus name is the generated nickname (also when signed in); the
  platform identity stays for sign-in, the account link, `pg` and leaderboards only.
- Opponents' stickers come from the `look` ids of their run; an id this build does not know
  falls back per layer (classic bird, no gear, no hat). The server checks every look id's
  shape (`^[a-z0-9_]{1,40}$`, function and rules) and pools a run with `avatar: ''` and a
  generated name (a platform name from an older app becomes a generated name derived from
  the uid).
- Tests: `test/p24/av_sticker_avatar_test.dart`, `test/p24/av_versus_avatars_test.dart`,
  `functions/test/p24_av.test.ts`.

### Tablets: a wider world (WP-TAB, 2026-10-17)

- DEVIATION (owner 2026-10-17; supersedes "the playfield is always 320 pt wide"): phones
  (screens taller than 568/320) are unchanged, bit for bit. A wider screen (iPad, Android
  tablets, foldables) gets a playfield 568 pt high and `568 × aspect` wide, capped at
  **426 pt (3:4)** (`Config.viewWidthFor`, `game.viewWidth`, `game.extraWidth` = width − 320);
  anything wider than 3:4 keeps side bars in the foreground tint.
- **Same look-ahead (fairness for versus and the leaderboard)**: the run keeps its phone
  coordinates (screen x 0..320, bird at x 70, spawning / planning at the right edge 320
  unchanged); it is drawn `extraWidth` further right, so the bird sits at screen x
  70 + extra and the extra width shows what is BEHIND the bird (run x from −extra to 0).
  Culling and every "on screen" test use the real left edge (`RunState.viewLeft` =
  −extra); the death tumble bounces off it. The run HUD, the score circle and the banner
  row stay on the phone's 320 pt column on the right (pause button at the screen's right
  edge); the banners and the first-run hint / tap reminder are centred on the screen (the
  hint's flap path stays between the bird and hoop 0); the banner bands, spike strips, run background, ride scenes, flashes, edge glows,
  dims and speed lines cover the whole width.
- **Menus** (home, shop, skins, levels, settings, popups, the results page, the bonus page,
  the pause card, the revive offer, the VS intro) stay a 320 pt column centred on the
  screen; their background, the spike strips, stage colours and the tap area fill the
  whole width.
- The banner strip in a run keeps its dp height (points per dp from the screen's full width
  in game points).


### 2.6 wave 1: showcase, gates and ceiling (WP-B/C/D)

- **DEVIATION (PRD-2.6 §3 WP-B, R2/R6):** showcase planning is step 0,
  before debug forces and first-meet pulls. START freezes the selected script;
  the ordinary planner still consumes its draws before the script overlays its
  highlights. Portal → comet → FEVER steps are pass-driven, with attempt-based
  scripts, Big Hoops + shield safety starters and one free revive. These are
  ordinary versus/upload-eligible runs. Debug assistance permanently excludes
  the run; it never consumes normal showcase progress. Existing upgraded
  installs skip the showcase. See `test/p26/showcase/`.
- **DEVIATION (WP-C, C1–C3):** lifetime gates are silent filters: saw opens
  at gamesPlayed 3 (game 4), squeeze at 5 (game 6). Other elements use the
  in-run introductions and existing first-meet pulls; saw/squeeze have no
  first-meet force. The initial portal window is hoop 12–25. Gate UI is gone.
- **DEVIATION (WP-D, D1/D2):** the shared opening curve reaches 70 pt at
  hoop 150, perfect band 10 pt; speed and 310 pt plane spacing remain pinned.
  Δy uses min(band, 540 pt), at most 270 pt, with a 0.85 maximum after a hard
  hoop. Screens above the 711 reference reuse its portable 623 pt
  centre-course band below the top tooth line, so centre rows and edge
  recovery produce the same point-space Δy at 711 and 730 (the rendered pair
  offset still scales with view height). Tilts start at 10,
  switch 15, rails 25, saw 30, strong aligned tilts 50, 45° at 60, slides 70,
  orbit/rock 90, saw-in-squeeze 100, moving + 30° at 150. Strong tilts follow
  the approach and require |Δy| ≥40; otherwise they clamp to 15°. A 45° ring
  receives +6 pt opening. A cramped slide before hoop 90 drops its motion
  instead of introducing rock early. Rendered moving angles include the
  motion's own angular offset under the 15°/30° cap.
- **DEVIATION (D3):** the last four slots carry hazard costs, with budget
  0/0.5/2/3/4/5/5.5 at hoops 0/3/10/25/50/100/150. Downgrades remove motion,
  reduce tilt, shorten Δy to p90, then remove the special. Forced slots count
  in the ledger but are exempt. Reward/ride slots cost zero. Calm slots also
  pass through hazard accounting. Spring reservations use the final kind,
  so a spring converted to calm cannot restore its discarded special.
- **DEVIATION (D3 × O18, issue #127, orchestrator decision 2026-10-26):**
  squeeze timing is fixed. Every squeezed non-reward/non-ride slot adds +1 to
  the rolling ledger, without resetting it at entry. As with forced slots,
  that fixed surcharge counts but is exempt from the budget limit:
  `window cost − squeeze surcharge ≤ hazard_budget`. Other costs are
  downgraded in D3 order; below budget 4 a squeezed slot must carry no cost
  beyond its surcharge. Reward/ride slots retain D3's zero cost.
  A non-forced spring whose fixed landing would enter a due calm stretch is
  downgraded before it commits. Below budget 4 it is also downgraded when
  the current or next slot reaches the squeeze window; the controller supplies
  that one-slot look-ahead using the next plane's travel time plus one slot
  spacing at cruise speed. Outside those windows springs remain available
  from hoop 10, subject to the rolling budget and the fixed 240 pt landing
  reservation. Below the 711 pt design height, the slot before a due calm
  is pre-positioned against the deepest squeeze band only when the current
  or next slot reaches the squeeze window. A strong ring keeps its signed
  approach of at least 40 pt when that intersects the safe reach; otherwise
  it loses its modifier. Ordinary slots outside those windows are unaffected.
  This preserves O18 timing, D4's median step and D3's zero-other-cost rule.
- **DEVIATION (D4/D5):** periodic calm lasts three slots, first at 30–34,
  growing intervals ×1.2 capped at 55. Revive gives three slots; squeeze/ride
  recovery two. Starts are at least 12 apart except mandatory revive calm.
  Calm is normal, motionless, ≤10° tilt and median Δy. Recovery from a spring
  may lie outside the row's centre range while retaining the physical band
  margin and median step. Squeeze timing remains 25–40 first / 25–45 gap;
  warnings wait outside calm and revives preserve the squeeze index.
- **DEVIATION (D6):** `headline_window` coordinates introductions, first
  meets, rides, big bonuses and squeeze warnings: one headline per eight
  hoops, with due events waiting at most five hoops.
- **DEVIATION (D7):** from hoop 150, all six formations ship (stairs,
  slalom, tilt wave, sync rails, saw gate, switch chain), every 12–20 hoops,
  avoiding the previous two shapes and respecting budget and recovery.
  Saw/switch/moving mix chapters rotate every 50 hoops at equal budget.
  Stairs face into the available band and short-screen slalom steps cap at
  the live Δy ceiling; sampler recovery re-enters centre rows gradually.
  Formation placement uses the same portable course band, so tall-screen
  edge clamps do not change Δy.
  Tilt waves retain the complete −30/−15/0/+15/+30° sequence and their
  rising/falling 40 pt steps when translated into the band. A wave is chosen
  only when its rising entrance and all five slots fit D2/D3; another shape
  takes the slot otherwise. A committed spring landing is a plain, still
  hoop at exactly ±240 pt; specials, first meets and formations wait until
  after it (§3.23). The debug autopilot previews the remaining Ring Train
  planes together, rather than accepting a head pass that strands the bird
  before the next 56 pt plane; train geometry and gameplay are unchanged.
  No new point source or timeline flag is added: `fl` remains 2 and the
  leaderboard maximum remains 32,500,000.

WP-D validation includes the 200-seed curve sweep (568 / 711 / 730,
with and without squeeze), the R2 setup/height matrix, the 150 / 250
autopilot starts and the ordinary gamesPlayed-10 human-noise median using
the shared `HumanNoiseBot`. D-BOT makes its timing noise closed-loop: one
Gaussian jitter draw is retained for each base decision while the bot asks
`Autopilot.nextFlapDelay()` again on every frame from the real bird state.
For nonnegative jitter it waits until the autopilot has continuously wanted
to flap for that duration; the wait resets when the request goes away.
For negative jitter it taps when the fresh forecast is within the early
window. It never moves a pending deadline forward by re-adding jitter.
An extra tap is scheduled 80 ms after an emitted base tap. Every emitted
tap, including an extra, clears the retained jitter and wait and invalidates
the selected controller plan, so the next frame replans from the changed
trajectory. Constructor parameters default to sigma 90 ms and 10% extra
flaps; noise is neither capped nor reduced. With both parameters zero,
the bot reproduces `flyRun` when seed and course history match. Diagnostics
record actual emitted base offsets against the current nominal decision,
including frame quantization; extra taps are excluded. Distribution checks
pool multiple seeded flights (at least 500 base taps) at each height,
retaining the mean 0 +/-10 ms and standard deviation 90 +/-10 ms limits.
The sigma-90 baseline comparison and calibrated 40-hoop median gates are
separate validation work under PRD-2.6 decision 8.3-1.
The curve, same-rules and D7 ceiling gates pass at their original thresholds.
The legacy cooldown audit accounts for D7's consecutive switch-chain rings.
The owner Pixel 8 ceiling playtest remains required.
