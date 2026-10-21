#!/usr/bin/env python3
"""Claude Code PreToolUse hook: stop zsh "no matches found" failures.

zsh aborts a command when an unquoted glob matches nothing (`grep --include=*.md`,
`curl https://x?y=1`); bash passes the word through. When the user's shell is zsh
and an unquoted glob would match nothing, log one Shim_Events firing and:

- in `auto` or `bypassPermissions` mode, rewrite the command with a
  `setopt no_nomatch;` prefix through `updatedInput`. Globs that match keep
  expanding exactly as before, and the rewritten command still goes through the
  normal permission flow;
- in any other mode, deny the call with the reason, so the model quotes the glob and
  retries. Permission rules match the command the hook returns, so a rewrite there
  would stop matching the user's allowlist (`Bash(echo:*)`) and add prompts.

The hook never returns `allow`. Any error exits 0 with no output, which leaves the
call untouched.
"""

from __future__ import annotations

import glob
import json
import os
from pathlib import Path
import re
import sys

SHIM_ID = "zsh-glob-guard"
PREFIX = "setopt no_nomatch; "
# Modes that do not depend on per-command allow rules, so a rewrite adds no prompts.
REWRITE_MODES = {"auto", "bypassPermissions"}
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
MAX_LOGGED = 5


def unquoted_words(command: str) -> list[tuple[str, bool]]:
    """Split into shell words; each carries whether it has an unquoted glob character.

    Skips comments, heredoc bodies, `${...}`, `$((...))`, `$?`, and `[[ ... ]]`
    conditions, where zsh does not filename-generate.
    """
    words: list[tuple[str, bool]] = []
    word, globbed, quote = [], False, ""
    heredocs: list[str] = []
    in_condition = False
    i, n = 0, len(command)

    def finish() -> None:
        nonlocal word, globbed, in_condition
        if word:
            text = "".join(word)
            if text == "[[":
                in_condition = True
            elif text == "]]":
                in_condition = False
            elif not in_condition:
                words.append((text, globbed))
        word, globbed = [], False

    while i < n:
        char = command[i]
        if quote:
            if char == "\\" and quote == '"' and i + 1 < n:
                word.append(command[i : i + 2])
                i += 2
                continue
            if char == quote:
                quote = ""
            else:
                word.append(char)
            i += 1
            continue
        if char in "'\"":
            quote = char
            i += 1
            continue
        if char == "\\" and i + 1 < n:
            word.append(command[i + 1])
            i += 2
            continue
        if char == "$" and command.startswith("$((", i):
            end = command.find("))", i)
            i = n if end < 0 else end + 2
            continue
        if char == "$" and command.startswith("${", i):
            end = command.find("}", i)
            i = n if end < 0 else end + 1
            continue
        if char == "$" and i + 1 < n and command[i + 1] in "?*#@$!-0123456789":
            word.append(command[i : i + 2])
            i += 2
            continue
        if char == "#" and not word:
            end = command.find("\n", i)
            i = n if end < 0 else end
            continue
        if char == "<" and command.startswith("<<", i) and not command.startswith("<<<", i):
            match = HEREDOC.match(command, i)
            if match:
                finish()
                heredocs.append(match.group(2))
                i = match.end()
                continue
        if char == "\n":
            finish()
            i += 1
            while heredocs:
                delimiter = heredocs.pop(0)
                body = re.compile(rf"^\t*{re.escape(delimiter)}[ \t]*$", re.M).search(command, i)
                i = n if body is None else body.end()
            continue
        if char.isspace() or char in ";&|()<>":
            finish()
            i += 1
            continue
        if char in "*?":
            globbed = True
        elif char == "[":
            # A bracket is a glob only when its word also closes it: `[ -x f ]` is not.
            end = next((k for k in range(i + 1, n) if command[k].isspace()), n)
            globbed = globbed or "]" in command[i + 1 : end]
        word.append(char)
        i += 1
    finish()
    return words


def unmatched_globs(command: str, cwd: str) -> list[str]:
    misses = []
    for word, globbed in unquoted_words(command):
        if not globbed or "$" in word or "`" in word:
            continue
        # ponytail: recursive globs are skipped to keep the hook fast in large trees.
        if "**" in word:
            continue
        # ponytail: matched against the hook's cwd; a `cd` earlier in the command
        # can change what zsh sees. Upgrade path: track leading `cd DIR &&`.
        pattern = os.path.expanduser(word)
        if not os.path.isabs(pattern):
            pattern = os.path.join(cwd, pattern)
        if not glob.glob(pattern):
            misses.append(word)
    return misses


def decide(payload: dict, shell: str) -> tuple[dict | None, list[str]]:
    if payload.get("tool_name") != "Bash" or not shell.endswith("zsh"):
        return None, []
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return None, []
    command = tool_input.get("command")
    if not isinstance(command, str) or command.lstrip().startswith("setopt no_nomatch"):
        return None, []
    if not any(char in command for char in "*?["):
        return None, []
    misses = unmatched_globs(command, str(payload.get("cwd") or os.getcwd()))
    if not misses:
        return None, []
    if payload.get("permission_mode") in REWRITE_MODES:
        updated = dict(tool_input, command=PREFIX + command)
        return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": updated}}, misses
    quoted = ", ".join(misses[:MAX_LOGGED])
    reason = (
        f"zsh would abort this command with 'no matches found' for the unquoted glob {quoted}. "
        "Quote each glob argument (for example --include='*.md') and run it again."
    )
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }, misses


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        output, misses = decide(payload, os.environ.get("SHELL", ""))
        if output is None:
            return 0
        print(json.dumps(output))
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import telemetry

        action = "rewrite" if "updatedInput" in output["hookSpecificOutput"] else "deny"
        telemetry.append("Shim_Events", {"shim": SHIM_ID, "action": action, "patterns": misses[:MAX_LOGGED]})
    except Exception:  # noqa: BLE001 — a hook must never break the tool call it guards.
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
