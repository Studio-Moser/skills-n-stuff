#!/usr/bin/env python3
"""Deterministic Codex App Server stub for Harness adapter tests."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


RAW_MARKER = "RAW_SECRET_MARKER"


def write_schema(output: Path, compatible: bool) -> None:
    output.mkdir(parents=True, exist_ok=True)
    thread_properties = {
        name: {} for name in (
            "allowProviderModelFallback", "approvalPolicy", "cwd", "ephemeral",
            "model", "sandbox",
        )
    }
    turn_properties = {
        name: {} for name in (
            "approvalPolicy", "cwd", "effort", "input", "model",
            "sandboxPolicy", "threadId",
        )
    }
    (output / "v2").mkdir()
    (output / "v2" / "ThreadStartParams.json").write_text(
        json.dumps({"properties": thread_properties}), encoding="utf-8"
    )
    (output / "v2" / "TurnStartParams.json").write_text(
        json.dumps({"properties": turn_properties}), encoding="utf-8"
    )
    error_properties = {"message": {"type": "string"}}
    if compatible:
        error_properties["codexErrorInfo"] = {}
    variants = [
        "contextWindowExceeded", "sessionBudgetExceeded", "usageLimitExceeded",
        "serverOverloaded", "cyberPolicy", "misalignmentPolicyViolation",
        "internalServerError", "unauthorized", "badRequest", "sandboxError",
        "other",
    ]
    structured = [
        "httpConnectionFailed", "responseStreamConnectionFailed",
        "responseStreamDisconnected", "responseTooManyFailedAttempts",
    ]
    completed = {
        "properties": {"turn": {"$ref": "#/definitions/Turn"}},
        "definitions": {
            "Turn": {
                "properties": {
                    "error": {"$ref": "#/definitions/TurnError"},
                    "status": {"type": "string"},
                }
            },
            "TurnError": {"properties": error_properties},
            "CodexErrorInfo": {
                "oneOf": [
                    {"enum": variants},
                    *[
                        {
                            "properties": {
                                name: {
                                    "properties": {
                                        "httpStatusCode": {
                                            "type": ["integer", "null"]
                                        }
                                    }
                                }
                            },
                            "required": [name],
                        }
                        for name in structured
                    ],
                ]
            },
        },
    }
    (output / "v2" / "TurnCompletedNotification.json").write_text(
        json.dumps(completed), encoding="utf-8"
    )


def capture(message: dict) -> None:
    path = os.environ.get("HARNESS_CODEX_CAPTURE")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(message, separators=(",", ":")) + "\n")


def send(message: dict) -> None:
    print(json.dumps(message, separators=(",", ":")), flush=True)


def codex_error_info(mode: str) -> object:
    values: dict[str, object] = {
        "quota": "usageLimitExceeded",
        "authentication": "unauthorized",
        "rate_limit": {
            "responseStreamConnectionFailed": {"httpStatusCode": 429}
        },
        "provider_unavailable": "serverOverloaded",
        "http_401": {"httpConnectionFailed": {"httpStatusCode": 401}},
        "http_403": {"httpConnectionFailed": {"httpStatusCode": 403}},
        "http_500": {"httpConnectionFailed": {"httpStatusCode": 500}},
        "connection": {"httpConnectionFailed": {"httpStatusCode": None}},
        "non_availability_http": {
            "responseStreamDisconnected": {"httpStatusCode": 400}
        },
        "malformed": {"httpConnectionFailed": {"httpStatusCode": "429"}},
        "bad_request": "badRequest",
    }
    return values[mode]


def serve(mode: str) -> int:
    for line in sys.stdin:
        if mode == "stdio_incompatible":
            print(RAW_MARKER, flush=True)
            return 0
        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            return 2
        capture(request)
        method = request.get("method")
        if method == "initialize":
            send({"id": request["id"], "result": {"userAgent": "stub"}})
        elif method == "initialized":
            continue
        elif method == "thread/start":
            send({"id": request["id"], "result": {"thread": {"id": "thread-1"}}})
        elif method == "turn/start":
            if mode == "malformed_protocol":
                print(RAW_MARKER, flush=True)
                return 0
            send(
                {
                    "id": request["id"],
                    "result": {
                        "turn": {"id": "turn-1", "status": "inProgress", "items": []}
                    },
                }
            )
            if mode == "process_failure":
                print(RAW_MARKER, file=sys.stderr, flush=True)
                return 7
            if mode == "success":
                item = {
                    "id": "message-1",
                    "type": "agentMessage",
                    "phase": "final_answer",
                    "text": "stub final report",
                }
                send(
                    {
                        "method": "item/completed",
                        "params": {
                            "threadId": "thread-1", "turnId": "turn-1",
                            "completedAtMs": 1, "item": item,
                        },
                    }
                )
                turn = {
                    "id": "turn-1", "status": "completed", "items": [item],
                    "error": None,
                }
            else:
                error: dict[str, object] = {"message": RAW_MARKER}
                if mode != "untyped":
                    error["codexErrorInfo"] = codex_error_info(mode)
                turn = {
                    "id": "turn-1", "status": "failed", "items": [],
                    "error": error,
                }
            send(
                {
                    "method": "turn/completed",
                    "params": {"threadId": "thread-1", "turn": turn},
                }
            )
            return 0
        else:
            send({"id": request.get("id"), "error": {"code": -32601}})
    return 0


def main() -> int:
    mode = os.environ.get("HARNESS_CODEX_STUB_MODE", "success")
    if sys.argv[1:3] == ["app-server", "generate-json-schema"]:
        output = Path(sys.argv[sys.argv.index("--out") + 1])
        write_schema(output, compatible=mode != "incompatible")
        return 0
    if sys.argv[1:] == ["app-server", "--stdio"]:
        return serve(mode)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
