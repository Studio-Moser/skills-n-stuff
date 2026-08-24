#!/usr/bin/env python3
"""Migrate shared Claude settings to the Harness control-plane plugin."""

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import sys
import tempfile


RETIRED = "machine@studio-moser"
CURRENT = "harness@studio-moser"


def load(path: Path) -> dict:
    if path.is_symlink():
        raise ValueError("refusing a symlink settings file")
    try:
        data = json.loads(path.read_text())
    except Exception as error:
        raise ValueError(f"invalid JSON ({type(error).__name__})") from error
    if not isinstance(data, dict):
        raise ValueError("top level must be an object")
    enabled = data.get("enabledPlugins", {})
    if not isinstance(enabled, dict):
        raise ValueError("enabledPlugins must be an object")
    return data


def write_atomic(path: Path, data: dict) -> None:
    mode = stat.S_IMODE(path.stat().st_mode)
    with tempfile.NamedTemporaryFile(
        "w", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as handle:
        temporary = Path(handle.name)
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    try:
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def main(argv: list[str]) -> int:
    check = bool(argv and argv[0] == "--check")
    names = argv[1:] if check else argv
    if not names:
        print(
            "usage: reconcile_shared_settings.py [--check] <settings.json> [...]",
            file=sys.stderr,
        )
        return 2

    loaded: list[tuple[Path, dict]] = []
    failures: list[str] = []
    for name in names:
        path = Path(name)
        try:
            data = load(path)
        except ValueError as error:
            failures.append(f"{path}: {error}")
            continue
        enabled = data.setdefault("enabledPlugins", {})
        if check and (RETIRED in enabled or enabled.get(CURRENT) is not True):
            failures.append(f"{path}: Harness is not the sole enabled control-plane plugin")
        loaded.append((path, data))

    if failures:
        for failure in failures:
            print(f"SETTINGS_STATE=failed: {failure}", file=sys.stderr)
        return 1
    if check:
        return 0

    for path, data in loaded:
        enabled = data.setdefault("enabledPlugins", {})
        enabled.pop(RETIRED, None)
        enabled[CURRENT] = True
        write_atomic(path, data)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
