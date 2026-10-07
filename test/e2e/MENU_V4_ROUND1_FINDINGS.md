# PRD-menu-v4 — QA round 1

Date: 2026-10-07. Branch: `v4-qa`. Scope: PRD §2–4 and §8, with
`briefs5/common.md`, `wpK1.md`, `wpK2.md` and `CLAUDE.md` applied.
**Two findings — both fixed in branch `v4-fix1` (Fix menu-v4 R1); the
S1-70 / S2-70 groups now run unskipped.**

## Gates and reproductions

| Check | Result |
| --- | --- |
| `flutter pub get` | Passed; no tracked dependency changes |
| Baseline `flutter analyze` | No issues |
| Baseline full `flutter test` | 749 passed |
| Final `flutter analyze --no-pub` | No issues |
| Final full `flutter test --no-pub --reporter expanded` | 783 passed, 4 explicitly skipped defect reproductions |
| Schedule E2E with `QA_V4_OPEN_DEFECTS=true` | 29 passed, 4 failed as expected: three S1-70 variants and one S2-70 |

Added 34 passing journeys and four quarantined reproductions under `test/e2e/`.
The groups carry `skip: 'S1-70 open'` / `skip: 'S2-70 open'` by default.
To execute the failing assertions without editing the files:

```bash
export PATH="$HOME/flutter/bin:$HOME/Android/Sdk/platform-tools:$PATH" \
  ANDROID_HOME="$HOME/Android/Sdk" JAVA_HOME="$(ls -d $HOME/opt/jdk-17* | head -1)"
flutter test --no-pub test/e2e/menu_v4_round1_schedule_e2e_test.dart \
  --dart-define=QA_V4_OPEN_DEFECTS=true --reporter expanded
```

## Findings

| ID | Severity | Location | What's wrong | Reproduction | Expected |
| --- | --- | --- | --- | --- | --- |
| S1-70 | Major | `lib/game/flappy_game.dart:517`, `:519`, `:524` | Each eligible session start adds an upsell request. The request retains its original reason and rechecks only ownership/runs, so multiple queued arrivals bypass the current gap, daily cap and consumed triggers when displayed. | Leave an owed LEVEL UP card open, advance 24 h, and background/resume three times for exactly 30 min each. Claim LEVEL UP, then close the offers. **Three** shows are recorded on the same day, at the same clock instant. A separate reproduction resumes after 24 h with an existing offer still open: closing that card immediately opens another. | Keep at most one pending session upsell, avoid queuing another while it is already displayed, and re-evaluate the policy immediately before presentation. Closing must close the offer; later shows must respect ≥4 h and ≤2/day. |
| S2-70 | Minor, timing/spec mismatch | `lib/menu/noads_popup_policy.dart:135` (with `:112`) | Dismissal increments the analytics count only; the cooldown remains anchored to display time. This misses PRD §8.5's closing rule. | Show at 08:00; leave the card open in the foreground until 09:00 and dismiss. Complete three videos, then resume home at 12:30 after 30 min away. The offer shows again, only **3 h 30 min after dismissal**. | PRD §8.5 says closing “simply starts the 4-hour gap.” With that rule, this arrival stays blocked until 13:00. Preserve the separate last-shown time if needed for the display gap and 24 h fallback. |

S1-70 also has a clock-correction reproduction: queue behind LEVEL UP after
24 h + 30 min, move the clock back 24 h before claiming, and the offer still
displays even though only 30 min have elapsed since the persisted prior show.
All three variants fail at their intended assertions when enabled.

S2-70 is reported against the requested PRD. Its §8.2 explicitly measures the
minimum gap from the last show, while §8.5 additionally says closing starts
the gap. The implementation and local `SPEC.md:127` describe display-time
behavior only. The failing test pins the explicit closing instruction rather
than silently treating those descriptions as equivalent.

## Verified behavior

- The queried/bought catalog contains exactly `coins_1000`, `coins_10000`,
  `coins_17000`, `coins_100000` and unchanged `no_ads`. No obsolete product-ID
  references remain in `lib/` or Dart tests. Coin amounts are 1,000 / 10,000 /
  17,000 / 100,000; consumable purchases grant a combined 128,000, with correct
  IDs and amounts in analytics and persistence after an actual game restart.
- Shop tags are on 10,000 (MOST POPULAR) and 100,000 (BEST DEAL). Amount labels
  fit at 568 and 711 pt. The existing 711 pt Shop screenshot was inspected:
  amounts, tags and USD buttons are legible, including 100,000.
- Shop banner and all pack buttons show the prescribed USD placeholders,
  then switch in place to verbatim `ProductDetails.price` strings as a partial
  catalog arrives. The automatic No-ads popup also updates while open, and its
  price matches the `PurchaseParam` passed to the native-store stand-in.
  Missing products retain their placeholders and fail without granting coins.
- Each successful pack produces its actual celebration: 6 / 9 / 12 / 16
  coins, 0.9 / 1.2 / 1.5 / 1.9 s, 40 / 70 / 100 / 150 confetti, common / rare /
  epic / legendary jingles, and flash only for the largest. A fresh No-ads
  purchase grants 1,000 bonus coins, persists ownership, and never pays another
  bonus or celebration for a replayed receipt.
- First-session suppression, day-2 eligibility without runs, day-1 eligibility
  at exactly 10 finished runs, 29:59 vs 30:00 background gaps, inactive-only
  returns, the exact 4 h boundary, the exact 24 h fallback, midnight rollover,
  and the normal two-per-day cap pass. The cap survives a restart.
- Three completed videos trigger `reason=videos`; two survive a restart and
  remain insufficient. Real game actions for free coins and the powerup slot
  feed the count. Dismissed, failed and unavailable ads do not. New-best and
  new-level runs give the corresponding reason; only the latest run supplies
  the mood. A score of 5 suppresses the offer, while 6 allows it. Completed
  runs, last score and mood survive game restarts.
- Ordinary queue ordering with LEVEL UP, cancelled/failed purchase results
  and No-ads purchase celebrations passes, with one active modal at a time.
  Ownership arriving before a queued offer suppresses it. Already-owned
  installs with all triggers never see the offer. The S1-70 repeated-queue
  cases above are the exception.
- Cross, dim, back and Esc close the card and increment dismissal analytics;
  no START occurs. One hundred prior dismissals impose no cap. The longer-open
  closing cooldown is the S2-70 exception above.
- Returns into Shop or an active run do not become offers between runs. A
  queued arrival during delayed START is discarded once gameplay starts.
  Backward clocks block fresh evaluations; debug day offsets move the stored
  time/day and survive restart. The queued-clock exception is in S1-70.

The tests mount the real Flame game and use `StoreIapService` for billing
journeys, replacing only the native store. Final-score injection reaches exact
run boundaries through the real death/replay handlers; physics remains covered
by the existing acceptance bot. Native Play billing/ad sheets and store-side
§5–7 were not exercised. Tablet screenshots written outside this worktree were
ignored and are not part of the commit.
