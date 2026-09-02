#!/usr/bin/env python3
"""Preload the Harness execute procedure for explicit contract prompts."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def _is_explicit_execute(prompt: object) -> bool:
    if not isinstance(prompt, str):
        return False
    normalized = " ".join(prompt.lower().split())
    padded = f" {normalized} "
    request_marker = any(
        marker in normalized
        for marker in ("harnessrequest", "harness request", "routing_request")
    )
    result_marker = "harnessresult" in normalized or "harness result" in normalized
    action_marker = any(
        marker in padded
        for marker in (
            " complete ",
            " construct ",
            " execute ",
            " produce ",
            " requires ",
            " return ",
            " write ",
        )
    )
    return (request_marker or result_marker) and action_marker


def _activation_context(skill: str) -> str:
    adapter_marker = "### Internal Codex adapter"
    verification_marker = "## Verify and return"
    before_adapter, remainder = skill.split(adapter_marker, 1)
    _, verification = remainder.split(verification_marker, 1)
    return (
        "Detected environment state: this is an explicit Harness execute contract. "
        "/harness:execute is already loaded for this turn; invoking the Skill tool "
        "again would duplicate context. The installed procedure below governs the "
        "task before any other task action.\n\n"
        f"{before_adapter}"
        f"{adapter_marker}\n\n"
        "The non-native Codex adapter details are intentionally not preloaded. That "
        "path requires loading the full /harness:execute skill before dispatch.\n\n"
        f"{verification_marker}{verification}"
    )


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return 0
    if not isinstance(event, dict):
        return 0
    if event.get("hook_event_name") != "UserPromptSubmit" or not _is_explicit_execute(
        event.get("prompt")
    ):
        return 0

    skill_path = Path(__file__).resolve().parents[1] / "skills" / "execute" / "SKILL.md"
    context = _activation_context(skill_path.read_text())
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": context,
            }
        },
        sys.stdout,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
