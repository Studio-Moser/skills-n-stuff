#!/usr/bin/env python3
"""Deterministic Harness usage counts from local transcripts and telemetry. READ-ONLY.

Counts only, never transcript content, so the same numbers can be compared across
models and machines. Interpretation belongs to the harness:audit playbook.

  usage-report.py [--days N | --month YYYY-MM | --since DATE [--until DATE]] [--local-only] [--flagged]

Sections: sessions, skills (Claude Skill tool + slash commands, Codex skill
injections and SKILL.md reads), unused installed skills, commands, tool calls
(each call id once), error classes overall and by tool, compactions and their
idle/in-session split, catalog detector hits, shim firings, delegation
results with failures split by cause, review rounds, delegate invocations versus
recorded results (all hosts and this host), sequence patterns in Claude sessions,
and tokens by model (Claude main sessions and sub-agents, Codex sessions by source;
this machine's transcripts only). --flagged adds the session ids behind each
sequence pattern so an audit can sample them; Sync never passes it.

Roots: --projects (${CLAUDE_CONFIG_DIR:-~/.claude}/projects), --codex-sessions
(${CODEX_HOME:-~/.codex}/sessions), --repo (${AGENTS_REPO:-~/.agents}), --catalog
(this plugin's Component_Catalog.toml). Missing roots count as empty.
"""

from __future__ import annotations

import argparse
import hashlib
from collections import Counter, defaultdict
import glob
import json
import os
from pathlib import Path
import re
import statistics
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
# Anchored to the failure message itself: a failing `cat` of a file that mentions
# "Timeout" is a nonzero exit, not a timeout.
ERROR_CLASSES = (
    ("zsh-nomatch", re.compile(r"(?:\(eval\)|zsh):\d+: no matches found")),
    ("command-not-found", re.compile(r"command not found")),
    ("permission-denied", re.compile(r"Permission denied|Operation not permitted")),
    ("user-rejected", re.compile(r"doesn.t want to (?:proceed|take this action)|user rejected|was rejected", re.I)),
    ("interrupted", re.compile(r"tool call was interrupted before a result|\[Request interrupted by user")),
    ("edit-read-order", re.compile(r"has not been read yet|modified since read")),
    ("edit-mismatch", re.compile(r"String to replace not found|Found \d+ matches of the string")),
    ("missing-file", re.compile(r"(?:^|>)File does not exist\.", re.M)),
    ("sandbox-path", re.compile(r"is outside allowed roots")),
    ("skill-unavailable", re.compile(r"Unknown skill:|cannot be used with Skill tool")),
    ("mcp-auth", re.compile(r"Authentication Failed: Requires authentication|AuthRequired")),
    ("browser-disconnected", re.compile(r"No browser is connected|Click Allow in the Browser MCP")),
    ("quota", re.compile(r"Credits insufficient|insufficient (?:credits|balance)", re.I)),
    ("rate-limit", re.compile(r"\"code\":\s*\"rate_limited\"|rate limit(?:ed| exceeded)", re.I)),
    ("host-blocked", re.compile(r"^Blocked: ", re.M)),
    ("timeout", re.compile(r"Command timed out after|connect(?:ion)? timed out", re.I)),
)
# Timeouts a tool reports about itself. Inside a failing command's output they are
# usually a test's own failure, so they count only when no exit code is present.
TOOL_TIMEOUT = re.compile(r"timed out after \d|Timeout \d+ ?ms|TimeoutError|Operation timed out", re.I)

# Sequence proxies. They choose sessions for an audit to sample; they are not verdicts.
SEQUENCE_KINDS = ("repeated_failure", "recovered_failure", "verification_rerun", "unsupported_completion")
# Matched at the start of each simple command, so `cat tests/x.bats` is not a check.
SEGMENT = re.compile(r"&&|\|\||[;|\n]")
LAUNCHER = re.compile(r"^(?:(?:\S+=\S*|time|npx|uv run|poetry run|bundle exec|(?:\S*/)?python3?(?:\.\d+)? -m)\s+)+")
CHECK = re.compile(
    r"^(?:\S*/)?(?:pytest|unittest|bats|vitest|jest|tsc|eslint|ruff|mypy|run-tests(?:\.sh)?|swift test"
    r"|xcodebuild\b.*\btest\b|(?:npm|pnpm|yarn|bun) (?:run )?test|node --test|playwright test"
    r"|cargo (?:test|check)|go (?:test|vet)|make (?:test|check))\b"
)
MUTATING_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
CHANGE = re.compile(
    r"^(?:rm|mv|cp|mkdir|touch|chmod|ln|patch|tee|sed -i|git (?:apply|checkout|switch|merge|rebase|reset|pull"
    r"|cherry-pick|stash|am)|(?:npm|pnpm|yarn) (?:i|install|add))\b|\s--(?:fix|write)\b|(?<!-)\bformat\b(?!=)"
)
REDIRECT = re.compile(r"(?:^|[^\d&>])>>?\s*(?!&|/dev/null)[^\s&|;]")
# Claims about a check's outcome, not every "done": design and media turns say "done"
# with nothing to test.
COMPLETION = re.compile(
    r"\b(?:tests? (?:pass|passed|are passing)|(?:all|every) (?:\w+ )?(?:tests|checks) (?:pass|passed|green)"
    r"|is fixed|now works|works now|verified)\b",
    re.I,
)
# Notes, memory, and docs written after a passing check do not invalidate it.
NOTE_FILE = re.compile(r"/memory/|\.(?:md|txt)$")
RECORD_RESULT = re.compile(r"telemetry\.py\W+record-result")
NOT_HUMAN = ("<local-command", "<task-notification", "<system-reminder", "This session is being continued")
# T3 Code compacts a thread shortly before its one-hour prompt cache expires; Claude
# Code records that /compact as trigger "manual".
IDLE_COMPACTION = timedelta(minutes=50)


def error_class(text: str) -> str:
    for name, pattern in ERROR_CLASSES:
        if pattern.search(text):
            return name
    if NONZERO_EXIT.search(text) or "Exit code" in text:
        return "nonzero-exit"
    return "timeout" if TOOL_TIMEOUT.search(text) else "other"


def tool_bucket(name: object) -> str:
    """An MCP tool reports under its server, so one flaky server shows up as one source."""
    name = str(name or "")
    if name.startswith("mcp__"):
        return "mcp:" + name.split("__")[1]
    return name or "unknown"


def is_human(obj: dict) -> bool:
    if obj.get("type") != "user" or obj.get("isMeta") or obj.get("isCompactSummary"):
        return False
    content = (obj.get("message") or {}).get("content")
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return False
        content = " ".join(b.get("text") or "" for b in content if isinstance(b, dict))
    text = content.lstrip() if isinstance(content, str) else ""
    return bool(text) and not text.startswith(NOT_HUMAN)


def simple_commands(command: str) -> list[str]:
    return [LAUNCHER.sub("", part.strip()) for part in SEGMENT.split(command) if part.strip()]


def is_check(command: str) -> bool:
    return any(CHECK.search(part) for part in simple_commands(command))


def is_change(command: str) -> bool:
    return bool(REDIRECT.search(command)) or any(CHANGE.search(part) for part in simple_commands(command))


def program(command: str) -> str:
    """The program a Bash command runs, past env assignments and a leading `cd DIR &&`."""
    words = command.split()
    if words[:1] == ["cd"] and "&&" in words:
        words = words[words.index("&&") + 1 :]
    words = [w for w in words if "=" not in w] or [""]
    return os.path.basename(words[0])


class Sequences:
    """Counts of four patterns in one Claude session: the same failing call three
    times in the session; within a human turn, a failure followed by a changed,
    successful call of the same tool and program; a passing check rerun with no change
    since; and a claim that checks pass after file edits with no passing check after
    the last edit, in a session that has a check to run."""

    def __init__(self) -> None:
        self.counts: Counter = Counter()
        self.calls: dict[str, tuple[tuple[str, str], tuple[str, str], bool]] = {}
        self.failures: Counter = Counter()
        self.has_seam = False
        self.begin_turn()

    def begin_turn(self) -> None:
        self.pending: dict[tuple[str, str], set] = {}
        self.passed_check: tuple[str, str] | None = None
        self.mutated = self.verified = False
        self.claim = ""

    def end_turn(self) -> None:
        if self.has_seam and self.mutated and not self.verified and COMPLETION.search(self.claim):
            self.counts["unsupported_completion"] += 1
        self.begin_turn()

    def use(self, block: dict) -> None:
        name = str(block.get("name") or "")
        tool_input = block.get("input") if isinstance(block.get("input"), dict) else {}
        command = " ".join(str(tool_input.get("command") or "").split()) if name == "Bash" else ""
        # A digest keeps a Write's whole file body out of memory.
        digest = hashlib.sha1(json.dumps(tool_input, sort_keys=True, default=str).encode()).hexdigest()
        key = (name, command if name == "Bash" else digest)
        verify = bool(command) and is_check(command)
        if name in MUTATING_TOOLS or (command and is_change(command)):
            self.passed_check = None
        if name in MUTATING_TOOLS and not NOTE_FILE.search(str(tool_input.get("file_path") or "")):
            # Only file-edit tools count as edits a claim must follow: Bash writes are
            # too often scratch files or merges of already tested code.
            self.mutated, self.verified = True, False
        if verify and key == self.passed_check:
            self.counts["verification_rerun"] += 1
        self.has_seam = self.has_seam or verify
        self.calls[str(block.get("id"))] = ((name, program(command) if command else ""), key, verify)

    def result(self, block: dict) -> None:
        call = self.calls.get(str(block.get("tool_use_id")))
        if call is None:
            return
        family, key, verify = call
        if block.get("is_error"):
            self.failures[key] += 1
            self.counts["repeated_failure"] += self.failures[key] == 3
            self.pending.setdefault(family, set()).add(key)
            return
        failed = self.pending.pop(family, set())
        self.counts["recovered_failure"] += bool(failed) and key not in failed
        if verify:
            self.verified, self.passed_check = True, key


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
    if args.since:
        start = datetime.strptime(args.since, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        end = (
            datetime.strptime(args.until, "%Y-%m-%d").replace(tzinfo=timezone.utc)
            if args.until
            else datetime.now(timezone.utc) + timedelta(minutes=1)
        )
        return Window(start, end, f"{args.since} to {args.until or 'now'}")
    if args.month:
        start = datetime.strptime(args.month, "%Y-%m").replace(tzinfo=timezone.utc)
        end = (start + timedelta(days=32)).replace(day=1)
        return Window(start, end, args.month)
    end = datetime.now(timezone.utc) + timedelta(minutes=1)
    return Window(end - timedelta(days=args.days), end, f"last {args.days} days")


def version_key(path: str) -> list:
    # shortcut: hash-named versions sort after numbered ones, then by hash, so the "newest"
    # hash is arbitrary. Only the unused-skill list depends on it; read the install record if that matters.
    return [(0, int(part), "") if part.isdigit() else (1, 0, part) for part in re.split(r"[.-]", os.path.basename(path))]


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


def load_detectors(catalog: Path) -> tuple[dict[str, re.Pattern], dict[str, re.Pattern], str]:
    """Text detectors match assistant text; command detectors match shell commands."""
    try:
        import tomllib
    except ImportError:
        # shortcut: Python < 3.11 has no tomllib; detectors are skipped there.
        return {}, {}, "unavailable: Python 3.11+ required to read the catalog"
    try:
        data = tomllib.loads(catalog.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        return {}, {}, f"unavailable: {type(error).__name__}"
    text, command = {}, {}
    for item in data.get("component", []):
        detector = str(item.get("detector") or "")
        kind, _, pattern = detector.partition(":")
        if kind in ("regex", "command") and pattern:
            (text if kind == "regex" else command)[item["id"]] = re.compile(pattern)
    return text, command, "loaded"


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


def add_tokens(bucket: Counter, input_: int, cache_read: int, cache_write: int, output: int) -> None:
    bucket.update(input=input_, cache_read=cache_read, cache_write=cache_write, output=output)


def claude_tokens(root: Path, window: Window) -> dict[str, dict[str, Counter]]:
    """Tokens by scope and model. One API message spans several lines, and a moved or
    resumed session repeats them, so each message id counts once."""
    messages: dict[str, tuple[str, str, dict]] = {}
    for path in root.glob("**/*.jsonl"):
        try:
            if datetime.fromtimestamp(path.stat().st_mtime, timezone.utc) < window.start:
                continue
        except OSError:
            continue
        scope = "subagent" if "subagents" in path.parts else "main"
        for index, obj in enumerate(read_jsonl(path)):
            message = obj.get("message")
            if obj.get("type") != "assistant" or not isinstance(message, dict) or not window.has(obj):
                continue
            usage = message.get("usage")
            # Locally generated messages carry an all-zero usage block.
            if isinstance(usage, dict) and message.get("model") != "<synthetic>":
                key = str(message.get("id") or f"{path}:{index}")
                messages[key] = (scope, str(message.get("model") or "unknown"), usage)
    totals: dict[str, dict[str, Counter]] = defaultdict(lambda: defaultdict(Counter))
    for scope, model, usage in messages.values():
        add_tokens(
            totals[scope][model],
            usage.get("input_tokens") or 0,
            usage.get("cache_read_input_tokens") or 0,
            usage.get("cache_creation_input_tokens") or 0,
            usage.get("output_tokens") or 0,
        )
    return totals


def codex_tokens(root: Path, window: Window) -> dict[str, dict[str, Counter]]:
    """Tokens by session source and model, from the deltas of Codex's running totals."""
    totals: dict[str, dict[str, Counter]] = defaultdict(lambda: defaultdict(Counter))
    if not root.is_dir():
        return totals
    fields = ("input_tokens", "cached_input_tokens", "cache_write_input_tokens", "output_tokens")
    for path in root.glob("**/*.jsonl"):
        try:
            if datetime.fromtimestamp(path.stat().st_mtime, timezone.utc) < window.start:
                continue
        except OSError:
            continue
        source, model, prior = "unknown", "unknown", dict.fromkeys(fields, 0)
        for obj in read_jsonl(path):
            payload = obj.get("payload") or {}
            if not isinstance(payload, dict):
                continue
            kind = obj.get("type")
            if kind == "session_meta":
                raw = payload.get("source")
                source = "subagent" if isinstance(raw, dict) and "subagent" in raw else str(raw or "unknown")
            elif kind == "turn_context":
                model = str(payload.get("model") or model)
            elif kind == "event_msg" and payload.get("type") == "token_count":
                current = (payload.get("info") or {}).get("total_token_usage")
                if not isinstance(current, dict):
                    continue
                delta = {field: max((current.get(field) or 0) - prior[field], 0) for field in fields}
                prior = {field: current.get(field) or 0 for field in fields}
                if window.has(obj):
                    # Codex's input count includes cached input; Claude's does not.
                    add_tokens(
                        totals[source][model],
                        max(delta["input_tokens"] - delta["cached_input_tokens"], 0),
                        delta["cached_input_tokens"],
                        delta["cache_write_input_tokens"],
                        delta["output_tokens"],
                    )
    return totals


def plain(totals: dict[str, dict[str, Counter]]) -> dict:
    return {scope: {model: dict(counts) for model, counts in models.items()} for scope, models in totals.items()}


def report(args: argparse.Namespace) -> dict:
    window = window_from(args)
    claude = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")).expanduser()
    projects = args.projects or claude / "projects"
    codex_root = args.codex_sessions or Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser() / "sessions"
    repo = args.repo or Path(os.environ.get("AGENTS_REPO", Path.home() / ".agents")).expanduser()
    detectors, command_detectors, catalog_state = load_detectors(args.catalog)
    installed = installed_skills(claude)

    sessions = Counter()
    skills: dict[str, Counter] = defaultdict(Counter)
    commands = Counter()
    tool_calls = Counter()
    errors: dict[str, Counter] = {"claude": Counter(), "codex": Counter()}
    errors_by_tool: dict[str, dict[str, Counter]] = {"claude": defaultdict(Counter), "codex": defaultdict(Counter)}
    compactions = Counter()
    compaction_split = Counter()
    pre_tokens: list[int] = []
    detector_hits = Counter()
    delegate_calls = record_calls = 0
    sequence_events: Counter = Counter()
    flagged: dict[str, list[str]] = defaultdict(list)

    for path in claude_transcripts(Path(projects), window):
        active = False
        # A resumed or forked session can repeat a call's records; each call id counts once.
        seen_uses: set[str] = set()
        seen_results: set[str] = set()
        call_names: dict[str, str] = {}
        sequences = Sequences()
        last_assistant: datetime | None = None
        for obj in read_jsonl(path):
            if obj.get("type") == "assistant":
                # Before the window filter: idle time can start before the window does.
                last_assistant = parse_ts(obj.get("timestamp")) or last_assistant
            if not window.has(obj):
                continue
            active = True
            message = obj.get("message") or {}
            content = message.get("content") if isinstance(message, dict) else None
            if obj.get("type") == "system" and obj.get("subtype") == "compact_boundary":
                meta = obj.get("compactMetadata") or {}
                trigger = meta.get("trigger") or "unknown"
                compactions[f"claude-{trigger}"] += 1
                if isinstance(meta.get("preTokens"), int):
                    pre_tokens.append(meta["preTokens"])
                if trigger == "manual":
                    at = parse_ts(obj.get("timestamp"))
                    idle = at is not None and last_assistant is not None and at - last_assistant >= IDLE_COMPACTION
                    compaction_split["manual_after_idle" if idle else "manual_in_session"] += 1
                else:
                    compaction_split[trigger] += 1
            if obj.get("type") == "user":
                for name in COMMAND_NAME.findall(as_text(content)):
                    if name in installed or ":" in name:
                        skills[name]["claude_slash"] += 1
                    else:
                        commands[name] += 1
                if is_human(obj):
                    sequences.end_turn()
                for block in content if isinstance(content, list) else []:
                    if not isinstance(block, dict) or block.get("type") != "tool_result":
                        continue
                    use_id = block.get("tool_use_id")
                    if use_id in seen_results:
                        continue
                    if use_id:
                        seen_results.add(use_id)
                    if block.get("is_error"):
                        kind = error_class(as_text(block.get("content")))
                        errors["claude"][kind] += 1
                        errors_by_tool["claude"][tool_bucket(call_names.get(use_id))][kind] += 1
                    sequences.result(block)
            if obj.get("type") == "assistant" and isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "text":
                        for component, pattern in detectors.items():
                            detector_hits[component] += len(pattern.findall(block.get("text") or ""))
                        sequences.claim = block.get("text") or ""
                    elif block.get("type") == "tool_use":
                        use_id = block.get("id")
                        if use_id in seen_uses:
                            continue
                        if use_id:
                            seen_uses.add(use_id)
                            call_names[use_id] = str(block.get("name") or "")
                        tool_calls["claude"] += 1
                        tool_input = block.get("input") if isinstance(block.get("input"), dict) else {}
                        if block.get("name") == "Skill":
                            name = str(tool_input.get("skill") or "")
                            skills[name]["claude_tool"] += 1
                            delegate_calls += name == "harness:delegate"
                        elif block.get("name") == "Bash":
                            command = str(tool_input.get("command") or "")
                            record_calls += bool(RECORD_RESULT.search(command))
                            for component, pattern in command_detectors.items():
                                detector_hits[component] += bool(pattern.search(command))
                        sequences.use(block)
        sequences.end_turn()
        sessions["claude"] += active
        for kind, count in sequences.counts.items():
            if count:
                sequence_events[kind] += count
                flagged[kind].append(path.stem)

    if Path(codex_root).is_dir():
        for path in Path(codex_root).glob("**/*.jsonl"):
            try:
                if datetime.fromtimestamp(path.stat().st_mtime, timezone.utc) < window.start:
                    continue
            except OSError:
                continue
            active = False
            loaded: set[str] = set()
            codex_names: dict[str, str] = {}
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
                    if payload.get("call_id"):
                        codex_names[str(payload["call_id"])] = str(payload.get("name") or "")
                    call = str(payload.get("arguments") or payload.get("input") or "")
                    record_calls += bool(RECORD_RESULT.search(call))
                    for component, pattern in command_detectors.items():
                        detector_hits[component] += bool(pattern.search(call))
                    for plugin, name in SKILL_PATH.findall(call):
                        loaded.add(f"{plugin}:{name}" if plugin else name)
                elif item in ("function_call_output", "custom_tool_call_output"):
                    text = as_text(payload.get("output"))
                    if NONZERO_EXIT.search(text) or "no matches found" in text:
                        kind = error_class(text)
                        errors["codex"][kind] += 1
                        name = codex_names.get(str(payload["call_id"])) if payload.get("call_id") else None
                        errors_by_tool["codex"][tool_bucket(name)][kind] += 1
            sessions["codex"] += active
            for name in loaded:
                skills[name]["codex_sessions"] += 1
            delegate_calls += "harness:delegate" in loaded

    results = [r for r in telemetry.events("Results", repo, local_only=args.local_only) if window.has(r)]
    shims = [e for e in telemetry.events("Shim_Events", repo, local_only=args.local_only) if window.has(e)]
    by_route: dict[str, Counter] = defaultdict(Counter)
    # A reviewer that ran checks and returned findings records `failed`; a run with no
    # checks at all is an executor or adapter failure.
    failed = Counter(review_changes_requested=0, no_checks=0, other=0)
    for record in results:
        route = (record.get("route") or {}).get("requested") or "unknown"
        by_route[route][f"{record.get('status')}/{record.get('outcome')}"] += 1
        if record.get("status") == "failed":
            if not record.get("checks"):
                failed["no_checks"] += 1
            elif record.get("operation") == "review":
                failed["review_changes_requested"] += 1
            else:
                failed["other"] += 1

    reviews = [r for r in telemetry.events("Review_Rounds", repo, local_only=args.local_only) if window.has(r)]
    review_models: dict[str, Counter] = defaultdict(Counter)
    over_limit: set[str] = set()
    diff_lines: dict[str, list[int]] = defaultdict(list)
    for record in reviews:
        name = f"{record.get('consumer')} {record.get('target')}"
        review_models[str(record.get("model"))]["rounds"] += 1
        review_models[str(record.get("model"))].update(record.get("findings") or {})
        if record.get("round", 0) > record.get("limit", 0) and not record.get("extension_approved"):
            over_limit.add(name)
        diff_lines[name].append(record.get("diff_lines", 0))

    used = {name for name, counts in skills.items() if sum(counts.values())}
    pre_tokens.sort()
    split = dict(compaction_split)
    if pre_tokens:
        split["pre_tokens"] = {
            "count": len(pre_tokens),
            "min": pre_tokens[0],
            "median": int(statistics.median(pre_tokens)),
            "max": pre_tokens[-1],
        }
    report_data = {
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
        "tool_errors_by_tool": {
            provider: {tool: dict(counts.most_common()) for tool, counts in sorted(tools.items())}
            for provider, tools in errors_by_tool.items()
        },
        "compactions": dict(compactions),
        "compaction_detail": {"claude": split},
        "sequences": {
            "claude": {kind: {"events": sequence_events[kind], "sessions": len(flagged[kind])} for kind in SEQUENCE_KINDS}
        },
        "detector_hits": dict(detector_hits.most_common()),
        "shim_firings": dict(Counter(str(e.get("shim")) for e in shims).most_common()),
        "results": {
            "total": len(results),
            "fallbacks": sum(1 for r in results if r.get("attempted")),
            "by_route": {route: dict(counts) for route, counts in sorted(by_route.items())},
            "failed": dict(failed),
        },
        "reviews": {
            "rounds": len(reviews),
            "by_model": {model: dict(counts) for model, counts in sorted(review_models.items())},
            "unapproved_over_limit": sorted(over_limit),
            "diff_growth": {
                name: {"first": lines[0], "last": lines[-1]}
                for name, lines in sorted(diff_lines.items())
                if lines[-1] > lines[0]
            },
        },
        # `invocations` counts this machine's skill loads against every host's rows, and
        # one load can record many rows; `local` compares this host with itself.
        "delegate": {
            "invocations": delegate_calls,
            "recorded_results": len(results),
            "local": {
                "skill_loads": delegate_calls,
                "record_calls": record_calls,
                "results": sum(1 for r in results if r.get("host") == telemetry.host()),
            },
        },
        "tokens": {
            "claude": plain(claude_tokens(Path(projects), window)),
            "codex": plain(codex_tokens(Path(codex_root), window)),
        },
    }
    if args.flagged:
        report_data["flagged_sessions"] = {kind: sorted(flagged[kind]) for kind in SEQUENCE_KINDS if flagged[kind]}
    return report_data


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    span = parser.add_mutually_exclusive_group()
    span.add_argument("--days", type=int, default=30)
    span.add_argument("--month", help="calendar month YYYY-MM (UTC)")
    span.add_argument("--since", help="start date YYYY-MM-DD (UTC), inclusive")
    parser.add_argument("--until", help="end date YYYY-MM-DD (UTC), exclusive; requires --since")
    parser.add_argument("--local-only", action="store_true", help="this machine's telemetry only")
    parser.add_argument("--flagged", action="store_true", help="list the session ids behind each sequence pattern")
    parser.add_argument("--projects", type=Path)
    parser.add_argument("--codex-sessions", type=Path)
    parser.add_argument("--repo", type=Path)
    parser.add_argument("--catalog", type=Path, default=Path(__file__).resolve().parent.parent / "Component_Catalog.toml")
    parser.add_argument("--output", type=Path, help="write the JSON here instead of stdout")
    args = parser.parse_args(argv)
    if args.until and not args.since:
        parser.error("--until requires --since")
    text = json.dumps(telemetry.redact(report(args)), indent=2, sort_keys=True) + "\n"
    if args.output:
        telemetry.write_atomic(args.output, text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
