#!/usr/bin/env python3
"""Move machine-local skill overrides out of shared Claude settings."""

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import sys
import tempfile
from typing import Any


def load_object(path: Path, *, missing_ok: bool = False) -> dict[str, Any]:
    if missing_ok and not path.exists():
        return {}
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected a JSON object")
    return value


def stage_json(path: Path, value: dict[str, Any]) -> Path:
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as handle:
        json.dump(value, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
        staged = Path(handle.name)
    os.chmod(staged, mode)
    return staged


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: localize-skill-overrides.py <shared-settings.json> <settings.local.json>",
            file=sys.stderr,
        )
        return 2

    shared_path = Path(sys.argv[1])
    local_path = Path(sys.argv[2])
    try:
        shared = load_object(shared_path)
        local = load_object(local_path, missing_ok=True)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"localize-skill-overrides: {error}", file=sys.stderr)
        return 2

    if "skillOverrides" not in shared:
        return 0

    local["skillOverrides"] = shared.pop("skillOverrides")
    shared_staged = local_staged = None
    try:
        shared_staged = stage_json(shared_path, shared)
        local_staged = stage_json(local_path, local)
        os.replace(local_staged, local_path)
        local_staged = None
        os.replace(shared_staged, shared_path)
        shared_staged = None
    except OSError as error:
        print(f"localize-skill-overrides: {error}", file=sys.stderr)
        return 2
    finally:
        for staged in (shared_staged, local_staged):
            if staged is not None:
                staged.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
