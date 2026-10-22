#!/usr/bin/env python3
"""Deterministic Harness usage counts from local transcripts and telemetry. READ-ONLY.

Counts only, never transcript content, so the same numbers can be compared across
models and machines. Interpretation belongs to the harness:audit playbook.

  usage-report.py [--days N | --month YYYY-MM] [--local-only]

Sections: sessions, skills (Claude Skill tool + slash commands, Codex skill
injections and SKILL.md reads), unused installed skills, commands, tool calls and
error classes, compactions, catalog regex detector hits, shim firings, delegation
results, and delegate invocations versus recorded results.

Roots: --projects (${CLAUDE_CONFIG_DIR:-~/.claude}/projects), --codex-sessions
(${CODEX_HOME:-~/.codex}/sessions), --repo (${AGENTS_REPO:-~/.agents}), --catalog
(this plugin's Component_Catalog.toml). Missing roots count as empty.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import glob
import json
import os
from pathlib import Path
import re
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, str(Path(__file__).resolve().parent))
import telemetry  # noqa: E402

COMMAND_NAME = re.compile(r"<command-name>/?([A-Za-z0-9:_.-]+)</command-name>")
CODEX_INJECTED = re.compile(r"<skill>\s*<name>([^<]+)</name>")
# Installed locations only: reading a skill's source in a repository is not using it.
SKILL_PATH = re.compile(
    r"(?:/plugins/cache/[^/\s\"']+/([^/\s\"']+)/[^/\s\"']+|/\.(?:claude|codex|agents))/skills/([A-Za-z0-9_.:-]+)/SKILL\.md"
)
NONZERO_EXIT = re.compile(r"(?:exit_code\\?\"?\s*:\s*|Process exited with code |Exit code:? )([1-9]\d*)")
ERROR_CLASSES = (
    ("zsh-nomatch", re.compile(r"no matches found")),
    ("command-not-found", re.compile(r"command not found")),
    ("permission-denied", re.compile(r"Permission denied|Operation not permitted")),
    ("user-rejected", re.compile(r"doesn.t want to proceed|user rejected|was rejected", re.I)),
    ("edit-read-order", re.compile(r"has not been read yet|modified since read")),
    ("edit-mismatch", re.compile(r"String to replace not found|Found \d+ matches")),
    ("timeout", re.compile(r"timed out|Timeout", re.I)),
)


def error_class(text: str) -> str:
    for name, pattern in ERROR_CLASSES:
        if pattern.search(text):
            return name
    return "nonzero-exit" if NONZERO_EXIT.search(text) or "Exit code" in text else "other"


def as_text(value: object) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(as_text(item) for item in value)
    if isinstance(value, dict):
        return as_text(value.get("text") or value.get("content") or value.get("output") or "")
    return ""


def parse_ts(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


class Window:
    def __init__(self, start: datetime, end: datetime, label: str) -> None:
        self.start, self.end, self.label = start, end, label

    def has(self, obj: dict) -> bool:
        # An entry with no timestamp counts, so hand-written fixtures still work.
        ts = parse_ts(obj.get("timestamp") or obj.get("ts"))
        return ts is None or self.start <= ts < self.end


def window_from(args: argparse.Namespace) -> Window:
    if args.month:
        start = datetime.strptime(args.month, "%Y-%m").replace(tzinfo=timezone.utc)
        end = (start + timedelta(days=32)).replace(day=1)
        return Window(start, end, args.month)
    end = datetime.now(timezone.utc) + timedelta(minutes=1)
    return Window(end - timedelta(days=args.days), end, f"last {args.days} days")


def version_key(path: str) -> list:
    return [int(part) if part.isdigit() else part for part in re.split(r"[.-]", os.path.basename(path))]


def installed_skills(claude: Path) -> set[str]:
    """Skills from enabled plugins (newest cached version) plus user skills."""
    try:
        enabled = json.loads((claude / "settings.json").read_text()).get("enabledPlugins") or {}
    except (OSError, ValueError, AttributeError):
        enabled = {}
    names: set[str] = set()
    for key, on in enabled.items():
        if not on or "@" not in key:
            continue
        plugin, market = key.split("@", 1)
        versions = sorted(glob.glob(str(claude / "plugins/cache" / market / plugin / "*")), key=version_key)
        if versions:
            names.update(f"{plugin}:{Path(p).parent.name}" for p in glob.glob(os.path.join(versions[-1], "skills/*/SKILL.md")))
    names.update(Path(p).parent.name for p in glob.glob(str(claude / "skills/*/SKILL.md")))
    return names


def load_detectors(catalog: Path) -> tuple[dict[str, re.Pattern], str]:
    try:
        import tomllib
    except ImportError:
        # ponytail: Python < 3.11 has no tomllib; detectors are skipped there.
        return {}, "unavailable: Python 3.11+ required to read the catalog"
    try:
        data = tomllib.loads(catalog.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        return {}, f"unavailable: {type(error).__name__}"
    detectors = {}
    for item in data.get("component", []):
        detector = str(item.get("detector") or "")
        if detector.startswith("regex:"):
            detectors[item["id"]] = re.compile(detector[len("regex:") :])
    return detectors, "loaded"


def claude_transcripts(root: Path, window: Window) -> list[Path]:
    chosen: dict[str, tuple[int, Path]] = {}
    for path in root.glob("**/*.jsonl"):
        # Sub-agent transcripts are dispatched work, not top-level sessions.
        if "subagents" in path.parts:
            continue
        try:
            stat = path.stat()
        except OSError:
            continue
        if datetime.fromtimestamp(stat.st_mtime, timezone.utc) < window.start:
            continue
        prior = chosen.get(path.stem)
        # A moved project leaves a duplicate copy; the larger one is the live session.
        if prior is None or stat.st_size > prior[0]:
            chosen[path.stem] = (stat.st_size, path)
    return [path for _size, path in chosen.values()]


def read_jsonl(path: Path):
    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if isinstance(obj, dict):
                yield obj


def report(args: argparse.Namespace) -> dict:
    window = window_from(args)
    claude = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")).expanduser()
    projects = args.projects or claude / "projects"
    codex_root = args.codex_sessions or Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser() / "sessions"
    repo = args.repo or Path(os.environ.get("AGENTS_REPO", Path.home() / ".agents")).expanduser()
    detectors, catalog_state = load_detectors(args.catalog)
    installed = installed_skills(claude)

    sessions = Counter()
    skills: dict[str, Counter] = defaultdict(Counter)
    commands = Counter()
    tool_calls = Counter()
    errors: dict[str, Counter] = {"claude": Counter(), "codex": Counter()}
    compactions = Counter()
    detector_hits = Counter()
    delegate_calls = 0

    for path in claude_transcripts(Path(projects), window):
        active = False
        for obj in read_jsonl(path):
            if not window.has(obj):
                continue
            active = True
            message = obj.get("message") or {}
            content = message.get("content") if isinstance(message, dict) else None
            if obj.get("type") == "system" and obj.get("subtype") == "compact_boundary":
                trigger = (obj.get("compactMetadata") or {}).get("trigger") or "unknown"
                compactions[f"claude-{trigger}"] += 1
            if obj.get("type") == "user":
                for name in COMMAND_NAME.findall(as_text(content)):
                    if name in installed or ":" in name:
                        skills[name]["claude_slash"] += 1
                    else:
                        commands[name] += 1
                for block in content if isinstance(content, list) else []:
                    if isinstance(block, dict) and block.get("type") == "tool_result" and block.get("is_error"):
                        errors["claude"][error_class(as_text(block.get("content")))] += 1
            if obj.get("type") == "assistant" and isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "text":
                        for component, pattern in detectors.items():
                            detector_hits[component] += len(pattern.findall(block.get("text") or ""))
                    elif block.get("type") == "tool_use":
                        tool_calls["claude"] += 1
                        if block.get("name") == "Skill":
                            name = str((block.get("input") or {}).get("skill") or "")
                            skills[name]["claude_tool"] += 1
                            delegate_calls += name == "harness:delegate"
        sessions["claude"] += active

    if Path(codex_root).is_dir():
        for path in Path(codex_root).glob("**/*.jsonl"):
            try:
                if datetime.fromtimestamp(path.stat().st_mtime, timezone.utc) < window.start:
                    continue
            except OSError:
                continue
            active = False
            loaded: set[str] = set()
            for obj in read_jsonl(path):
                payload = obj.get("payload") or {}
                kind = obj.get("type")
                if kind == "session_meta":
                    source = payload.get("source")
                    if isinstance(source, dict) and "subagent" in source:
                        break
                    continue
                if not window.has(obj):
                    continue
                if kind == "compacted":
                    compactions["codex"] += 1
                    continue
                if kind != "response_item":
                    continue
                active = True
                item = payload.get("type")
                if item == "message" and payload.get("role") == "user":
                    loaded.update(name.strip() for name in CODEX_INJECTED.findall(as_text(payload.get("content"))))
                elif item == "message" and payload.get("role") == "assistant":
                    text = as_text(payload.get("content"))
                    for component, pattern in detectors.items():
                        detector_hits[component] += len(pattern.findall(text))
                elif item in ("function_call", "custom_tool_call"):
                    tool_calls["codex"] += 1
                    call = str(payload.get("arguments") or payload.get("input") or "")
                    for plugin, name in SKILL_PATH.findall(call):
                        loaded.add(f"{plugin}:{name}" if plugin else name)
                elif item in ("function_call_output", "custom_tool_call_output"):
                    text = as_text(payload.get("output"))
                    if NONZERO_EXIT.search(text) or "no matches found" in text:
                        errors["codex"][error_class(text)] += 1
            sessions["codex"] += active
            for name in loaded:
                skills[name]["codex_sessions"] += 1
            delegate_calls += "harness:delegate" in loaded

    results = [r for r in telemetry.events("Results", repo, local_only=args.local_only) if window.has(r)]
    shims = [e for e in telemetry.events("Shim_Events", repo, local_only=args.local_only) if window.has(e)]
    by_route: dict[str, Counter] = defaultdict(Counter)
    for record in results:
        route = (record.get("route") or {}).get("requested") or "unknown"
        by_route[route][f"{record.get('status')}/{record.get('outcome')}"] += 1

    used = {name for name, counts in skills.items() if sum(counts.values())}
    return {
        "window": {"label": window.label, "start": window.start.isoformat(), "end": window.end.isoformat()},
        "host": telemetry.host(),
        "scope": "local" if args.local_only else "all hosts",
        "catalog": catalog_state,
        "sessions": dict(sessions),
        "skills": {name: dict(counts) for name, counts in sorted(skills.items()) if name},
        "unused_skills": sorted(installed - used),
        "commands": dict(commands.most_common()),
        "tool_calls": dict(tool_calls),
        "tool_errors": {provider: dict(counts.most_common()) for provider, counts in errors.items()},
        "compactions": dict(compactions),
        "detector_hits": dict(detector_hits.most_common()),
        "shim_firings": dict(Counter(str(e.get("shim")) for e in shims).most_common()),
        "results": {
            "total": len(results),
            "fallbacks": sum(1 for r in results if r.get("attempted")),
            "by_route": {route: dict(counts) for route, counts in sorted(by_route.items())},
        },
        "delegate": {"invocations": delegate_calls, "recorded_results": len(results)},
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    span = parser.add_mutually_exclusive_group()
    span.add_argument("--days", type=int, default=30)
    span.add_argument("--month", help="calendar month YYYY-MM (UTC)")
    parser.add_argument("--local-only", action="store_true", help="this machine's telemetry only")
    parser.add_argument("--projects", type=Path)
    parser.add_argument("--codex-sessions", type=Path)
    parser.add_argument("--repo", type=Path)
    parser.add_argument("--catalog", type=Path, default=Path(__file__).resolve().parent.parent / "Component_Catalog.toml")
    parser.add_argument("--output", type=Path, help="write the JSON here instead of stdout")
    args = parser.parse_args(argv)
    text = json.dumps(telemetry.redact(report(args)), indent=2, sort_keys=True) + "\n"
    if args.output:
        telemetry.write_atomic(args.output, text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
