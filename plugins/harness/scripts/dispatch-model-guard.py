#!/usr/bin/env python3
"""Claude Code PreToolUse hook: every Agent dispatch names its model.

An Agent (or legacy Task) call without a `model` parameter runs on the session's
model, so a lookup or a search silently runs on the most expensive model and the
rubric audit reports it as UNSET. Instructions and memory only ask; memory is also
per project folder, so a session in another folder never sees the rule.

Denies such a call with a reason, so the model adds `model` and dispatches again,
and logs one Shim_Events firing. A call is left alone when it sets `model`, is a
fork (which always runs on the parent's model), or uses an agent type whose
definition declares its own `model:` (user, project, or plugin agents), which is
exactly what rubric-audit.sh does not count as UNSET. The hook never returns
`allow`. Any error exits 0 with no output, which leaves the call untouched.
"""

from __future__ import annotations

import glob
import json
import os
from pathlib import Path
import re
import sys

SHIM_ID = "dispatch-model-guard"
TOOLS = {"Agent", "Task"}
FRONT_MODEL = re.compile(r"\A---\n(.*?)\n---", re.S)


def version_key(path: str) -> list:
    return [int(x) if x.isdigit() else x for x in re.split(r"[.-]", os.path.basename(path))]


def declared_model(agent_type: str, cwd: str) -> str | None:
    """The `model:` an agent definition declares, as rubric-audit.sh resolves it."""
    config = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    if ":" in agent_type:
        plugin, _, name = agent_type.partition(":")
        versions = sorted((d for d in glob.glob(os.path.join(config, "plugins", "cache", "*", plugin, "*"))
                           if os.path.isdir(d)), key=version_key)
        candidates = [os.path.join(versions[-1], "agents", name + ".md")] if versions else []
    else:
        candidates = [os.path.join(cwd, ".claude", "agents", agent_type + ".md"),
                      os.path.join(config, "agents", agent_type + ".md")]
    for path in candidates:
        try:
            front = FRONT_MODEL.match(Path(path).read_text(encoding="utf-8"))
        except OSError:
            continue
        found = front and re.search(r"^model:\s*(\S+)", front.group(1), re.M)
        return found.group(1) if found else None
    return None


def decide(payload: dict) -> dict | None:
    if payload.get("tool_name") not in TOOLS or "turn_id" in payload:  # turn_id: Codex
        return None
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict) or tool_input.get("model"):
        return None
    agent_type = str(tool_input.get("subagent_type") or "general-purpose")
    if agent_type == "fork" or declared_model(agent_type, str(payload.get("cwd") or os.getcwd())):
        return None
    reason = (
        f"This {agent_type} dispatch has no `model`, so it would run on the session's model. "
        "Add a `model` parameter chosen for the work (harness:delegate resolves one by route) "
        "and dispatch it again."
    )
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                   "permissionDecisionReason": reason}}


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        output = decide(payload)
        if output is None:
            return 0
        print(json.dumps(output))
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import telemetry

        agent_type = str(payload["tool_input"].get("subagent_type") or "general-purpose")
        telemetry.append("Shim_Events", {"shim": SHIM_ID, "agent": "claude", "action": "deny",
                                         "subagent_type": agent_type[:60]})
    except Exception:  # noqa: BLE001 — a hook must never break the tool call it guards.
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
