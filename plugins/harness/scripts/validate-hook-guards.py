#!/usr/bin/env python3
"""Reject command hooks whose optional executable is not safely guarded."""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys


SAFE_COMMANDS = {":", "echo", "exit", "printf", "true"}


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


def guarded(command: str) -> bool:
    first = command.lstrip().split(None, 1)[0]
    if first in SAFE_COMMANDS and "$(" not in command and "`" not in command:
        return True
    availability = re.search(r"(?:command\s+-v\s+|(?:\[|test)\s+-x\s+)", command)
    conditional = bool(re.search(r"\bif\b.*\bthen\b.*\bfi\b", command, re.DOTALL))
    return bool(availability and (conditional or ("&&" in command and "|| true" in command)))


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
