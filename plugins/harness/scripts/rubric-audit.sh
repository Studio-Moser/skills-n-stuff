#!/usr/bin/env bash
# Audit how sub-agents were actually routed, from Claude Code and Codex session
# transcripts. READ-ONLY. Tallies Claude Agent/Task dispatches by their `model` param,
# Codex spawn_agent calls by model and effort, and Claude-to-Codex handoffs (codex
# exec/review and codex-dispatch.sh Bash calls, pm:codex-* skill invocations). An
# unset model inherits the session's model; the report names what was inherited.
#
#   rubric-audit.sh [--days N] [--projects DIR] [--codex-sessions DIR]
#
# Defaults: --days 7, --projects ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects,
#           --codex-sessions ${CODEX_HOME:-$HOME/.codex}/sessions
# Exit 0 = clean. Exit 1 = findings (any UNSET model in either provider, or any haiku dispatch).
# Exit 3 = python3 not available (needed to parse JSONL portably).
set -euo pipefail

days=7
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
codex_sessions="${CODEX_HOME:-$HOME/.codex}/sessions"
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days="$2"; shift 2 ;;
    --projects) projects="$2"; shift 2 ;;
    --codex-sessions) codex_sessions="$2"; shift 2 ;;
    *) echo "rubric-audit.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "rubric-audit.sh: python3 required" >&2; exit 3; }

python3 - "$projects" "$days" "$codex_sessions" << 'PY'
import json, os, re, sys, time
from collections import Counter
from datetime import datetime

root, days, codex_root = sys.argv[1], int(sys.argv[2]), sys.argv[3]
cutoff = time.time() - days * 86400
CODEX_RE = re.compile(r'(^|[^A-Za-z0-9_-])codex (exec|review)\b')
# An invocation, not a mention (grep, ls, docs): the script always takes --operation.
DISPATCH_RE = re.compile(r'codex-dispatch\.sh"?\s+(?:\\\s*)?--operation')

def in_window(obj):
    # Entries carry their own ISO timestamp; file mtime only says when the file
    # was last touched (a moved project directory refreshes it). An entry with
    # no timestamp is counted so hand-written fixtures still work.
    ts = obj.get("timestamp")
    if not isinstance(ts, str) or not ts:
        return True
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp() >= cutoff
    except ValueError:
        return True

sessions = 0
transcripts = {}            # session id -> path; a moved project dir leaves a duplicate transcript
models = Counter()          # 'fable' | 'opus' | 'sonnet' | 'haiku' | other | 'UNSET'
inherited = Counter()       # session model an UNSET Claude dispatch inherited
codex_bash = codex_dispatch = codex_skill = 0

if os.path.isdir(root):
    for dirpath, dirnames, filenames in os.walk(root):
        # ponytail: skip sub-agent transcripts by path segment; they are the dispatched
        # work, not dispatches. Upgrade path if the layout changes: read isSidechain.
        if "/subagents" in dirpath.replace(os.sep, "/"):
            continue
        for fn in filenames:
            if not fn.endswith(".jsonl"):
                continue
            path = os.path.join(dirpath, fn)
            try:
                if os.path.getmtime(path) < cutoff:
                    continue
                size = os.path.getsize(path)
            except OSError:
                continue
            session_id = fn[:-len(".jsonl")]
            # A session copied then continued in the new location: the larger copy is
            # the live one, so it wins regardless of os.walk order.
            prior = transcripts.get(session_id)
            if prior is None or size > prior[0]:
                transcripts[session_id] = (size, path)

for _size, path in transcripts.values():
    active = False
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if obj.get("type") != "assistant" or not in_window(obj):
                continue
            active = True
            content = (obj.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for c in content:
                if not isinstance(c, dict) or c.get("type") != "tool_use":
                    continue
                name = c.get("name")
                inp = c.get("input") or {}
                if name in ("Task", "Agent"):
                    model = inp.get("model") or "UNSET"
                    models[model] += 1
                    if model == "UNSET":
                        inherited[(obj.get("message") or {}).get("model") or "unknown"] += 1
                elif name == "Bash" and DISPATCH_RE.search(inp.get("command") or ""):
                    codex_dispatch += 1
                elif name == "Bash" and CODEX_RE.search(inp.get("command") or ""):
                    codex_bash += 1
                elif name == "Skill" and str(inp.get("skill") or "").startswith("pm:codex-"):
                    codex_skill += 1
    if active:
        sessions += 1

# Codex: one rollout file per thread. Sub-agent threads carry source.subagent in
# session_meta; like Claude's subagents/ transcripts they are the dispatched work.
codex_sessions = 0
codex_models = Counter()    # "model@effort" | "UNSET"
codex_inherited = Counter() # turn model an UNSET spawn_agent inherited
if os.path.isdir(codex_root):
    for dirpath, _dirnames, filenames in os.walk(codex_root):
        for fn in filenames:
            if not fn.endswith(".jsonl"):
                continue
            path = os.path.join(dirpath, fn)
            try:
                if os.path.getmtime(path) < cutoff:
                    continue
            except OSError:
                continue
            active = False
            turn_model = "unknown"
            with open(path, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    try:
                        obj = json.loads(line)
                    except ValueError:
                        continue
                    payload = obj.get("payload") or {}
                    kind = obj.get("type")
                    if kind == "session_meta":
                        source = payload.get("source")
                        if isinstance(source, dict) and "subagent" in source:
                            break
                        continue
                    if kind == "turn_context":
                        turn_model = payload.get("model") or turn_model
                        continue
                    if kind != "response_item" or not in_window(obj):
                        continue
                    active = True
                    if payload.get("type") != "function_call" or payload.get("name") != "spawn_agent":
                        continue
                    try:
                        args = json.loads(payload.get("arguments") or "{}")
                    except ValueError:
                        args = {}
                    model = args.get("model")
                    effort = args.get("reasoning_effort")
                    if model:
                        codex_models[f"{model}@{effort}" if effort else model] += 1
                    else:
                        codex_models["UNSET"] += 1
                        codex_inherited[turn_model] += 1
            if active:
                codex_sessions += 1

def inherited_note(counter):
    if not counter:
        return ""
    return " (inherited: " + ", ".join(f"{m} {n}" for m, n in counter.most_common()) + ")"

total = sum(models.values())
unset = models.get("UNSET", 0)
claude_named = ("fable", "opus", "sonnet", "haiku")
by = " · ".join(
    [f"{m} {models.get(m, 0)}" for m in claude_named]
    + [f"{m} {n}" for m, n in models.most_common() if m not in claude_named and m != "UNSET"]
)
codex_total = sum(codex_models.values())
codex_unset = codex_models.get("UNSET", 0)
codex_by = " · ".join(f"{m} {n}" for m, n in codex_models.most_common() if m != "UNSET") or "none"
handoffs = codex_bash + codex_dispatch + codex_skill
print(f"Rubric audit — last {days} days, {sessions + codex_sessions} session(s)")
print(f"  Claude:            {sessions} session(s)")
print(f"  Agent dispatches:  {total} total — model set: {total - unset}, UNSET: {unset}{inherited_note(inherited)}")
print(f"    by model:        {by}")
print(f"  Codex handoffs:    {handoffs} (codex exec/review Bash calls: {codex_bash}, codex-dispatch.sh: {codex_dispatch}, pm:codex-* skills: {codex_skill})")
print(f"  Codex:             {codex_sessions} session(s)")
print(f"  spawn_agent:       {codex_total} total — model set: {codex_total - codex_unset}, UNSET: {codex_unset}{inherited_note(codex_inherited)}")
print(f"    by model:        {codex_by}")
sys.exit(1 if (unset or codex_unset or models.get("haiku", 0)) else 0)
PY
