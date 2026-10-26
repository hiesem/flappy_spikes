# Flappy Spikes 2.6 — build notes

The product spec is [`PRD-2.6-fun-progression.md`](PRD-2.6-fun-progression.md) (final, owner-approved 2026-10-23,
decisions O1–O96). Every design, text and icon in it is approved (O92–O96). This branch, `feat/2.6`, starts at
`feat/2.5` = 2.5.0+48 (`d0a72c2`); the PRD's `file:line` references point at that tree (`.worktrees/p25-merge` in the
PRD = this branch's first commit).

## Where the PRD's paths are in this repo

| PRD says | In this repo |
|---|---|
| `design/approvals_v26/<page>.html` | `docs/p26/design/approvals_v26/<page>.html` (texts: `texts.html`) |
| `design/levels_v26/<page>.html` | `docs/p26/design/levels_v26/<page>.html` |
| `design/achievements/` (48 approved icons, `ach_art.js`) and the 10 new ones (`ach_art_v26.js`, page `achievement_icons.html`) | `docs/p26/design/achievements/`, `docs/p26/design/approvals_v26/achievement_icons.html` |
| `.worktrees/p25-merge/...` | this repo at `d0a72c2` |

The design pages are self-contained HTML: open the source for exact sizes, colours, timings and texts. When the PRD and
a page disagree, the PRD wins; where the PRD is silent, the page is the reference (O92). Player-facing strings come
from `texts.html` (approved, O93), not from mockup placeholder lines (O83 / Q16).

## Milestones = the PRD's build waves (§4)

| Milestone | PRD wave | Contents (see PRD §4 for the full list) |
|---|---|---|
| M0 | 0 — server + consoles | Functions, rules, indexes, schemas and their tests (brackets / `plv` / `look.card` / `space` / `passHist` + `jump`, the duel staircase fixtures, WP-LB server: collections, callables, import + cleanup scripts, TTL). **Code and tests only — deploying is an owner/orchestrator step after M0 merges.** |
| M1 | 1 — run core | WP-A events, WP-D curve / tilt / Δy / hazard budget / calm / formations / mix chapters, WP-C gates, WP-B showcase. |
| M2 | 2 — progression model | WP-J model + payout, WP-E client, WP-K, WP-F F5/F6/F7/F11, WP-H arm plumbing, WP-LB client model (no UI). |
| M3 | 3 — daily meta | WP-G1 missions, G2 streak + STREAK LOST restore, G3 notifications, popup budget C2. |
| M4 | 4 — long-term layer | WP-LB board + results climb, Levels tabs (worlds / guide / album), G5 weekly course, F9 versus cards, F10 skill items + HOW TO EARN, Home without the medal box, G6 extras + Star Road. |
| M5 | 5 — art, polish, docs | Emblem PNGs, cosmetic art, 10 achievement icons (export from the approved pages), goldens, WP-I docs, version 2.6.0. |

Not buildable here (they are user actions in the plans and the reports): Firebase deploys and the leaderboard import,
console / store work (PRD §7.3), Play uploads, device (Pixel) e2e, the privacy-page deploy, release clicks.
