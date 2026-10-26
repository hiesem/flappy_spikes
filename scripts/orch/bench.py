#!/usr/bin/env python3
"""Benchmark logging for the 2.6 orchestration (compared with df4 afterwards). Append-only JSON Lines in
bench/events.jsonl of the feat/2.6 checkout; never rewrites a line. See docs/p26/ORCHESTRATION.md §8.

  bench.py ev <type> [key=value | key:=json ...]      any event (ts added unless given)
  bench.py worker <worker-id> --task T --role R [--wave W]   a finished builder/tester/verify worker -> turn or test event
  bench.py test --task T --scope targeted|full --where task-worktree|integration [--wave W] -- <cmd...>
                                                       run a test command, log a test event, exit with its code
  bench.py orch-turn --from ISO [--to ISO] [--transcript F]  one orchestrator turn: tokens from the Claude transcript
  bench.py summary                                     write bench/summary.md from the events
"""
import json, os, re, subprocess, sys, time, glob
from datetime import datetime, timezone

REPO = os.environ.get("REPO", "/home/killerhis/Projects/flappyspikes/.worktrees/p26")
ORCH = os.environ.get("ORCH", "/home/killerhis/Projects/flappyspikes/.worktrees/briefs26")
BENCH = os.path.join(REPO, "bench")
EVENTS = os.path.join(BENCH, "events.jsonl")
TRANSCRIPTS = os.path.expanduser("~/.claude/projects/-home-killerhis-Projects-flappyspikes")


def iso(t=None):
    return datetime.fromtimestamp(t if t is not None else time.time(), timezone.utc).astimezone().isoformat(timespec="seconds")


def append(ev):
    os.makedirs(BENCH, exist_ok=True)
    ev.setdefault("ts", iso()) if "ts_start" not in ev else None
    with open(EVENTS, "a") as f:
        f.write(json.dumps(ev, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(json.dumps(ev, ensure_ascii=False)[:300])


def parse_kv(args):
    out = {}
    for a in args:
        if ":=" in a:
            k, v = a.split(":=", 1); out[k] = json.loads(v)
        elif "=" in a:
            k, v = a.split("=", 1); out[k] = v
    return out


def flutter_failures(text):
    """failures from the last flutter summary line (+P ~S -F: ...), plus mocha 'N failing'."""
    n = 0
    m = re.findall(r"\+\d+(?: ~\d+)? -(\d+):", text)
    if m:
        n += int(m[-1])
    m2 = re.findall(r"^\s*(\d+) failing", text, re.M)
    if m2:
        n += int(m2[-1])
    return n


def worker(a):
    wid, task, role, wave = a.pos[0], a.opt.get("task"), a.opt.get("role"), a.opt.get("wave")
    d = os.path.join(ORCH, "workers", wid)
    cmd = open(os.path.join(d, "cmd")).read()
    start = int(open(os.path.join(d, "started")).read())
    exitf = os.path.join(d, "exit")
    end = os.path.getmtime(exitf) if os.path.exists(exitf) else time.time()
    code = open(exitf).read().strip() if os.path.exists(exitf) else "running"
    log = open(os.path.join(d, "log"), errors="replace").read() if os.path.exists(os.path.join(d, "log")) else ""
    cap = int(open(os.path.join(d, "cap")).read()) if os.path.exists(os.path.join(d, "cap")) else 0
    outcome = "ok" if code == "0" else ("timeout" if code == "killed" or (cap and end - start >= cap * 60) else "error")
    if "codex" in cmd and " exec" in cmd:
        tok = {"in": 0, "cached": 0, "out": 0, "reasoning": 0}; err = ""
        for line in log.splitlines():
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if e.get("type") == "turn.completed":
                u = e.get("usage") or {}
                tok["in"] += u.get("input_tokens", 0); tok["cached"] += u.get("cached_input_tokens", 0)
                tok["out"] += u.get("output_tokens", 0); tok["reasoning"] += u.get("reasoning_output_tokens", 0)
            elif e.get("type") in ("turn.failed", "error"):
                err = json.dumps(e)[:300]
        m = re.search(r"model_reasoning_effort=\"?(\w+)", cmd)
        if err and outcome == "ok":
            outcome = "error"
        append({"ev": "turn", "ts_start": iso(start), "ts_end": iso(end), "task_id": task, "role": role, "wave": wave,
                "model": "gpt-6.1-sol", "effort": m.group(1) if m else None, "outcome": outcome,
                "error": err or (log[-300:] if outcome != "ok" else ""), "tokens": tok, "worker": wid})
    elif "claude" in cmd and " -p" in cmd:
        tok = {"in": 0, "cached": 0, "out": 0, "reasoning": 0}; err = ""; result = ""
        try:
            j = json.loads(log[log.index("{"):]) if "{" in log else {}
            u = j.get("usage") or {}
            tok = {"in": u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0),
                   "cached": u.get("cache_read_input_tokens", 0), "out": u.get("output_tokens", 0),
                   "reasoning": (u.get("output_tokens_details") or {}).get("thinking_tokens", 0)}
            result = j.get("result") or ""
            if j.get("is_error"):
                err = str(result)[:300]
        except ValueError:
            err = "unparsed output: " + log[-200:]
        if err and outcome == "ok":
            outcome = "error"
        append({"ev": "turn", "ts_start": iso(start), "ts_end": iso(end), "task_id": task, "role": role, "wave": wave,
                "model": "claude-opus-5-5", "effort": "medium", "outcome": outcome, "error": err, "tokens": tok,
                "worker": wid})
        if role == "review" and result:
            rev = review_from_text(result)
            rev.update({"task_id": task, "model": "claude-opus-5-5", "wave": wave, "worker": wid})
            append(rev)
    else:   # a verify / test worker: log a test event
        append({"ev": "test", "ts_start": iso(start), "ts_end": iso(end), "task_id": task, "wave": wave,
                "cmd": cmd.strip()[:300], "scope": a.opt.get("scope", "full"),
                "where": a.opt.get("where", "task-worktree"), "exit": int(code) if code.isdigit() else -1,
                "failures": flutter_failures(log), "seconds": int(end - start), "worker": wid})


def review_from_text(text):
    v = re.search(r"VERDICT:\s*(PASS|FAIL)", text)
    findings = []
    for m in re.finditer(r"^\s*-\s*\[(blocker|major|minor)\]\s*(.+?)\s+—\s+(.+?)(?:\s+—\s+fix:.*)?$", text, re.M | re.I):
        findings.append({"severity": m.group(1).lower(), "file": m.group(2).strip()[:160], "issue": m.group(3).strip()[:300]})
    return {"ev": "review", "ts": iso(), "verdict": (v.group(1).lower() if v else "unknown"), "findings": findings}


def test(a):
    start = time.time()
    p = subprocess.run(a.rest, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    sys.stdout.write(p.stdout)
    append({"ev": "test", "ts_start": iso(start), "ts_end": iso(), "task_id": a.opt.get("task"), "wave": a.opt.get("wave"),
            "cmd": " ".join(a.rest)[:300], "scope": a.opt.get("scope", "targeted"),
            "where": a.opt.get("where", "task-worktree"), "exit": p.returncode,
            "failures": flutter_failures(p.stdout), "seconds": int(time.time() - start)})
    sys.exit(p.returncode)


def orch_turn(a):
    t0 = a.opt["from"]; t1 = a.opt.get("to") or iso()
    f = a.opt.get("transcript") or max(glob.glob(os.path.join(TRANSCRIPTS, "*.jsonl")), key=os.path.getmtime)
    def norm(s):
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    lo, hi = norm(t0), norm(t1)
    tok = {"in": 0, "cached": 0, "out": 0, "reasoning": 0}; n = 0
    for line in open(f, errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        m = d.get("message") or {}
        if d.get("type") != "assistant" or not m.get("usage") or not d.get("timestamp"):
            continue
        if not (lo <= norm(d["timestamp"]) <= hi):
            continue
        u = m["usage"]; n += 1
        tok["in"] += u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
        tok["cached"] += u.get("cache_read_input_tokens", 0); tok["out"] += u.get("output_tokens", 0)
    append({"ev": "turn", "ts_start": t0, "ts_end": t1, "task_id": None, "role": "orchestrate",
            "model": "claude-opus-5-5", "effort": "medium", "outcome": "ok", "error": "", "tokens": tok,
            "messages": n, "who": a.opt.get("who", "session")})


def summary(a):
    evs = [json.loads(l) for l in open(EVENTS)]
    t = lambda s: datetime.fromisoformat(s)
    out = ["# 2.6 orchestration benchmark summary", ""]
    rs = [e for e in evs if e["ev"] == "run_start"]; re_ = [e for e in evs if e["ev"] == "run_end"]
    if rs:
        out.append(f"Start {rs[0]['ts']} at `{rs[0].get('base_sha')}`; scope {rs[0].get('scope')}; "
                   f"max parallel agents {rs[0].get('max_parallel_agents')}.")
    if re_:
        out.append(f"End {re_[-1]['ts']} at `{re_[-1].get('end_sha')}`; total wall time "
                   f"{(t(re_[-1]['ts']) - t(rs[0]['ts'])).total_seconds() / 3600:.1f} h." if rs else "")
    out += ["", "## 1. Wall time per wave", "", "| wave | first task start | last merge | hours |", "|---|---|---|---|"]
    waves = sorted({e.get("wave") for e in evs if e.get("wave")})
    for w in waves:
        st = [t(e["ts_start"]) for e in evs if e.get("wave") == w and e["ev"] == "turn" and e.get("role") == "build"]
        mg = [t(e["ts_end"]) for e in evs if e.get("wave") == w and e["ev"] == "merge"]
        if st and mg:
            out.append(f"| {w} | {min(st).isoformat()} | {max(mg).isoformat()} | {(max(mg) - min(st)).total_seconds() / 3600:.1f} |")
    out += ["", "## 2. Tasks, turns and tokens per model", ""]
    tasks = {e.get("task_id") for e in evs if e["ev"] == "merge"}
    out.append(f"Tasks merged: {len(tasks)}.")
    per = {}
    for e in evs:
        if e["ev"] != "turn":
            continue
        k = (e.get("model"), e.get("role"))
        p = per.setdefault(k, {"turns": 0, "sec": 0, "in": 0, "cached": 0, "out": 0, "reasoning": 0, "bad": 0})
        p["turns"] += 1; p["sec"] += (t(e["ts_end"]) - t(e["ts_start"])).total_seconds()
        for x in ("in", "cached", "out", "reasoning"):
            p[x] += (e.get("tokens") or {}).get(x, 0) or 0
        p["bad"] += e.get("outcome") != "ok"
    out += ["| model | role | turns | hours | tokens in | cached | out | reasoning | not ok |", "|---|---|---|---|---|---|---|---|---|"]
    for (m, r), p in sorted(per.items(), key=lambda x: str(x[0])):
        out.append(f"| {m} | {r} | {p['turns']} | {p['sec'] / 3600:.1f} | {p['in']:,} | {p['cached']:,} | {p['out']:,} | {p['reasoning']:,} | {p['bad']} |")
    full = [e for e in evs if e["ev"] == "test" and e.get("scope") == "full"]
    out += ["", "## 3. Full-suite runs", "",
            f"{len(full)} runs, {sum(e.get('seconds', 0) for e in full) / 3600:.1f} h in total, "
            f"{sum(1 for e in full if e.get('exit') != 0)} red."]
    fixes = {}
    for e in evs:
        if e["ev"] == "turn" and e.get("role") == "fix":
            fixes[e["task_id"]] = fixes.get(e["task_id"], 0) + 1
    dist = {}
    for tid in tasks:
        dist[fixes.get(tid, 0)] = dist.get(fixes.get(tid, 0), 0) + 1
    out += ["", "## 4. Fix rounds per task", "", "| fix rounds | tasks |", "|---|---|"] + \
           [f"| {k} | {v} |" for k, v in sorted(dist.items())]
    out += ["", "## 5. Final check", "", "See bench/final-verify.log (unscoped `bash scripts/verify.sh`) and the list below.", ""]
    fv = [e for e in evs if e["ev"] == "final_check"]
    if fv:
        out.append("```\n" + json.dumps(fv[-1], indent=1, ensure_ascii=False) + "\n```")
    out += ["", "## 6. PRD acceptance per wave", "", "See bench/acceptance.md.", "",
            "## 7. Human interventions and incidents", ""]
    for e in evs:
        if e["ev"] in ("human", "incident"):
            out.append(f"- {e['ts']} **{e['ev']}** {e.get('what')}: {e.get('detail', '')}")
    open(os.path.join(BENCH, "summary.md"), "w").write("\n".join(out) + "\n")
    print("wrote bench/summary.md")


class A:
    pass


def main():
    argv = sys.argv[1:]
    if not argv:
        print(__doc__); return
    a = A(); a.cmd = argv[0]; a.pos = []; a.opt = {}; a.rest = []
    rest = argv[1:]
    if "--" in rest:
        i = rest.index("--"); a.rest = rest[i + 1:]; rest = rest[:i]
    i = 0
    while i < len(rest):
        if rest[i].startswith("--"):
            a.opt[rest[i][2:]] = rest[i + 1]; i += 2
        else:
            a.pos.append(rest[i]); i += 1
    if a.cmd == "ev":
        ev = {"ev": a.pos[0]}; ev.update(parse_kv(a.pos[1:]))
        if "ts" not in ev and "ts_start" not in ev:
            ev["ts"] = iso()
        append(ev)
    elif a.cmd == "worker":
        worker(a)
    elif a.cmd == "test":
        test(a)
    elif a.cmd == "orch-turn":
        orch_turn(a)
    elif a.cmd == "summary":
        summary(a)
    else:
        print(__doc__); sys.exit(2)


if __name__ == "__main__":
    main()
