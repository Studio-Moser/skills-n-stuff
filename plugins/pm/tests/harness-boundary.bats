#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "PM contains no Harness control-plane implementation" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]) / "plugins" / "pm"
forbidden = [
    "model-rubric.yml",
    "references/model-orchestration.md",
    "via:",
    "codex-implementation",
    "codex-review",
    "codex-computer-use",
    "command -v codex",
    "routing.bulk",
    "routing.review",
    "model@effort",
]
hits = []
for path in sorted(root.rglob("*")):
    if not path.is_file() or "tests" in path.relative_to(root).parts:
        continue
    text = path.read_text(errors="ignore")
    for needle in forbidden:
        if needle in text:
            hits.append(f"{path.relative_to(root)}: {needle}")

assert not hits, "PM owns Harness control-plane behavior:\n" + "\n".join(hits)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "PM workflows send semantic Harness operations with domain constraints" {
  run python3 - "$REPO" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]) / "plugins" / "pm"
contracts = {
    "dev-task": (
        root / "skills/dev-task/SKILL.md",
        ("harness:execute", "operation: execute", "harness:review", "operation: review",
         "Outcome", "Blockers", "Testing Seam", "Proof", "Spec Fidelity", "Blast Radius"),
    ),
    "sprint-dev": (
        root / "skills/sprint-dev/SKILL.md",
        ("harness:execute", "operation: execute", "harness:review", "operation: review",
         "unblocked frontier", "delivery slice", "Blockers", "Testing Seam",
         "Spec Fidelity", "Blast Radius"),
    ),
    "ingest": (
        root / "skills/ingest/SKILL.md",
        ("harness:execute", "operation: execute", "route: bulk", "source claims",
         "status/needs-triage"),
    ),
    "triage-scorecard": (
        root / "references/triage-scorecard.md",
        ("harness:execute", "operation: execute", "route: bulk", "work-readiness.md",
         "one delivery slice", "Blockers", "Testing Seam"),
    ),
    "code-reviewer": (
        root / "agents/code-reviewer.md",
        ("harness:review", "operation: review", "route: review", "fixed target",
         "Quality", "Spec Fidelity", "Blast Radius"),
    ),
}

failures = []
for name, (path, required) in contracts.items():
    text = path.read_text()
    normalized = " ".join(text.split()).lower()
    missing = [value for value in required if value.lower() not in normalized]
    if missing:
        failures.append(f"{name}: {', '.join(missing)}")

assert not failures, "incomplete PM Harness requests:\n" + "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
