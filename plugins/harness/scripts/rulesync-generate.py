#!/usr/bin/env python3
"""Generate every agent tool's instructions, MCP servers, hooks, skills, subagents,
and commands from the agents repository's rulesync source. Called by harness:sync.

  rulesync-generate.py [--dry-run] <agents-repo>

Runs only when <repo>/rulesync.jsonc exists; prints RULESYNC_STATE=skipped otherwise.
Steps, all inside the repo:
  1. `rulesync install` when the config declares `sources` (third-party skills,
     pinned by rulesync.lock).
  2. Build a temporary input root: .rulesync/ plus this machine's untracked
     .rulesync.local/mcp.jsonc servers merged in. rulesync overlays replace whole
     files, so the merge happens here to keep machine-only servers per machine.
  3. Remove the outputs of skills this machine generated last time that are no longer
     in the source, using rulesync's own `--delete` dry run and nothing else it lists
     (it also lists folders other installers own, such as ~/.claude/skills/synced).
  4. `rulesync generate --global`.
Prints one RULESYNC_STATE line. Exit 0 unless rulesync is missing or a command failed.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

RULESYNC = os.environ.get("HARNESS_RULESYNC", "rulesync@39.0.0")
DELETE_LINE = re.compile(r'Would delete directory: "([^"]+)"')


def strip_jsonc(text: str) -> str:
    """Remove // and /* */ comments outside strings, then trailing commas."""
    out, i, quote = [], 0, False
    while i < len(text):
        char = text[i]
        if quote:
            out.append(char)
            if char == "\\" and i + 1 < len(text):
                out.append(text[i + 1])
                i += 1
            elif char == '"':
                quote = False
        elif char == '"':
            quote = True
            out.append(char)
        elif text.startswith("//", i):
            i = text.find("\n", i)
            if i < 0:
                break
            continue
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
            continue
        else:
            out.append(char)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def load_jsonc(path: Path) -> dict:
    data = json.loads(strip_jsonc(path.read_text(encoding="utf-8")))
    if not isinstance(data, dict):
        raise ValueError(f"{path} must hold a JSON object")
    return data


def merge_mcp(shared: dict, local: dict) -> dict:
    """Local servers join the shared map; tool-scoped blocks merge per tool."""
    merged = json.loads(json.dumps(shared))
    for key, value in local.items():
        if key == "mcpServers" or isinstance(value, dict) and isinstance(value.get("mcpServers"), dict):
            servers = value if key == "mcpServers" else value["mcpServers"]
            target = merged.setdefault(key, {}) if key == "mcpServers" else merged.setdefault(key, {}).setdefault("mcpServers", {})
            target.update(servers)
    return merged


def state_file() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state")
    return Path(base) / "studio-moser/harness/rulesync-skills.json"


def source_skills(root: Path) -> set[str]:
    skills = root / "skills"
    names = {p.name for p in skills.iterdir() if p.is_dir() and not p.name.startswith(".")} if skills.is_dir() else set()
    curated = skills / ".curated"
    if curated.is_dir():
        names |= {p.name for p in curated.iterdir() if p.is_dir()}
    return names


def rulesync(repo: Path, *args: str) -> subprocess.CompletedProcess:
    env = dict(os.environ, npm_config_yes="true")
    return subprocess.run(["npx", "-y", RULESYNC, *args], cwd=repo, text=True, capture_output=True, env=env)


def last_line(result: subprocess.CompletedProcess) -> str:
    lines = (result.stderr or result.stdout).strip().splitlines()
    return lines[-1] if lines else f"exit {result.returncode}"


def main(argv: list[str]) -> int:
    dry_run = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    repo = Path(args[0]).expanduser().resolve()
    config = repo / "rulesync.jsonc"
    if not config.is_file():
        print("RULESYNC_STATE=skipped: no rulesync.jsonc")
        return 0
    if not shutil.which("npx"):
        print("RULESYNC_STATE=failed: npx not on PATH")
        return 1
    try:
        declared_sources = bool(load_jsonc(config).get("sources"))
    except ValueError as error:
        print(f"RULESYNC_STATE=failed: rulesync.jsonc unreadable ({error})")
        return 1

    if declared_sources and not dry_run:
        installed = rulesync(repo, "install")
        if installed.returncode:
            print(f"RULESYNC_STATE=failed: install: {last_line(installed)}")
            return 1

    with tempfile.TemporaryDirectory(prefix="harness-rulesync.") as temp:
        root = Path(temp) / ".rulesync"
        if (repo / ".rulesync").is_dir():
            shutil.copytree(repo / ".rulesync", root, symlinks=False)
        else:
            root.mkdir()
        local_mcp = repo / ".rulesync.local" / "mcp.jsonc"
        if local_mcp.is_file():
            shared_path = root / "mcp.jsonc"
            shared = load_jsonc(shared_path) if shared_path.is_file() else {"mcpServers": {}}
            shared_path.write_text(json.dumps(merge_mcp(shared, load_jsonc(local_mcp)), indent=2) + "\n")

        current = source_skills(root)
        state = state_file()
        previous = set(json.loads(state.read_text())) if state.is_file() else set()
        removed = previous - current
        cleaned = 0
        if removed and not dry_run:
            listing = rulesync(repo, "generate", "--global", "--input-roots", str(root), "--dry-run", "--delete")
            home = Path.home().resolve()
            for match in DELETE_LINE.finditer(listing.stdout + listing.stderr):
                path = Path(match.group(1)).expanduser()
                if path.name in removed and home in path.resolve().parents and path.is_dir():
                    shutil.rmtree(path)
                    cleaned += 1

        generate_args = ["generate", "--global", "--input-roots", str(root)] + (["--dry-run"] if dry_run else [])
        generated = rulesync(repo, *generate_args)
        if generated.returncode:
            print(f"RULESYNC_STATE=failed: generate: {last_line(generated)}")
            return 1
        written = re.search(r"Written (\d+) file\(s\) total", generated.stdout)
        if not dry_run:
            state.parent.mkdir(parents=True, exist_ok=True)
            state.write_text(json.dumps(sorted(current)) + "\n")

    detail = "dry run" if dry_run else f"{written.group(1) if written else 0} file(s) written"
    print(f"RULESYNC_STATE=generated: {detail}; {len(current)} skill(s); {cleaned} stale skill folder(s) removed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
