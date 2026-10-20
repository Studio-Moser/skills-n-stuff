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
# Exit 0 = clean. Exit 1 = findings (any UNSET model in either provider).
# Exit 3 = python3 not available (needed to parse JSONL portably).
set -euo pipefail

days=7
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
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

python3 - "$projects" "$days" "$codex_sessions" "$config_dir" << 'PY'
import glob, json, os, re, sys, time
from collections import Counter
from datetime import datetime

root, days, codex_root, config_dir = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
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

declared_cache = {}

def declared_model(agent_type):
    """The `model:` an agent definition declares, from the newest installed plugin copy
    (`plugin:name`) or the user agents dir (`name`). None when absent or not found."""
    # ponytail: plugin and user agents only; project agents would need the session cwd.
    if not agent_type:
        return None
    if agent_type not in declared_cache:
        plugin, _, name = agent_type.rpartition(":")
        if plugin:
            versions = sorted(
                (d for d in glob.glob(os.path.join(config_dir, "plugins", "cache", "*", plugin, "*")) if os.path.isdir(d)),
                key=lambda d: [int(x) if x.isdigit() else x for x in re.split(r"[.-]", os.path.basename(d))],
            )
            path = os.path.join(versions[-1], "agents", name + ".md") if versions else ""
        else:
            path = os.path.join(config_dir, "agents", name + ".md")
        model = None
        try:
            text = open(path, encoding="utf-8").read()
            front = re.match(r"---\n(.*?)\n---", text, re.S)
            found = front and re.search(r"^model:\s*(\S+)", front.group(1), re.M)
            model = found.group(1) if found else None
        except OSError:
            pass
        declared_cache[agent_type] = model
    return declared_cache[agent_type]

def family(model):
    found = re.search(r"fable|opus|sonnet|haiku", model)
    return found.group(0) if found else model

for _size, path in transcripts.values():
    active = False
    unset_calls = []        # (tool_use id, session model) per dispatch without a model param
    resolved = {}           # tool_use id -> model the dispatch actually ran on
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            result = obj.get("toolUseResult")
            if obj.get("type") == "user" and isinstance(result, dict) and result.get("resolvedModel"):
                for c in (obj.get("message") or {}).get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_result":
                        resolved[c.get("tool_use_id")] = result["resolvedModel"]
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
                    if inp.get("model"):
                        models[inp["model"]] += 1
                    else:
                        unset_calls.append((c.get("id"), (obj.get("message") or {}).get("model") or "unknown", inp.get("subagent_type")))
                elif name == "Bash" and DISPATCH_RE.search(inp.get("command") or ""):
                    codex_dispatch += 1
                elif name == "Bash" and CODEX_RE.search(inp.get("command") or ""):
                    codex_bash += 1
                elif name == "Skill" and str(inp.get("skill") or "").startswith("pm:codex-"):
                    codex_skill += 1
    # An agent type can define its own model. A dispatch without a model param that ran
    # on a different model than the session's was routed by its definition, not inherited.
    # An agent definition that declares `model: inherit` chose the session model on purpose.
    for call_id, session_model, agent_type in unset_calls:
        ran_on = resolved.get(call_id)
        if ran_on and ran_on != session_model:
            models[family(ran_on)] += 1
        elif declared_model(agent_type) == "inherit":
            models["inherit"] += 1
        else:
            models["UNSET"] += 1
            inherited[session_model] += 1
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
sys.exit(1 if (unset or codex_unset) else 0)
PY
