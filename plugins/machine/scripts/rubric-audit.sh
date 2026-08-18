#!/usr/bin/env bash
# Audit how sub-agents were actually routed, from Claude Code session transcripts.
# READ-ONLY. Tallies Agent/Task dispatches by their `model` param and counts codex
# handoffs (codex exec/review Bash calls + pm:codex-* skill invocations).
#
#   rubric-audit.sh [--days N] [--projects DIR]
#
# Defaults: --days 7, --projects ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects
# Exit 0 = clean. Exit 1 = findings (any UNSET model, or any haiku dispatch).
# Exit 3 = python3 not available (needed to parse JSONL portably).
set -euo pipefail

days=7
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days="$2"; shift 2 ;;
    --projects) projects="$2"; shift 2 ;;
    *) echo "rubric-audit.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "rubric-audit.sh: python3 required" >&2; exit 3; }

python3 - "$projects" "$days" << 'PY'
import json, os, re, sys, time
from collections import Counter

root, days = sys.argv[1], int(sys.argv[2])
cutoff = time.time() - days * 86400
CODEX_RE = re.compile(r'(^|[^A-Za-z0-9_-])codex (exec|review)\b')

sessions = 0
models = Counter()          # 'fable' | 'opus' | 'sonnet' | 'haiku' | other | 'UNSET'
codex_bash = codex_skill = 0

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
            except OSError:
                continue
            sessions += 1
            with open(path, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    try:
                        obj = json.loads(line)
                    except ValueError:
                        continue
                    if obj.get("type") != "assistant":
                        continue
                    content = (obj.get("message") or {}).get("content")
                    if not isinstance(content, list):
                        continue
                    for c in content:
                        if not isinstance(c, dict) or c.get("type") != "tool_use":
                            continue
                        name = c.get("name")
                        inp = c.get("input") or {}
                        if name in ("Task", "Agent"):
                            models[inp.get("model") or "UNSET"] += 1
                        elif name == "Bash" and CODEX_RE.search(inp.get("command") or ""):
                            codex_bash += 1
                        elif name == "Skill" and str(inp.get("skill") or "").startswith("pm:codex-"):
                            codex_skill += 1

total = sum(models.values())
unset = models.get("UNSET", 0)
by = " · ".join(f"{m} {models.get(m, 0)}" for m in ("fable", "opus", "sonnet", "haiku"))
print(f"Rubric audit — last {days} days, {sessions} session(s)")
print(f"  Agent dispatches:  {total} total — model set: {total - unset}, UNSET: {unset}")
print(f"    by model:        {by}")
print(f"  Codex handoffs:    {codex_bash + codex_skill} (codex exec/review Bash calls: {codex_bash}, pm:codex-* skills: {codex_skill})")
sys.exit(1 if (unset or models.get("haiku", 0)) else 0)
PY
