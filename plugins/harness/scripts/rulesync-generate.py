#!/usr/bin/env python3
"""Generate every agent tool's instructions, MCP servers, hooks, skills, subagents,
and commands from the agents repository's rulesync source. Called by harness:sync.

  rulesync-generate.py [--dry-run] [--update] <agents-repo>

Runs only when <repo>/rulesync.jsonc exists; prints RULESYNC_STATE=skipped otherwise.
Steps, all inside the repo:
  1. `rulesync install` when the config declares `sources` (third-party skills,
     pinned by rulesync.lock) and the config, lockfile, or installed skills changed
     since this machine's last install. It runs from a private root (see install())
     and reuses the `gh` login token. `"delete": true` is refused.
  2. Build a temporary input root: .rulesync/ plus this machine's untracked
     .rulesync.local/mcp.jsonc servers and hooks.jsonc entries merged in. rulesync
     overlays replace whole files, so the merge happens here to keep machine-only
     servers and hooks (absolute paths, app-bundled tools) per machine.
  3. Remove the outputs of skills this machine generated last time that are no longer
     in the source, using rulesync's own `--delete` dry run and nothing else it lists
     (it also lists folders other installers own, such as ~/.claude/skills/synced).
  4. `rulesync generate --global`.
Prints one RULESYNC_STATE line, then one RULESYNC_UPDATES line: whether a newer
rulesync or newer commits for locked skill sources exist (checked at most once a day,
read-only). `--update` re-resolves every source to its latest commit and rewrites
rulesync.lock (sync commits it). Exit 0 unless rulesync is missing or a command failed.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

RULESYNC = os.environ.get("HARNESS_RULESYNC", "rulesync@40.2.0")
DELETE_LINE = re.compile(r'Would delete directory: "([^"]+)"')
WRITE_LINE = re.compile(r"Would write: (.+?)\s*$", re.M)
HERE = Path(__file__).resolve().parent
# What `rulesync install` reads and writes, carried through its private root.
INSTALL_LOCKS = ("rulesync.lock", "rulesync-npm.lock.json")
INSTALL_FILES = ("rulesync.jsonc", "rulesync.local.jsonc", *INSTALL_LOCKS)
INSTALL_FOLDERS = (".rulesync/skills/.curated", ".rulesync/rules/.curated")
# rulesync's error when it creates a folder through a symlink whose target is gone.
CONTENT_FOLDERS = {"skills", "agents", "commands", "rules", "prompts", "subagents"}
MKDIR_ENOENT = re.compile(r"ENOENT: no such file or directory, mkdir '([^']+)'")


def without_timestamps(text: str) -> object:
    """A lockfile's content minus resolvedAt, which every fresh install rewrites."""
    def strip(value: object) -> object:
        if isinstance(value, dict):
            return {k: strip(v) for k, v in value.items() if k != "resolvedAt"}
        if isinstance(value, list):
            return [strip(v) for v in value]
        return value
    try:
        return strip(json.loads(text))
    except ValueError:
        return text


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


def merge_hooks(shared: dict, local: dict) -> dict:
    """Local hook entries are appended per event, shared and per tool."""
    merged = json.loads(json.dumps(shared))
    merged.setdefault("hooks", {})  # rulesync requires the shared map, even when empty

    def extend(target: dict, events: dict) -> None:
        for event, entries in events.items():
            if isinstance(entries, list):
                target.setdefault(event, []).extend(entries)

    for key, value in local.items():
        if key == "hooks" and isinstance(value, dict):
            extend(merged.setdefault("hooks", {}), value)
        elif isinstance(value, dict) and isinstance(value.get("hooks"), dict):
            extend(merged.setdefault(key, {}).setdefault("hooks", {}), value["hooks"])
        elif key not in merged:
            merged[key] = value
    return merged


def claude_settings_in_repo(repo: Path) -> bool:
    """Harness links ~/.claude/settings.json into the repo, so rulesync's Claude hooks
    land in a tracked file there."""
    settings = Path.home() / ".claude" / "settings.json"
    try:
        settings.resolve().relative_to(repo.resolve())
    except ValueError:
        return False
    return settings.is_symlink()


def local_claude_hooks(repo: Path) -> bool:
    local = repo / ".rulesync.local" / "hooks.jsonc"
    if not local.is_file():
        return False
    data = load_jsonc(local)
    return bool(data.get("hooks")) or bool((data.get("claudecode") or {}).get("hooks"))


def build_input_root(repo: Path, parent: Path) -> Path:
    """Copy .rulesync into parent and merge this machine's .rulesync.local overlay into it."""
    root = parent / ".rulesync"
    if (repo / ".rulesync").is_dir():
        shutil.copytree(repo / ".rulesync", root, symlinks=False)
    else:
        root.mkdir()
    for name, merge, empty in (("mcp.jsonc", merge_mcp, {"mcpServers": {}}), ("hooks.jsonc", merge_hooks, {"version": 1, "hooks": {}})):
        local = repo / ".rulesync.local" / name
        if local.is_file():
            shared_path = root / name
            shared = load_jsonc(shared_path) if shared_path.is_file() else empty
            shared_path.write_text(json.dumps(merge(shared, load_jsonc(local)), indent=2) + "\n")
    return root


def backup_first_run(repo: Path, root: Path) -> bool:
    """Before this repo's first generate on this machine, copy every live file it will write.

    Returns False when rulesync could not list those files: the first generate must not
    run without its backup."""
    listing = rulesync(repo, "generate", "--global", "--input-roots", str(root), "--dry-run")
    if listing.returncode:
        print(f"RULESYNC_BACKUP=failed: {last_line(listing)}")
        return False
    home = Path.home().resolve()
    backup = state_dir() / "backups" / f"rulesync-{time.strftime('%Y%m%d-%H%M%S')}"
    os.makedirs(backup.parent, mode=0o700, exist_ok=True)
    os.chmod(backup.parent, 0o700)
    os.makedirs(backup, mode=0o700, exist_ok=True)  # private before any copy lands
    copied = 0
    for raw in WRITE_LINE.findall(listing.stdout + listing.stderr):
        path = Path(raw.strip().strip('"')).expanduser()
        try:
            rel = path.resolve().relative_to(home)
        except ValueError:
            continue
        if path.is_file():
            target = backup / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
            copied += 1
    if not copied:
        backup.rmdir()
    print(f"RULESYNC_BACKUP={copied} live file(s) copied to {backup}" if copied else "RULESYNC_BACKUP=nothing to back up")
    return True


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state")
    return Path(base) / "studio-moser/harness"


def state_file(repo: Path) -> Path:
    """Per repo, so a second checkout never compares against another repo's history."""
    key = hashlib.sha256(str(repo).encode()).hexdigest()[:12]
    return state_dir() / f"rulesync-skills-{key}.json"


def source_skills(root: Path) -> set[str]:
    skills = root / "skills"
    names = {p.name for p in skills.iterdir() if p.is_dir() and not p.name.startswith(".")} if skills.is_dir() else set()
    curated = skills / ".curated"
    if curated.is_dir():
        names |= {p.name for p in curated.iterdir() if p.is_dir()}
    return names


def install_state_file(repo: Path) -> Path:
    return state_file(repo).with_name(state_file(repo).name.replace("skills", "install"))


def install_fingerprint(repo: Path) -> str:
    """Config plus lockfile: an unchanged pair needs no new fetch."""
    digest = hashlib.sha256()
    for name in ("rulesync.jsonc", "rulesync.lock"):
        path = repo / name
        digest.update(path.read_bytes() if path.is_file() else b"-")
    return digest.hexdigest()


def locked_skills(repo: Path) -> set[str]:
    lock = repo / "rulesync.lock"
    if not lock.is_file():
        return set()
    try:
        sources = json.loads(lock.read_text()).get("sources", {})
    except ValueError:
        return set()
    return {name for entry in sources.values() if isinstance(entry, dict) for name in entry.get("skills", {})}


def declared_skills(config: dict) -> set[str]:
    return {name for source in config.get("sources") or [] if isinstance(source, dict)
            for name in source.get("skills") or [] if isinstance(name, str) and name != "*"}


def install(repo: Path, update: bool = False, extra: tuple[str, ...] = ()) -> subprocess.CompletedProcess:
    """Run `rulesync install` from a private root, then copy its results back.

    rulesync treats every folder in <cwd>/skills as the user's own skill and refuses to
    install over it. In global mode that folder is ~/.agents/skills, where rulesync's
    own Codex output lands, so installing from the repo would skip every declared skill
    after the first generate. A private root has no skills/ folder.
    """
    with tempfile.TemporaryDirectory(prefix="harness-rulesync-install.") as temp:
        root = Path(temp)
        for name in INSTALL_FILES:
            if (repo / name).is_file():
                shutil.copy2(repo / name, root / name)
        for folder in INSTALL_FOLDERS:
            if (repo / folder).is_dir():
                shutil.copytree(repo / folder, root / folder, symlinks=True)
        result = rulesync(root, "install", *(["--update"] if update else []), *extra)
        if result.returncode == 0 and not extra:
            for folder in INSTALL_FOLDERS:
                if (repo / folder).exists():
                    shutil.rmtree(repo / folder)
                if (root / folder).is_dir():
                    (repo / folder).parent.mkdir(parents=True, exist_ok=True)
                    shutil.copytree(root / folder, repo / folder, symlinks=True)
            for name in INSTALL_LOCKS:
                if not (root / name).is_file():
                    continue
                new = (root / name).read_text(encoding="utf-8")
                old = (repo / name).read_text(encoding="utf-8") if (repo / name).is_file() else None
                # Same pins with fresh timestamps is not a change worth committing.
                if old is None or without_timestamps(new) != without_timestamps(old):
                    shutil.copy2(root / name, repo / name)
        return result


def install_needed(repo: Path) -> bool:
    state = install_state_file(repo)
    if not state.is_file() or state.read_text().strip() != install_fingerprint(repo):
        return True
    curated = repo / ".rulesync" / "skills" / ".curated"
    return any(not (curated / name).is_dir() for name in locked_skills(repo))


def github_token() -> str | None:
    # Anonymous GitHub API calls are rate limited to 60 an hour; reuse the gh login.
    if os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or not shutil.which("gh"):
        return None
    result = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


UPDATE_LINE = re.compile(r"^(?!up to date)(\S[^\n]*?)\s{2,}(\S+) \(", re.M)
CHECK_EVERY = 24 * 3600


def latest_rulesync() -> str | None:
    try:
        result = subprocess.run(["npm", "view", "rulesync", "version"], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def check_updates(repo: Path, settings: dict) -> str:
    """Read-only: is a newer rulesync or a newer locked skill commit available?"""
    cache = state_file(repo).with_name(state_file(repo).name.replace("skills", "updates"))
    if cache.is_file() and os.environ.get("HARNESS_UPDATE_CHECK") != "always":
        try:
            cached = json.loads(cache.read_text())
            if time.time() - cached["checked"] < CHECK_EVERY and cached.get("fingerprint") == install_fingerprint(repo):
                return cached["result"]
        except (ValueError, KeyError, TypeError):
            pass
    notes = []
    pinned = RULESYNC.rpartition("@")[2]
    latest = latest_rulesync()
    if latest is None:
        notes.append("rulesync latest version unknown")
    elif latest != pinned:
        notes.append(f"rulesync {pinned} -> {latest} (bump the Harness pin after scripts/rulesync-rehearse.py {latest})")
    if settings.get("sources"):
        outdated = install(repo, extra=("--outdated",))
        behind = [source for status, source in UPDATE_LINE.findall(outdated.stdout + outdated.stderr)]
        if outdated.returncode == 2:
            notes.append("a skill source could not be resolved")
        elif outdated.returncode == 1 or behind:
            notes.append(f"{len(behind)} skill source(s) behind: {', '.join(behind)} (run /harness:sync --update-skills)")
    result = "; ".join(notes) or "none"
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps({"checked": time.time(), "fingerprint": install_fingerprint(repo), "result": result}) + "\n")
    return result


def rulesync(repo: Path, *args: str) -> subprocess.CompletedProcess:
    # rulesync reads HOME_DIR before HOME; pin it so a stray export cannot redirect writes.
    env = dict(os.environ, HOME_DIR=str(Path.home()), npm_config_yes="true")
    if args and args[0] == "install":
        token = github_token()
        if token:
            env["GITHUB_TOKEN"] = token
    return subprocess.run(["npx", "-y", RULESYNC, *args], cwd=repo, text=True, capture_output=True, env=env)


def move_broken_links(output: str) -> str | None:
    """rulesync cannot create a skill folder through a broken symlink. Move every broken
    link out of that folder's parent (they point at nothing) into a backup; None when
    the failure is something else."""
    match = MKDIR_ENOENT.search(output)
    if not match:
        return None
    blocked = Path(match.group(1))
    home = Path.home().resolve()
    link = next((p for p in (blocked, *blocked.parents) if p.is_symlink() and not p.exists()), None)
    if link is None or home not in link.parent.resolve().parents:
        return None
    parent = link.parent
    backup = state_dir() / "backups" / f"broken-links-{time.strftime('%Y%m%d-%H%M%S')}" / parent.resolve().relative_to(home)
    backup.mkdir(parents=True, exist_ok=True)
    broken = [link]
    if parent.name in CONTENT_FOLDERS:
        # Siblings left by the same deleted folder (an old profile's skills) go too; never
        # in a tool root, where a link like settings.json may only point at an unmounted volume.
        origin = Path(os.readlink(link).rstrip("/")).parent
        broken += [p for p in parent.iterdir() if p != link and p.is_symlink() and not p.exists()
                   and Path(os.readlink(p).rstrip("/")).parent == origin]
    for path in broken:
        shutil.move(str(path), str(backup / path.name))
    return f"moved {len(broken)} broken link(s) from {parent} to {backup}"


def last_line(result: subprocess.CompletedProcess) -> str:
    lines = (result.stderr or result.stdout).strip().splitlines()
    return lines[-1] if lines else f"exit {result.returncode}"


def main(argv: list[str]) -> int:
    dry_run = "--dry-run" in argv
    update = "--update" in argv and not dry_run
    args = [a for a in argv if a not in ("--dry-run", "--update")]
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
        settings = load_jsonc(config)
    except ValueError as error:
        print(f"RULESYNC_STATE=failed: rulesync.jsonc unreadable ({error})")
        return 1
    local_config = repo / "rulesync.local.jsonc"
    try:
        local_settings = load_jsonc(local_config) if local_config.is_file() else {}
    except ValueError as error:
        print(f"RULESYNC_STATE=failed: rulesync.local.jsonc unreadable ({error})")
        return 1
    if settings.get("delete") is True or local_settings.get("delete") is True:
        # Its sweep removes every skill folder rulesync did not generate this run,
        # including other installers' folders such as ~/.claude/skills/synced.
        print('RULESYNC_STATE=failed: set "delete": false in rulesync.jsonc and rulesync.local.jsonc; Harness removes dropped skills itself')
        return 1
    try:
        return generate(repo, settings, dry_run, update)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"RULESYNC_STATE=failed: {type(error).__name__}: {error}")
        return 1


def generate(repo: Path, settings: dict, dry_run: bool, update: bool = False) -> int:
    declared_sources = bool(settings.get("sources"))

    if declared_sources and not dry_run and (update or install_needed(repo)):
        installed = install(repo, update=update)
        if installed.returncode:
            print(f"RULESYNC_STATE=failed: install: {last_line(installed)}")
            return 1
        install_state_file(repo).parent.mkdir(parents=True, exist_ok=True)
        install_state_file(repo).write_text(install_fingerprint(repo) + "\n")

    if not dry_run and not (repo / ".rulesync.local").exists():
        # First managed sync on this machine: keep what the shared source lacks.
        capture = subprocess.run([sys.executable, str(HERE / "rulesync-bootstrap.py"), "--machine", str(repo)],
                                 capture_output=True, text=True)
        line = next((l for l in capture.stdout.splitlines() if l.startswith("RULESYNC_CAPTURE=")), "")
        if capture.returncode:
            print(f"RULESYNC_STATE=failed: machine capture: {line.partition('=')[2] or capture.stderr.strip()[-200:]}")
            return 1
        print(line)
    elif not dry_run:
        # Keep app-installed servers as their apps last wrote them. Never fails the sync:
        # if the tool cannot be read, the overlay keeps its last copy.
        apps = subprocess.run([sys.executable, str(HERE / "rulesync-bootstrap.py"), "--apps", str(repo)],
                              capture_output=True, text=True)
        note = next((l for l in apps.stdout.splitlines() if l.startswith(("RULESYNC_APPS=refreshed", "RULESYNC_APPS=failed"))), "")
        if note:
            print(note)

    if local_claude_hooks(repo) and claude_settings_in_repo(repo):
        # A machine-only Claude hook would be committed in claude/settings.json and
        # overwritten by every other machine's sync.
        print("RULESYNC_STATE=failed: .rulesync.local/hooks.jsonc has Claude hooks, but ~/.claude/settings.json "
              "is shared through the repo; move them to .rulesync/hooks.jsonc or remove them")
        return 1

    with tempfile.TemporaryDirectory(prefix="harness-rulesync.") as temp:
        root = build_input_root(repo, Path(temp))

        # A declared skill is never "removed", even if this run failed to fetch it.
        current = source_skills(root) | declared_skills(settings)
        state = state_file(repo)
        previous = set(json.loads(state.read_text())) if state.is_file() else set()
        removed = previous - current
        cleaned = 0
        if removed and not dry_run:
            listing = rulesync(repo, "generate", "--global", "--input-roots", str(root), "--dry-run", "--delete")
            home = Path.home().resolve()
            for match in DELETE_LINE.finditer(listing.stdout + listing.stderr):
                path = Path(match.group(1)).expanduser()
                if path.is_symlink() or path.name not in removed:
                    continue
                if home in path.resolve().parents and path.is_dir():
                    shutil.rmtree(path)
                    cleaned += 1

        if not dry_run and not state.is_file() and not backup_first_run(repo, root):
            print("RULESYNC_STATE=failed: could not list the files to back up before the first generate")
            return 1
        generate_args = ["generate", "--global", "--input-roots", str(root)] + (["--dry-run"] if dry_run else [])
        generated = rulesync(repo, *generate_args)
        # ponytail: one broken link (with its siblings) per retry, ten at most; more means
        # something else is wrong, and the failure is reported.
        for _attempt in range(10):
            moved = None if dry_run or not generated.returncode else move_broken_links(generated.stdout + generated.stderr)
            if moved is None:
                break
            print(f"RULESYNC_LINKS={moved}")
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
    print(f"RULESYNC_UPDATES={check_updates(repo, settings)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
