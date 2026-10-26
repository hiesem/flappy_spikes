#!/usr/bin/env bash
# tester.sh <wp> <round> — start the Opus tester for build round <round> of <wp> (worker <wp>-t<round>, cap 45 min).
set -euo pipefail
. "$(dirname "$0")/env.sh"
wp=$1; n=$2; wt=$WS/.worktrees/p26-$wp; base=$(cat "$ORCH/base-$wp")
p=$ORCH/$wp.t$n.md
{
cat <<HDR
You are the Claude Opus 5.5 TESTER for work package $wp, build round $n, of the Flappy Spikes 2.6 build.
Worktree: $wt (branch p26/$wp). You may READ and RUN only: never edit, create or delete files in the repo, never
commit, never git reset/checkout/stash. Read CLAUDE.md (the "How 2.6 is built" block), docs/p26/BUILD_NOTES.md and
docs/p26/SHARED_ELEMENTS.md. Toolchain: export PATH="\$HOME/flutter/bin:\$HOME/.local/share/mise/installs/node/26.7.0/bin:\$PATH".

Review the change \`git diff $base...p26/$wp\` (and \`git log $base..p26/$wp\`) against the work package below:
- every acceptance criterion: met or not, with evidence (file:line or a test you ran);
- the PRD lines it cites and PRD §8.3 decisions; SPEC.md for gameplay; no second drawing of a shared element;
- paths: changes outside the package's paths are a finding unless clearly needed (say why);
- tests: run the package's tests and any test file the diff touches (single files, \`flutter test --no-pub -j 4 <files>\`;
  never the whole suite — the orchestrator runs that); no weakened or deleted assertions;
- obvious regressions or bugs in the touched code.
Blocker/major = must fix before merge; minor = nice to have.

End your reply with exactly this block (nothing after it):
VERDICT: PASS | FAIL
- [blocker|major|minor] <file:line> — <what is wrong> — fix: <what to do>
TESTS RUN: <files and results>
NOTES: <one line per acceptance criterion: met / not met>

=== THE WORK PACKAGE (builder brief) ===
HDR
cat "$ORCH/$wp.md"
echo; echo "=== BUILDER'S FINAL MESSAGE (round $n) ==="
cat "$ORCH/$wp.b$n.last.txt" 2>/dev/null || echo "(none)"
} > "$p"
exec "$(dirname "$0")/spawn.sh" "$wp-t$n" 45 "$wt" -- claude -p --model claude-opus-5-5 --effort medium \
  --permission-mode bypassPermissions --output-format json "$(cat "$p")"
