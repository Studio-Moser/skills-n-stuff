#!/usr/bin/env python3
"""Compose a complete setup HarnessResult from bounded dependency results."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def load_json(path: str) -> Any:
    with Path(path).open() as handle:
        return json.load(handle)


def checks_from(value: Any) -> list[str]:
    if not isinstance(value, dict):
        return []
    checks = value.get("checks", [])
    return [check for check in checks if isinstance(check, str)] if isinstance(checks, list) else []


def files_from(value: Any) -> list[str]:
    if not isinstance(value, dict):
        return []
    files = value.get("files", [])
    return [path for path in files if isinstance(path, str)] if isinstance(files, list) else []


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sync-result", required=True)
    parser.add_argument("--rubric-result", required=True)
    parser.add_argument("--tool-names", required=True)
    parser.add_argument("--shelby-result")
    parser.add_argument("--model", required=True)
    parser.add_argument("--effort", required=True)
    parser.add_argument("--provider", required=True)
    parser.add_argument("--executor", required=True)
    parser.add_argument("--fixed-target", required=True)
    parser.add_argument("--proof", required=True, choices=("proven", "unproven"))
    parser.add_argument("--report-path")
    parser.add_argument("--elapsed")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sync = load_json(args.sync_result)
    rubric = load_json(args.rubric_result)
    tool_names = load_json(args.tool_names)

    if not isinstance(sync, dict) or not isinstance(rubric, dict):
        raise SystemExit("dependency results must be JSON objects")
    if not isinstance(tool_names, list) or not all(isinstance(name, str) for name in tool_names):
        raise SystemExit("tool names must be a JSON string array")

    initial_sync = sync.get("initial", {})
    final_sync = sync.get("final", {})
    rubric_changed = rubric.get("changed") is True
    blockers: list[str] = []
    checks = [*checks_from(initial_sync), *checks_from(rubric)]

    if not isinstance(initial_sync, dict) or initial_sync.get("status") != "accepted":
        blockers.append("initial Sync did not establish the agents repository and links")
    if rubric.get("status") != "accepted":
        blockers.append("model rubric setup did not complete")
    if rubric.get("reconciled") is not True:
        blockers.append("rubric capabilities were not reconciled")
    if rubric_changed:
        checks.extend(checks_from(final_sync))
        if not isinstance(final_sync, dict) or final_sync.get("status") != "accepted":
            blockers.append("final Sync did not publish the changed rubric")

    shelby = {"project_id": None, "run_id": None, "checkpoint_ids": []}
    shelby_available = any("shelby" in name.lower() for name in tool_names)
    if shelby_available:
        shelby_result = load_json(args.shelby_result) if args.shelby_result else {}
        if isinstance(shelby_result, dict) and shelby_result.get("status") == "accepted":
            shelby = {
                "project_id": shelby_result.get("project_id"),
                "run_id": shelby_result.get("run_id"),
                "checkpoint_ids": shelby_result.get("checkpoint_ids", []),
            }
            if not isinstance(shelby["checkpoint_ids"], list):
                shelby["checkpoint_ids"] = []
            checks.extend(checks_from(shelby_result))
        else:
            checks.append("Shelby enrichment failed; setup continued without optional state")

    proven = args.proof == "proven" and not blockers
    status = "accepted" if proven else "blocked" if blockers else "failed"
    files = list(dict.fromkeys([*files_from(sync), *files_from(rubric)]))
    attempts = 2 + int(rubric_changed) + int(shelby_available)

    result = {
        "status": status,
        "route": {
            "requested": "default",
            "actual_model": args.model,
            "effort": args.effort,
            "provider": args.provider,
            "executor": args.executor,
        },
        "artifacts": {"files": files, "report": args.report_path},
        "evidence": {
            "fixed_target": args.fixed_target,
            "checks": checks,
            "outcome": "proven" if proven else "unproven",
        },
        "telemetry": {
            "attempts": attempts,
            "elapsed": args.elapsed,
            "verification_failures": len(blockers) + int(args.proof == "unproven"),
            "token_or_quota_usage": None,
        },
        "shelby": shelby,
        "blockers": blockers,
    }
    json.dump(result, fp=sys.stdout, separators=(",", ":"))
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
