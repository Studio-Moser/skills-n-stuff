#!/usr/bin/env python3
"""Rehearse a rulesync upgrade against this machine's real agent config. READ-ONLY
for live files: everything is written under a temporary HOME and then deleted.

  rulesync-rehearse.py <candidate-version> [agents-repo]

Generates the repo's source (with this machine's .rulesync.local overlay) twice, with
the pinned rulesync and with the candidate, each into its own temporary HOME seeded
with copies of the live files either version writes. Prints every file whose result
differs, with a unified diff, then REHEARSAL=identical (exit 0) or
REHEARSAL=<n> file(s) differ (exit 1). Bump the pin in rulesync-generate.py only
after reviewing the differences.
"""

from __future__ import annotations

import difflib
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("rulesync_generate", HERE / "rulesync-generate.py")
generate_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generate_module)

WRITE_LINE = re.compile(r"Would write: (.+?)\s*$", re.M)
MAX_DIFF_LINES = 400


def rulesync(version: str, repo: Path, home: Path, root: Path, *extra: str) -> subprocess.CompletedProcess:
    env = dict(os.environ, HOME=str(home), HOME_DIR=str(home), npm_config_yes="true")
    command = ["npx", "-y", f"rulesync@{version}", "generate", "--global", "--input-roots", str(root), *extra]
    return subprocess.run(command, cwd=repo, env=env, text=True, capture_output=True)


def planned_paths(version: str, repo: Path, home: Path, root: Path) -> set[str]:
    """Paths (relative to HOME) this version writes, from its own dry run into an empty HOME."""
    result = rulesync(version, repo, home, root, "--dry-run")
    if result.returncode:
        raise RuntimeError(f"rulesync@{version} dry run failed: {(result.stderr or result.stdout).strip()[-300:]}")
    paths = set()
    for raw in WRITE_LINE.findall(result.stdout + result.stderr):
        path = raw.strip().strip('"')
        path = str(home) + path[1:] if path.startswith("~/") else path
        try:
            paths.add(str(Path(path).resolve().relative_to(home.resolve())))
        except ValueError:
            continue
    return paths


def read(path: Path) -> list[str] | None:
    try:
        return path.read_text(encoding="utf-8").splitlines(keepends=True)
    except (OSError, UnicodeDecodeError):
        return None


def main(argv: list[str]) -> int:
    if not argv or len(argv) > 2:
        print(__doc__, file=sys.stderr)
        return 2
    candidate = argv[0].removeprefix("rulesync@")
    repo = Path(argv[1] if len(argv) == 2 else os.environ.get("AGENTS_REPO", Path.home() / ".agents")).expanduser().resolve()
    if not (repo / "rulesync.jsonc").is_file():
        print(f"REHEARSAL=skipped: {repo} has no rulesync.jsonc")
        return 2
    pinned = generate_module.RULESYNC.rpartition("@")[2]
    live_home = Path.home()
    with tempfile.TemporaryDirectory(prefix="harness-rehearse.") as temp:
        temp_path = Path(temp)
        os.chmod(temp_path, 0o700)  # seeded with copies of live config
        root = generate_module.build_input_root(repo, temp_path / "source")
        homes = {label: temp_path / label for label in ("pinned", "candidate")}
        versions = {"pinned": pinned, "candidate": candidate}
        paths: set[str] = set()
        for label, home in homes.items():
            empty = temp_path / f"empty-{label}"
            empty.mkdir()
            paths |= planned_paths(versions[label], repo, empty, root)
        for home in homes.values():
            for rel in sorted(paths):
                live = live_home / rel
                if live.is_file():
                    target = home / rel
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(live, target)  # follows links, like the tools do
        for label, home in homes.items():
            result = rulesync(versions[label], repo, home, root)
            if result.returncode:
                print(f"REHEARSAL=failed: rulesync@{versions[label]} generate: {(result.stderr or result.stdout).strip()[-300:]}")
                return 1
        different = []
        budget = MAX_DIFF_LINES
        for rel in sorted(paths):
            old, new = read(homes["pinned"] / rel), read(homes["candidate"] / rel)
            if old == new:
                continue
            different.append(rel)
            print(f"differs: ~/{rel}")
            if old is None or new is None:
                print(f"  (only {'candidate' if old is None else 'pinned'} wrote it, or it is not text)")
                continue
            for line in difflib.unified_diff(old, new, f"rulesync@{pinned}/~/{rel}", f"rulesync@{candidate}/~/{rel}"):
                if budget <= 0:
                    break
                sys.stdout.write(line if line.endswith("\n") else line + "\n")
                budget -= 1
    print(f"{len(paths)} file(s) compared between rulesync@{pinned} and rulesync@{candidate}")
    if different:
        print(f"REHEARSAL={len(different)} file(s) differ")
        return 1
    print("REHEARSAL=identical")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
