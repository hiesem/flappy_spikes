#!/usr/bin/env bash
# rebaseprompt.sh <wp> <next-round> — the merge-conflict round prompt for <wp> (prints its path)
. "$(dirname "$0")/env.sh"
p="$ORCH/$1.fix$2.md"
cat > "$p" <<TXT
Merge-conflict round (orchestrator): branch p26/$1 no longer rebases cleanly onto feat/2.6 (other packages merged since).
In your worktree run \`git rebase feat/2.6\`, resolve every conflict keeping BOTH sides' intent (your package + the merged
changes), make sure nothing the merged packages added is reverted or lost, run your package's test files and the scoped
verify (\`VERIFY_BASE=feat/2.6 VERIFY_SCOPED=1 VERIFY_SKIP_HEAVY=1 bash scripts/verify.sh\`), and leave the branch rebased
(no merge commits, everything committed). Final message: each conflict and how you resolved it.
TXT
echo "$p"
