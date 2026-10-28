#!/usr/bin/env python3
"""mkbrief.py <wp> <title> <status-file> <start-marker> <end-marker> [--extra FILE] — writes .worktrees/briefs26/<wp>.md:
the standing builder header + the WP block cut from docs/p26/status/<status-file> (start marker inclusive, end exclusive)."""
import sys, os
REPO = "/home/killerhis/Projects/flappyspikes/.worktrees/p26"
ORCH = "/home/killerhis/Projects/flappyspikes/.worktrees/briefs26"
wp, title, sf, a, b = sys.argv[1:6]
extra = ""
if "--extra" in sys.argv:
    extra = open(sys.argv[sys.argv.index("--extra") + 1]).read()
src = open(os.path.join(REPO, "docs/p26/status", sf)).read()
i = src.index(a); j = src.index(b, i + len(a)) if b != "EOF" else len(src)
block = src[i:j].strip()
head = f"""# Work package {wp} — {title}

You are a DeepSeek V4.1 Flash builder (codex) in the Flappy Spikes 2.6 build. Your worktree is
`/home/killerhis/Projects/flappyspikes/.worktrees/p26-{wp}` (branch `p26/{wp}`); stay in it.

Read first: `AGENTS.md` (the "How 2.6 is built" block is binding for you), `docs/p26/BUILD_NOTES.md`, and the PRD
lines this package cites (`docs/p26/PRD-2.6-fun-progression.md`, including §8.3 decisions). The full audit evidence for
this area is `docs/p26/status/{sf}`.

Rules (binding): build ONLY this package; touch only the paths below (plus the tests it names); edits in shared hot
files stay inside a `// region P26-{wp}` … `// endregion` block; never edit `scripts/known_red_tests.txt`; never weaken or
delete an assertion to get green; no deploys, no adb/devices, no store consoles, never read secrets or key files.
Toolchain: `export PATH="$HOME/flutter/bin:$HOME/.local/share/mise/installs/node/26.7.0/bin:$PATH"`. Run single test
files while you work (`flutter test --no-pub -j 4 <file>`), never the whole suite. Before you stop run
`VERIFY_BASE=feat/2.6 VERIFY_SCOPED=1 bash scripts/verify.sh` and get it green, then commit everything on your branch
(`git add -A && git commit -m "{wp}: <summary>"`).

Final message (short): files changed; tests added/changed; the scoped verify result line; known-red entries that now
pass; anything you could not do and why; any conflict with the PRD or another area.

## The work package
"""
out = head + "\n" + block + "\n" + (("\n## Orchestrator notes\n" + extra) if extra else "")
open(os.path.join(ORCH, f"{wp}.md"), "w").write(out)
print(f"{wp}: {len(out)} chars")
