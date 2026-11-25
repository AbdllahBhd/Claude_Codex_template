#!/usr/bin/env python3
"""usage-report.py - what Claude Code sessions cost, and where (read-only).

Reads the session logs under ~/.claude/projects (stdlib only, writes nothing):

    python3 scripts/usage-report.py                       # every project
    python3 scripts/usage-report.py --project . --since 2026-11-01 --until 2026-11-25
    python3 scripts/usage-report.py --json                # machine-readable

Reports per project and model: tokens and API-equivalent dollars, the largest
context each session reached, sessions past 150k / 400k, the subagent share,
Agent calls that named no model (they inherit the session's), and browser calls
and images in main threads. A project opened from several mount paths
(/mnt/..., /media/<user>/..., /run/media/<user>/...) and its worktrees count
as one project. Streamed messages repeat their usage on every line: each
message id is counted once. Figures are list-price estimates, not the bill.
"""
import argparse
import datetime
import glob
import json
import os
import re
import sys
from collections import defaultdict

# Prices as of 2026-11-25, USD per million tokens:
# (input, output, cache write 5m, cache write 1h, cache read).
# Source: Anthropic model docs (claude-api skill, shared/models.md and
# shared/model-migration.md). Update the date and rows when prices change.
PRICES_AS_OF = "2026-11-25"
PRICES = {
    "claude-fable-5-1": (10, 50, 12.5, 20, 0.25),
    "claude-mythos-5-1": (10, 50, 12.5, 20, 0.25),
    "claude-fable-5": (10, 50, 12.5, 20, 1.0),
    "claude-opus-5-5": (4, 20, 5, 8, 0.20),
    "claude-opus-5": (5, 25, 6.25, 10, 0.50),
    "claude-opus-4-8": (5, 25, 6.25, 10, 0.50),
    "claude-sonnet-5-5": (2, 10, 2.5, 4, 0.20),
    "claude-sonnet-5": (2, 10, 2.5, 4, 0.20),
    "claude-sonnet-4-6": (3, 15, 3.75, 6, 0.30),
    "claude-haiku-4-5": (1, 5, 1.25, 2, 0.10),
}
# Haiku 5.5 is tiered on prompt size: <=100k tokens / above.
HAIKU_55 = ((0.10, 0.50, 0.125, 0.20, 0.01), (0.50, 2.50, 0.625, 1.0, 0.05))
BROWSER_PREFIXES = ("mcp__Claude_Browser__", "mcp__claude-in-chrome__")


def price_row(model, prompt_tokens):
    if model.startswith("claude-haiku-5-5"):
        return HAIKU_55[prompt_tokens > 100_000]
    for name in sorted(PRICES, key=len, reverse=True):  # longest id wins
        if model.startswith(name):
            return PRICES[name]
    return None


def project_key(dirname):
    """One key per project, whatever mount path or worktree it was opened from."""
    key = dirname.lower()
    key = re.sub(r"--claude-worktrees-.*$", "", key)
    key = re.sub(r"^-(run-media-[^-]+-|media-[^-]+-|mnt-)", "", key)
    return key.strip("-")


def mangle(path):
    """Claude Code's projects-dir name for a path: non-alphanumerics become '-'."""
    return re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(path))


def day(value):
    try:
        return datetime.date.fromisoformat(value).isoformat()
    except ValueError:
        raise argparse.ArgumentTypeError(f"{value!r}: expected YYYY-MM-DD") from None


def in_range(ts, since, until):
    day = (ts or "")[:10]
    if not day:
        return since is None and until is None
    return (since is None or day >= since) and (until is None or day <= until)


def lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    yield json.loads(line)
                except ValueError:
                    continue  # partial line of a live session, or a non-JSON record
    except OSError as e:
        print(f"usage-report: skipped {path}: {e}", file=sys.stderr)


def scan(root, only_project, since, until):
    r = {
        "projects": defaultdict(lambda: {"usd": 0.0, "sessions": set(), "models": defaultdict(lambda: defaultdict(float))}),
        "max_context": defaultdict(int), "subagent_usd": 0.0, "unpriced": defaultdict(int),
        "agent_calls": 0, "agent_calls_no_model": 0, "main_browser_calls": 0, "main_images": 0,
    }
    seen_msgs, seen_tools = set(), set()
    for d in sorted(glob.glob(os.path.join(root, "*"))):
        if not os.path.isdir(d):
            continue
        key = project_key(os.path.basename(d))
        if only_project and key != only_project:
            continue
        files = glob.glob(os.path.join(d, "*.jsonl")) + glob.glob(os.path.join(d, "*", "subagents", "*.jsonl"))
        for path in sorted(files):
            sub_file = os.sep + "subagents" + os.sep in path
            for e in lines(path):
                if not isinstance(e, dict) or not in_range(e.get("timestamp"), since, until):
                    continue
                side = sub_file or bool(e.get("isSidechain"))
                msg = e.get("message") if isinstance(e.get("message"), dict) else {}
                content = msg.get("content") if isinstance(msg.get("content"), list) else []
                if e.get("type") == "user" and not side:
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "tool_result" and isinstance(c.get("content"), list):
                            r["main_images"] += sum(1 for x in c["content"] if isinstance(x, dict) and x.get("type") == "image")
                if e.get("type") != "assistant":
                    continue
                for c in content:
                    if not isinstance(c, dict) or c.get("type") != "tool_use":
                        continue
                    if c.get("id"):  # an id-less call cannot be a repeat of another
                        if c["id"] in seen_tools:
                            continue
                        seen_tools.add(c["id"])
                    name = c.get("name", "")
                    if name in ("Agent", "Task"):
                        r["agent_calls"] += 1
                        if not (c.get("input") or {}).get("model"):
                            r["agent_calls_no_model"] += 1
                    elif name.startswith(BROWSER_PREFIXES) and not side:
                        r["main_browser_calls"] += 1
                mid, usage = msg.get("id"), msg.get("usage")
                if not usage or (mid and mid in seen_msgs):
                    continue
                if mid:
                    seen_msgs.add(mid)
                sid = e.get("sessionId") or os.path.basename(path)
                model = msg.get("model", "?")
                inp = usage.get("input_tokens", 0) or 0
                out = usage.get("output_tokens", 0) or 0
                cw = usage.get("cache_creation_input_tokens", 0) or 0
                cr = usage.get("cache_read_input_tokens", 0) or 0
                cw1h = (usage.get("cache_creation") or {}).get("ephemeral_1h_input_tokens", 0) or 0
                prompt = inp + cw + cr
                row = price_row(model, prompt)
                usd = 0.0
                if row is None:
                    if model != "<synthetic>":
                        r["unpriced"][model] += 1
                else:
                    usd = (inp * row[0] + out * row[1] + (cw - cw1h) * row[2] + cw1h * row[3] + cr * row[4]) / 1e6
                p = r["projects"][key]
                p["usd"] += usd
                p["sessions"].add(sid)
                m = p["models"][model]
                for k, v in (("input", inp), ("output", out), ("cache_write", cw), ("cache_read", cr), ("usd", usd)):
                    m[k] += v
                if side:
                    r["subagent_usd"] += usd
                else:
                    r["max_context"][sid] = max(r["max_context"][sid], prompt)
    return r


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--project", help="project path (default: all projects)")
    ap.add_argument("--since", type=day, help="YYYY-MM-DD, inclusive (log timestamps are UTC)")
    ap.add_argument("--until", type=day, help="YYYY-MM-DD, inclusive (log timestamps are UTC)")
    ap.add_argument("--root", default=os.path.expanduser("~/.claude/projects"), help="session log directory")
    ap.add_argument("--json", action="store_true", help="print JSON instead of text")
    a = ap.parse_args()
    only = project_key(mangle(a.project)) if a.project else None
    r = scan(a.root, only, a.since, a.until)

    total = sum(p["usd"] for p in r["projects"].values())
    ctx = r["max_context"]
    summary = {
        "prices_as_of": PRICES_AS_OF,
        "total_usd": total,
        "subagent_usd": r["subagent_usd"],
        "projects": {k: {"usd": p["usd"], "sessions": len(p["sessions"]),
                         "models": {m: dict(v) for m, v in p["models"].items()}}
                     for k, p in sorted(r["projects"].items(), key=lambda kv: -kv[1]["usd"])},
        "max_context": dict(ctx),
        "sessions_over_150k": sum(1 for v in ctx.values() if v > 150_000),
        "sessions_over_400k": sum(1 for v in ctx.values() if v > 400_000),
        "agent_calls": r["agent_calls"],
        "agent_calls_no_model": r["agent_calls_no_model"],
        "main_browser_calls": r["main_browser_calls"],
        "main_images": r["main_images"],
        "unpriced_messages": dict(r["unpriced"]),
    }
    if a.json:
        json.dump(summary, sys.stdout, indent=2)
        print()
        return

    pct = lambda n, d: f"{100 * n / d:.0f}%" if d else "-"
    print(f"Claude Code usage ({a.since or 'start'} .. {a.until or 'now'}). Prices as of {PRICES_AS_OF}; list-price estimate.")
    print(f"Total ≈ ${total:,.2f}   subagents: {pct(r['subagent_usd'], total)}")
    print()
    print(f"{'project':40} {'sessions':>8} {'$':>10}  top model")
    for k, p in summary["projects"].items():
        top = max(p["models"].items(), key=lambda kv: kv[1]["usd"])[0] if p["models"] else "-"
        print(f"{k[:40]:40} {p['sessions']:>8} {p['usd']:>10,.2f}  {top}")
    print()
    print(f"Largest context per session: max {max(ctx.values(), default=0):,} tokens; "
          f"{summary['sessions_over_150k']} sessions > 150k, {summary['sessions_over_400k']} > 400k (of {len(ctx)})")
    print(f"Agent calls without a model: {r['agent_calls_no_model']} of {r['agent_calls']} ({pct(r['agent_calls_no_model'], r['agent_calls'])})")
    print(f"Main-thread browser calls: {r['main_browser_calls']}, images returned to main threads: {r['main_images']}")
    if r["unpriced"]:
        print(f"Unpriced models (add them to PRICES): {', '.join(sorted(r['unpriced']))}")


if __name__ == "__main__":
    main()
