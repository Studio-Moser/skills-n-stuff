#!/usr/bin/env python3
"""Run Codex through the typed App Server protocol without leaking raw failures."""

from __future__ import annotations

import argparse
import json
import os
import re
import selectors
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


EXIT_FAILED = 1
EXIT_MISSING_EXECUTOR = 69
EXIT_AVAILABILITY = 75
PREFLIGHT_TIMEOUT_SECONDS = 15
TURN_TIMEOUT_SECONDS = 3600
MAX_PROTOCOL_LINE_BYTES = 16 * 1024 * 1024
FIXED_TARGET_PATTERN = re.compile(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}")
STRING_AVAILABILITY = {
    "usageLimitExceeded": "quota",
    "unauthorized": "authentication",
    "serverOverloaded": "provider_unavailable",
    "internalServerError": "provider_unavailable",
}
STRUCTURED_CONNECTION_ERRORS = {
    "httpConnectionFailed",
    "responseStreamConnectionFailed",
    "responseStreamDisconnected",
    "responseTooManyFailedAttempts",
}


class AdapterFailure(Exception):
    """The App Server result is not a typed provider-availability failure."""


class MissingExecutor(AdapterFailure):
    """The Codex binary or required App Server protocol seam is unavailable."""


class Arguments(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise AdapterFailure from None


def compact_json(value: dict[str, object]) -> None:
    print(json.dumps(value, separators=(",", ":")))


def resolve_binary(value: str) -> str:
    if os.sep in value:
        path = Path(value)
        if not path.is_file() or not os.access(path, os.X_OK):
            raise MissingExecutor
        return str(path)
    resolved = shutil.which(value)
    if resolved is None:
        raise MissingExecutor
    return resolved


def load_schema(path: Path) -> dict[str, Any]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise MissingExecutor from error
    if not isinstance(document, dict):
        raise MissingExecutor
    return document


def schema_properties(document: dict[str, Any]) -> set[str]:
    properties = document.get("properties")
    if not isinstance(properties, dict):
        raise MissingExecutor
    return set(properties)


def validate_protocol_schema(root: Path) -> None:
    thread = load_schema(root / "v2" / "ThreadStartParams.json")
    turn = load_schema(root / "v2" / "TurnStartParams.json")
    completed = load_schema(root / "v2" / "TurnCompletedNotification.json")
    if not {
        "allowProviderModelFallback",
        "approvalPolicy",
        "cwd",
        "ephemeral",
        "model",
        "sandbox",
    }.issubset(schema_properties(thread)):
        raise MissingExecutor
    if not {
        "approvalPolicy",
        "cwd",
        "effort",
        "input",
        "model",
        "sandboxPolicy",
        "threadId",
    }.issubset(schema_properties(turn)):
        raise MissingExecutor

    definitions = completed.get("definitions")
    if not isinstance(definitions, dict):
        raise MissingExecutor
    turn_error = definitions.get("TurnError")
    error_info = definitions.get("CodexErrorInfo")
    if not isinstance(turn_error, dict) or not isinstance(error_info, dict):
        raise MissingExecutor
    if "codexErrorInfo" not in schema_properties(turn_error):
        raise MissingExecutor
    variants = error_info.get("oneOf")
    if not isinstance(variants, list):
        raise MissingExecutor
    strings: set[str] = set()
    structured: set[str] = set()
    for variant in variants:
        if not isinstance(variant, dict):
            continue
        values = variant.get("enum")
        if isinstance(values, list):
            strings.update(value for value in values if isinstance(value, str))
        required = variant.get("required")
        if isinstance(required, list) and len(required) == 1 and isinstance(required[0], str):
            structured.add(required[0])
    if not set(STRING_AVAILABILITY).issubset(strings):
        raise MissingExecutor
    if not STRUCTURED_CONNECTION_ERRORS.issubset(structured):
        raise MissingExecutor


def check_app_server(binary: str) -> None:
    with tempfile.TemporaryDirectory(prefix="harness-codex-schema.") as temporary:
        try:
            process = subprocess.run(
                [
                    binary,
                    "app-server",
                    "generate-json-schema",
                    "--experimental",
                    "--out",
                    temporary,
                ],
                check=False,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=PREFLIGHT_TIMEOUT_SECONDS,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise MissingExecutor from error
        if process.returncode != 0:
            raise MissingExecutor
        validate_protocol_schema(Path(temporary))


def classify_availability(value: object) -> str | None:
    if isinstance(value, str):
        return STRING_AVAILABILITY.get(value)
    if not isinstance(value, dict) or len(value) != 1:
        return None
    name, details = next(iter(value.items()))
    if name not in STRUCTURED_CONNECTION_ERRORS or not isinstance(details, dict):
        return None
    status = details.get("httpStatusCode")
    if status is not None and (isinstance(status, bool) or not isinstance(status, int)):
        return None
    if status in {401, 403}:
        return "authentication"
    if status == 429:
        return "rate_limit"
    if status is None or 500 <= status <= 599:
        return "provider_unavailable"
    return None


def sandbox_policy(mode: str, cwd: str) -> dict[str, object]:
    if mode == "read-only":
        return {"type": "readOnly"}
    if mode == "workspace-write":
        return {"type": "workspaceWrite", "writableRoots": [cwd]}
    if mode == "danger-full-access":
        return {"type": "dangerFullAccess"}
    raise AdapterFailure


class AppServer:
    def __init__(self, binary: str, cwd: str) -> None:
        try:
            self.process = subprocess.Popen(
                [binary, "app-server", "--stdio"],
                cwd=cwd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                bufsize=0,
            )
        except OSError as error:
            raise MissingExecutor from error
        if self.process.stdin is None or self.process.stdout is None:
            raise MissingExecutor
        self.stdin = self.process.stdin
        self.stdout = self.process.stdout
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.stdout, selectors.EVENT_READ)
        self.buffer = b""

    def close(self) -> None:
        self.selector.close()
        try:
            self.stdin.close()
        except OSError:
            pass
        try:
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=2)

    def send(self, value: dict[str, object]) -> None:
        payload = json.dumps(value, separators=(",", ":")).encode() + b"\n"
        try:
            self.stdin.write(payload)
            self.stdin.flush()
        except (BrokenPipeError, OSError) as error:
            raise AdapterFailure from error

    def receive(self, deadline: float) -> dict[str, Any]:
        while True:
            line, separator, remainder = self.buffer.partition(b"\n")
            if separator:
                self.buffer = remainder
                try:
                    message = json.loads(line)
                except (UnicodeError, json.JSONDecodeError) as error:
                    raise AdapterFailure from error
                if not isinstance(message, dict):
                    raise AdapterFailure
                return message
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AdapterFailure
            if not self.selector.select(remaining):
                raise AdapterFailure
            try:
                chunk = os.read(self.stdout.fileno(), 65536)
            except OSError as error:
                raise AdapterFailure from error
            if not chunk:
                raise AdapterFailure
            self.buffer += chunk
            if len(self.buffer) > MAX_PROTOCOL_LINE_BYTES:
                raise AdapterFailure

    def response(self, request_id: int, deadline: float) -> dict[str, Any]:
        while True:
            message = self.receive(deadline)
            if message.get("id") != request_id:
                if "id" in message and "method" in message:
                    raise AdapterFailure
                continue
            result = message.get("result")
            if "error" in message or not isinstance(result, dict):
                raise AdapterFailure
            return result


def check_app_server_stdio(binary: str) -> None:
    server: AppServer | None = None
    try:
        server = AppServer(binary, os.getcwd())
        deadline = time.monotonic() + PREFLIGHT_TIMEOUT_SECONDS
        server.send(
            {
                "id": 1,
                "method": "initialize",
                "params": {
                    "clientInfo": {
                        "name": "studio-moser-harness-preflight",
                        "title": "Harness Codex adapter preflight",
                        "version": "0.8.0",
                    }
                },
            }
        )
        server.response(1, deadline)
        server.send({"method": "initialized", "params": {}})
    except Exception as error:
        raise MissingExecutor from error
    finally:
        if server is not None:
            try:
                server.close()
            except Exception:
                pass


def final_agent_text(turn: dict[str, Any], completed_items: list[dict[str, Any]]) -> str:
    items = turn.get("items")
    if not isinstance(items, list):
        raise AdapterFailure
    by_id: dict[str, dict[str, Any]] = {}
    for item in [*completed_items, *items]:
        if isinstance(item, dict) and isinstance(item.get("id"), str):
            by_id[item["id"]] = item
    messages = [
        item
        for item in by_id.values()
        if item.get("type") == "agentMessage" and isinstance(item.get("text"), str)
    ]
    finals = [item for item in messages if item.get("phase") == "final_answer"]
    chosen = finals[-1] if finals else messages[-1] if messages else None
    if chosen is None or not chosen["text"]:
        raise AdapterFailure
    return chosen["text"]


def review_prompt(prompt: str, fixed_target: str | None) -> str:
    if fixed_target is None or FIXED_TARGET_PATTERN.fullmatch(fixed_target) is None:
        raise AdapterFailure
    binding = (
        f"Binding instruction: review only immutable fixed target {fixed_target}. "
        "Do not review HEAD, the working tree, another ref, or a moving diff.\n\n"
    )
    return binding + prompt


def require_git_repository(cwd: str) -> None:
    try:
        process = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--is-inside-work-tree"],
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except OSError as error:
        raise AdapterFailure from error
    if process.returncode != 0 or process.stdout.strip() != "true":
        raise AdapterFailure


def run_turn(args: argparse.Namespace, binary: str) -> str | None:
    if not args.skip_git_repo_check:
        require_git_repository(args.cwd)
    try:
        prompt = Path(args.prompt).read_text(encoding="utf-8")
        Path(args.report).write_text("", encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise AdapterFailure from error
    if args.operation == "review":
        prompt = review_prompt(prompt, args.fixed_target)

    server = AppServer(binary, args.cwd)
    try:
        deadline = time.monotonic() + TURN_TIMEOUT_SECONDS
        server.send(
            {
                "id": 1,
                "method": "initialize",
                "params": {
                    "clientInfo": {
                        "name": "studio-moser-harness",
                        "title": "Harness Codex adapter",
                        "version": "0.8.0",
                    }
                },
            }
        )
        server.response(1, deadline)
        server.send({"method": "initialized", "params": {}})
        server.send(
            {
                "id": 2,
                "method": "thread/start",
                "params": {
                    "allowProviderModelFallback": False,
                    "approvalPolicy": "never",
                    "cwd": args.cwd,
                    "ephemeral": True,
                    "model": args.model,
                    "sandbox": "read-only",
                },
            }
        )
        thread_result = server.response(2, deadline)
        thread = thread_result.get("thread")
        if not isinstance(thread, dict) or not isinstance(thread.get("id"), str):
            raise AdapterFailure
        thread_id = thread["id"]
        server.send(
            {
                "id": 3,
                "method": "turn/start",
                "params": {
                    "approvalPolicy": "never",
                    "cwd": args.cwd,
                    "effort": args.effort,
                    "input": [{"type": "text", "text": prompt}],
                    "model": args.model,
                    "sandboxPolicy": sandbox_policy(args.sandbox, args.cwd),
                    "threadId": thread_id,
                },
            }
        )
        turn_result = server.response(3, deadline)
        started_turn = turn_result.get("turn")
        if not isinstance(started_turn, dict) or not isinstance(started_turn.get("id"), str):
            raise AdapterFailure
        turn_id = started_turn["id"]
        completed_items: list[dict[str, Any]] = []
        while True:
            message = server.receive(deadline)
            if "id" in message and "method" in message:
                raise AdapterFailure
            method = message.get("method")
            params = message.get("params")
            if method == "item/completed" and isinstance(params, dict):
                item = params.get("item")
                if isinstance(item, dict):
                    completed_items.append(item)
                continue
            if method != "turn/completed":
                continue
            if not isinstance(params, dict) or params.get("threadId") != thread_id:
                raise AdapterFailure
            turn = params.get("turn")
            if not isinstance(turn, dict) or turn.get("id") != turn_id:
                raise AdapterFailure
            if turn.get("status") == "completed" and turn.get("error") is None:
                text = final_agent_text(turn, completed_items)
                try:
                    Path(args.report).write_text(f"{text.rstrip()}\n", encoding="utf-8")
                except OSError as error:
                    raise AdapterFailure from error
                return None
            error = turn.get("error")
            if not isinstance(error, dict):
                raise AdapterFailure
            reason = classify_availability(error.get("codexErrorInfo"))
            if reason is None:
                raise AdapterFailure
            return reason
    finally:
        server.close()


def parser() -> Arguments:
    root = Arguments(prog="codex-app-server.py")
    subcommands = root.add_subparsers(dest="command", required=True)
    check = subcommands.add_parser("check")
    check.add_argument("--codex-bin", default="codex")
    run = subcommands.add_parser("run")
    run.add_argument("--codex-bin", default="codex")
    run.add_argument("--operation", choices=("execute", "review", "computer-use"), required=True)
    run.add_argument("--cwd", required=True)
    run.add_argument(
        "--sandbox",
        choices=("read-only", "workspace-write", "danger-full-access"),
        required=True,
    )
    run.add_argument("--approval", choices=("never",), required=True)
    run.add_argument("--model", required=True)
    run.add_argument("--effort", required=True)
    run.add_argument("--prompt", required=True)
    run.add_argument("--report", required=True)
    run.add_argument("--fixed-target")
    run.add_argument("--skip-git-repo-check", action="store_true")
    return root


def main(argv: list[str]) -> int:
    try:
        args = parser().parse_args(argv)
        binary = resolve_binary(args.codex_bin)
        check_app_server(binary)
        check_app_server_stdio(binary)
        if args.command == "check":
            compact_json({"status": "available"})
            return 0
        reason = run_turn(args, binary)
        if reason is not None:
            compact_json({"status": "availability_failure", "reason": reason})
            return EXIT_AVAILABILITY
        compact_json({"status": "succeeded"})
        return 0
    except MissingExecutor:
        compact_json({"status": "missing_executor"})
        return EXIT_MISSING_EXECUTOR
    except Exception:
        compact_json({"status": "failed"})
        return EXIT_FAILED


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
