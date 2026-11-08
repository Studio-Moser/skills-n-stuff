#!/usr/bin/env python3
"""Claude Code and Codex PreToolUse hook: stop zsh "no matches found" failures.

zsh aborts a command when an unquoted glob matches nothing (`grep --include=*.md`,
`curl https://x?y=1`); bash passes the word through. When the user's shell is zsh
and an unquoted glob would match nothing, log one Shim_Events firing and:

- in Claude Code `auto` or `bypassPermissions` mode, rewrite the command with a
  `setopt no_nomatch;` prefix through `updatedInput`. Globs that match keep
  expanding exactly as before, and the rewritten command still goes through the
  normal permission flow;
- otherwise, deny the call with the reason, so the model quotes the glob and
  retries. In Claude Code's other modes, permission rules match the command the hook
  returns, so a rewrite would stop matching the user's allowlist (`Bash(echo:*)`)
  and add prompts. Codex applies `updatedInput` only together with an `allow`
  decision, which would skip its approval policy, so Codex always gets the denial.

Both tools read this plugin's hooks/hooks.json; Codex sets CLAUDE_PLUGIN_ROOT for
plugin hooks and identifies itself with a `turn_id` in the payload. The hook never
returns `allow`. Any error exits 0 with no output, which leaves the call untouched.
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
# zsh does not filename-generate a scalar assignment (`x=*.md`) without GLOB_ASSIGN:
# before the command word, or as an argument of a declaring builtin.
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=")
DECLARING = {"export", "local", "typeset", "declare", "readonly", "integer", "float"}
SEP = "\0"  # marks a command boundary (; & | ( ) newline) in the word list


class Uncertain(Exception):
    """The command uses syntax this tokenizer does not follow; make no decision."""


def unquoted_words(command: str) -> list[tuple[str, bool]]:
    """Split into shell words; each carries whether it has an unquoted glob character.

    Skips comments, heredoc bodies, `$((...))`, `((...))`, and `[[ ... ]]` conditions,
    where zsh does not filename-generate; `${...}` and `$?` stay in the word as text. Raises Uncertain for
    a command substitution inside double quotes, whose nested quoting it cannot track.
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
            if quote == '"' and (char == "`" or command.startswith("$(", i)):
                raise Uncertain
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
        if not word and command.startswith("((", i):
            end = command.find("))", i)
            i = n if end < 0 else end + 2
            continue
        if char == "$" and command.startswith("${", i):
            # Kept as text so the caller sees a variable, not the bare path around it.
            end = command.find("}", i)
            word.append(command[i:] if end < 0 else command[i : end + 1])
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
            words.append((SEP, False))
            i += 1
            while heredocs:
                delimiter = heredocs.pop(0)
                body = re.compile(rf"^\t*{re.escape(delimiter)}[ \t]*$", re.M).search(command, i)
                i = n if body is None else body.end()
            continue
        if char.isspace() or char in ";&|()<>":
            finish()
            if char in ";&|()":
                words.append((SEP, False))
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


def expand(word: str, cwd: str) -> str:
    """Substitute the two variables whose values the hook knows; any other `$` stays."""
    home = os.path.expanduser("~")
    for name, value in (("HOME", home), ("PWD", cwd)):
        word = word.replace("${" + name + "}", value)
        word = re.sub(rf"\${name}(?![A-Za-z0-9_])", lambda _match: value, word)
    return os.path.expanduser(word)


def unmatched_globs(command: str, cwd: str) -> list[str]:
    try:
        words = unquoted_words(command)
    except Uncertain:
        return []
    misses = []
    # The directory later words run in; None once it can no longer be known. A subshell
    # `( cd x ... )` restores the directory where the word list cannot see it.
    base: str | None = cwd
    at_start, declaring = True, False
    for index, (word, globbed) in enumerate(words):
        if word == SEP:
            at_start, declaring = True, False
            continue
        # A case pattern (`*.md)`) is matched against a string, never against files.
        if at_start and word == "case":
            return []
        command_word = at_start
        assignment = bool(ASSIGNMENT.match(word)) and (at_start or declaring)
        if at_start and not assignment:
            at_start, declaring = False, word in DECLARING
        if word in ("cd", "pushd", "popd"):
            following = words[index + 1][0] if index + 1 < len(words) else SEP
            known = command_word and word != "popd" and following != SEP
            target = expand(following, base or cwd) if known else ""
            if "(" in command or base is None or not target or "$" in target or target.startswith("-"):
                base = None if not (target and os.path.isabs(target) and "(" not in command) else target
            else:
                base = os.path.normpath(os.path.join(base, target))
            if base is not None and not os.path.isdir(base):
                base = None
        if not globbed or "`" in word or assignment:
            continue
        pattern = expand(word, base or cwd)
        if "$" in pattern:
            continue
        # shortcut: recursive globs are skipped to keep the hook fast in large trees.
        if "**" in word:
            continue
        # Once the directory is unknown, only absolute patterns and options (which never
        # name files) are checked.
        if base is None and not os.path.isabs(pattern) and not word.startswith("-"):
            continue
        if not os.path.isabs(pattern):
            pattern = os.path.join(base or cwd, pattern)
        if not glob.glob(pattern):
            misses.append(word)
    return misses


def redacted(word: str) -> str:
    """A loggable shape only: letters and digits collapse, so no value reaches telemetry."""
    if "://" in word:
        return "<url>"
    return re.sub(r"[A-Za-z0-9_]+", "a", word)[:60]


def agent_of(payload: dict) -> str:
    # Codex PreToolUse payloads carry turn_id; Claude Code's do not.
    return "codex" if "turn_id" in payload else "claude"


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
    if agent_of(payload) == "claude" and payload.get("permission_mode") in REWRITE_MODES:
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
        # Claude Code runs commands in CLAUDE_CODE_SHELL when it is set.
        shell = os.environ.get("CLAUDE_CODE_SHELL") or os.environ.get("SHELL", "")
        output, misses = decide(payload, shell)
        if output is None:
            return 0
        print(json.dumps(output))
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import telemetry

        action = "rewrite" if "updatedInput" in output["hookSpecificOutput"] else "deny"
        telemetry.append(
            "Shim_Events",
            {"shim": SHIM_ID, "agent": agent_of(payload), "action": action,
             "patterns": [redacted(word) for word in misses[:MAX_LOGGED]]},
        )
    except Exception:  # noqa: BLE001 — a hook must never break the tool call it guards.
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
