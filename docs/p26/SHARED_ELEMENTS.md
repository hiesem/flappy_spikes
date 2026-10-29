# 2.6 shared visual elements — one master each

**Status:** binding for every 2.6 build and test round. Created by the first
M0 issue (PRD O97–O100) and kept current by every issue that adds or changes a
master. The PRD remains the product authority; this file is the implementation
map for shared art.

## Rules

### O97 — reuse the in-game master

When an approved 2.6 design shows an element the game already has, use the
existing in-game element and its code. The design page supplies **layout,
size, colour and timing only**. A difference in look is allowed only as a
parameter (colour, size, label, pose, phase) of the same master. Never draw a
second copy, variant or local reimplementation of a listed element.

### O98 — exactly four ray versions, reused as they are

The four existing ray drawings are the complete ray set. No new ray master,
shape, fade or rotation style is added in 2.6. Pick the closest existing
version for a reward moment and pass only its documented parameters. The old
O41 “longer rays with a radial fade” look is dropped; the existing versions
already sit behind their item and turn slowly.

1. **Results-page gold / light rays** — `ResultsScreen._paintRays` +
   `ResultsConfig` in `lib/run/screens/results_screen.dart` and
   `lib/run/config/results_config.dart`.
2. **LEVEL UP pink rays** — `LevelUpPopup._Header` in
   `lib/components/levels/level_up_popup.dart`.
3. **No-Ads celebration gold rays** — `NoAdsCelebrationRays` (also used by
   `NoAdsCelebration._Header`) in
   `lib/components/noads_celebration.dart`.
4. **Shop preview rarity rays** — `PreviewStage` in
   `lib/components/skins/preview_stage.dart`.

### O99 — one box master

Every 2.6 box draws through `MysteryBox` in
`lib/components/ui/mystery_box.dart`: the level mystery box, the gold bonus
chest, the gold / silver / bronze leaderboard gifts, Star Road mystery tiles
and the in-run paired-hoops gift. Colour, size, label (`?`), ribbon and lid
phase are parameters. No other file owns box geometry or a second box path.

The approved reference is **`levels_v26/item_reveal.html`, LEVEL ITEM REVEAL,
style A**. The master keeps its art-unit geometry (body `(-40,-10)…(40,42)`,
lid `(-46,-24)…(46,-8)`, 80-unit reference width) and style A's timing:

- reveal time 0.00–0.30 s: the closed/rest box (the page's separate entrance
  scale is owned by the reveal screen, not the box master);
- 0.30–1.05 s (`shake` progress `sh`, elapsed reveal time `u`):
  `sin(u × 42) × (2 + 12sh²)` degrees of wobble and
  `abs(sin(u × 21)) × (-3 - 6sh)` art units of hop — frequency uses elapsed
  time while amplitude uses normalized shake progress;
- 1.05–1.55 s: the lid translates `(60u, -150u + 40u²)` and rotates `80u`
  degrees over the 0.5 s opening clip (`u` is now opening progress).

### O100 — enforcement

**Builders:** check this file before drawing anything. Reuse the listed master
and add a parameter, never a second drawing. If a new shared-looking element
appears, add it here with its master path/class, parameters and design map in
the same change.

**Testers:** **any second drawing of a listed element is a blocker.** Also
fail a new shared-looking element that is not added to this registry. Point at
the duplicated drawing and the master that should have been used.

## Registry

Paths are repository-relative. “Design map” names the approved page and the
section whose element must be expressed through the master. “Parameters” are
the only permitted differences; layout geometry stays in the owning screen.

### Rays

| # | Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|---|
| R1 | `lib/run/screens/results_screen.dart` — `ResultsScreen._paintRays` with `lib/run/config/results_config.dart` — `ResultsConfig` | strength / opacity envelope, scale, rotation phase, reduce-motion freeze; colours remain the results-page gold + light pair | `levels_v26/item_reveal.html` — LEVEL ITEM REVEAL, reward stage rays behind the emblem/reveal; `approvals_v26/missions.html` — §4 ALL DONE: THE BONUS CHEST ON HOME; `approvals_v26/leaderboard_gifts.html` — §2 OPENING THE BOX; `approvals_v26/star_road.html` — tier claim / reward moments; `approvals_v26/puzzle_album.html` — picture-complete / album reward |
| R2 | `lib/components/levels/level_up_popup.dart` — `LevelUpPopup._Header` | header size and centre, rotation phase, reduce-motion freeze; the 16 soft-pink wedges stay this master | `levels_v26/item_reveal.html` — LEVEL ITEM REVEAL, LEVEL UP / result-stage moment; `approvals_v26/levels_tabs.html` — level-up reward presentation |
| R3 | `lib/components/noads_celebration.dart` — `NoAdsCelebrationRays` (shared with `NoAdsCelebration._Header`) | clip bounds and centre, rotation phase, reduce-motion freeze; the 16 gold wedges stay this master | `approvals_v26/day_streak.html` — §2 THE DAILY REWARD MOMENT / §3 THE STREAK CARD / §4 STREAK LOST restore; `approvals_v26/first_win_of_day.html` — first-win reward; `approvals_v26/weekly_course.html` — §3 WEEKLY RESULTS reward moment |
| R4 | `lib/components/skins/preview_stage.dart` — `PreviewStage` | stage rect, rarity colours selected by the existing rarity branch, ray lifetime (1.4 / 2.6 s) and reduce-motion freeze | `approvals_v26/versus_cards.html` — THE 51 ITEMS + 9 SKILL ITEMS, item reveal / celebration; `approvals_v26/skill_cosmetics.html` — THE 24 ITEMS, gold skill-item reveal |

### Mystery box (O99)

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/components/ui/mystery_box.dart` — `MysteryBox`, `MysteryBoxComponent`, `MysteryBoxLook`, `MysteryBoxTier`, `MysteryBoxAnimation`, `MysteryBoxLid`, `MysteryBoxPhase` | `main` / `dark` / `ribbon` / `labelColor`, `label` (`'?'` or null), `size` (80-unit reference scaled), `shake` progress plus its separate `revealTime`, lid-off progress, `drawBody` / `drawLid` for the split reveal, component position / priority | **Reference:** `levels_v26/item_reveal.html` — LEVEL ITEM REVEAL, style A mystery box, shake and lid-off. Also: `levels_v26/levels_screen.html` — locked LEVELS row grey box (`GREY` #BDBDBD/#9C9C9C, `?`); `approvals_v26/missions.html` — §4 ALL DONE: THE BONUS CHEST ON HOME (gold); `approvals_v26/leaderboard_gifts.html` — §1 GO TO COLLECT and §2 OPENING THE BOX (gold / silver / bronze); `approvals_v26/star_road.html` — MYSTERY tiers / tier-claim box; `lib/run/hoops/kinds/pair/gift_box.dart` — in-run paired-hoops gift (visual only) |

`MysteryBox.paintPair` is the pair's parameterised shortcut: a label-less,
reward-coloured box at the pair's existing 43.5 pt size. It contains no
geometry of its own and exists so the run cannot grow a second path.

### Confetti

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/components/ui/confetti.dart` — `ConfettiBurst` (`burst` / `rain`) | origin, count, speed, upward lift, sideways drift, coin / star cadence, stars on/off, rain width and left edge, injected seeded random, priority; existing colour cycle stays | `levels_v26/item_reveal.html` — LEVEL ITEM REVEAL, reveal bursts; `approvals_v26/missions.html` — §4 ALL DONE: THE BONUS CHEST ON HOME; `approvals_v26/day_streak.html` — §2 THE DAILY REWARD MOMENT; `approvals_v26/leaderboard.html` — §1 RESULTS PAGE: THE CLIMB; `approvals_v26/leaderboard_gifts.html` — §2 OPENING THE BOX; `approvals_v26/star_road.html` — Home popup and tier claim; `approvals_v26/first_win_of_day.html` — reward moment; `approvals_v26/puzzle_album.html` — picture-complete |

### Coin fly / counter

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/components/ui/coin_fly.dart` — `CoinFly` (`fine` flight, `burst`) | coin sprite, source rect / origin, target, count, duration, stagger, delay, coin size, spread / jitter / rise, seeded random, land / done callbacks, priority | `approvals_v26/missions.html` — §3 RESULTS PAGE: PIPS FILL, COINS FLY; `approvals_v26/day_streak.html` — §2 THE DAILY REWARD MOMENT; `approvals_v26/leaderboard_gifts.html` — §2 OPENING THE BOX / COLLECT; `approvals_v26/star_road.html` — tier claim; `approvals_v26/weekly_course.html` — §3 WEEKLY RESULTS |
| `lib/components/ui/coin_reward.dart` — `CoinRewardAnimation` | amount, source, coin count, flight / count duration, tick count, confetti count and profile, flash, progress delay, origin / spread / rise, jingle, seeded random, callbacks | `approvals_v26/leaderboard.html` — §1 RESULTS PAGE: THE CLIMB; `approvals_v26/weekly_course.html` — §3 WEEKLY RESULTS; `approvals_v26/missions.html` — §3 results coins; `approvals_v26/star_road.html` — claim |
| `lib/components/home/home_screen.dart` — `CoinPill` | initial balance, top-right position, press callback, active state / priority; live balance, reward reservations / holds, `countFrom(from, duration, linear)`, `nudge(shake)`; existing pink pill, plus box, coin sprite, spacing, count / flash / shake curves stay | Every wallet counter: `approvals_v26/day_streak.html` — §1 HOME and §2 THE DAILY REWARD MOMENT (collect into pill); `approvals_v26/leaderboard_gifts.html` — §2 OPENING THE BOX (COLLECT count-up); `approvals_v26/missions.html` — §3 results coins and §4 bonus chest; `approvals_v26/star_road.html` — tier claim; `approvals_v26/versus_cards.html` — CARDS shop header |
| `lib/run/effects/coin_icon.dart` — `CoinIcon` | size, centre, opacity only; the `menu/coin.png` sprite is fixed | Every 2.6 coin badge / pill / results row that needs the game's coin: `approvals_v26/missions.html` §3, `approvals_v26/day_streak.html` §2, `approvals_v26/leaderboard.html` §1–§2, `approvals_v26/leaderboard_gifts.html` §2, `approvals_v26/star_road.html`, `approvals_v26/weekly_course.html` §3 |
| `lib/run/effects/coin_popup.dart` — `CoinPopup` | pass point, amount, doubled flag, delay, priority; the 1.1 s motion and `+N`/`×2` layout stay | In-run coin feedback reused wherever a 2.6 screen depicts a run pass (`approvals_v26/leaderboard.html` §4 picture guide; `approvals_v26/flight_guide.html` run pictures) |

### Popup frame

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/components/ui/p1_popup.dart` — `P1Popup` (+ `MenuParagraph`, `closeBox`) | dim overlap / priority, card height and content, card pose animation, dismiss target, active state; card width and P1 dim/fill styling stay shared | `levels_v26/item_reveal.html` — LEVEL ITEM REVEAL confirmation sheet; `approvals_v26/missions.html` — §4 ALL DONE: THE BONUS CHEST ON HOME; `approvals_v26/day_streak.html` — §2 THE DAILY REWARD MOMENT and §4 STREAK LOST; `approvals_v26/leaderboard_gifts.html` — §1 GO TO COLLECT; `approvals_v26/star_road.html` — HOME POPUP · A REWARD IS WAITING; `approvals_v26/star_road_popup.html`; `approvals_v26/first_win_of_day.html`; `approvals_v26/puzzle_album.html` — picture-complete result |

### Buttons

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/components/home/menu_primitives.dart` — `MenuButton` | position, size, fill colour (null = flat label button), active / tappable / dimmed, pressed scale and shade duration, rumble knock, priority, children | Every rectangular 2.6 action button: `approvals_v26/missions.html` §1–§4 (panel rows, chest, collect); `approvals_v26/day_streak.html` §2–§5; `approvals_v26/leaderboard.html` §2–§6; `approvals_v26/leaderboard_gifts.html` §1–§2; `approvals_v26/star_road.html`; `approvals_v26/puzzle_album.html`; `approvals_v26/worlds_map.html`; `approvals_v26/versus_cards.html`; `approvals_v26/weekly_course.html` §1–§3; `approvals_v26/first_win_of_day.html`; `approvals_v26/flight_guide.html`; `approvals_v26/levels_tabs.html` |
| `lib/components/home/mode_button.dart` — `ModeButton` | rect, mode, active state, press callback; the two-part strip and its swap curve stay | `approvals_v26/weekly_course.html` — §2 THE WEEKLY RUN mode/context chip styling; `approvals_v26/versus_cards.html` — versus/free-fly mode affordances |
| `lib/components/skins/shop_widgets.dart` — `ShopActionButton` (+ `PriceChip`, `ShopText`) | bottom-right, action kind, price, affordability, tint, reduce motion, active state; pulse and colour rules stay | `approvals_v26/versus_cards.html` — CARDS tab BUY / EQUIPPED / NOTHING ON; `approvals_v26/skill_cosmetics.html` — skill-item action button; `approvals_v26/levels_tabs.html` — shop-like row actions |

### Tags

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/components/home/menu_primitives.dart` — `MenuTag` | text, font size / family, letter spacing, fill and text colours, position / anchor, priority; gold fill and white text default, padding stays | `approvals_v26/levels_tabs.html` — gold NEW tag / locked NEXT tag (colour parameter only); `approvals_v26/versus_cards.html` — NEW / price tags on card items; `approvals_v26/skill_cosmetics.html` — secret / NEW tags; `approvals_v26/missions.html` — row reward tags |
| `lib/run/screens/results_screen.dart` — `ResultsWinnerTag` | winner / opponent position only; gold WINNER tag styling stays | `approvals_v26/leaderboard.html` — §1 RESULTS PAGE: THE CLIMB winner marker; `approvals_v26/versus_cards.html` — versus result footer |
| `lib/run/effects/gold_sticker.dart` — `GoldSticker` | text, font size, letter spacing, padding, minimum height, tilt, pop length / start tilt, back-out mode, position, priority, opacity | `approvals_v26/missions.html` — §3 results pips / collect sticker; `approvals_v26/weekly_course.html` — NEW WEEK BEST! sticker; `approvals_v26/leaderboard.html` — results climb labels; `approvals_v26/puzzle_album.html` — PICTURE COMPLETE sticker; `approvals_v26/day_streak.html` — collection sticker |
| `lib/run/hoops/kinds/pair/gift_tag.dart` — `GiftTag` | reward (colours / icon / word), anchor, above/below, sway; the luggage-tag shape and outline stay | In-run paired hoops only; any 2.6 drawing of the pair must call this tag rather than redraw it (`SPEC.md` pair flow; `docs/gameplay-v2/VERSUS-BACKEND.md` run visuals) |

### Banners

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/run/hud/banners.dart` — `RunBanner`, `StreakBanner`, `ElementBanner`, `BannerHost`; `lib/run/hud/fever_banner.dart` — `FeverBanner` | lane, band width, text / colour / font size, duration, subtitle, host priority; the y-190 band, scale-in / hold / fade curve and one-at-a-time rule stay | Any 2.6 run depiction: `approvals_v26/weekly_course.html` — §2 WEEKLY COURSE chip and results banner; `approvals_v26/leaderboard.html` — §4 picture guide run scene; `approvals_v26/flight_guide.html` — run pictures; `approvals_v26/versus_cards.html` — versus run HUD |
| `lib/components/skins/celebration.dart` — `UnlockBanner` | item, centre x, top, reduce motion; rarity block styling and legend duration stay | `approvals_v26/versus_cards.html` — card-item unlock; `approvals_v26/skill_cosmetics.html` — skill-item unlock; `approvals_v26/levels_tabs.html` — level reward unlock |

### Stickers

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/run/effects/gold_sticker.dart` — `GoldSticker` | as listed under **Tags**; use `.newBest` / `.collect` factories where they fit | `approvals_v26/weekly_course.html` — NEW WEEK BEST!; `approvals_v26/puzzle_album.html` — picture-complete; `approvals_v26/leaderboard.html` — results climb; `approvals_v26/missions.html` — collect stickers |

### Versus-card cosmetics (F9, O82 / O86)

Frame internals reuse `LookPainter` / `BirdArt` for the miniature birds,
`HoopPainter` for Hoop Loop, `SpikeTeethPainter` for Spike Teeth and
`CollectArt.star4` for twinkles. Those drawings remain owned by their masters.

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/skins/art/card_frame_art.dart` — `CardFrameArt`, `CardFramePainter` | frame id (all 20 incl. skill), avatar size / centre, back or front layer, caller-supplied game time; leave `CardFrameArt.outset(size)` around the avatar (at most 7 pt) | `approvals_v26/versus_cards.html` — FRAMES tiles / preview, VS intro and 38 pt HUD avatar (frame under score box, O82); `approvals_v26/leaderboard.html` — podium / row / pinned-row frames (PRD:1202) |
| `lib/skins/art/card_name_art.dart` — shared name-style painter (F9c) | name-style id (all 20 incl. skill), text, font size / alignment, caller-supplied game time; gradient mask, per-glyph Flappy and O86 Thunderstruck belong to this master | `approvals_v26/versus_cards.html` — NAMES tiles / preview, VS intro, animated run name plate and results; `approvals_v26/leaderboard.html` — podium / row / pinned-row names (PRD:1202) |
| `lib/skins/art/card_sticker_art.dart` — shared victory-sticker painter (F9d) | sticker id (all 20 incl. skill), size / centre, caller-supplied game time; host supplies the intro's ≈42% scale / tilt | `approvals_v26/versus_cards.html` — STICKERS tiles / preview, both VS intro cards and winner's results sticker; leaderboard contexts reuse this master if showing a card sticker |

### Sparkles

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/run/effects/twinkle.dart` — `Twinkle` | centre, size, colour, rotation, waist, normalised curve time; the 8-vertex shape and curve stay | `levels_v26/item_reveal.html` — LEVEL ITEM REVEAL sparkles; `approvals_v26/missions.html` — §4 chest sparkle ring; `approvals_v26/leaderboard_gifts.html` — §2 OPENING THE BOX stars; `approvals_v26/star_road.html` — tier-claim sparkles; `approvals_v26/day_streak.html` — reward sparkles |
| `lib/run/effects/particle_pool.dart` — `ParticlePool` + `Particle` | capacity, spawn position / velocity / size / colour / life / gravity / fade / shape, draw priority; pool recycling and twinkle scheduling stay | `levels_v26/item_reveal.html` — reveal particles; `approvals_v26/missions.html` §4; `approvals_v26/leaderboard_gifts.html` §2; `approvals_v26/star_road.html` claim; `approvals_v26/weekly_course.html` §3 |
| `lib/run/effects/ring_tier_fx.dart` — `RingTierFx` | ring opening, seeded random, tier / glow state, back / front paint hooks; the glow + flame / sparkle art stays | In-run ring feedback reused in 2.6 run pictures: `approvals_v26/leaderboard.html` §4; `approvals_v26/flight_guide.html`; `approvals_v26/weekly_course.html` §2 |

### Emblems

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/levels/emblem_painter.dart` — `EmblemPainter`; `lib/components/levels/emblem_view.dart` — `EmblemView` | level (0 unranked, 1–31), art scale, time, grey, shine, pop scale, position / priority; the 32 approved drawings and their per-level colours stay | `levels_v26/emblems.html` — PROGRESSION and IN-GAME SIZES (all 32); `levels_v26/levels_screen.html` — LEVELS rows / current and next emblem; `approvals_v26/levels_tabs.html` — level emblem and tabs; `approvals_v26/leaderboard.html` — §1–§5 player / Home board emblems; `approvals_v26/versus_cards.html` — versus competitor emblem; `approvals_v26/star_road.html` — tier emblems; `approvals_v26/worlds_map.html` — world / level marker |
| `lib/components/levels/emblem_view.dart` — `recordEmblem` (recorded `Picture` shared with the LEVELS list, results and Home) | level, time, shine, grey and the canvas `PictureRecorder`; the emblem drawing comes from `EmblemPainter` | `approvals_v26/leaderboard.html` — §1 RESULTS PAGE: THE CLIMB climb / record emblem; `levels_v26/levels_screen.html` — static LEVELS row emblems; `approvals_v26/worlds_map.html` — record progress |

### Avatars

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/components/sticker_avatar.dart` — `StickerAvatars` | `Look` (bird / gear / hat), pixel size, mirror, cache size, frozen animation time, pixel ratio; star blob, white edge, tilt and shadow stay | `approvals_v26/leaderboard.html` — §1 RESULTS PAGE: THE CLIMB player pictures, §2–§3 HOME BOARD rows, §5 HOME ENTRY; `approvals_v26/versus_cards.html` — VS intro plates and versus bar; `approvals_v26/leaderboard_gifts.html` — §1 GO TO COLLECT player panel |

### Card painters

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/run/screens/results_screen.dart` — `ResultsCard` (+ `ResultsPlayerColumn`, `ResultsHeader`, `ResultsBar`, `ResultsClaimButton`, `ResultsLevelStage`, `ResultsFx`) | card content / rows, player data, result state, stage level, bar values, layout scale; the soft panel, columns and result-stage composition stay | `approvals_v26/leaderboard.html` — §1 RESULTS PAGE: THE CLIMB; `approvals_v26/weekly_course.html` — §3 WEEKLY RESULTS; `approvals_v26/missions.html` — §3 results pips / coins; `approvals_v26/first_win_of_day.html` — first-win results; `approvals_v26/versus_cards.html` — versus results |
| `lib/components/settings_panel.dart` — `SettingsCard` (+ `SettingsRow`, `SettingsTile`, `_TagBox`) | caption, rows, layout, position / size, danger / busy / on state; white card, chevrons, divider and tile styling stay | `approvals_v26/levels_tabs.html` — settings-like card / tab rows; `approvals_v26/versus_cards.html` — card sheet rows; `approvals_v26/texts.html` supporting Settings copy (not a new card) |
| `lib/share/share_card.dart` — `ShareCardPainter` | `ShareCardData` (kind, score / best, level, look, name, banner, text), loaded assets, 1080 canvas; card kinds, colours and layout stay | `approvals_v26/versus_cards.html` — card frame / name / sticker presentation; any 2.6 share entry reuses this painter (`approvals_v26/leaderboard.html` §1 climb share affordance) |
| `lib/components/skins/item_tile.dart` — `ItemTile` (+ `ItemTileState`, `PriceChip`, `TileBuyPill`) | item, rect, state (owned / equipped / trying / new / affordable), art cache, card colour, tint, reduce motion, on-screen test, enter delay; `rewardTile` selects a static, non-interactive rarity-bordered reward frame at the supplied rect size, with a 4 pt bottom border; normal shop decoration rules stay | `approvals_v26/versus_cards.html` — THE 51 ITEMS + 9 SKILL ITEMS; `approvals_v26/skill_cosmetics.html` — THE 24 ITEMS / secret tiles; `approvals_v26/levels_tabs.html` — reward item tiles |
| `lib/components/progression/star_road_popup.dart` — `StarRoadPopupTile` | reward, hidden-tier `extra`, tile index, coin image, appear time, position; the 52 pt frame, 4 pt bottom border, label and pop/wiggle motion stay | `approvals_v26/star_road_popup.html` — the waiting reward tiles (coins / feather / piece / mystery / +N) |
| `lib/components/progression/star_road_popup.dart` — `StarRoadPopup._BadgeGlow` | badge centre, radial radius, white → gold stops and opacity envelope; the cached 160 × 160 landing glow stays | `approvals_v26/star_road_popup.html` — the tier badge landing glow (`#pglow`) |
| `lib/components/shop/pack_art.dart` — `PackArtPainter` | tier, time, still; the 120 × 68 art box and cached tier pictures stay | `approvals_v26/missions.html` — §4 bonus chest coin-pack prize art only (feathers and pieces use the dedicated masters below); `approvals_v26/leaderboard_gifts.html` — §2 prize presentation where a pack-like reward tile is shown; `approvals_v26/star_road.html` — reward tiles |

### Reward and life icons

These painters supply the item art for reward stages, tiles, slots and fetch
flights; their owners apply the layout's canvas position / scale. A feather
or puzzle prize never uses `PackArtPainter`, which draws coin packs.

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/run/pickups/feather_pickup.dart` — `FeatherArt.paint` | `ghost` silhouette colour, white `outline` width, `opacity`; canvas position / scale / rotation supplied by the caller; vane, quill, notches and gold / pink palette stay | `approvals_v26/day_streak.html` — §2 THE DAILY REWARD MOMENT (day-7 feather) and §3 THE STREAK CARD reward icons; `approvals_v26/leaderboard_gifts.html` — §2 OPENING THE BOX feather prize; `approvals_v26/missions.html` — §4 BONUS CHEST feather prize; `approvals_v26/star_road.html` — feather reward tiers; `approvals_v26/flight_guide.html` — golden-feather entry |
| `lib/run/pickups/puzzle_piece_pickup.dart` — `PuzzleArt.paintPicture`, `paintPiece`, `paintPieceCentred`, `centreOf` / `paths` | `PuzzleTheme` colours, piece index 0–3, `ghost` silhouette / `seam` colour on `paintPiece`, caller canvas position / scale; shared four-piece outlines, tabs, picture and edge styling stay. Reward art uses these methods; new reward rays select R1–R4 above (O98) | `approvals_v26/day_streak.html` — §2 THE DAILY REWARD MOMENT (puzzle-piece fallback); `approvals_v26/leaderboard_gifts.html` — §2 OPENING THE BOX piece prize; `approvals_v26/missions.html` — §4 BONUS CHEST piece prize; `approvals_v26/puzzle_album.html` — ALBUM pictures, missing pieces and picture-complete result; `approvals_v26/star_road.html` — puzzle reward tiers; `approvals_v26/flight_guide.html` — puzzle-piece entry |
| `lib/run/effects/life_icons.dart` — `LifeIcons.paintHeart`, `paintShield` | heart: centre, size, fill, outline width / colour, shine, opacity, rotation; shield: centre, width, opacity; caller canvas transforms for layout; shared heart / shield paths and shield pink / gold / star styling stay | `approvals_v26/day_streak.html` — §2 THE DAILY REWARD MOMENT and §3 THE STREAK CARD (FREE SHIELD icon / flight / landing); `approvals_v26/flight_guide.html` — heart, extra-life and shield entries; `approvals_v26/weekly_course.html` — §2 THE WEEKLY RUN life HUD; `approvals_v26/leaderboard.html` — §4 THE PICTURE GUIDE life / shield depictions |

### Bird idle, look and flip

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/components/ui/bird_idle.dart` — `BirdIdle` | seeded random, calm mode, first-action delay, reduce-motion `still`, hop power / burst; bob, blink, lean and flip curves stay | `approvals_v26/leaderboard.html` — §5 HOME ENTRY / board player pictures; `approvals_v26/star_road.html` — Home popup bird; `approvals_v26/levels_tabs.html` — level emblem / bird idle |
| `lib/skins/art/look_painter.dart` — `LookPainter`; `lib/components/look_component.dart` — `LookComponent` | `Look` (bird / gear / hat / trail), art scale, pose (idle / flap / dead), blink, gold tier, blend tint, opacity, paused, flap override, position / priority; the art box and all skin drawings stay | `levels_v26/item_reveal.html` — reveal bird; `levels_v26/levels_screen.html` — level bird; `approvals_v26/leaderboard.html` — board avatars; `approvals_v26/versus_cards.html` — VS intro / card looks; `approvals_v26/flight_guide.html` — bird pictures |
| `lib/components/ui/flip.dart` — `FlipEffect`, `FlipDriver`, `ShrinkAway`, `ShrinkDriver` | decoration target, flip axis / squash, durations, swap / done callbacks, shrink start / end; the CSS flip and shrink curves stay | `approvals_v26/versus_cards.html` — card flip / selection; `approvals_v26/leaderboard.html` — tab change / card swap; `approvals_v26/levels_tabs.html` — tab content transition |

### Live UI motion

These are shared motion masters, not per-screen CSS rewrites. `LiveClock`
supplies one elapsed clock and the decorators consume it; reduce motion calls
`rest()` / `still`, never a second animation.

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/components/ui/live_effects.dart` — `LiveCurves` | input loop time and, where a curve already defines it, cascade delay; every keyframe, period and curve stay fixed | Idle motion on buttons, tags, packs and trophies in every 2.6 home / panel page: `approvals_v26/missions.html` §1–§2 and §4; `approvals_v26/day_streak.html` §1–§4; `approvals_v26/leaderboard.html` §2–§6; `approvals_v26/leaderboard_gifts.html` §1–§2; `approvals_v26/star_road.html` / `star_road_popup.html`; `approvals_v26/puzzle_album.html`; `approvals_v26/worlds_map.html`; `approvals_v26/versus_cards.html`; `approvals_v26/weekly_course.html` §1 and §3 |
| `lib/components/ui/live_effects.dart` — `WiggleEffect` | target component, pivot, a `LivePose` supplied by `LiveCurves`, rest / reduce-motion state; no ad-hoc sine wiggle | NEW / MOST POPULAR / BEST DEAL tags, trophy and emblem idle poses in the pages above |
| `lib/components/ui/live_effects.dart` — `PulseEffect` | target, peak amount, glow colour, blur, spread, inflate, pulse value, pivot, rest state; the pulse curve stays | `approvals_v26/missions.html` §1 home entry / mission strip and §4 chest; `approvals_v26/day_streak.html` §1 flame chip and §2 reward; `approvals_v26/star_road_popup.html` claim button; `approvals_v26/leaderboard.html` §5 home entry; `approvals_v26/levels_tabs.html` primary buttons |
| `lib/components/ui/live_effects.dart` — `LightStreak` | target, existing cascade delay, clock-driven progress, rest state; band width, skew, gradient and period stay | Primary / buy / claim buttons and selectable cards in `approvals_v26/missions.html`, `approvals_v26/day_streak.html`, `approvals_v26/leaderboard.html`, `approvals_v26/leaderboard_gifts.html`, `approvals_v26/star_road.html`, `approvals_v26/star_road_popup.html`, `approvals_v26/versus_cards.html` and `approvals_v26/weekly_course.html` |
| `lib/components/ui/live_effects.dart` — `LiveClock` | paused / still predicates and decorator bindings; period and scale factors never change here | The single idle clock for every animated 2.6 menu surface named above |

### Other run masters reused by 2.6 art

| Master file / class | Allowed parameters | 2.6 design elements that map here |
|---|---|---|
| `lib/run/hoops/ring_painter.dart` — `RingPainter` / `HoopPainter` | ring colours, opening, stroke width, dash, glow, front / back pass, tilt; the 24 pt vertical ring and 7 pt rim stay | `approvals_v26/leaderboard.html` — §4 run picture; `approvals_v26/flight_guide.html` — ring pictures; `approvals_v26/weekly_course.html` — §2 weekly run visuals |
| `lib/components/levels/tabs/worlds_tab.dart` — `WorldScenePreview`, using `kScenes` / `BackdropScene.draw` in `lib/run/backdrop/` | scene index, thumbnail size, fixed world palette, grey-to-colour reveal; existing scene geometry is cached unchanged | `approvals_v26/worlds_map.html` — WORLDS header and cards |
| `lib/run/effects/perfect_burst.dart` — `PerfectBurst` | tier, position, particle pool, seeded random; count and colour cycle stay | Run depictions in `approvals_v26/leaderboard.html` §4, `approvals_v26/flight_guide.html`, `approvals_v26/weekly_course.html` §2 |
| `lib/run/effects/shock_ring.dart` — `ShockRing` | position, radii, tilt, scale, stroke, opacity, length, delay, grow, glow; named presets stay the entry points | Reward / pass moments in `approvals_v26/missions.html` §4; `approvals_v26/leaderboard_gifts.html` §2; `approvals_v26/star_road.html`; run pictures in `approvals_v26/flight_guide.html` |
| `lib/skins/art/trail.dart` — `TrailEmitter` | trail id, seeded random, look painter, capacity seed history, scale, head, scroll / emit delta; the trail catalogue art stays | `levels_v26/item_reveal.html` — trail reveal art; `approvals_v26/versus_cards.html` — trail card items; `approvals_v26/leaderboard.html` — board avatars / run pictures |
| `lib/run/effects/spike_teeth.dart` — `SpikeTeethPainter` | edge, width, phase, colour / tint, strip height; the 44 pt strip shape and tooth rhythm stay | Any 2.6 drawing of the run: `approvals_v26/leaderboard.html` §4 picture guide (real full-bleed strips per O90); `approvals_v26/flight_guide.html`; `approvals_v26/weekly_course.html` §2; `levels_v26/item_reveal.html` review-stage strips |
| `lib/components/score_hud.dart` — `ScoreHud` (+ `ScoreCoverOverlay`) | score, position, tint / score colour, opacity, ride scene circle+digits / mix / alpha, squeeze cover amount and text colour; the 183 pt circle and LVDC digit art stay | `approvals_v26/weekly_course.html` §2 weekly run and §3 weekly results; `approvals_v26/leaderboard.html` §4 run picture; `approvals_v26/flight_guide.html` run depictions |
| `lib/run/effects/particle_pool.dart` — `ParticlePool` | capacity, seeded spawn position / velocity / size / life / spin / fade / shape / colour; pool ownership and the flat-particle style stay | Run sparkles, confetti, shards and bursts behind `approvals_v26/missions.html` §4, `approvals_v26/leaderboard_gifts.html` §2, `approvals_v26/star_road.html`, `approvals_v26/puzzle_album.html`, `approvals_v26/weekly_course.html` §2–§3 |
| `lib/run/effects/fireworks.dart` — `Fireworks` | launch y, launch x / burst y / colour / delay, seeded random, priority; rise, 34-streak burst, drag and fade stay | Level-up / reward moments in `levels_v26/item_reveal.html`; `approvals_v26/missions.html` §4; `approvals_v26/day_streak.html` §2; `approvals_v26/leaderboard.html` §1; `approvals_v26/first_win_of_day.html`; `approvals_v26/weekly_course.html` §3 |
| `lib/run/effects/pickup_touch_fx.dart` — `PickupTouchFx` / `PickupTouchSpec` | named pickup preset or body-colour preset, position, pool, delay / priority; flash, ring and square timings stay | Item / collect touch moments in `approvals_v26/missions.html` §4; `approvals_v26/leaderboard_gifts.html` §2; `approvals_v26/star_road.html`; `approvals_v26/flight_guide.html`; `levels_v26/item_reveal.html` reward interactions |
| `lib/run/effects/fetch_flight.dart` — `FetchFlight` / `FetchSpec` | source / target, item painter, named or value `FetchSpec`, particle pool, seeded random, land callback, priority; curve, swell and trail envelopes stay | Collect / claim flights in `approvals_v26/missions.html` §3–§4; `approvals_v26/day_streak.html` §2; `approvals_v26/leaderboard_gifts.html` §2; `approvals_v26/star_road.html`; `approvals_v26/puzzle_album.html` |
| `lib/run/effects/hud_fetch.dart` — `HudFetch`, `CoinFetch`, `GlowFetch` | source / target, custom item painter, life, priority; coin and glow subclasses keep their fixed art / timings | Coin / firefly HUD flights behind `approvals_v26/missions.html` §3, `approvals_v26/leaderboard_gifts.html` §2 and `approvals_v26/weekly_course.html` §3 |
| `lib/run/effects/collect_art.dart` — `CollectArt` | centre, radius / size, colour, alpha, triangle points, rounded-rect bounds; halo, four-point star and basic shapes stay | Shared sparkle / halo primitives in `levels_v26/item_reveal.html`; `approvals_v26/missions.html` §4; `approvals_v26/leaderboard_gifts.html` §2; `approvals_v26/star_road.html`; `approvals_v26/puzzle_album.html` |
| `lib/run/effects/collect_fx.dart` — `CollectBursts` / `CollectShake` | burst origin, colours, piece count / speed / shape / size / life / gravity; shake target, amplitude, decay; the pooled style stays | Hatch / smash / celebration moments used by `levels_v26/item_reveal.html`; `approvals_v26/missions.html` §4; `approvals_v26/leaderboard_gifts.html` §2; `approvals_v26/star_road.html`; `approvals_v26/puzzle_album.html` |
| `lib/run/effects/text_pop.dart` — `TextPop` | text, position, colour, font size; rise, fade and 1 s life stay | Small collect / reward count pops in `approvals_v26/missions.html` §3–§4; `approvals_v26/leaderboard_gifts.html` §2; `approvals_v26/weekly_course.html` §2–§3 |
| `lib/run/hud/collect_slot.dart` — `CollectSlot` / `CollectSlotItem` | queued item painter / timings already exposed by the item contract, banner host or null, position / layer ownership; one-at-a-time queue and fade / slide stay | Feather / puzzle-style collection and reward queues in `approvals_v26/missions.html` §3–§4; `approvals_v26/leaderboard_gifts.html` §2; `approvals_v26/puzzle_album.html`; `approvals_v26/star_road.html` |

## Approved design index

The files live under `docs/p26/design/` (path map: `docs/p26/README.md`).

| Approved page | Sections used above |
|---|---|
| `levels_v26/item_reveal.html` | LEVEL ITEM REVEAL — style A mystery box, lid shake / opening, reveal rays, sparkles, confetti |
| `levels_v26/levels_screen.html` | LEVELS — locked-row grey mystery box, level emblems, item tiles |
| `levels_v26/emblems.html` | PROGRESSION; IN-GAME SIZES |
| `approvals_v26/missions.html` | §1 HOME: THE MISSIONS STRIP; §2 THE MISSIONS PANEL; §3 RESULTS PAGE: PIPS FILL, COINS FLY; §4 ALL DONE: THE BONUS CHEST ON HOME |
| `approvals_v26/day_streak.html` | §1 HOME: THE FLAME CHIP; §2 THE DAILY REWARD MOMENT; §3 THE STREAK CARD; §4 STREAK LOST; §4b WHICH STREAK RESTORE BRINGS BACK |
| `approvals_v26/leaderboard.html` | §1 RESULTS PAGE: THE CLIMB; §2 HOME BOARD · TODAY TAB; §3 HOME BOARD · BEST RUN TAB; §4 THE PICTURE GUIDE; §5 THE HOME ENTRY; §6 ACHIEVEMENTS TAB |
| `approvals_v26/leaderboard_gifts.html` | §1 GO TO COLLECT; §2 OPENING THE BOX; §3 WHAT IS IN THE BOXES (owner-facing rule, not a player drawing) |
| `approvals_v26/star_road.html` | HOME POPUP · A REWARD IS WAITING; track / tiers; tier-claim moment; SEASON NAMES |
| `approvals_v26/star_road_popup.html` | Home popup |
| `approvals_v26/puzzle_album.html` | ALBUM header, picture-complete result and album rays |
| `approvals_v26/worlds_map.html` | WORLDS cards, locked worlds, level markers |
| `approvals_v26/versus_cards.html` | CARDS tab, VS intro, versus bar, 51 items + 9 skill items |
| `approvals_v26/skill_cosmetics.html` | THE 24 ITEMS, secret tiles, gold skill reveal |
| `approvals_v26/weekly_course.html` | §1 ENTRY POINTS; §2 THE WEEKLY RUN; §3 WEEKLY RESULTS |
| `approvals_v26/first_win_of_day.html` | First versus win of the day reward / results |
| `approvals_v26/flight_guide.html` | GUIDE tab, silhouettes, run pictures |
| `approvals_v26/levels_tabs.html` | Level tabs, gold NEW tag, grey locked mystery box at full size |
| `approvals_v26/achievement_icons.html` | Achievement icon presentation (icons are PNG exports, not a shared painter) |

## Verification notes

- `test/components/ui/mystery_box_test.dart` renders every tier and the grey
  level box, with and without `?`, steps closed → shake → lid-off, and writes
  the deterministic contact sheet `build/p26/mystery_box_style_a.png` for the
  visual comparison against `item_reveal.html` style A.
- `test/run/hoops/pair_gift_box_look_test.dart` proves each pair reward and
  the flying lid are pixel-identical to direct calls on the master, and pins
  the pair plane / ring / reach geometry. `test/run/hoops/s3_21_pair_test.dart`
  remains the behavioural authority for pair hits, rewards and timings.


### Day streak flame (G2b)

| Master file / class | Allowed parameters | Design map |
|---|---|---|
| `lib/components/progression/streak_strip.dart` — `StreakFlame`, `StreakStrip`, `StreakCard` | lit / grey, still, size, count, pending gold dot; three flame layers use 1.2 / 0.9 / 0.6 s loops and two embers with ≤ 1 pt travel | `approvals_v26/day_streak.html` §1–§3; G2c reuses this flame |

### Star Road star and tier plate (G6eA)

| Master file / class | Allowed parameters | Design map |
|---|---|---|
| `lib/components/star_road/star_road_art.dart` — `StarRoadStar` | size, position | `approvals_v26/star_road.html` header, card, rows and G6f popup; five-point gold star with dark edge |
| `lib/components/star_road/star_road_art.dart` — `StarRoadTierNode` | tier, size, position, claimed / claimable / next / locked state, optional label size / colour (G6f popup badge) | `approvals_v26/star_road.html` track, mini road and G6f popup / summary |
