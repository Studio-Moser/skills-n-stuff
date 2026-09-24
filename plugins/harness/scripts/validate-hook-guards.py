#!/usr/bin/env python3
"""Reject command hooks whose optional executable is not safely guarded."""

from __future__ import annotations

import json
from pathlib import Path
import re
import shlex
import sys


# Standard commands present on every supported machine; anything else is optional
# and must be guarded before it runs.
SYSTEM_COMMANDS = {":", "[", "cat", "date", "echo", "exit", "false", "mkdir", "printf", "test", "touch", "true"}
CONTROL_TOKENS = {";", "&", "&&", "|", "||"}


def command_hooks(settings: object) -> list[tuple[str, str]]:
    if not isinstance(settings, dict):
        raise ValueError("top level must be an object")
    hooks = settings.get("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("hooks must be an object")
    found: list[tuple[str, str]] = []
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            raise ValueError(f"hooks.{event} must be a list")
        for group_index, group in enumerate(groups):
            if not isinstance(group, dict) or not isinstance(group.get("hooks", []), list):
                raise ValueError(f"hooks.{event}[{group_index}] must contain a hooks list")
            for hook_index, hook in enumerate(group.get("hooks", [])):
                if not isinstance(hook, dict):
                    raise ValueError(f"hooks.{event}[{group_index}].hooks[{hook_index}] must be an object")
                if hook.get("type") != "command":
                    continue
                command = hook.get("command")
                if not isinstance(command, str) or not command.strip():
                    raise ValueError(f"hooks.{event}[{group_index}].hooks[{hook_index}].command must be a string")
                found.append((f"hooks.{event}[{group_index}].hooks[{hook_index}]", command))
    return found


_SUBSTITUTION = re.compile(r"\$\(([^()`]*)\)")


def _tokens(command: str) -> list[str] | None:
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|<>")
    lexer.whitespace_split = True
    lexer.commenters = ""
    try:
        return list(lexer)
    except ValueError:
        return None


def _chains(tokens: list[str]) -> list[list[list[str]]]:
    """Split into `;`/`&`/`|`/`||`-separated chains of `&&`-joined simple commands."""
    chains: list[list[list[str]]] = [[[]]]
    for token in tokens:
        if token == "&&":
            chains[-1].append([])
        elif token in CONTROL_TOKENS:
            chains.append([[]])
        else:
            chains[-1][-1].append(token)
    return chains


def _guard(simple: list[str]) -> str | None:
    """The program a guard command proves runnable, if it is one."""
    if len(simple) == 4 and simple[:2] == ["[", "-x"] and simple[3] == "]":
        return simple[2]
    if len(simple) == 3 and simple[:2] == ["test", "-x"]:
        return simple[2]
    if simple[:2] == ["command", "-v"] and len(simple) >= 3 and re.fullmatch(r"[A-Za-z0-9_.+-]+", simple[2]):
        return simple[2]
    return None


def guarded(command: str) -> bool:
    """Every program outside SYSTEM_COMMANDS runs only after a matching guard earlier
    in the same `&&` chain: `[ -x P ]`, `test -x P`, or `command -v NAME`."""
    if "`" in command or "\n" in command:
        return False
    substitutions = _SUBSTITUTION.findall(command)
    if any(not guarded(inner) for inner in substitutions):
        return False
    outer = _SUBSTITUTION.sub("SUBSTITUTED", command)
    if "$(" in outer:
        return False
    tokens = _tokens(outer)
    if not tokens:
        return False
    if tokens[-2:] == ["||", "true"]:
        tokens = tokens[:-2]
    for chain in _chains(tokens):
        proven: set[str] = set()
        for simple in chain:
            words = [word for word in simple if word not in {"<", ">", ">>", ">&", "2", "1"}]
            if not words:
                return False
            program = words[0]
            if program in SYSTEM_COMMANDS or program == "command":
                guard = _guard(simple)
                if guard is not None:
                    proven.add(guard)
                continue
            if program not in proven:
                return False
    return True


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: validate-hook-guards.py <settings.json>", file=sys.stderr)
        return 2
    path = Path(argv[0])
    if not path.exists():
        return 0
    try:
        settings = json.loads(path.read_text(encoding="utf-8"))
        hooks = command_hooks(settings)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"hook guard validation failed: {path}: {error}", file=sys.stderr)
        return 1
    failures = 0
    for location, command in hooks:
        if guarded(command):
            continue
        print(f"unguarded command hook: claude/settings.json {location}: {command}")
        failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
