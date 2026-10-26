#!/usr/bin/env python3
"""fixprompt.py <wp> <round-tested> <next-round> — the fix prompt for the next builder round: the tester's verdict
block and, when the verify was red, its failure tail. Written to briefs26/<wp>.fix<next>.md; prints the path."""
import json, os, re, sys
ORCH = "/home/killerhis/Projects/flappyspikes/.worktrees/briefs26"; W = ORCH + "/workers"
wp, n, nxt = sys.argv[1:4]
parts = [f"Fix round {nxt} for work package {wp} (orchestrator). The independent review and/or the full verify of round {n} "
         "found the problems below. Fix them all within the package's paths (the files named below are in scope for this "
         "round). Where an old test only encodes a rule that PRD 2.6 changed, update its expectation with a comment "
         "citing the PRD section — never weaken assertions; where it shows a real defect, fix the code. Then run every "
         "test file named below, then the scoped verify, and commit. Final message as before (list each finding: fixed how)."]
t = f"{W}/{wp}-t{n}/log"
if os.path.exists(t):
    s = open(t).read()
    try:
        r = json.loads(s[s.index("{"):]).get("result", "")
        parts.append("## Tester findings\n" + r[r.find("VERDICT"):] if "VERDICT" in r else r[-4000:])
    except ValueError:
        pass
v = f"{W}/{wp}-v{n}/log"
if os.path.exists(v) and open(f"{W}/{wp}-v{n}/exit").read().strip() != "0":
    s = open(v, errors="replace").read()
    i = s.rfind("=== flutter test: failures NOT in")
    tail = s[i:i + 3000] if i >= 0 else s[-3000:]
    parts.append("## Full verify was red\n```\n" + tail + "\n```")
p = f"{ORCH}/{wp}.fix{nxt}.md"
open(p, "w").write("\n\n".join(parts) + "\n")
print(p)
